#include "RNNoiseBridge.h"
#include "rnnoise.h"
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>

// Human-readable diagnostic for the most recent vt_rnnoise_create() failure.
// The original code called the convenience rnnoise_create(NULL) wrapper,
// which on failure only ever returns NULL -- there was no way to tell
// whether that meant "malloc failed" or "model init failed" or anything
// else. This reimplements the same three steps rnnoise_create() performs
// internally, using the public API (rnnoise_get_size / rnnoise_init), so we
// can capture exactly which step failed and why.
static char vt_rnnoise_error_buf[256] = {0};

static void vt_rnnoise_set_error(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vsnprintf(vt_rnnoise_error_buf, sizeof(vt_rnnoise_error_buf), fmt, args);
    va_end(args);
}

bool vt_rnnoise_available(void) { return true; }

void *vt_rnnoise_create(void) {
    vt_rnnoise_error_buf[0] = '\0';

    int size = rnnoise_get_size();
    if (size <= 0) {
        vt_rnnoise_set_error("rnnoise_get_size() returned invalid size: %d", size);
        return NULL;
    }

    DenoiseState *st = (DenoiseState *)malloc((size_t)size);
    if (!st) {
        vt_rnnoise_set_error("malloc(%d bytes) failed for DenoiseState", size);
        return NULL;
    }

    // Passing NULL uses the built-in default model (compiled from
    // rnnoise_data.c). A non-zero return means that initialization failed --
    // most commonly because the generated model weights are missing,
    // truncated, or mismatched with this build of the library.
    int ret = rnnoise_init(st, NULL);
    if (ret != 0) {
        vt_rnnoise_set_error(
            "rnnoise_init() failed with code %d (default model weights missing, "
            "truncated, or incompatible with this build)", ret);
        free(st);
        return NULL;
    }

    return (void *)st;
}

int vt_rnnoise_frame_size(void) { return rnnoise_get_frame_size(); }

float vt_rnnoise_process_frame(void *state, const float *input, float *output) {
    if (!state || !input || !output) return 0.0f;
    return rnnoise_process_frame((DenoiseState *)state, output, input);
}

void vt_rnnoise_destroy(void *state) {
    if (state) rnnoise_destroy((DenoiseState *)state);
}

const char *vt_rnnoise_last_error(void) {
    return vt_rnnoise_error_buf[0] != '\0' ? vt_rnnoise_error_buf : NULL;
}

// FIX #5: BenchmarkManager calls processor.reset() right before every run,
// including the very first one -- immediately after a successful
// vt_rnnoise_create(). The old RNNoiseProcessor.reset() called
// vt_rnnoise_destroy() there and never recreated the state, so RNNoise
// always reported "NOT AVAILABLE" even though init had actually succeeded.
// This reinitializes the SAME allocation in place (same three steps as
// vt_rnnoise_create, minus the malloc) so the pointer the Swift side is
// still holding remains valid and usable.
bool vt_rnnoise_reset(void *state) {
    vt_rnnoise_error_buf[0] = '\0';
    if (!state) {
        vt_rnnoise_set_error("vt_rnnoise_reset() called with a null state");
        return false;
    }
    int ret = rnnoise_init((DenoiseState *)state, NULL);
    if (ret != 0) {
        vt_rnnoise_set_error(
            "rnnoise_init() failed with code %d during reset (default model weights missing, "
            "truncated, or incompatible with this build)", ret);
        return false;
    }
    return true;
}
