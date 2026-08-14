#include "RNNoiseBridge.h"
#include "rnnoise.h"

bool vt_rnnoise_available(void) { return true; }
void *vt_rnnoise_create(void) { return (void *)rnnoise_create(NULL); }
int vt_rnnoise_frame_size(void) { return rnnoise_get_frame_size(); }
float vt_rnnoise_process_frame(void *state, const float *input, float *output) {
    if (!state || !input || !output) return 0.0f;
    return rnnoise_process_frame((DenoiseState *)state, output, input);
}
void vt_rnnoise_destroy(void *state) {
    if (state) rnnoise_destroy((DenoiseState *)state);
}
