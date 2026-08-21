#ifndef MacMixAudioIOProc_h
#define MacMixAudioIOProc_h

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef void *MacMixAudioIOContextRef;

typedef struct {
    AudioStreamBasicDescription format;
    uint32_t inputBufferOffset;
    uint32_t inputBufferCount;
    uint32_t outputBufferOffset;
    float initialGain;
    float targetGain;
} MacMixAudioTapConfiguration;

MacMixAudioIOContextRef _Nullable MacMixAudioIOContextCreate(
    const MacMixAudioTapConfiguration * _Nonnull configurations,
    size_t configurationCount,
    const uint32_t * _Nonnull outputBufferIndices,
    size_t outputBufferIndexCount
);

void MacMixAudioIOContextRetain(MacMixAudioIOContextRef _Nonnull context);

void MacMixAudioIOContextDestroy(MacMixAudioIOContextRef _Nullable context);

void MacMixAudioIOContextSetTargetGain(
    MacMixAudioIOContextRef _Nonnull context,
    size_t configurationIndex,
    float gain
);

float MacMixAudioIOContextRenderedGain(
    MacMixAudioIOContextRef _Nonnull context,
    size_t configurationIndex
);

OSStatus MacMixAudioDeviceIOProc(
    AudioObjectID device,
    const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull inputData,
    const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull outputData,
    const AudioTimeStamp * _Nonnull outputTime,
    void * _Nullable clientData
);

OSStatus MacMixNoopAudioDeviceIOProc(
    AudioObjectID device,
    const AudioTimeStamp * _Nonnull now,
    const AudioBufferList * _Nonnull inputData,
    const AudioTimeStamp * _Nonnull inputTime,
    AudioBufferList * _Nonnull outputData,
    const AudioTimeStamp * _Nonnull outputTime,
    void * _Nullable clientData
);

#endif /* MacMixAudioIOProc_h */
