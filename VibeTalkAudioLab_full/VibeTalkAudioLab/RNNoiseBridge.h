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

#ifdef __cplusplus
}
#endif
#endif
