#ifndef MacMixEQDSP_h
#define MacMixEQDSP_h
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#define MacMixEQSpectrumBarCount 66
// One serialized control producer and one audio consumer. Destroy after IO stops.
void *MacMixEQCreate(double sampleRate, uint32_t channels);
void MacMixEQSetGains(void *context, const double *gains, bool enabled);
void MacMixEQSetToneGains(void *context, const double *threeGains, bool enabled);
void MacMixEQFitToneGains(const double *threeGains, double *tenGains);
void MacMixEQProcessFrame(void *context, double *samples, uint32_t channels);
void MacMixEQBeginBlock(void *context);
double MacMixEQProcessSample(void *context, double sample, uint32_t channel);
bool MacMixEQIsSettled(void *context);
// Metering is opt-in. The audio thread writes a bounded triple-buffered snapshot;
// CopySpectrum runs FFT on the serialized control thread, never in the IO callback.
void MacMixEQSetMetering(void *context, bool enabled);
bool MacMixEQMeteringIsActive(void *context);
void MacMixEQObserveSample(void *context, double outputSample, uint32_t channel);
void MacMixEQEndBlock(void *context);
bool MacMixEQCopySpectrum(void *context, float *bars, size_t count);
void MacMixEQDestroy(void *context);
#endif
