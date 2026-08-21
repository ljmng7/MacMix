#include "MacMixAudioIOProc.h"

#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

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
} MacMixAudioTapState;

typedef struct {
    _Atomic(size_t) referenceCount;
    size_t tapCount;
    MacMixAudioTapState *taps;
    size_t outputBufferIndexCount;
    uint32_t *outputBufferIndices;
} MacMixAudioIOContext;

typedef struct {
    float start;
    float end;
    uint32_t frameCount;
} MacMixGainRamp;

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
    free(context->taps);
    free(context);
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
    AudioStreamBasicDescription format
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
            destination[index] += source[index] * gain;
        }
        if (ramp.end != 0.0f) {
            for (size_t index = rampSampleCount; index < sampleCount; ++index) {
                destination[index] += source[index] * ramp.end;
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
            destination[index] += source[index] * gain;
        }
        if (ramp.end != 0.0f) {
            for (size_t index = rampSampleCount; index < sampleCount; ++index) {
                destination[index] += source[index] * (double)ramp.end;
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
            const double mixed = (double)destination[index] + (double)source[index] * gain;
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
            const double mixed = (double)destination[index] + (double)source[index] * gain;
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
            const double mixed = (double)destinationSample + (double)sourceSample * gain;
            const int32_t clamped = (int32_t)fmax(-8388608, fmin(8388607, round(mixed)));
            MacMixWriteInt24(
                clamped, destination + offset, bytesPerSample, isBigEndian, isAlignedHigh
            );
        }
        return true;
    }

    return false;
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

    for (size_t tapIndex = 0; tapIndex < context->tapCount; ++tapIndex) {
        MacMixAudioTapState *state = &context->taps[tapIndex];
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

        const MacMixGainRamp ramp = MacMixNextRamp(state, frameCount);
        bool didMixAudio = false;
        for (uint32_t localIndex = 0; localIndex < state->inputBufferCount; ++localIndex) {
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
                state->format
            )) {
                didMixAudio = true;
            }
        }

        if (didMixAudio) {
            atomic_store_explicit(
                &state->renderedGainBits,
                MacMixFloatBits(ramp.end),
                memory_order_relaxed
            );
        }
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
