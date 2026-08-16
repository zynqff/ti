#ifndef VIBETALK_RNNOISE_BRIDGE_H
#define VIBETALK_RNNOISE_BRIDGE_H

#include <stdbool.h>
#ifdef __cplusplus
extern "C" {
#endif

bool vt_rnnoise_available(void);
void *vt_rnnoise_create(void);
int vt_rnnoise_frame_size(void);
float vt_rnnoise_process_frame(void *state, const float *input, float *output);
void vt_rnnoise_destroy(void *state);

/// Human-readable reason the last vt_rnnoise_create() call failed, or NULL if
/// the last call succeeded (or none has been made yet). The returned pointer
/// is owned by the bridge, stays valid until the next vt_rnnoise_create()
/// call, and must NOT be freed by the caller.
const char *vt_rnnoise_last_error(void);

#ifdef __cplusplus
}
#endif
#endif


