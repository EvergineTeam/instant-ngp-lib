#pragma once

#ifdef _MSC_VER
    #define INTERFACE_API __stdcall
    #define EXPORT_API __declspec(dllexport)
#else
    #define EXPORT_API
    #error "Unsported compiler have fun"
#endif

#ifdef __cplusplus
extern "C" {
#endif

EXPORT_API void INTERFACE_API nerf_initialize(const char* scene, const char* checkpoint, bool use_dlss);
EXPORT_API void INTERFACE_API nerf_deinitialize();

EXPORT_API unsigned int INTERFACE_API nerf_create_texture(int width, int height);
EXPORT_API void INTERFACE_API nerf_update_texture(float *camera_matrix0,
												  unsigned int handle,
												  float *camera_matrix1 = 0,
												  float *rolling_shutter = 0,
												  int is_rgb = 1);
EXPORT_API void INTERFACE_API nerf_update_aabb_crop(float* min_vec, float* max_vec);
EXPORT_API float nerf_fov();
EXPORT_API void nerf_set_fov(float val);
EXPORT_API Eigen::Vector2f nerf_fov_xy();
EXPORT_API void nerf_set_fov_xy(float *xy)
EXPORT_API void INTERFACE_API nerf_destroy_texture(unsigned int handle);
EXPORT_API void INTERFACE_API nerf_reset_camera();

#ifdef __cplusplus
}
#endif
