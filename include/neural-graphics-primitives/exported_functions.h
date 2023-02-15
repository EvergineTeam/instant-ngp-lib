#pragma once

#ifdef _MSC_VER
#define INTERFACE_API __stdcall
#define EXPORT_API __declspec(dllexport)
#else
#define EXPORT_API
#error "Unsported compiler have fun"
#endif

#ifdef __cplusplus
extern "C"
{
#endif

	EXPORT_API void INTERFACE_API nerf_initialize(const char *scene, const char *checkpoint, bool use_dlss);
	EXPORT_API void INTERFACE_API nerf_deinitialize();

	EXPORT_API void INTERFACE_API nerf_create_textures(int num_views, float *fov, int width, int height, float scaleFactor, unsigned int *handles);
	EXPORT_API void INTERFACE_API nerf_update_textures(float *camera_matrix);

	EXPORT_API void nerf_set_fov(float val);
	EXPORT_API void INTERFACE_API nerf_update_aabb_crop(float *min_vec, float *max_vec);
	EXPORT_API void INTERFACE_API nerf_reset_camera();

#ifdef __cplusplus
}
#endif
