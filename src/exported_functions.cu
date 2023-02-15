#include "neural-graphics-primitives/exported_functions.h"

#ifdef _WIN32
#include <GL/gl3w.h>
#else
#include <GL/glew.h>
#endif
#include <GLFW/glfw3.h>
#include "gl/GL.h"
#include "gl/GLU.h"

#include <neural-graphics-primitives/common_device.cuh>
#include <neural-graphics-primitives/common.h>
#include <neural-graphics-primitives/random_val.cuh>
#include <neural-graphics-primitives/adam_optimizer.h>
#include <neural-graphics-primitives/camera_path.h>
#include <neural-graphics-primitives/discrete_distribution.h>
#include <neural-graphics-primitives/nerf.h>
#include <neural-graphics-primitives/nerf_loader.h>
#include <neural-graphics-primitives/render_buffer.h>
#include <neural-graphics-primitives/sdf.h>
#include <neural-graphics-primitives/shared_queue.h>
#include <neural-graphics-primitives/trainable_buffer.cuh>
#include <neural-graphics-primitives/render_buffer.h>
#include <neural-graphics-primitives/tinyexr_wrapper.h>
#include <neural-graphics-primitives/testbed.h>

#include <tiny-cuda-nn/gpu_memory.h>
#include <filesystem/path.h>
#include <cuda_gl_interop.h>

#include <tiny-cuda-nn/multi_stream.h>
#include <tiny-cuda-nn/random.h>

#include <json/json.hpp>
#include <filesystem/path.h>
#include <thread>
#include "gl/GL.h"
#include "gl/GLU.h"
#include <memory>

using Texture = std::shared_ptr<ngp::GLTexture>;
using RenderBuffer = std::shared_ptr<ngp::CudaRenderBuffer>;
using namespace Eigen;

// FIXME por qué hay que redefinirlas?
inline constexpr float PI() { return 3.14159265358979323846f; }
inline NGP_HOST_DEVICE Eigen::Vector2f fov_to_focal_length(const Eigen::Vector2i &resolution, const Eigen::Vector2f &degrees)
{
	return 0.5f * resolution.cast<float>().cwiseQuotient((0.5f * degrees * (float)PI() / 180).array().tan().matrix());
}

struct TextureData
{
	TextureData(const Texture &tex, const RenderBuffer &buf, int width, int heigth)
		: surface_texture(tex), render_buffer(buf), width(width), height(height)
	{
	}

	Texture surface_texture;
	RenderBuffer render_buffer;
	int width;
	int height;
};

static bool already_initalized = false;
static std::shared_ptr<ngp::Testbed> testbed = nullptr;

/*
Check Testbed::init_window and main::main_func
*/
extern "C" void nerf_initialize(const char *scene, const char *snapshot, bool dlss)
{
	if (already_initalized)
	{
		std::cout << "Already initalized nerf" << std::endl;
		return;
	}

	testbed = std::make_shared<ngp::Testbed>(
		ngp::ETestbedMode::Nerf,
		scene);

	if (snapshot)
	{
		testbed->load_snapshot(
			snapshot);
	}

	if (!glfwInit())
	{
		std::cout << "Could not initialize glfw" << std::endl;
	}
	if (gl3wInit() != 0)
	{
		std::cout << "Could not initialize gl3w" << std::endl;
	}

#ifdef NGP_VULKAN
	if (dlss)
	{
		try
		{
			testbed->m_dlss_provider = ngp::init_vulkan_and_ngx();
			if (testbed->m_testbed_mode == ngp::ETestbedMode::Nerf)
			{
				testbed->m_aperture_size = 0.0f;
				testbed->m_dlss = true;
			}
		}
		catch (const std::runtime_error &e)
		{
			tlog::warning() << "Could not initialize Vulkan and NGX. DLSS not supported. (" << e.what() << ")";
		}
	}
#endif

	already_initalized = true;
}

extern "C" void nerf_deinitialize()
{
	testbed->m_views.clear();
	testbed->m_rgba_render_textures.clear();
	testbed->m_depth_render_textures.clear();

	testbed->m_pip_render_buffer.reset();
	testbed->m_pip_render_texture.reset();

	testbed->m_dlss = false;
	testbed->m_dlss_provider.reset();
	testbed.reset();
	glfwTerminate();

	already_initalized = false;
}

/*
Check Testbed::begin_vr_frame_and_handle_vr_input, Testbed::init_window
*/
extern "C" void nerf_create_textures(int num_views, float *fov, int width, int height, float scaleFactor, unsigned int *handles)
{
	if (!testbed)
		return;

	testbed->set_n_views(num_views);
	testbed->m_foveated_rendering = false; // TODO foveated rendering

	// set fov and screen center
	if (num_views == 1)
	{
		// Desktop render
		testbed->m_views[0].relative_focal_length = testbed->m_relative_focal_length;
		testbed->m_views[0].screen_center = testbed->m_screen_center;
	}
	else
	{
		// VR render
		for (int i = 0; i < num_views; i++)
		{
			float angleLeft = fov[i * 4];
			float angleRight = fov[(i * 4) + 1];
			float angleUp = fov[(i * 4) + 2];
			float angleDown = fov[(i * 4) + 3];

			// Compute the distance on the image plane (1 unit away from the camera) that an angle of the respective FOV spans
			Vector2f rel_focal_length_left_down = 0.5f * fov_to_focal_length(Vector2i::Ones(), Vector2f{360.0f * angleLeft / PI(), 360.0f * angleDown / PI()});
			Vector2f rel_focal_length_right_up = 0.5f * fov_to_focal_length(Vector2i::Ones(), Vector2f{360.0f * angleRight / PI(), 360.0f * angleUp / PI()});
			testbed->m_views[i].relative_focal_length = rel_focal_length_right_up - rel_focal_length_left_down;

			// Compute fraction of that distance that is spanned by the right-up part and set screen center accordingly.
			Vector2f ratio = rel_focal_length_right_up.cwiseQuotient(testbed->m_views[i].relative_focal_length);
			testbed->m_views[i].screen_center = {1.0f - ratio.x(), ratio.y()};
		}
	}

	// create textures and dlss
	for (int i = 0; i < num_views; i++)
	{
		// TODO render on different GPUs if available
		testbed->m_views[i].device = &(testbed->primary_device()); // Render each view on primary GPU
		testbed->m_views[i].full_resolution = {width, height};
		testbed->m_views[i].render_buffer->set_hidden_area_mask(nullptr);
		testbed->m_views[i].visualized_dimension = -1;
		testbed->m_views[i].foveation = {}; // TODO foveated rendering

		// dlss with scaled resolution
		auto buffer = testbed->m_views[i].render_buffer;
		auto full_resolution = testbed->m_views[i].full_resolution;

		if (testbed->m_dlss)
		{
			buffer->enable_dlss(*testbed->m_dlss_provider, full_resolution);
		}
		else
		{
			buffer->disable_dlss();
		}

		Eigen::Vector2i render_res = buffer->in_resolution();
		Eigen::Vector2i new_render_res = (full_resolution.cast<float>() * scaleFactor).cast<int>().cwiseMin(full_resolution).cwiseMax(full_resolution / 16);

		float ratio = std::sqrt((float)render_res.prod() / (float)new_render_res.prod());
		if (ratio > 1.2f || ratio < 0.8f || scaleFactor == 1.0f || !testbed->m_dynamic_res)
		{
			render_res = new_render_res;
		}

		if (buffer->dlss())
		{
			render_res = buffer->dlss()->clamp_resolution(render_res);
			buffer->dlss()->update_feature(render_res, buffer->dlss()->is_hdr(), buffer->dlss()->sharpen());
		}

		buffer->resize(render_res);

		auto texture = testbed->m_rgba_render_textures[i];
		handles[i] = texture->texture();
	}
}

extern "C" void nerf_update_textures(float *camera_matrix)
{
	if (!testbed)
		return;

	int num_views = testbed->m_views.size();
	if (num_views > 1)
	{
		testbed->reset_accumulation(true);
	}
	else
	{
		testbed->reset_accumulation();
	}

	if (testbed->m_dlss)
	{
		testbed->m_aperture_size = 0.0f;
		if (!ngp::supports_dlss(testbed->m_nerf.render_lens.mode))
		{
			testbed->m_nerf.render_with_lens_distortion = false;
		}
	}

	// TODO update dynamic res and DLSS #2706

	// TODO foveated rendering #2758

	for (int i = 0; i < num_views; i++)
	{
		auto matrix_slice = &camera_matrix[i * 12];
		Eigen::Matrix<float, 3, 4> camera{matrix_slice};

		auto &view = testbed->m_views[i];
		testbed->render_frame(testbed->m_stream.get(),
							  camera,
							  camera,
							  camera,
							  view.screen_center,
							  view.relative_focal_length,
							  {0.0f, 0.0f, 0.0f, 1.0f},
							  view.foveation,
							  view.prev_foveation,
							  view.visualized_dimension,
							  *view.render_buffer,
							  true,
							  view.device);
	}
}

// utility functions

extern "C" void nerf_set_fov(float val)
{
	if (!testbed || testbed->m_views.size() != 1)
		return;

	testbed->set_fov(val);
	testbed->m_views[0].relative_focal_length = testbed->m_relative_focal_length;
}

extern "C" void nerf_update_aabb_crop(float *min_vec, float *max_vec)
{
	if (!testbed)
		return;

	Eigen::Vector3f min_aabb{min_vec};
	Eigen::Vector3f max_aabb{max_vec};

	testbed->m_render_aabb = ngp::BoundingBox(min_aabb, max_aabb);
}

extern "C" void nerf_reset_camera()
{
	if (!testbed)
		return;
	testbed->reset_camera();
}
