#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif
void *vt_df3_create(float atten_lim_db);
size_t vt_df3_frame_length(const void *st);
float vt_df3_process_frame(void *st,const float *input,float *output);
void vt_df3_reset(void *st);
void vt_df3_free(void *st);
#ifdef __cplusplus
}
#endif
