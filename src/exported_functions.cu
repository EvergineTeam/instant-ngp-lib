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
static bool use_dlss = false;
static uint32_t nullHandle;
static std::shared_ptr<ngp::Testbed> testbed = nullptr;
static std::unordered_map<GLuint, std::shared_ptr<TextureData>> textures;

extern "C" void nerf_initialize(const char *scene, const char *snapshot, bool dlss)
{
	if (already_initalized)
	{
		std::cout << "Already initalized nerf" << std::endl;
		return;
	}

	use_dlss = dlss;
	already_initalized = true;

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
	if (!gl3wInit())
	{
		std::cout << "Could not initialize gl3w" << std::endl;
	}

#ifdef NGP_VULKAN
	if (use_dlss)
	{
		try
		{
			ngp::vulkan_and_ngx_init();
		}
		catch (std::runtime_error exception)
		{
			std::cout << "Could not initialize vulkan" << std::endl;
		}
	}
#endif
}

extern "C" void nerf_deinitialize()
{

#ifdef NGP_VULKAN
	if (use_dlss)
	{
		ngp::vulkan_and_ngx_destroy();
	}
#endif
	already_initalized = false;
	testbed.reset();
	glfwTerminate();
}

extern "C" unsigned int nerf_create_texture(int width, int height)
{
	if (!testbed)
		return 0;

	// gladly ngp already implements gl textures for us
	// so we just need to call GLTexture to create a new one.
	auto texture = std::make_shared<ngp::GLTexture>();
	auto buffer = std::make_shared<ngp::CudaRenderBuffer>(texture);

	Eigen::Vector2i render_res{width, height};
#if defined(NGP_VULKAN)
	if (use_dlss)
	{
		buffer->enable_dlss({width, height});
		// buffer->resize({ width, height });

		Eigen::Vector2i texture_res{width, height};
		render_res = buffer->in_resolution();
		if (render_res.isZero())
		{
			render_res = texture_res / 16;
		}
		else
		{
			render_res = render_res.cwiseMin(texture_res);
		}

		if (buffer->dlss())
		{
			render_res = buffer->dlss()->clamp_resolution(render_res);
		}
	}
#endif

	buffer->resize(render_res);

	GLuint handle = texture->texture();

	textures[texture->texture()] = std::make_shared<TextureData>(
		texture,
		buffer,
		width,
		height);

	return handle;
}

extern "C" void nerf_set_fov(float val)
{
	if (!testbed)
		return;

	testbed->set_fov(val);
}

extern "C" void nerf_update_texture(float *camera_matrix, unsigned int handle, float *fov)
{
	if (!testbed)
		return;

	auto found = textures.find(handle);
	if (found == std::end(textures))
	{
		return;
	}

	Eigen::Matrix<float, 3, 4> camera{camera_matrix};

	/*********Set fov for view*********/
	float angleLeft = fov[0];
	float angleRight = fov[1];
	float angleUp = fov[2];
	float angleDown = fov[3];

	// Compute the distance on the image plane (1 unit away from the camera) that an angle of the respective FOV spans
	Vector2f rel_focal_length_left_down = 0.5f * fov_to_focal_length(Vector2i::Ones(), Vector2f{360.0f * angleLeft / PI(), 360.0f * angleDown / PI()});
	Vector2f rel_focal_length_right_up = 0.5f * fov_to_focal_length(Vector2i::Ones(), Vector2f{360.0f * angleRight / PI(), 360.0f * angleUp / PI()});

	// Compute total distance (for X and Y) that is spanned on the image plane.
	testbed->m_relative_focal_length = rel_focal_length_right_up - rel_focal_length_left_down;

	// Compute fraction of that distance that is spanned by the right-up part and set screen center accordingly.
	Vector2f ratio = rel_focal_length_right_up.cwiseQuotient(testbed->m_relative_focal_length);
	testbed->m_screen_center = {1.0f - ratio.x(), ratio.y()};

	// Fix up weirdness in the rendering pipeline
	// // relative_focal_length[(m_fov_axis + 1) % 2] *= (float)view_resolution[(m_fov_axis + 1) % 2] / (float)view_resolution[m_fov_axis];

	RenderBuffer render_buffer = found->second->render_buffer;
	render_buffer->reset_accumulation();
	testbed->render_frame(camera,
						  camera,
						  Eigen::Vector4f::Zero(),
						  *render_buffer.get(),
						  true);
}

extern "C" void nerf_update_aabb_crop(float *min_vec, float *max_vec)
{
	if (!testbed)
		return;

	Eigen::Vector3f min_aabb{min_vec};
	Eigen::Vector3f max_aabb{max_vec};

	testbed->m_render_aabb = ngp::BoundingBox(min_aabb, max_aabb);
}

extern "C" void nerf_destroy_texture(unsigned int handle)
{
	if (!testbed)
		return;

	// @TODO add warnings and stuff
	// GLuint handle = static_cast<GLuint>(*handle_ptr);
	auto found = textures.find(handle);
	if (found == std::end(textures))
	{
		return;
	}

	found->second->surface_texture.reset();
	found->second->render_buffer.reset();

	found->second.reset();
}

// utility functions

extern "C" void nerf_reset_camera()
{
	if (!testbed)
		return;
	testbed->reset_camera();
}
