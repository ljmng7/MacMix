#include "MacMixEQDSP.h"
#include <math.h>
#include <Accelerate/Accelerate.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define BANDS 10
#define CHANNELS 64
#define DIRTY 4u
#define FFT_LOG2 13
#define FFT_SIZE (1u << FFT_LOG2)
#define SPECTRUM_BARS MacMixEQSpectrumBarCount
_Static_assert(ATOMIC_INT_LOCK_FREE == 2, "EQ needs lock-free atomics");
typedef struct { double b0, b1, b2, a1, a2; } Coefficients;
typedef struct { Coefficients bands[BANDS]; bool active; } Parameters;
typedef struct { double z1, z2, x1, x2, y1, y2; } EQDelay;
typedef struct { double gain; uint32_t hold; } PeakEnvelope;
typedef struct { Parameters parameters; EQDelay delays[CHANNELS][BANDS]; } Bank;
typedef struct {
    double sampleRate;
    uint32_t channels, fadeFrames;
    Parameters slots[3];
    unsigned front, back;
    _Atomic(unsigned) middle;
    _Atomic(bool) settled;
    Bank current, next;
    uint32_t progress[CHANNELS];
    bool transitioning;
    PeakEnvelope linkedPeak;
    PeakEnvelope scalarPeaks[CHANNELS];
    double releaseStep;
    uint32_t peakHoldFrames;
    _Atomic(bool) meterRequested;
    bool meterActive;
    float *meterRing, *meterSlots[3];
    unsigned meterFront, meterBack;
    _Atomic(unsigned) meterMiddle;
    unsigned meterOffsets[CHANNELS], meterSampleCounts[CHANNELS], meterHop;
    FFTSetup fft;
    double spectrumNormalization;
    float window[FFT_SIZE], fftInput[FFT_SIZE];
    float real[FFT_SIZE / 2], imaginary[FFT_SIZE / 2], powers[FFT_SIZE / 2];
} Equalizer;
static const double frequencies[BANDS] = {31.25,62.5,125,250,500,1000,2000,4000,8000,16000};
static Parameters flat(void) {
    Parameters p = {.active = false};
    for (unsigned b = 0; b < BANDS; ++b) p.bands[b].b0 = 1;
    return p;
}
void *MacMixEQCreate(double sampleRate, uint32_t channels) {
    if (!isfinite(sampleRate) || sampleRate < 8000 || sampleRate > 768000 || channels == 0 || channels > CHANNELS) return NULL;
    Equalizer *eq = calloc(1, sizeof(*eq));
    if (!eq) return NULL;
    eq->sampleRate = sampleRate;
    eq->channels = channels;
    eq->fadeFrames = (uint32_t)(sampleRate * 0.04);
    eq->linkedPeak.gain = 1;
    for (unsigned ch = 0; ch < channels; ++ch) eq->scalarPeaks[ch].gain = 1;
    eq->peakHoldFrames = (uint32_t)(sampleRate * 0.05);
    eq->releaseStep = 1 - exp(-1 / (sampleRate * 0.20));
    eq->front = 0; eq->back = 2;
    atomic_init(&eq->middle, 1);
    atomic_init(&eq->settled, true);
    atomic_init(&eq->meterRequested, false);
    atomic_init(&eq->meterMiddle, 1);
    eq->meterFront = 0; eq->meterBack = 2;
    // Allocate before starting IO, even though capture/FFT remain off until visible.
    eq->meterRing = calloc(channels * FFT_SIZE, sizeof(float));
    for (unsigned i = 0; i < 3; ++i) eq->meterSlots[i] = calloc(channels * FFT_SIZE, sizeof(float));
    eq->fft = vDSP_create_fftsetup(FFT_LOG2, kFFTRadix2);
    if (!eq->meterRing || !eq->meterSlots[0] || !eq->meterSlots[1] || !eq->meterSlots[2] || !eq->fft) {
        MacMixEQDestroy(eq);
        return NULL;
    }
    vDSP_hann_window(eq->window, FFT_SIZE, vDSP_HANN_NORM);
    float windowSum = 0;
    vDSP_sve(eq->window, 1, &windowSum, FFT_SIZE);
    // Real vDSP FFT has a factor of two; 1/sum(window) restores sine peak dBFS.
    eq->spectrumNormalization = 1.0 / windowSum;
    eq->current.parameters = eq->next.parameters = flat();
    for (unsigned i = 0; i < 3; ++i) eq->slots[i] = flat();
    return eq;
}
static double boundedGain(double gain) {
    return isfinite(gain) ? fmax(-12, fmin(12, gain)) : 0;
}
static Coefficients peakCoefficients(double frequency, double gain, double q, double rate) {
    double a = pow(10, gain / 40), w = 2 * M_PI * frequency / rate;
    double alpha = sin(w) / (2 * q), a0 = 1 + alpha / a;
    return (Coefficients){(1 + alpha * a) / a0, -2 * cos(w) / a0,
        (1 - alpha * a) / a0, -2 * cos(w) / a0, (1 - alpha / a) / a0};
}
// Standard RBJ shelves, slope S = 1. These are MacMix's own tone-control choices,
// not a claim about Apple's unpublished AirPods filter frequencies.
static Coefficients shelfCoefficients(double frequency, double gain, bool high, double rate) {
    double a = pow(10, gain / 40), w = 2 * M_PI * frequency / rate;
    double c = cos(w), beta = sqrt(2 * a) * sin(w), sum = a + 1, difference = a - 1;
    if (high) {
        double denominator = sum - difference * c + beta;
        return (Coefficients){a * (sum + difference * c + beta) / denominator,
            -2 * a * (difference + sum * c) / denominator,
            a * (sum + difference * c - beta) / denominator,
            2 * (difference - sum * c) / denominator,
            (sum - difference * c - beta) / denominator};
    }
    double denominator = sum + difference * c + beta;
    return (Coefficients){a * (sum - difference * c + beta) / denominator,
        2 * a * (difference - sum * c) / denominator,
        a * (sum - difference * c - beta) / denominator,
        -2 * (difference + sum * c) / denominator,
        (sum + difference * c - beta) / denominator};
}
static Parameters toneParameters(const double *gains, double rate) {
    Parameters p = flat();
    double low = boundedGain(gains[0]), mid = boundedGain(gains[1]), high = boundedGain(gains[2]);
    p.bands[0] = shelfCoefficients(200, low, false, rate);
    p.bands[1] = peakCoefficients(1000, mid, 0.55, rate);
    p.bands[2] = shelfCoefficients(fmin(4000, rate * 0.35), high, true, rate);
    p.active = fabs(low) + fabs(mid) + fabs(high) > 0.001;
    return p;
}
static void publishParameters(Equalizer *eq, Parameters p) {
    eq->slots[eq->back] = p;
    atomic_store_explicit(&eq->settled, false, memory_order_relaxed);
    eq->back = atomic_exchange_explicit(&eq->middle, eq->back | DIRTY, memory_order_acq_rel) & 3u;
}
void MacMixEQSetGains(void *context, const double *gains, bool enabled) {
    Equalizer *eq = context;
    if (!eq) return;
    Parameters p = flat();
    if (enabled && gains) for (unsigned b = 0; b < BANDS; ++b) {
        double gain = boundedGain(gains[b]);
        if (frequencies[b] >= eq->sampleRate * 0.45 || fabs(gain) < 0.001) continue;
        p.active = true;
        p.bands[b] = peakCoefficients(frequencies[b], gain, 1.4, eq->sampleRate);
    }
    publishParameters(eq, p);
}
void MacMixEQSetToneGains(void *context, const double *gains, bool enabled) {
    Equalizer *eq = context;
    if (eq) publishParameters(eq, enabled && gains ? toneParameters(gains, eq->sampleRate) : flat());
}
static double responseDB(Coefficients c, double frequency, double rate) {
    double w = 2 * M_PI * frequency / rate, c1 = cos(w), s1 = sin(w), c2 = cos(2*w), s2 = sin(2*w);
    double nr = c.b0 + c.b1*c1 + c.b2*c2, ni = c.b1*s1 + c.b2*s2;
    double dr = 1 + c.a1*c1 + c.a2*c2, di = c.a1*s1 + c.a2*s2;
    return 10 * log10(fmax(1e-24, (nr*nr + ni*ni) / (dr*dr + di*di)));
}
// Fit the ten graphic controls to the tone response. Merely switching views keeps
// the original tone filters; the fit avoids a large jump on the first fine edit.
// This bounded solver runs on the control/UI thread only.
void MacMixEQFitToneGains(const double *tones, double *gains) {
    if (!tones || !gains) return;
    const double rate = 48000;
    Parameters target = toneParameters(tones, rate);
    double desired[BANDS] = {0};
    for (unsigned row = 0; row < BANDS; ++row) {
        gains[row] = 0;
        for (unsigned b = 0; b < 3; ++b) desired[row] += responseDB(target.bands[b], frequencies[row], rate);
    }
    for (unsigned iteration = 0; iteration < 7; ++iteration) {
        double matrix[BANDS][BANDS + 1] = {0};
        for (unsigned row = 0; row < BANDS; ++row) {
            double actual = 0;
            for (unsigned b = 0; b < BANDS; ++b) {
                double value = responseDB(peakCoefficients(frequencies[b], gains[b], 1.4, rate), frequencies[row], rate);
                actual += value;
                matrix[row][b] = (responseDB(peakCoefficients(frequencies[b], gains[b] + 0.01, 1.4, rate), frequencies[row], rate) - value) / 0.01;
            }
            matrix[row][BANDS] = desired[row] - actual;
        }
        for (unsigned column = 0; column < BANDS; ++column) {
            unsigned pivot = column;
            for (unsigned row = column + 1; row < BANDS; ++row)
                if (fabs(matrix[row][column]) > fabs(matrix[pivot][column])) pivot = row;
            for (unsigned j = column; j <= BANDS; ++j) {
                double t = matrix[column][j]; matrix[column][j] = matrix[pivot][j]; matrix[pivot][j] = t;
            }
            if (fabs(matrix[column][column]) < 1e-8) return;
            double divisor = matrix[column][column];
            for (unsigned j = column; j <= BANDS; ++j) matrix[column][j] /= divisor;
            for (unsigned row = 0; row < BANDS; ++row) if (row != column) {
                double factor = matrix[row][column];
                for (unsigned j = column; j <= BANDS; ++j) matrix[row][j] -= factor * matrix[column][j];
            }
        }
        for (unsigned b = 0; b < BANDS; ++b) gains[b] = boundedGain(gains[b] + 0.8 * matrix[b][BANDS]);
    }
}
void MacMixEQBeginBlock(void *context) {
    Equalizer *eq = context;
    if (!eq) return;
    bool meterRequested = atomic_load_explicit(&eq->meterRequested, memory_order_relaxed);
    if (meterRequested && !eq->meterActive) {
        memset(eq->meterOffsets, 0, sizeof(eq->meterOffsets));
        memset(eq->meterSampleCounts, 0, sizeof(eq->meterSampleCounts));
        eq->meterHop = 0;
    }
    eq->meterActive = meterRequested;
    if (eq->transitioning) {
        bool done = true;
        for (unsigned ch = 0; ch < eq->channels; ++ch) done &= eq->progress[ch] >= eq->fadeFrames;
        if (!done) return;
        eq->current = eq->next;
        eq->transitioning = false;
    }
    if (atomic_load_explicit(&eq->middle, memory_order_acquire) & DIRTY) {
        eq->front = atomic_exchange_explicit(&eq->middle, eq->front, memory_order_acq_rel) & 3u;
        atomic_store_explicit(&eq->settled, false, memory_order_relaxed);
        eq->next.parameters = eq->slots[eq->front];
        // Preserve signal history when tuning. Rebuild transposed states for the
        // new coefficients instead of restarting every filter from silence.
        for (unsigned ch = 0; ch < eq->channels; ++ch) for (unsigned b = 0; b < BANDS; ++b) {
            EQDelay d = eq->current.parameters.active ? eq->current.delays[ch][b] : (EQDelay){0};
            Coefficients c = eq->next.parameters.bands[b];
            d.z1 = c.b1*d.x1 + c.b2*d.x2 - c.a1*d.y1 - c.a2*d.y2;
            d.z2 = c.b2*d.x1 - c.a2*d.y1;
            eq->next.delays[ch][b] = d;
        }
        memset(eq->progress, 0, sizeof(eq->progress));
        eq->transitioning = true;
    } else {
        bool restored = eq->current.parameters.active || eq->linkedPeak.gain >= 1;
        if (!eq->current.parameters.active)
            for (unsigned ch = 0; ch < eq->channels; ++ch) restored &= eq->scalarPeaks[ch].gain >= 1;
        atomic_store_explicit(&eq->settled, restored, memory_order_release);
    }
}
static double filter(Bank *bank, double sample, uint32_t channel) {
    if (!bank->parameters.active) return sample;
    double value = sample;
    for (unsigned b = 0; b < BANDS; ++b) {
        Coefficients c = bank->parameters.bands[b];
        EQDelay *d = &bank->delays[channel][b];
        double y = c.b0 * value + d->z1;
        d->z1 = c.b1 * value - c.a1 * y + d->z2;
        d->z2 = c.b2 * value - c.a2 * y;
        d->x2 = d->x1; d->x1 = value;
        d->y2 = d->y1; d->y1 = y;
        // Avoid denormal slowdowns during long silence.
        if (fabs(d->z1) < 1e-24) d->z1 = 0;
        if (fabs(d->z2) < 1e-24) d->z2 = 0;
        value = y;
    }
    return isfinite(value) ? value : 0;
}
// A held peak envelope scales the waveform; it does not reshape every peak like
// tanh/clipping. Instant attack prevents overs, 50 ms hold spans low-frequency
// cycles, and 200 ms release avoids audio-rate gain modulation.
static double envelopeGain(Equalizer *eq, PeakEnvelope *envelope, double peak) {
    double requested = peak > 0.98 ? 0.98 / peak : 1;
    if (requested < envelope->gain) {
        envelope->gain = requested;
        envelope->hold = eq->peakHoldFrames;
    } else if (requested <= envelope->gain * 1.001 && requested < 1) {
        envelope->hold = eq->peakHoldFrames;
    } else if (envelope->hold > 0) {
        envelope->hold--;
    } else {
        envelope->gain += (requested - envelope->gain) * eq->releaseStep;
    }
    return envelope->gain;
}
static double restoreUnity(Equalizer *eq, PeakEnvelope *envelope) {
    envelope->hold = 0;
    envelope->gain = fmin(1, envelope->gain + 1.0 / eq->fadeFrames);
    return envelope->gain;
}
static double filteredSample(Equalizer *eq, double sample, uint32_t channel) {
    if (!isfinite(sample)) sample = 0;
    double value = filter(&eq->current, sample, channel);
    if (eq->transitioning) {
        uint32_t progress = eq->progress[channel];
        double mix = fmin(1, (double)progress / eq->fadeFrames);
        if (progress < eq->fadeFrames) eq->progress[channel]++;
        value = value * (1 - mix) + filter(&eq->next, sample, channel) * mix;
    }
    return value;
}
static bool hasEffect(Equalizer *eq) {
    return eq->current.parameters.active || (eq->transitioning && eq->next.parameters.active);
}
void MacMixEQProcessFrame(void *context, double *samples, uint32_t channels) {
    Equalizer *eq = context;
    if (!eq || !samples || channels != eq->channels) return;
    if (!eq->current.parameters.active && !eq->transitioning && eq->linkedPeak.gain == 1) {
        for (unsigned ch = 0; ch < channels; ++ch) if (!isfinite(samples[ch])) samples[ch] = 0;
        return;
    }
    double peak = 0;
    for (unsigned ch = 0; ch < channels; ++ch) {
        samples[ch] = filteredSample(eq, samples[ch], ch);
        peak = fmax(peak, fabs(samples[ch]));
    }
    double gain = hasEffect(eq) ? envelopeGain(eq, &eq->linkedPeak, peak) : restoreUnity(eq, &eq->linkedPeak);
    for (unsigned ch = 0; ch < channels; ++ch) samples[ch] *= gain;
}
// Scalar helper for mono/offline consumers. The app always uses ProcessFrame so
// stereo/multichannel attenuation is linked, including noninterleaved buffers.
double MacMixEQProcessSample(void *context, double sample, uint32_t channel) {
    Equalizer *eq = context;
    if (!eq || channel >= eq->channels) return sample;
    double value = filteredSample(eq, sample, channel);
    double gain = hasEffect(eq) ? envelopeGain(eq, &eq->scalarPeaks[channel], fabs(value))
        : restoreUnity(eq, &eq->scalarPeaks[channel]);
    return value * gain;
}
bool MacMixEQIsSettled(void *context) {
    Equalizer *eq = context;
    return !eq || (atomic_load_explicit(&eq->settled, memory_order_acquire)
        && !(atomic_load_explicit(&eq->middle, memory_order_acquire) & DIRTY));
}
void MacMixEQSetMetering(void *context, bool enabled) {
    Equalizer *eq = context;
    if (!eq) return;
    bool wasEnabled = atomic_exchange_explicit(&eq->meterRequested, enabled, memory_order_relaxed);
    if (enabled && !wasEnabled && (atomic_load_explicit(&eq->meterMiddle, memory_order_acquire) & DIRTY)) {
        // Discard frames retained from the previous visible interval.
        eq->meterFront = atomic_exchange_explicit(&eq->meterMiddle, eq->meterFront, memory_order_acq_rel) & 3u;
    }
}
bool MacMixEQMeteringIsActive(void *context) {
    Equalizer *eq = context;
    return eq && eq->meterActive;
}
void MacMixEQObserveSample(void *context, double outputSample, uint32_t channel) {
    Equalizer *eq = context;
    if (!eq || !eq->meterActive || channel >= eq->channels) return;
    unsigned offset = eq->meterOffsets[channel];
    eq->meterRing[channel * FFT_SIZE + offset] = isfinite(outputSample) ? (float)outputSample : 0;
    eq->meterOffsets[channel] = (offset + 1) % FFT_SIZE;
    if (eq->meterSampleCounts[channel] < FFT_SIZE) eq->meterSampleCounts[channel]++;
    if (channel == 0) eq->meterHop++;
}
void MacMixEQEndBlock(void *context) {
    Equalizer *eq = context;
    if (!eq || !eq->meterActive || eq->meterHop < 512) return;
    for (unsigned ch = 0; ch < eq->channels; ++ch) {
        if (eq->meterSampleCounts[ch] < FFT_SIZE) return;
    }
    eq->meterHop = 0;
    for (unsigned ch = 0; ch < eq->channels; ++ch) {
        unsigned offset = eq->meterOffsets[ch];
        float *destination = eq->meterSlots[eq->meterBack] + ch * FFT_SIZE;
        const float *source = eq->meterRing + ch * FFT_SIZE;
        memcpy(destination, source + offset, (FFT_SIZE - offset) * sizeof(float));
        memcpy(destination + FFT_SIZE - offset, source, offset * sizeof(float));
    }
    eq->meterBack = atomic_exchange_explicit(&eq->meterMiddle, eq->meterBack | DIRTY, memory_order_acq_rel) & 3u;
}
bool MacMixEQCopySpectrum(void *context, float *bars, size_t count) {
    Equalizer *eq = context;
    if (!eq || !bars || count != SPECTRUM_BARS
        || !atomic_load_explicit(&eq->meterRequested, memory_order_relaxed)
        || !(atomic_load_explicit(&eq->meterMiddle, memory_order_acquire) & DIRTY)) return false;
    eq->meterFront = atomic_exchange_explicit(&eq->meterMiddle, eq->meterFront, memory_order_acq_rel) & 3u;
    memset(eq->powers, 0, sizeof(eq->powers));
    DSPSplitComplex spectrum = {eq->real, eq->imaginary};
    const double normalization = eq->spectrumNormalization;
    for (unsigned ch = 0; ch < eq->channels; ++ch) {
        const float *source = eq->meterSlots[eq->meterFront] + ch * FFT_SIZE;
        vDSP_vmul(source, 1, eq->window, 1, eq->fftInput, 1, FFT_SIZE);
        vDSP_ctoz((const DSPComplex *)eq->fftInput, 2, &spectrum, 1, FFT_SIZE / 2);
        vDSP_fft_zrip(eq->fft, &spectrum, 1, FFT_LOG2, FFT_FORWARD);
        for (unsigned bin = 1; bin < FFT_SIZE / 2; ++bin) {
            eq->powers[bin] += (eq->real[bin] * eq->real[bin] + eq->imaginary[bin] * eq->imaginary[bin]) / eq->channels;
        }
    }
    // Combine channel energy, not samples: opposite-phase stereo must still be visible.
    for (unsigned bar = 0; bar < SPECTRUM_BARS; ++bar) {
        double frequency = 32 * pow(500, (double)bar / (SPECTRUM_BARS - 1));
        if (frequency >= eq->sampleRate * 0.5) { bars[bar] = 0; continue; }
        double bin = frequency * FFT_SIZE / eq->sampleRate;
        double ratio = pow(500, 0.5 / (SPECTRUM_BARS - 1));
        float power = 0;
        if (bin * (ratio - 1 / ratio) < 1) {
            // Interpolate narrow bands instead of duplicating the same peak bin.
            unsigned lower = (unsigned)fmax(1, fmin(FFT_SIZE / 2 - 2, floor(bin)));
            double fraction = fmax(0, fmin(1, bin - lower));
            power = eq->powers[lower] * (1 - fraction) + eq->powers[lower + 1] * fraction;
        } else {
            unsigned lo = (unsigned)fmax(1, ceil(bin / ratio));
            unsigned hi = (unsigned)fmin(FFT_SIZE / 2 - 1, floor(bin * ratio));
            for (unsigned i = lo; i <= hi; ++i) power = fmaxf(power, eq->powers[i]);
        }
        double amplitude = sqrt(power) * normalization;
        double decibels = 20 * log10(fmax(1e-12, amplitude));
        bars[bar] = (float)fmax(0, fmin(1, (decibels + 72) / 72));
    }
    return true;
}
void MacMixEQDestroy(void *context) {
    Equalizer *eq = context;
    if (!eq) return;
    if (eq->fft) vDSP_destroy_fftsetup(eq->fft);
    free(eq->meterRing);
    for (unsigned i = 0; i < 3; ++i) free(eq->meterSlots[i]);
    free(eq);
}
