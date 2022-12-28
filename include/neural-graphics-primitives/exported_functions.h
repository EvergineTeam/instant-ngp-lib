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
EXPORT_API void INTERFACE_API nerf_update_texture(float* camera_matrix, unsigned int handle);
EXPORT_API void INTERFACE_API nerf_update_aabb_crop(float* min_vec, float* max_vec);
EXPORT_API void INTERFACE_API nerf_destroy_texture(unsigned int handle);
EXPORT_API void INTERFACE_API nerf_reset_camera();

#ifdef __cplusplus
}
#endif
