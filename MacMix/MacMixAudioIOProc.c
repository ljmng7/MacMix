#include "MacMixAudioIOProc.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>
#include <mach/mach_time.h>

static const double kMacMixRampDurationSeconds = 0.04;
static const double kMacMixFallbackSampleRate = 48000.0;
static const float kMacMixMaximumGain = 2.0f;

_Static_assert(
    ATOMIC_INT_LOCK_FREE == 2,
    "The realtime gain state requires lock-free 32-bit atomics"
);

typedef struct {
    AudioStreamBasicDescription format;
    uint32_t inputBufferOffset;
    uint32_t inputBufferCount;
    uint32_t outputBufferOffset;
    _Atomic(uint32_t) targetGainBits;
    _Atomic(uint32_t) renderedGainBits;
    float currentGain;
    float lastTargetGain;
    uint32_t remainingRampFrames;
    void *effect;
    void (*beginEffectBlock)(void *);
    double (*processEffectSample)(void *, double, uint32_t);
    void (*destroyEffect)(void *);
    void (*processEffectFrame)(void *, double *, uint32_t);
    bool (*meterIsActive)(void *);
    void (*observeSample)(void *, double, uint32_t);
    void (*endEffectBlock)(void *);
    bool metersOutput;
    bool routesOutput;
    size_t outputChannelCount;
    MacMixAudioOutputChannel *outputChannels;
    float *destinationGains;
    _Atomic(uint64_t) destinationMask;
} MacMixAudioTapState;

typedef struct {
    uint64_t start;
    uint64_t duration;
    float from;
    float to;
} MacMixOutputFade;

typedef struct {
    _Atomic(size_t) referenceCount;
    size_t tapCount;
    MacMixAudioTapState *taps;
    size_t outputBufferIndexCount;
    uint32_t *outputBufferIndices;
    bool hasRoutedOutput;
    MacMixAudioTapState outputGain;
    _Atomic(uint64_t) renderedFrames;
    double hostTicksPerSecond;
    _Atomic(uint32_t) fadeRevision;
    _Atomic(uint64_t) fadeStart;
    _Atomic(uint64_t) fadeDuration;
    _Atomic(uint32_t) fadeFrom;
    _Atomic(uint32_t) fadeTo;
    uint32_t cachedFadeRevision;
    MacMixOutputFade cachedFade;
} MacMixAudioIOContext;

typedef struct {
    float start;
    float end;
    uint32_t frameCount;
} MacMixGainRamp;

typedef struct {
    MacMixGainRamp ramp;
    bool timed;
    double progress;
    double step;
    float from;
    float to;
} MacMixOutputEnvelope;

static uint32_t MacMixFloatBits(float value) {
    uint32_t bits;
    memcpy(&bits, &value, sizeof(bits));
    return bits;
}

static float MacMixFloatFromBits(uint32_t bits) {
    float value;
    memcpy(&value, &bits, sizeof(value));
    return value;
}

static float MacMixClampGain(float gain) {
    if (!isfinite(gain) || gain <= 0.0f) {
        return 0.0f;
    }
    return gain >= kMacMixMaximumGain ? kMacMixMaximumGain : gain;
}

MacMixAudioIOContextRef MacMixAudioIOContextCreate(
    const MacMixAudioTapConfiguration *configurations,
    size_t configurationCount,
    const uint32_t *outputBufferIndices,
    size_t outputBufferIndexCount
) {
    if (configurations == NULL || configurationCount == 0
        || outputBufferIndices == NULL || outputBufferIndexCount == 0) {
        return NULL;
    }

    MacMixAudioIOContext *context = calloc(1, sizeof(*context));
    if (context == NULL) {
        return NULL;
    }
    atomic_init(&context->referenceCount, 1);
    atomic_init(&context->renderedFrames, 0);
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    context->hostTicksPerSecond = 1e9 * timebase.denom / timebase.numer;
    atomic_init(&context->fadeRevision, 0);
    atomic_init(&context->fadeStart, 0);
    atomic_init(&context->fadeDuration, 0);
    atomic_init(&context->fadeFrom, MacMixFloatBits(1));
    atomic_init(&context->fadeTo, MacMixFloatBits(1));
    context->outputGain.format = configurations[0].format;
    atomic_init(&context->outputGain.targetGainBits, MacMixFloatBits(1));
    atomic_init(&context->outputGain.renderedGainBits, MacMixFloatBits(1));
    context->outputGain.currentGain = 1;
    context->outputGain.lastTargetGain = 1;

    context->taps = calloc(configurationCount, sizeof(*context->taps));
    context->outputBufferIndices = calloc(
        outputBufferIndexCount,
        sizeof(*context->outputBufferIndices)
    );
    if (context->taps == NULL || context->outputBufferIndices == NULL) {
        MacMixAudioIOContextDestroy(context);
        return NULL;
    }

    context->tapCount = configurationCount;
    context->outputBufferIndexCount = outputBufferIndexCount;
    memcpy(
        context->outputBufferIndices,
        outputBufferIndices,
        outputBufferIndexCount * sizeof(*outputBufferIndices)
    );

    for (size_t index = 0; index < configurationCount; ++index) {
        const MacMixAudioTapConfiguration configuration = configurations[index];
        MacMixAudioTapState *state = &context->taps[index];
        const float initialGain = MacMixClampGain(configuration.initialGain);
        const float targetGain = MacMixClampGain(configuration.targetGain);
        state->format = configuration.format;
        state->inputBufferOffset = configuration.inputBufferOffset;
        state->inputBufferCount = configuration.inputBufferCount;
        state->outputBufferOffset = configuration.outputBufferOffset;
        atomic_init(&state->destinationMask, UINT64_MAX);
        atomic_init(&state->targetGainBits, MacMixFloatBits(targetGain));
        atomic_init(&state->renderedGainBits, MacMixFloatBits(initialGain));
        state->currentGain = initialGain;
        state->lastTargetGain = initialGain;
    }

    return context;
}

void MacMixAudioIOContextRetain(MacMixAudioIOContextRef contextReference) {
    MacMixAudioIOContext *context = contextReference;
    if (context != NULL) {
        atomic_fetch_add_explicit(&context->referenceCount, 1, memory_order_relaxed);
    }
}

void MacMixAudioIOContextDestroy(MacMixAudioIOContextRef contextReference) {
    MacMixAudioIOContext *context = contextReference;
    if (context == NULL) {
        return;
    }
    if (atomic_fetch_sub_explicit(
        &context->referenceCount,
        1,
        memory_order_acq_rel
    ) != 1) {
        return;
    }

    free(context->outputBufferIndices);
    for (size_t i = 0; context->taps && i < context->tapCount; ++i) {
        if (context->taps[i].destroyEffect) context->taps[i].destroyEffect(context->taps[i].effect);
        free(context->taps[i].outputChannels);
        free(context->taps[i].destinationGains);
    }
    free(context->taps);
    free(context);
}

bool MacMixAudioIOContextSetOutputChannels(MacMixAudioIOContextRef reference,
    size_t index, const MacMixAudioOutputChannel *channels, size_t count) {
    MacMixAudioIOContext *context = reference;
    if (!context || index >= context->tapCount || count > 256 || (count && !channels)) return false;
    MacMixAudioOutputChannel *copy = count ? calloc(count, sizeof(*copy)) : NULL;
    float *gains = count ? calloc(count, sizeof(*gains)) : NULL;
    if (count && (!copy || !gains)) { free(copy); free(gains); return false; }
    for (size_t i = 0; i < count; ++i) {
        if (channels[i].destinationIndex >= 64) { free(copy); free(gains); return false; }
        gains[i] = 1;
    }
    if (count) memcpy(copy, channels, count * sizeof(*copy));
    MacMixAudioTapState *state = &context->taps[index];
    free(state->outputChannels);
    free(state->destinationGains);
    state->outputChannels = copy;
    state->destinationGains = gains;
    state->outputChannelCount = count;
    state->routesOutput = true;
    context->hasRoutedOutput = true;
    return true;
}

void MacMixAudioIOContextSetDestinationMask(MacMixAudioIOContextRef reference,
    size_t index, uint64_t mask, bool initializeBeforeStart) {
    MacMixAudioIOContext *context = reference;
    if (index >= context->tapCount) return;
    MacMixAudioTapState *state = &context->taps[index];
    if (initializeBeforeStart) {
        for (size_t i = 0; i < state->outputChannelCount; ++i)
            state->destinationGains[i] = (mask & (UINT64_C(1) << state->outputChannels[i].destinationIndex)) ? 1 : 0;
    }
    atomic_store_explicit(&state->destinationMask, mask, memory_order_relaxed);
}

void MacMixAudioIOContextSetInitialOutputGain(MacMixAudioIOContextRef reference, float gain) {
    MacMixAudioIOContext *context = reference;
    gain = fminf(1, MacMixClampGain(gain));
    context->outputGain.currentGain = gain;
    context->outputGain.lastTargetGain = gain;
    context->outputGain.remainingRampFrames = 0;
    atomic_store(&context->outputGain.targetGainBits, MacMixFloatBits(gain));
    atomic_store(&context->outputGain.renderedGainBits, MacMixFloatBits(gain));
}
void MacMixAudioIOContextSetOutputGain(MacMixAudioIOContextRef reference, float gain) {
    MacMixAudioIOContext *context = reference;
    atomic_store_explicit(&context->outputGain.targetGainBits,
        MacMixFloatBits(fminf(1, MacMixClampGain(gain))), memory_order_relaxed);
    atomic_fetch_add_explicit(&context->fadeRevision, 1, memory_order_acq_rel);
    atomic_store_explicit(&context->fadeDuration, 0, memory_order_relaxed);
    atomic_fetch_add_explicit(&context->fadeRevision, 1, memory_order_release);
}
uint64_t MacMixAudioOutputFadeStartTime(double delaySeconds) {
    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    double seconds = isfinite(delaySeconds) ? fmax(0, fmin(1, delaySeconds)) : 0;
    return mach_absolute_time() + (uint64_t)(seconds * 1e9 * timebase.denom / timebase.numer);
}
void MacMixAudioIOContextScheduleOutputGain(MacMixAudioIOContextRef reference,
    float from, float to, uint64_t startHostTime, double durationSeconds) {
    MacMixAudioIOContext *context = reference;
    double seconds = isfinite(durationSeconds) ? fmax(0.001, fmin(1, durationSeconds)) : 0.04;
    from = fminf(1, MacMixClampGain(from)); to = fminf(1, MacMixClampGain(to));
    atomic_fetch_add_explicit(&context->fadeRevision, 1, memory_order_acq_rel);
    atomic_store_explicit(&context->fadeStart, startHostTime, memory_order_relaxed);
    atomic_store_explicit(&context->fadeDuration, (uint64_t)(seconds * context->hostTicksPerSecond), memory_order_relaxed);
    atomic_store_explicit(&context->fadeFrom, MacMixFloatBits(from), memory_order_relaxed);
    atomic_store_explicit(&context->fadeTo, MacMixFloatBits(to), memory_order_relaxed);
    atomic_fetch_add_explicit(&context->fadeRevision, 1, memory_order_release);
}
float MacMixAudioIOContextRenderedOutputGain(MacMixAudioIOContextRef reference) {
    MacMixAudioIOContext *context = reference;
    return MacMixFloatFromBits(atomic_load_explicit(&context->outputGain.renderedGainBits, memory_order_relaxed));
}
uint64_t MacMixAudioIOContextRenderedFrames(MacMixAudioIOContextRef reference) {
    MacMixAudioIOContext *context = reference;
    return atomic_load_explicit(&context->renderedFrames, memory_order_relaxed);
}

OSStatus MacMixAudioDisablePhysicalInputs(AudioObjectID device, AudioDeviceIOProcID ioProc,
    uint32_t physicalStreamCount, uint32_t totalStreamCount) {
    if (!physicalStreamCount) return noErr;
    if (physicalStreamCount > totalStreamCount || totalStreamCount > 4096) return kAudioHardwareIllegalOperationError;
    size_t size = offsetof(AudioHardwareIOProcStreamUsage, mStreamIsOn) + totalStreamCount * sizeof(UInt32);
    AudioHardwareIOProcStreamUsage *usage = calloc(1, size);
    if (!usage) return kAudioHardwareUnspecifiedError;
    usage->mIOProc = (void *)ioProc;
    usage->mNumberStreams = totalStreamCount;
    for (uint32_t i = physicalStreamCount; i < totalStreamCount; ++i) usage->mStreamIsOn[i] = 1;
    AudioObjectPropertyAddress address = { kAudioDevicePropertyIOProcStreamUsage,
        kAudioDevicePropertyScopeInput, kAudioObjectPropertyElementMain };
    OSStatus result = AudioObjectSetPropertyData(device, &address, 0, NULL, (UInt32)size, usage);
    free(usage);
    return result;
}

void MacMixAudioIOContextSetTargetGain(
    MacMixAudioIOContextRef contextReference,
    size_t configurationIndex,
    float gain
) {
    MacMixAudioIOContext *context = contextReference;
    if (context == NULL || configurationIndex >= context->tapCount) {
        return;
    }

    atomic_store_explicit(
        &context->taps[configurationIndex].targetGainBits,
        MacMixFloatBits(MacMixClampGain(gain)),
        memory_order_relaxed
    );
}

void MacMixAudioIOContextSetEffect(MacMixAudioIOContextRef reference, size_t index,
    void *effect, void (*beginBlock)(void *),
    double (*processSample)(void *, double, uint32_t), void (*destroy)(void *)) {
    MacMixAudioIOContext *context = reference;
    if (!context || index >= context->tapCount) return;
    MacMixAudioTapState *state = &context->taps[index];
    state->effect = effect;
    state->beginEffectBlock = beginBlock;
    state->processEffectSample = processSample;
    state->destroyEffect = destroy;
}

void MacMixAudioIOContextSetFrameEffect(MacMixAudioIOContextRef reference, size_t index,
    void (*processFrame)(void *, double *, uint32_t)) {
    MacMixAudioIOContext *context = reference;
    if (context && index < context->tapCount) context->taps[index].processEffectFrame = processFrame;
}

void MacMixAudioIOContextSetMeter(MacMixAudioIOContextRef reference, size_t index,
    bool (*isActive)(void *), void (*observeSample)(void *, double, uint32_t),
    void (*endBlock)(void *)) {
    MacMixAudioIOContext *context = reference;
    if (!context || index >= context->tapCount) return;
    MacMixAudioTapState *state = &context->taps[index];
    state->meterIsActive = isActive;
    state->observeSample = observeSample;
    state->endEffectBlock = endBlock;
}

static double MacMixProcessedSample(MacMixAudioTapState *state, double sample, uint32_t channel, double gain) {
    const double input = sample * gain;
    const double output = state->processEffectSample ? state->processEffectSample(state->effect, input, channel) : input;
    if (state->metersOutput) state->observeSample(state->effect, output, channel);
    return output;
}

float MacMixAudioIOContextRenderedGain(
    MacMixAudioIOContextRef contextReference,
    size_t configurationIndex
) {
    MacMixAudioIOContext *context = contextReference;
    if (context == NULL || configurationIndex >= context->tapCount) {
        return 0.0f;
    }

    const uint32_t bits = atomic_load_explicit(
        &context->taps[configurationIndex].renderedGainBits,
        memory_order_relaxed
    );
    return MacMixFloatFromBits(bits);
}

static MacMixGainRamp MacMixNextRamp(
    MacMixAudioTapState *state,
    uint32_t frameCount
) {
    const uint32_t targetBits = atomic_load_explicit(
        &state->targetGainBits,
        memory_order_relaxed
    );
    const float target = MacMixFloatFromBits(targetBits);
    if (fabsf(target - state->lastTargetGain) > 0.0001f) {
        state->lastTargetGain = target;
        const double sampleRate = isfinite(state->format.mSampleRate)
            && state->format.mSampleRate > 0.0
            ? state->format.mSampleRate
            : kMacMixFallbackSampleRate;
        const double rampFrameCount = fmin(
            sampleRate * kMacMixRampDurationSeconds,
            (double)UINT32_MAX
        );
        state->remainingRampFrames = (uint32_t)fmax(ceil(rampFrameCount), 1.0);
    }

    const float start = state->currentGain;
    if (state->remainingRampFrames == 0 || frameCount == 0) {
        state->currentGain = target;
        return (MacMixGainRamp){ target, target, 0 };
    }

    const uint32_t framesThisBuffer = frameCount < state->remainingRampFrames
        ? frameCount
        : state->remainingRampFrames;
    const float progress = (float)framesThisBuffer / (float)state->remainingRampFrames;
    state->currentGain += (target - state->currentGain) * progress;
    state->remainingRampFrames -= framesThisBuffer;
    if (state->remainingRampFrames == 0) {
        state->currentGain = target;
    }

    return (MacMixGainRamp){ start, state->currentGain, framesThisBuffer };
}

static float MacMixGainForSample(
    size_t sampleIndex,
    size_t channelCount,
    size_t frameCount,
    size_t rampFrameCount,
    MacMixGainRamp ramp
) {
    const size_t frame = sampleIndex / channelCount < frameCount
        ? sampleIndex / channelCount
        : frameCount - 1;
    if (frame >= rampFrameCount) {
        return ramp.end;
    }

    const float gainStep = rampFrameCount > 0
        ? (ramp.end - ramp.start) / (float)rampFrameCount
        : 0.0f;
    return ramp.start + (float)frame * gainStep;
}

static int32_t MacMixReadInt32Bytes(const uint8_t *source, bool isBigEndian) {
    uint32_t raw;
    if (isBigEndian) {
        raw = (uint32_t)source[0] << 24
            | (uint32_t)source[1] << 16
            | (uint32_t)source[2] << 8
            | (uint32_t)source[3];
    } else {
        raw = (uint32_t)source[0]
            | (uint32_t)source[1] << 8
            | (uint32_t)source[2] << 16
            | (uint32_t)source[3] << 24;
    }
    return (int32_t)raw;
}

static void MacMixWriteInt32Bytes(int32_t sample, uint8_t *destination, bool isBigEndian) {
    const uint32_t raw = (uint32_t)sample;
    if (isBigEndian) {
        destination[0] = (uint8_t)(raw >> 24);
        destination[1] = (uint8_t)(raw >> 16);
        destination[2] = (uint8_t)(raw >> 8);
        destination[3] = (uint8_t)raw;
    } else {
        destination[0] = (uint8_t)raw;
        destination[1] = (uint8_t)(raw >> 8);
        destination[2] = (uint8_t)(raw >> 16);
        destination[3] = (uint8_t)(raw >> 24);
    }
}

static int32_t MacMixSignExtendInt24(int32_t value) {
    return (value & 0x00800000) != 0 ? value | (int32_t)0xFF000000 : value;
}

static int32_t MacMixReadInt24(
    const uint8_t *source,
    size_t bytesPerSample,
    bool isBigEndian,
    bool isAlignedHigh
) {
    if (bytesPerSample == 4) {
        const int32_t raw32 = MacMixReadInt32Bytes(source, isBigEndian);
        return isAlignedHigh
            ? raw32 >> 8
            : MacMixSignExtendInt24(raw32 & 0x00FFFFFF);
    }

    const int32_t raw24 = isBigEndian
        ? (int32_t)source[0] << 16 | (int32_t)source[1] << 8 | (int32_t)source[2]
        : (int32_t)source[0] | (int32_t)source[1] << 8 | (int32_t)source[2] << 16;
    return MacMixSignExtendInt24(raw24);
}

static void MacMixWriteInt24(
    int32_t sample,
    uint8_t *destination,
    size_t bytesPerSample,
    bool isBigEndian,
    bool isAlignedHigh
) {
    if (bytesPerSample == 4) {
        const int32_t raw32 = isAlignedHigh ? sample << 8 : sample & 0x00FFFFFF;
        MacMixWriteInt32Bytes(raw32, destination, isBigEndian);
        return;
    }

    const uint32_t raw24 = (uint32_t)sample & 0x00FFFFFF;
    if (isBigEndian) {
        destination[0] = (uint8_t)(raw24 >> 16);
        destination[1] = (uint8_t)(raw24 >> 8);
        destination[2] = (uint8_t)raw24;
    } else {
        destination[0] = (uint8_t)raw24;
        destination[1] = (uint8_t)(raw24 >> 8);
        destination[2] = (uint8_t)(raw24 >> 16);
    }
}

static bool MacMixMixAudioBuffer(
    const AudioBuffer *inputBuffer,
    AudioBuffer *outputBuffer,
    MacMixGainRamp ramp,
    AudioStreamBasicDescription format,
    MacMixAudioTapState *state, uint32_t channelOffset
) {
    if (inputBuffer->mData == NULL || outputBuffer->mData == NULL
        || inputBuffer->mNumberChannels != outputBuffer->mNumberChannels
        || format.mFormatID != kAudioFormatLinearPCM) {
        return false;
    }

    const size_t byteCount = inputBuffer->mDataByteSize < outputBuffer->mDataByteSize
        ? inputBuffer->mDataByteSize
        : outputBuffer->mDataByteSize;
    if (byteCount == 0) {
        return false;
    }

    const size_t requestedChannelCount = inputBuffer->mNumberChannels > 0
        ? inputBuffer->mNumberChannels
        : 1;
    const bool isFloat = (format.mFormatFlags & kAudioFormatFlagIsFloat) != 0;
    const bool isSignedInteger = (format.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0;

    if (isFloat && format.mBitsPerChannel == 32) {
        const size_t sampleCount = byteCount / sizeof(float);
        if (sampleCount == 0) {
            return true;
        }
        const size_t channelCount = requestedChannelCount < sampleCount
            ? requestedChannelCount
            : sampleCount;
        const size_t frameCount = sampleCount / channelCount;
        const size_t rampFrameCount = ramp.frameCount < frameCount
            ? ramp.frameCount
            : frameCount;
        const size_t rampSampleCount = rampFrameCount * channelCount;
        const float gainStep = rampFrameCount > 0
            ? (ramp.end - ramp.start) / (float)rampFrameCount
            : 0.0f;
        const float *source = inputBuffer->mData;
        float *destination = outputBuffer->mData;
        for (size_t index = 0; index < rampSampleCount; ++index) {
            const float gain = ramp.start + (float)(index / channelCount) * gainStep;
            destination[index] += MacMixProcessedSample(state, source[index], channelOffset + (uint32_t)(index % channelCount), gain);
        }
        if (ramp.end != 0.0f || state->processEffectSample) {
            for (size_t index = rampSampleCount; index < sampleCount; ++index) {
                destination[index] += MacMixProcessedSample(state, source[index], channelOffset + (uint32_t)(index % channelCount), ramp.end);
            }
        }
        return true;
    }

    if (isFloat && format.mBitsPerChannel == 64) {
        const size_t sampleCount = byteCount / sizeof(double);
        if (sampleCount == 0) {
            return true;
        }
        const size_t channelCount = requestedChannelCount < sampleCount
            ? requestedChannelCount
            : sampleCount;
        const size_t frameCount = sampleCount / channelCount;
        const size_t rampFrameCount = ramp.frameCount < frameCount
            ? ramp.frameCount
            : frameCount;
        const size_t rampSampleCount = rampFrameCount * channelCount;
        const double startGain = (double)ramp.start;
        const double gainStep = rampFrameCount > 0
            ? ((double)ramp.end - startGain) / (double)rampFrameCount
            : 0.0;
        const double *source = inputBuffer->mData;
        double *destination = outputBuffer->mData;
        for (size_t index = 0; index < rampSampleCount; ++index) {
            const double gain = startGain + (double)(index / channelCount) * gainStep;
            destination[index] += MacMixProcessedSample(state, source[index], channelOffset + (uint32_t)(index % channelCount), gain);
        }
        if (ramp.end != 0.0f || state->processEffectSample) {
            for (size_t index = rampSampleCount; index < sampleCount; ++index) {
                destination[index] += MacMixProcessedSample(state, source[index], channelOffset + (uint32_t)(index % channelCount), (double)ramp.end);
            }
        }
        return true;
    }

    if (isSignedInteger && format.mBitsPerChannel == 16) {
        const size_t sampleCount = byteCount / sizeof(int16_t);
        if (sampleCount == 0) {
            return true;
        }
        const size_t channelCount = requestedChannelCount < sampleCount
            ? requestedChannelCount
            : sampleCount;
        const size_t frameCount = sampleCount / channelCount;
        const size_t rampFrameCount = ramp.frameCount < frameCount
            ? ramp.frameCount
            : frameCount;
        const int16_t *source = inputBuffer->mData;
        int16_t *destination = outputBuffer->mData;
        for (size_t index = 0; index < sampleCount; ++index) {
            const float gain = MacMixGainForSample(
                index, channelCount, frameCount, rampFrameCount, ramp
            );
            const double mixed = (double)destination[index] + MacMixProcessedSample(state, (double)source[index] / 32768.0, channelOffset + (uint32_t)(index % channelCount), gain) * 32768.0;
            const double clamped = fmax(INT16_MIN, fmin(INT16_MAX, round(mixed)));
            destination[index] = (int16_t)clamped;
        }
        return true;
    }

    if (isSignedInteger && format.mBitsPerChannel == 32) {
        const size_t sampleCount = byteCount / sizeof(int32_t);
        if (sampleCount == 0) {
            return true;
        }
        const size_t channelCount = requestedChannelCount < sampleCount
            ? requestedChannelCount
            : sampleCount;
        const size_t frameCount = sampleCount / channelCount;
        const size_t rampFrameCount = ramp.frameCount < frameCount
            ? ramp.frameCount
            : frameCount;
        const int32_t *source = inputBuffer->mData;
        int32_t *destination = outputBuffer->mData;
        for (size_t index = 0; index < sampleCount; ++index) {
            const float gain = MacMixGainForSample(
                index, channelCount, frameCount, rampFrameCount, ramp
            );
            const double mixed = (double)destination[index] + MacMixProcessedSample(state, (double)source[index] / 2147483648.0, channelOffset + (uint32_t)(index % channelCount), gain) * 2147483648.0;
            const double clamped = fmax(INT32_MIN, fmin(INT32_MAX, round(mixed)));
            destination[index] = (int32_t)clamped;
        }
        return true;
    }

    if (isSignedInteger && format.mBitsPerChannel == 24) {
        const bool isBigEndian = (format.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0;
        const bool isAlignedHigh = (format.mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0;
        const bool isNonInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0;
        const size_t channelsPerFrame = format.mChannelsPerFrame > 0
            ? format.mChannelsPerFrame
            : 1;
        const size_t bytesPerFrame = format.mBytesPerFrame;
        const size_t bytesPerSample = bytesPerFrame > 0
            ? (isNonInterleaved ? bytesPerFrame : bytesPerFrame / channelsPerFrame)
            : 3;
        if (bytesPerSample != 3 && bytesPerSample != 4) {
            return false;
        }

        const size_t sampleCount = byteCount / bytesPerSample;
        if (sampleCount == 0) {
            return true;
        }
        const size_t channelCount = requestedChannelCount < sampleCount
            ? requestedChannelCount
            : sampleCount;
        const size_t frameCount = sampleCount / channelCount;
        const size_t rampFrameCount = ramp.frameCount < frameCount
            ? ramp.frameCount
            : frameCount;
        const uint8_t *source = inputBuffer->mData;
        uint8_t *destination = outputBuffer->mData;
        for (size_t index = 0; index < sampleCount; ++index) {
            const float gain = MacMixGainForSample(
                index, channelCount, frameCount, rampFrameCount, ramp
            );
            const size_t offset = index * bytesPerSample;
            const int32_t sourceSample = MacMixReadInt24(
                source + offset, bytesPerSample, isBigEndian, isAlignedHigh
            );
            const int32_t destinationSample = MacMixReadInt24(
                destination + offset, bytesPerSample, isBigEndian, isAlignedHigh
            );
            const double mixed = (double)destinationSample + MacMixProcessedSample(state, (double)sourceSample / 8388608.0, channelOffset + (uint32_t)(index % channelCount), gain) * 8388608.0;
            const int32_t clamped = (int32_t)fmax(-8388608, fmin(8388607, round(mixed)));
            MacMixWriteInt24(
                clamped, destination + offset, bytesPerSample, isBigEndian, isAlignedHigh
            );
        }
        return true;
    }

    return false;
}

// Frame-level effects see every channel together, regardless of HAL buffer layout.
// This is necessary for linked dynamics: independent L/R limiters alter stereo balance.
static size_t MacMixSampleBytes(AudioStreamBasicDescription format) {
    size_t channels = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : format.mChannelsPerFrame;
    return channels ? format.mBytesPerFrame / channels : 0;
}
static bool MacMixEffectFormatSupported(AudioStreamBasicDescription format, size_t bytes) {
    if (format.mFormatID != kAudioFormatLinearPCM) return false;
    if (format.mFormatFlags & kAudioFormatFlagIsFloat)
        return !(format.mFormatFlags & kAudioFormatFlagIsBigEndian)
            && ((format.mBitsPerChannel == 32 && bytes == 4) || (format.mBitsPerChannel == 64 && bytes == 8));
    if (!(format.mFormatFlags & kAudioFormatFlagIsSignedInteger)) return false;
    if (format.mBitsPerChannel == 24) return bytes == 3 || bytes == 4;
    return !(format.mFormatFlags & kAudioFormatFlagIsBigEndian)
        && ((format.mBitsPerChannel == 16 && bytes == 2) || (format.mBitsPerChannel == 32 && bytes == 4));
}
static double MacMixReadNormalized(const AudioBuffer *buffer, size_t index,
    AudioStreamBasicDescription format, size_t bytes) {
    if (format.mFormatFlags & kAudioFormatFlagIsFloat)
        return bytes == 4 ? ((const float *)buffer->mData)[index] : ((const double *)buffer->mData)[index];
    if (format.mBitsPerChannel == 16) return ((const int16_t *)buffer->mData)[index] / 32768.0;
    if (format.mBitsPerChannel == 32) return ((const int32_t *)buffer->mData)[index] / 2147483648.0;
    return MacMixReadInt24((const uint8_t *)buffer->mData + index * bytes, bytes,
        (format.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0,
        (format.mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0) / 8388608.0;
}
static void MacMixAddNormalized(AudioBuffer *buffer, size_t index, double sample,
    AudioStreamBasicDescription format, size_t bytes) {
    double mixed = MacMixReadNormalized(buffer, index, format, bytes) + sample;
    if (format.mFormatFlags & kAudioFormatFlagIsFloat) {
        if (bytes == 4) ((float *)buffer->mData)[index] = (float)mixed;
        else ((double *)buffer->mData)[index] = mixed;
    } else if (format.mBitsPerChannel == 16) {
        ((int16_t *)buffer->mData)[index] = (int16_t)fmax(INT16_MIN, fmin(INT16_MAX, round(mixed * 32768.0)));
    } else if (format.mBitsPerChannel == 32) {
        ((int32_t *)buffer->mData)[index] = (int32_t)fmax(INT32_MIN, fmin(INT32_MAX, round(mixed * 2147483648.0)));
    } else {
        int32_t value = (int32_t)fmax(-8388608, fmin(8388607, round(mixed * 8388608.0)));
        uint8_t *destination = (uint8_t *)buffer->mData + index * bytes;
        bool bigEndian = (format.mFormatFlags & kAudioFormatFlagIsBigEndian) != 0;
        bool alignedHigh = (format.mFormatFlags & kAudioFormatFlagIsAlignedHigh) != 0;
        if (bytes == 4) {
            uint32_t raw = (uint32_t)value & 0x00FFFFFFu;
            if (alignedHigh) raw <<= 8; // Unsigned packing, including negative samples.
            MacMixWriteInt32Bytes((int32_t)raw, destination, bigEndian);
        } else {
            MacMixWriteInt24(value, destination, bytes, bigEndian, false);
        }
    }
}
static bool MacMixMixEffectFrames(MacMixAudioTapState *state, const AudioBufferList *input,
    AudioBufferList *output, MacMixGainRamp ramp) {
    const size_t bytes = MacMixSampleBytes(state->format);
    if (!MacMixEffectFormatSupported(state->format, bytes) || state->format.mChannelsPerFrame > 64) return false;
    uint32_t channels = 0;
    size_t frames = SIZE_MAX;
    for (uint32_t b = 0; b < state->inputBufferCount; ++b) {
        uint32_t inIndex = state->inputBufferOffset + b, outIndex = state->outputBufferOffset + b;
        if (inIndex >= input->mNumberBuffers || outIndex >= output->mNumberBuffers) return false;
        const AudioBuffer *source = &input->mBuffers[inIndex], *destination = &output->mBuffers[outIndex];
        if (!source->mData || !destination->mData || !source->mNumberChannels
            || source->mNumberChannels != destination->mNumberChannels) return false;
        size_t stride = bytes * source->mNumberChannels;
        size_t count = source->mDataByteSize / stride;
        size_t capacity = destination->mDataByteSize / stride;
        if (capacity < count) count = capacity;
        if (count < frames) frames = count;
        channels += source->mNumberChannels;
    }
    if (channels != state->format.mChannelsPerFrame || channels == 0 || channels > 64 || frames == SIZE_MAX) return false;
    double samples[64]; // Bounded stack storage, no callback allocation.
    for (size_t frame = 0; frame < frames; ++frame) {
        const double gain = frame < ramp.frameCount
            ? ramp.start + (ramp.end - ramp.start) * (double)frame / ramp.frameCount : ramp.end;
        uint32_t channel = 0;
        for (uint32_t b = 0; b < state->inputBufferCount; ++b) {
            const AudioBuffer *source = &input->mBuffers[state->inputBufferOffset + b];
            for (uint32_t ch = 0; ch < source->mNumberChannels; ++ch)
                samples[channel++] = MacMixReadNormalized(source, frame * source->mNumberChannels + ch, state->format, bytes) * gain;
        }
        state->processEffectFrame(state->effect, samples, channels);
        channel = 0;
        for (uint32_t b = 0; b < state->inputBufferCount; ++b) {
            AudioBuffer *destination = &output->mBuffers[state->outputBufferOffset + b];
            for (uint32_t ch = 0; ch < destination->mNumberChannels; ++ch) {
                if (state->metersOutput) state->observeSample(state->effect, samples[channel], channel);
                MacMixAddNormalized(destination, frame * destination->mNumberChannels + ch, samples[channel++], state->format, bytes);
            }
        }
    }
    return frames > 0;
}

static double MacMixOutputGainAtFrame(MacMixOutputEnvelope envelope, size_t frame) {
    if (envelope.timed) {
        double progress = fmax(0, fmin(1, envelope.progress + frame * envelope.step));
        return envelope.from + (envelope.to - envelope.from) * progress;
    }
    MacMixGainRamp ramp = envelope.ramp;
    return frame < ramp.frameCount
        ? ramp.start + (ramp.end - ramp.start) * (double)frame / ramp.frameCount : ramp.end;
}

static MacMixOutputEnvelope MacMixOutputEnvelopeForBlock(MacMixAudioIOContext *context,
    uint32_t frames, const AudioTimeStamp *now, const AudioTimeStamp *outputTime) {
    uint32_t revision = atomic_load_explicit(&context->fadeRevision, memory_order_acquire);
    if (!(revision & 1) && revision != context->cachedFadeRevision) {
        MacMixOutputFade next = {
            atomic_load_explicit(&context->fadeStart, memory_order_relaxed),
            atomic_load_explicit(&context->fadeDuration, memory_order_relaxed),
            MacMixFloatFromBits(atomic_load_explicit(&context->fadeFrom, memory_order_relaxed)),
            MacMixFloatFromBits(atomic_load_explicit(&context->fadeTo, memory_order_relaxed))
        };
        // One bounded attempt, never spin on the audio thread. Keep the previous
        // complete plan if the control thread is publishing a new one.
        if (revision == atomic_load_explicit(&context->fadeRevision, memory_order_acquire)) {
            context->cachedFade = next;
            context->cachedFadeRevision = revision;
        }
    }
    MacMixOutputFade fade = context->cachedFade;
    if (!fade.duration) return (MacMixOutputEnvelope){.ramp = MacMixNextRamp(&context->outputGain, frames)};
    uint64_t host = outputTime->mFlags & kAudioTimeStampHostTimeValid ? outputTime->mHostTime
        : (now->mFlags & kAudioTimeStampHostTimeValid ? now->mHostTime : mach_absolute_time());
    double rate = context->outputGain.format.mSampleRate;
    if (!isfinite(rate) || rate <= 0) rate = kMacMixFallbackSampleRate;
    MacMixOutputEnvelope envelope = {.timed = true,
        .progress = ((double)host - (double)fade.start) / fade.duration,
        .step = context->hostTicksPerSecond / rate / fade.duration, .from = fade.from, .to = fade.to};
    float end = (float)MacMixOutputGainAtFrame(envelope, frames);
    context->outputGain.currentGain = end;
    context->outputGain.lastTargetGain = fade.to;
    context->outputGain.remainingRampFrames = 0;
    if (envelope.progress >= 1 || envelope.progress + frames * envelope.step <= 0) {
        envelope.timed = false;
        envelope.ramp = (MacMixGainRamp){end, end, 0};
    }
    return envelope;
}

static bool MacMixRouteFrames(MacMixAudioTapState *state, const AudioBufferList *input,
    AudioBufferList *output, MacMixOutputEnvelope outputEnvelope) {
    const size_t bytes = MacMixSampleBytes(state->format);
    if (!MacMixEffectFormatSupported(state->format, bytes) || state->format.mChannelsPerFrame != 2) return false;
    size_t frames = SIZE_MAX;
    uint32_t channelCount = 0;
    for (uint32_t b = 0; b < state->inputBufferCount; ++b) {
        if (state->inputBufferOffset + b >= input->mNumberBuffers) return false;
        const AudioBuffer *buffer = &input->mBuffers[state->inputBufferOffset + b];
        if (!buffer->mData || !buffer->mNumberChannels) return false;
        size_t count = buffer->mDataByteSize / (bytes * buffer->mNumberChannels);
        if (count < frames) frames = count;
        channelCount += buffer->mNumberChannels;
    }
    if (channelCount != 2 || frames == SIZE_MAX || !frames || frames > UINT32_MAX) return false;
    MacMixGainRamp destinationRamps[256];
    uint64_t destinationMask = atomic_load_explicit(&state->destinationMask, memory_order_relaxed);
    double fadeFrames = fmax(1, state->format.mSampleRate * kMacMixRampDurationSeconds);
    for (size_t i = 0; i < state->outputChannelCount; ++i) {
        float start = state->destinationGains[i];
        float target = destinationMask & (UINT64_C(1) << state->outputChannels[i].destinationIndex) ? 1 : 0;
        uint32_t remaining = (uint32_t)ceil(fabs(target - start) * fadeFrames);
        uint32_t count = frames < remaining ? (uint32_t)frames : remaining;
        float end = remaining ? start + (target - start) * (float)count / remaining : target;
        destinationRamps[i] = (MacMixGainRamp){start, end, count};
        state->destinationGains[i] = end;
    }
    // Validate layout and discard silent destinations once per block. The old
    // path repeated format decoding and bounds setup for every sample/channel.
    struct PreparedDestination {
        AudioBuffer *buffer;
        const MacMixAudioOutputChannel *route;
        size_t bytes;
        size_t frames;
        bool float32;
        MacMixGainRamp ramp;
    } destinations[256];
    size_t destinationCount = 0;
    for (size_t i = 0; i < state->outputChannelCount; ++i) {
        if (destinationRamps[i].start == 0 && destinationRamps[i].end == 0) continue;
        const MacMixAudioOutputChannel *route = &state->outputChannels[i];
        if (route->bufferIndex >= output->mNumberBuffers) continue;
        AudioBuffer *buffer = &output->mBuffers[route->bufferIndex];
        size_t destinationBytes = MacMixSampleBytes(route->format);
        if (!buffer->mData || !destinationBytes || !MacMixEffectFormatSupported(route->format, destinationBytes)
            || route->channelIndex >= buffer->mNumberChannels
            || (route->sourceChannel != UINT32_MAX && route->sourceChannel >= 2)) continue;
        destinations[destinationCount++] = (struct PreparedDestination){buffer,route,destinationBytes,
            buffer->mDataByteSize / (destinationBytes * buffer->mNumberChannels),
            (route->format.mFormatFlags & kAudioFormatFlagIsFloat) && destinationBytes == 4,destinationRamps[i]};
    }
    bool sourceFloat32 = (state->format.mFormatFlags & kAudioFormatFlagIsFloat) && bytes == 4;
    if (state->beginEffectBlock) state->beginEffectBlock(state->effect);
    state->metersOutput = state->observeSample && state->meterIsActive && state->meterIsActive(state->effect);
    const MacMixGainRamp ramp = MacMixNextRamp(state, (uint32_t)frames);
    for (size_t frame = 0; frame < frames; ++frame) {
        double samples[2];
        uint32_t channel = 0;
        double gain = frame < ramp.frameCount
            ? ramp.start + (ramp.end - ramp.start) * (double)frame / ramp.frameCount : ramp.end;
        for (uint32_t b = 0; b < state->inputBufferCount; ++b) {
            const AudioBuffer *source = &input->mBuffers[state->inputBufferOffset + b];
            for (uint32_t ch = 0; ch < source->mNumberChannels; ++ch) {
                size_t sampleIndex = frame * source->mNumberChannels + ch;
                double sample = (sourceFloat32 ? ((const float *)source->mData)[sampleIndex]
                    : MacMixReadNormalized(source, sampleIndex, state->format, bytes)) * gain;
                samples[channel] = state->processEffectSample && !state->processEffectFrame
                    ? state->processEffectSample(state->effect, sample, channel) : sample;
                ++channel;
            }
        }
        if (state->processEffectFrame) state->processEffectFrame(state->effect, samples, 2);
        if (state->metersOutput) for (uint32_t ch = 0; ch < 2; ++ch) state->observeSample(state->effect, samples[ch], ch);
        // Fade after EQ/limiting so changing graph ownership cannot change the
        // processing curve or create a doubled limiter input on shared outputs.
        double outputGain = MacMixOutputGainAtFrame(outputEnvelope, frame);
        for (size_t i = 0; i < destinationCount; ++i) {
            const struct PreparedDestination *prepared = &destinations[i];
            if (frame >= prepared->frames) continue;
            const MacMixAudioOutputChannel *route = prepared->route;
            AudioBuffer *destination = prepared->buffer;
            size_t index = frame * destination->mNumberChannels + route->channelIndex;
            double sample = route->sourceChannel == UINT32_MAX ? (samples[0] + samples[1]) * 0.5 : samples[route->sourceChannel];
            MacMixGainRamp destinationRamp = prepared->ramp;
            double destinationGain = frame < destinationRamp.frameCount
                ? destinationRamp.start + (destinationRamp.end - destinationRamp.start) * (double)frame / destinationRamp.frameCount
                : destinationRamp.end;
            double value = sample * outputGain * destinationGain;
            if (prepared->float32) ((float *)destination->mData)[index] += (float)value;
            else MacMixAddNormalized(destination, index, value, route->format, prepared->bytes);
        }
    }
    if (state->metersOutput && state->endEffectBlock) state->endEffectBlock(state->effect);
    atomic_store_explicit(&state->renderedGainBits, MacMixFloatBits(ramp.end), memory_order_relaxed);
    return true;
}

OSStatus MacMixAudioDeviceIOProc(
    AudioObjectID device,
    const AudioTimeStamp *now,
    const AudioBufferList *inputData,
    const AudioTimeStamp *inputTime,
    AudioBufferList *outputData,
    const AudioTimeStamp *outputTime,
    void *clientData
) {
    (void)device;
    (void)now;
    (void)inputTime;
    (void)outputTime;

    MacMixAudioIOContext *context = clientData;
    if (context == NULL || inputData == NULL || outputData == NULL) {
        return noErr;
    }

    for (size_t index = 0; index < context->outputBufferIndexCount; ++index) {
        const uint32_t outputIndex = context->outputBufferIndices[index];
        if (outputIndex >= outputData->mNumberBuffers) {
            continue;
        }

        AudioBuffer *buffer = &outputData->mBuffers[outputIndex];
        if (buffer->mData != NULL && buffer->mDataByteSize > 0) {
            memset(buffer->mData, 0, buffer->mDataByteSize);
        }
    }

    uint32_t outputFrames = 0;
    MacMixOutputEnvelope outputEnvelope = {.ramp = {1, 1, 0}};
    if (context->tapCount) {
        const MacMixAudioTapState *first = &context->taps[0];
        if (first->inputBufferOffset < inputData->mNumberBuffers && first->format.mBytesPerFrame) {
            const AudioBuffer *buffer = &inputData->mBuffers[first->inputBufferOffset];
            if (buffer->mData) outputFrames = buffer->mDataByteSize / first->format.mBytesPerFrame;
        }
        if (outputFrames) outputEnvelope = MacMixOutputEnvelopeForBlock(context, outputFrames, now, outputTime);
    }
    for (size_t tapIndex = 0; tapIndex < context->tapCount; ++tapIndex) {
        MacMixAudioTapState *state = &context->taps[tapIndex];
        if (state->routesOutput) {
            MacMixRouteFrames(state, inputData, outputData, outputEnvelope);
            continue;
        }
        const uint32_t bytesPerFrame = state->format.mBytesPerFrame > 0
            ? state->format.mBytesPerFrame
            : 1;
        uint32_t frameCount = 0;

        for (uint32_t localIndex = 0; localIndex < state->inputBufferCount; ++localIndex) {
            const uint32_t inputIndex = state->inputBufferOffset + localIndex;
            const uint32_t outputIndex = state->outputBufferOffset + localIndex;
            if (inputIndex >= inputData->mNumberBuffers
                || outputIndex >= outputData->mNumberBuffers) {
                continue;
            }

            const AudioBuffer *inputBuffer = &inputData->mBuffers[inputIndex];
            const AudioBuffer *outputBuffer = &outputData->mBuffers[outputIndex];
            if (inputBuffer->mData != NULL && outputBuffer->mData != NULL
                && inputBuffer->mNumberChannels == outputBuffer->mNumberChannels
                && outputBuffer->mDataByteSize >= inputBuffer->mDataByteSize
                && inputBuffer->mDataByteSize > 0) {
                frameCount = inputBuffer->mDataByteSize / bytesPerFrame;
                break;
            }
        }

        if (frameCount == 0) {
            continue;
        }

        if (state->beginEffectBlock) state->beginEffectBlock(state->effect);
        state->metersOutput = state->observeSample && state->meterIsActive && state->meterIsActive(state->effect);
        const MacMixGainRamp ramp = MacMixNextRamp(state, frameCount);
        bool didMixAudio = state->processEffectFrame
            ? MacMixMixEffectFrames(state, inputData, outputData, ramp) : false;
        for (uint32_t localIndex = 0; !state->processEffectFrame && localIndex < state->inputBufferCount; ++localIndex) {
            const uint32_t inputIndex = state->inputBufferOffset + localIndex;
            const uint32_t outputIndex = state->outputBufferOffset + localIndex;
            if (inputIndex >= inputData->mNumberBuffers
                || outputIndex >= outputData->mNumberBuffers) {
                continue;
            }

            if (MacMixMixAudioBuffer(
                &inputData->mBuffers[inputIndex],
                &outputData->mBuffers[outputIndex],
                ramp,
                state->format, state,
                (state->format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? localIndex : 0
            )) {
                didMixAudio = true;
            }
        }

        if (state->metersOutput && state->endEffectBlock) state->endEffectBlock(state->effect);
        if (didMixAudio) {
            atomic_store_explicit(
                &state->renderedGainBits,
                MacMixFloatBits(ramp.end),
                memory_order_relaxed
            );
        }
    }

    // Legacy single-output graphs also participate in overlapping replacement.
    // Apply their envelope to the final mix, once per buffer and after all DSP.
    if (!context->hasRoutedOutput && (outputEnvelope.timed || outputEnvelope.ramp.start != 1 || outputEnvelope.ramp.end != 1)) {
        for (size_t i = 0; i < context->outputBufferIndexCount; ++i) {
            uint32_t index = context->outputBufferIndices[i];
            if (index >= outputData->mNumberBuffers) continue;
            const MacMixAudioTapState *owner = NULL;
            for (size_t t = 0; t < context->tapCount; ++t) {
                const MacMixAudioTapState *tap = &context->taps[t];
                if (index >= tap->outputBufferOffset && index - tap->outputBufferOffset < tap->inputBufferCount) {
                    owner = tap; break;
                }
            }
            if (!owner) continue;
            AudioBuffer *buffer = &outputData->mBuffers[index];
            size_t bytes = MacMixSampleBytes(owner->format);
            if (!buffer->mData || !buffer->mNumberChannels || !MacMixEffectFormatSupported(owner->format, bytes)) continue;
            size_t frames = buffer->mDataByteSize / (bytes * buffer->mNumberChannels);
            for (size_t frame = 0; frame < frames; ++frame) {
                double gain = MacMixOutputGainAtFrame(outputEnvelope, frame);
                for (uint32_t ch = 0; ch < buffer->mNumberChannels; ++ch) {
                    size_t sampleIndex = frame * buffer->mNumberChannels + ch;
                    double value = MacMixReadNormalized(buffer, sampleIndex, owner->format, bytes);
                    MacMixAddNormalized(buffer, sampleIndex, value * (gain - 1), owner->format, bytes);
                }
            }
        }
    }
    if (outputFrames) {
        atomic_store_explicit(&context->outputGain.renderedGainBits,
            MacMixFloatBits((float)MacMixOutputGainAtFrame(outputEnvelope, outputFrames)), memory_order_relaxed);
        atomic_fetch_add_explicit(&context->renderedFrames, outputFrames, memory_order_relaxed);
    }

    return noErr;
}

OSStatus MacMixNoopAudioDeviceIOProc(
    AudioObjectID device,
    const AudioTimeStamp *now,
    const AudioBufferList *inputData,
    const AudioTimeStamp *inputTime,
    AudioBufferList *outputData,
    const AudioTimeStamp *outputTime,
    void *clientData
) {
    (void)device;
    (void)now;
    (void)inputData;
    (void)inputTime;
    (void)outputData;
    (void)outputTime;
    (void)clientData;
    return noErr;
}
