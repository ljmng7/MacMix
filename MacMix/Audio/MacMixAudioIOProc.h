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

typedef struct {
    AudioStreamBasicDescription format;
    uint32_t bufferIndex;
    uint32_t channelIndex;
    uint32_t sourceChannel; // 0/1 = L/R, UINT32_MAX = stereo-to-mono.
    uint32_t destinationIndex;
} MacMixAudioOutputChannel;

// Configured only before AudioDeviceStart. A zero-length map consumes the tap
// silently, preserving mute-on-capture when all selected devices are offline.
bool MacMixAudioIOContextSetOutputChannels(MacMixAudioIOContextRef _Nonnull context,
    size_t configurationIndex, const MacMixAudioOutputChannel * _Nullable channels, size_t count);
// Descriptors stay immutable while running. Only this lock-free destination mask
// changes; common outputs remain at unity and removed outputs fade to silence.
void MacMixAudioIOContextSetDestinationMask(MacMixAudioIOContextRef _Nonnull context,
    size_t configurationIndex, uint64_t mask, bool initializeBeforeStart);
OSStatus MacMixAudioDisablePhysicalInputs(AudioObjectID device, AudioDeviceIOProcID _Nonnull ioProc,
    uint32_t physicalStreamCount, uint32_t totalStreamCount);
// The initial value is set before IO starts; subsequent changes use a post-DSP
// linear ramp, independently of saved app volumes and EQ state.
void MacMixAudioIOContextSetInitialOutputGain(MacMixAudioIOContextRef _Nonnull context, float gain);
void MacMixAudioIOContextSetOutputGain(MacMixAudioIOContextRef _Nonnull context, float gain);
float MacMixAudioIOContextRenderedOutputGain(MacMixAudioIOContextRef _Nonnull context);
uint64_t MacMixAudioIOContextRenderedFrames(MacMixAudioIOContextRef _Nonnull context);
uint64_t MacMixAudioOutputFadeStartTime(double delaySeconds);
void MacMixAudioIOContextScheduleOutputGain(MacMixAudioIOContextRef _Nonnull context,
    float from, float to, uint64_t startHostTime, double durationSeconds);

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

// Optional DSP supplied by the MacMixStudio package. Installed before IO starts;
// the context owns it until the stopped IO context is released.
void MacMixAudioIOContextSetEffect(MacMixAudioIOContextRef _Nonnull context, size_t index,
    void * _Nullable effect,
    void (* _Nullable beginBlock)(void * _Nullable),
    double (* _Nullable processSample)(void * _Nullable, double, uint32_t),
    void (* _Nullable destroy)(void * _Nullable));
void MacMixAudioIOContextSetFrameEffect(MacMixAudioIOContextRef _Nonnull context, size_t index,
    void (* _Nullable processFrame)(void * _Nullable, double * _Nullable, uint32_t));
void MacMixAudioIOContextSetMeter(MacMixAudioIOContextRef _Nonnull context, size_t index,
    bool (* _Nullable isActive)(void * _Nullable),
    void (* _Nullable observeSample)(void * _Nullable, double, uint32_t),
    void (* _Nullable endBlock)(void * _Nullable));

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
