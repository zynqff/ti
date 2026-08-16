#pragma once
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

void *vt_df3_create(float atten_lim_db);
size_t vt_df3_frame_length(const void *st);
float vt_df3_process_frame(void *st, const float *input, float *output);
void vt_df3_reset(void *st);
void vt_df3_free(void *st);

/// Human-readable reason the last vt_df3_create() (or a subsequent
/// vt_df3_process_frame()) call failed -- including the captured Rust panic
/// message and location -- or NULL if the last call succeeded. The returned
/// pointer is owned by the Rust side, stays valid until the next
/// vt_df3_create() call, and must NOT be freed by the caller.
const char *vt_df3_last_error(void);

#ifdef __cplusplus
}
#endif
