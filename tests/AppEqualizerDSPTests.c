// Build with MacMixEQDSP.c and MacMixAudioIOProc.c; no device or audio permission needed.
#include "MacMixEQDSP.h"
#include "MacMixAudioIOProc.h"
#include <assert.h>
#include <math.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <mach/mach_time.h>

static double amplitude(double rate, double frequency, double bandGain) {
    void *eq = MacMixEQCreate(rate, 1);
    assert(eq);
    double gains[10] = {0}; gains[5] = bandGain;
    MacMixEQSetGains(eq, gains, true);
    double energy = 0;
    unsigned count = (unsigned)rate;
    for (unsigned i = 0; i < count; ++i) {
        if (i % 128 == 0) MacMixEQBeginBlock(eq);
        double y = MacMixEQProcessSample(eq, 0.1 * sin(2 * M_PI * frequency * i / rate), 0);
        if (i >= count / 2) energy += y * y;
    }
    MacMixEQDestroy(eq);
    return sqrt(energy / (count - count / 2)) * sqrt(2);
}
static void frequencyTests(void) {
    double rates[] = {44100,48000,96000};
    for (unsigned r = 0; r < 3; ++r) {
        double flat = amplitude(rates[r], 1000, 0);
        assert(fabs(flat - 0.1) < 1e-5);
        double cut = amplitude(rates[r], 1000, -6);
        assert(fabs(20 * log10(cut / flat) + 6) < 0.02);
        double boost = amplitude(rates[r], 1000, 6);
        double other = amplitude(rates[r], 100, 6);
        assert(20 * log10(boost / other) > 5.8);
        assert(fabs(20 * log10(boost / flat) - 6) < 0.02);
        assert(fabs(20 * log10(other / flat)) < 0.1); // Unrelated frequencies are not attenuated.
    }
}
static void isolationAndBypassTests(void) {
    void *eq = MacMixEQCreate(48000, 2);
    double gains[10] = {0}; gains[0] = 12; gains[5] = -12;
    MacMixEQSetGains(eq, gains, true);
    for (unsigned i = 0; i < 12000; ++i) {
        if (i % 64 == 0) MacMixEQBeginBlock(eq);
        double l = MacMixEQProcessSample(eq, i == 0 ? 1 : 0, 0);
        double r = MacMixEQProcessSample(eq, 0, 1);
        assert(isfinite(l) && fabs(l) <= 1);
        assert(r == 0);
    }
    MacMixEQSetGains(eq, NULL, false);
    for (unsigned i = 0; i < 12000; ++i) {
        if (i % 64 == 0) MacMixEQBeginBlock(eq);
        double sample = sin(i * 0.1) * 0.3;
        double l = MacMixEQProcessSample(eq, sample, 0);
        MacMixEQProcessSample(eq, 0, 1);
        if (i > 4096) assert(l == sample);
    }
    assert(MacMixEQIsSettled(eq));
    MacMixEQDestroy(eq);
}
static void integrationTest(void) {
    float input[256], output[256];
    for (unsigned i = 0; i < 256; ++i) input[i] = sinf(i * 0.1f) * 0.25f;
    AudioStreamBasicDescription format = {
        .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 8, .mFramesPerPacket = 1, .mBytesPerFrame = 8,
        .mChannelsPerFrame = 2, .mBitsPerChannel = 32
    };
    MacMixAudioTapConfiguration configuration = {.format = format, .inputBufferCount = 1, .initialGain = 1, .targetGain = 1};
    uint32_t index = 0;
    void *context = MacMixAudioIOContextCreate(&configuration, 1, &index, 1);
    void *eq = MacMixEQCreate(48000, 2);
    MacMixAudioIOContextSetEffect(context, 0, eq, MacMixEQBeginBlock, NULL, MacMixEQDestroy);
    MacMixAudioIOContextSetFrameEffect(context, 0, MacMixEQProcessFrame);
    MacMixAudioIOContextSetMeter(context, 0, MacMixEQMeteringIsActive, MacMixEQObserveSample, MacMixEQEndBlock);
    MacMixEQSetMetering(eq, true);
    AudioBufferList in = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(input), input}}};
    AudioBufferList out = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(output), output}}};
    AudioTimeStamp timestamp = {0};
    MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
    for (unsigned i = 0; i < 256; ++i) assert(input[i] == output[i]);
    double gains[10] = {0}; gains[5] = -12;
    MacMixEQSetGains(eq, gains, true);
    for (unsigned block = 0; block < 80; ++block) {
        MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
        for (unsigned i = 0; i < 256; ++i) assert(isfinite(output[i]));
    }
    assert(MacMixEQIsSettled(eq));
    float bars[MacMixEQSpectrumBarCount];
    assert(MacMixEQCopySpectrum(eq, bars, MacMixEQSpectrumBarCount));
    float peak = 0;
    for (unsigned i = 0; i < MacMixEQSpectrumBarCount; ++i) peak = fmaxf(peak, bars[i]);
    assert(peak > 0.1);
    MacMixAudioIOContextSetTargetGain(context, 0, 0);
    for (unsigned block = 0; block < 80; ++block)
        MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
    assert(MacMixEQCopySpectrum(eq, bars, MacMixEQSpectrumBarCount));
    for (unsigned i = 0; i < MacMixEQSpectrumBarCount; ++i) assert(bars[i] == 0); // Measures post-volume, not input.
    MacMixAudioIOContextDestroy(context);
}
static void volumeBeforeLimitingTest(void) {
    float input[512], output[512];
    AudioStreamBasicDescription format = {
        .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 4, .mFramesPerPacket = 1, .mBytesPerFrame = 4,
        .mChannelsPerFrame = 1, .mBitsPerChannel = 32
    };
    MacMixAudioTapConfiguration configuration = {.format = format, .inputBufferCount = 1, .initialGain = 0.2f, .targetGain = 0.2f};
    uint32_t index = 0;
    void *context = MacMixAudioIOContextCreate(&configuration, 1, &index, 1);
    void *eq = MacMixEQCreate(48000, 1);
    double gains[10] = {0}; gains[5] = 12;
    MacMixEQSetGains(eq, gains, true);
    MacMixAudioIOContextSetEffect(context, 0, eq, MacMixEQBeginBlock, NULL, MacMixEQDestroy);
    MacMixAudioIOContextSetFrameEffect(context, 0, MacMixEQProcessFrame);
    AudioBufferList in = {.mNumberBuffers = 1, .mBuffers = {{1, sizeof(input), input}}};
    AudioBufferList out = {.mNumberBuffers = 1, .mBuffers = {{1, sizeof(output), output}}};
    AudioTimeStamp timestamp = {0};
    double peak = 0;
    for (unsigned block = 0; block < 40; ++block) {
        for (unsigned i = 0; i < 512; ++i) input[i] = 0.8f * sinf(2 * M_PI * 1000 * (block * 512 + i) / 48000);
        MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
        if (block > 20) for (unsigned i = 0; i < 512; ++i) peak = fmax(peak, fabs(output[i]));
    }
    // 0.8 input * 20% volume * +12 dB = 0.637; limiting before the volume
    // would incorrectly flatten the result to about 0.2.
    assert(peak > 0.63 && peak < 0.65);
    MacMixAudioIOContextDestroy(context);
}

// 200% volume and maximum EQ can coexist: the limiter follows the processed
// peak, stays armed with EQ off or Flat, and releases fully once back at unity.
static void boostedVolumeLimiterTest(void) {
    for (unsigned mode = 0; mode < 3; ++mode) { // 0: no EQ, 1: every band +12 dB, 2: EQ turned off while boosted
        float input[512], output[512];
        AudioStreamBasicDescription format = {
            .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
            .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            .mBytesPerPacket = 8, .mFramesPerPacket = 1, .mBytesPerFrame = 8,
            .mChannelsPerFrame = 2, .mBitsPerChannel = 32
        };
        MacMixAudioTapConfiguration configuration = {.format = format, .inputBufferCount = 1, .initialGain = 2, .targetGain = 2};
        uint32_t index = 0;
        void *context = MacMixAudioIOContextCreate(&configuration, 1, &index, 1);
        void *eq = MacMixEQCreate(48000, 2);
        double gains[10]; for (unsigned b = 0; b < 10; ++b) gains[b] = 12;
        if (mode) MacMixEQSetGains(eq, gains, true);
        MacMixAudioIOContextSetEffect(context, 0, eq, MacMixEQBeginBlock, NULL, MacMixEQDestroy);
        MacMixAudioIOContextSetFrameEffect(context, 0, MacMixEQProcessFrame);
        AudioBufferList in = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(input), input}}};
        AudioBufferList out = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(output), output}}};
        AudioTimeStamp timestamp = {0};
        unsigned frame = 0;
        double peak = 0;
        for (unsigned block = 0; block < 200; ++block) {
            if (mode == 2 && block == 100) MacMixEQSetGains(eq, NULL, false);
            for (unsigned i = 0; i < 256; ++i, ++frame) {
                float sample = (float)(sin(2 * M_PI * 60 * frame / 48000) * 0.7 + sin(2 * M_PI * 3000 * frame / 48000) * 0.3);
                input[2 * i] = sample; input[2 * i + 1] = -sample;
            }
            memset(output, 0, sizeof(output));
            MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
            for (unsigned i = 0; i < 512; ++i) {
                assert(isfinite(output[i]) && fabs(output[i]) <= 0.980001);
                assert(output[i] == -output[i ^ 1u]); // Channels stay linked.
                peak = fmax(peak, fabs(output[i]));
            }
        }
        assert(peak > 0.95); // Boost reaches the ceiling instead of being pre-attenuated.
        // Back to unity without EQ: the limiter settles quickly enough for the
        // 120 ms unity handoff and then passes audio bit-exactly.
        MacMixEQSetGains(eq, NULL, false);
        MacMixAudioIOContextSetTargetGain(context, 0, 1);
        for (unsigned i = 0; i < 512; ++i) input[i] = (float)(sin(i * 0.05) * 0.5);
        unsigned blocks = 0;
        do {
            MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
            ++blocks;
        } while (!MacMixEQIsSettled(eq) && blocks < 200);
        printf("Unity handoff after 200%% volume (case %u): limiter settled in %.0f ms\n", mode, blocks * 256 / 48.0);
        assert(blocks * 256 < 48000 * 0.12);
        memset(output, 0, sizeof(output));
        MacMixAudioDeviceIOProc(0, &timestamp, &in, &timestamp, &out, &timestamp, context);
        for (unsigned i = 0; i < 512; ++i) assert(output[i] == input[i]);
        MacMixAudioIOContextDestroy(context);
    }
}
static void spectrumTests(void) {
    void *eq = MacMixEQCreate(48000, 2);
    float bars[MacMixEQSpectrumBarCount];
    assert(!MacMixEQCopySpectrum(eq, bars, MacMixEQSpectrumBarCount));
    MacMixEQSetMetering(eq, true);
    for (unsigned block = 0; block < 24; ++block) {
        MacMixEQBeginBlock(eq);
        // Process planar channels in irregular 480-frame blocks, like real device layouts.
        for (unsigned ch = 0; ch < 2; ++ch) {
            for (unsigned frame = 0; frame < 480; ++frame) {
                double sample = 0.1 * sin(2 * M_PI * 1000 * (block * 480 + frame) / 48000);
                MacMixEQObserveSample(eq, ch == 0 ? sample : -sample, ch);
            }
        }
        MacMixEQEndBlock(eq);
    }
    assert(MacMixEQCopySpectrum(eq, bars, MacMixEQSpectrumBarCount));
    unsigned peak = 0;
    for (unsigned i = 1; i < MacMixEQSpectrumBarCount; ++i) if (bars[i] > bars[peak]) peak = i;
    double frequency = 32 * pow(500, (double)peak / (MacMixEQSpectrumBarCount - 1));
    assert(frequency > 850 && frequency < 1150);
    assert(bars[peak] > 0.68 && bars[peak] < 0.76); // -20 dBFS, including window leakage.
    MacMixEQSetMetering(eq, false);
    MacMixEQBeginBlock(eq);
    assert(!MacMixEQMeteringIsActive(eq));
    assert(!MacMixEQCopySpectrum(eq, bars, MacMixEQSpectrumBarCount));
    MacMixEQDestroy(eq);
}

static double measuredAmplitude(void *eq, double frequency) {
    const unsigned segment = 24576; // Coherent for every ISO band at 48 kHz.
    double energy = 0;
    for (unsigned i = 0; i < segment * 2; ++i) {
        if (i % 128 == 0) MacMixEQBeginBlock(eq);
        double frame = 0.01 * sin(2 * M_PI * frequency * i / 48000);
        MacMixEQProcessFrame(eq, &frame, 1);
        if (i >= segment) energy += frame * frame;
    }
    return sqrt(energy / segment) * sqrt(2);
}
static void toneAndConversionTests(void) {
    double tones[3] = {0,6,0}, fitted[10];
    MacMixEQFitToneGains(tones, fitted);
    void *tone = MacMixEQCreate(48000, 1);
    MacMixEQSetToneGains(tone, tones, true);
    assert(fabs(20 * log10(measuredAmplitude(tone, 1000) / 0.01) - 6) < 0.02);
    MacMixEQDestroy(tone);
    const double frequencies[10] = {31.25,62.5,125,250,500,1000,2000,4000,8000,16000};
    for (unsigned band = 0; band < 10; ++band) {
        tone = MacMixEQCreate(48000, 1);
        void *graphic = MacMixEQCreate(48000, 1);
        MacMixEQSetToneGains(tone, tones, true);
        MacMixEQSetGains(graphic, fitted, true);
        double expected = measuredAmplitude(tone, frequencies[band]);
        double converted = measuredAmplitude(graphic, frequencies[band]);
        assert(fabs(20 * log10(converted / expected)) < 0.15);
        MacMixEQDestroy(tone); MacMixEQDestroy(graphic);
    }
}
static void retuningContinuityTest(void) {
    void *reference = MacMixEQCreate(48000,1), *retuned = MacMixEQCreate(48000,1);
    double gains[10] = {0}; gains[3]=6; gains[5]=-3;
    MacMixEQSetGains(reference,gains,true); MacMixEQSetGains(retuned,gains,true);
    double maxError = 0;
    for(unsigned i=0;i<96000;++i) {
        if(i>12000 && i%2048==0) MacMixEQSetGains(retuned,gains,true);
        if(i%128==0) { MacMixEQBeginBlock(reference); MacMixEQBeginBlock(retuned); }
        double input = 0.1*sin(2*M_PI*250*i/48000) + 0.05*sin(2*M_PI*1000*i/48000);
        double a=input,b=input;
        MacMixEQProcessFrame(reference,&a,1); MacMixEQProcessFrame(retuned,&b,1);
        if(i>12000) maxError=fmax(maxError,fabs(a-b));
    }
    assert(maxError<1e-9); // No periodic reset transient when coefficients are republished.
    MacMixEQDestroy(reference); MacMixEQDestroy(retuned);
}

static void distortionTest(bool tones, bool twoTones) {
    void *eq = MacMixEQCreate(48000, 2);
    double gains[10] = {0}; for (unsigned b = 3; b <= 6; ++b) gains[b] = 12;
    double toneGains[3] = {0,12,0};
    if (tones) MacMixEQSetToneGains(eq, toneGains, true);
    else MacMixEQSetGains(eq, gains, true);
    double energy = 0, sine[2] = {0}, cosine[2] = {0};
    for (unsigned i = 0; i < 48000; ++i) {
        if (i % 128 == 0) MacMixEQBeginBlock(eq);
        double phase = 2 * M_PI * 1000 * i / 48000, second = 2 * M_PI * 200 * i / 48000;
        double sample = twoTones ? 0.4 * sin(phase) + 0.2 * sin(second) : 0.6 * sin(phase);
        double frame[2] = {sample, sample * 0.1};
        MacMixEQProcessFrame(eq, frame, 2);
        assert(fabs(frame[0]) <= 0.980001 && fabs(frame[1]) <= 0.980001);
        assert(fabs(frame[1] - frame[0] * 0.1) < 1e-10);
        if (i >= 24000) {
            energy += frame[0] * frame[0];
            sine[0] += frame[0] * sin(phase); cosine[0] += frame[0] * cos(phase);
            sine[1] += frame[0] * sin(second); cosine[1] += frame[0] * cos(second);
        }
    }
    double fundamentals = 0;
    for (unsigned tone = 0; tone < (twoTones ? 2u : 1u); ++tone)
        fundamentals += 2 * (sine[tone]*sine[tone] + cosine[tone]*cosine[tone]) / (24000.0 * 24000.0);
    double distortion = sqrt(fmax(0, energy / 24000 - fundamentals) / fundamentals);
    printf("%s +12 dB %s: steady-state residual distortion %.5f%%\n", tones ? "Tone mid" : "Four graphic mids", twoTones ? "two-tone" : "sine", distortion * 100);
    assert(distortion < 0.0005); // <0.05%, versus 36.7% from the previous waveshaper.
    MacMixEQDestroy(eq);
}
static void frameFormatRoundTripTests(void) {
    const unsigned bits[] = {32,64,16,32,24,24,24,24};
    const unsigned bytes[] = {4,8,2,4,3,3,4,4};
    for (unsigned kind=0;kind<8;++kind) {
        union { double alignment[64]; unsigned char data[512]; } source={0},destination={0};
        bool floating=kind<2, big=kind==5 || kind==7, high=kind>=6;
        for (unsigned i=0;i<32;++i) {
            if(kind==0) ((float *)source.data)[i]=((int)i%7-3)*0.125f;
            else if(kind==1) ((double *)source.data)[i]=((int)i%7-3)*0.125;
            else if(kind==2) ((int16_t *)source.data)[i]=(int16_t)(((int)i-16)*1900);
            else if(kind==3) ((int32_t *)source.data)[i]=((int)i-16)*100000000;
            else {
                int32_t value=((int)i-16)*450000;
                uint32_t raw=(uint32_t)value & 0xFFFFFFu;
                if(high) raw<<=8;
                for(unsigned b=0;b<bytes[kind];++b) source.data[i*bytes[kind]+b]=(uint8_t)(raw>>(8*(big?bytes[kind]-1-b:b)));
            }
        }
        AudioStreamBasicDescription format={.mSampleRate=48000,.mFormatID=kAudioFormatLinearPCM,
            .mFormatFlags=(floating?kAudioFormatFlagIsFloat:kAudioFormatFlagIsSignedInteger)
                |(big?kAudioFormatFlagIsBigEndian:0)|(high?kAudioFormatFlagIsAlignedHigh:kAudioFormatFlagIsPacked),
            .mBytesPerFrame=bytes[kind]*2,.mBytesPerPacket=bytes[kind]*2,.mFramesPerPacket=1,.mChannelsPerFrame=2,.mBitsPerChannel=bits[kind]};
        MacMixAudioTapConfiguration configuration={.format=format,.inputBufferCount=1,.initialGain=1,.targetGain=1};
        uint32_t index=0; void *context=MacMixAudioIOContextCreate(&configuration,1,&index,1);
        void *eq=MacMixEQCreate(48000,2);
        MacMixAudioIOContextSetEffect(context,0,eq,MacMixEQBeginBlock,NULL,MacMixEQDestroy);
        MacMixAudioIOContextSetFrameEffect(context,0,MacMixEQProcessFrame);
        AudioBufferList input={.mNumberBuffers=1,.mBuffers={{2,32*bytes[kind],source.data}}};
        AudioBufferList output={.mNumberBuffers=1,.mBuffers={{2,32*bytes[kind],destination.data}}};
        AudioTimeStamp timestamp={0};
        MacMixAudioDeviceIOProc(0,&timestamp,&input,&timestamp,&output,&timestamp,context);
        assert(memcmp(source.data,destination.data,32*bytes[kind])==0);
        MacMixAudioIOContextDestroy(context);
    }
}

static void planarLinkedLimiterTest(void) {
    float left[480], right[480], outLeft[480], outRight[480];
    AudioStreamBasicDescription format = {.mSampleRate=48000,.mFormatID=kAudioFormatLinearPCM,
        .mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsNonInterleaved|kAudioFormatFlagIsPacked,
        .mBytesPerFrame=4,.mBytesPerPacket=4,.mFramesPerPacket=1,.mChannelsPerFrame=2,.mBitsPerChannel=32};
    MacMixAudioTapConfiguration configuration = {.format=format,.inputBufferCount=2,.initialGain=1,.targetGain=1};
    uint32_t indices[2] = {0,1};
    void *context = MacMixAudioIOContextCreate(&configuration,1,indices,2);
    void *eq = MacMixEQCreate(48000,2);
    double tones[3] = {0,12,0}; MacMixEQSetToneGains(eq,tones,true);
    MacMixAudioIOContextSetEffect(context,0,eq,MacMixEQBeginBlock,NULL,MacMixEQDestroy);
    MacMixAudioIOContextSetFrameEffect(context,0,MacMixEQProcessFrame);
    struct { UInt32 count; AudioBuffer buffers[2]; } input = {2,{{1,sizeof(left),left},{1,sizeof(right),right}}};
    struct { UInt32 count; AudioBuffer buffers[2]; } output = {2,{{1,sizeof(outLeft),outLeft},{1,sizeof(outRight),outRight}}};
    AudioTimeStamp timestamp = {0};
    for (unsigned block=0;block<50;++block) {
        for(unsigned i=0;i<480;++i) {left[i]=0.6*sin(2*M_PI*1000*(block*480+i)/48000);right[i]=left[i]*0.1f;}
        MacMixAudioDeviceIOProc(0,&timestamp,(AudioBufferList *)&input,&timestamp,(AudioBufferList *)&output,&timestamp,context);
        for(unsigned i=0;i<480;++i) {
            assert(fabs(outLeft[i])<=0.980001);
            assert(fabs(outRight[i]-outLeft[i]*0.1f)<1e-6);
        }
    }
    MacMixAudioIOContextDestroy(context);
}

typedef struct { void *eq; _Atomic(bool) done; } Stress;
static void *producer(void *context) {
    Stress *stress = context;
    for (unsigned revision = 0; revision < 1000; ++revision) {
        double gains[10];
        for (unsigned b = 0; b < 10; ++b) gains[b] = ((revision + b * 7) % 25) - 12.0;
        MacMixEQSetGains(stress->eq, gains, revision % 7 != 0);
        MacMixEQSetMetering(stress->eq, revision % 7 != 0);
        float bars[MacMixEQSpectrumBarCount];
        if (MacMixEQCopySpectrum(stress->eq, bars, MacMixEQSpectrumBarCount)) {
            for (unsigned i = 0; i < MacMixEQSpectrumBarCount; ++i) assert(isfinite(bars[i]) && bars[i] >= 0 && bars[i] <= 1);
        }
    }
    atomic_store(&stress->done, true);
    return NULL;
}
static void concurrencyTest(void) {
    Stress stress = {.eq = MacMixEQCreate(48000, 2)};
    atomic_init(&stress.done, false);
    pthread_t thread;
    assert(pthread_create(&thread, NULL, producer, &stress) == 0);
    while (!atomic_load(&stress.done)) {
        MacMixEQBeginBlock(stress.eq);
        for (unsigned i = 0; i < 128; ++i) {
            double frame[2] = {0.25,-0.25};
            MacMixEQProcessFrame(stress.eq, frame, 2);
            double l = frame[0], r = frame[1];
            assert(isfinite(l) && isfinite(r));
            assert(fabs(l) <= 1 && fabs(r) <= 1);
            MacMixEQObserveSample(stress.eq, l, 0);
            MacMixEQObserveSample(stress.eq, r, 1);
        }
        MacMixEQEndBlock(stress.eq);
    }
    pthread_join(thread, NULL);
    MacMixEQDestroy(stress.eq);
}
static unsigned routingEffectFrames;
static void routingFrameEffect(void *unused, double *samples, uint32_t channels) {
    (void)unused;
    ++routingEffectFrames;
    for (uint32_t i = 0; i < channels; ++i) samples[i] *= 0.5;
}
static void multiOutputRoutingTest(void) {
    AudioStreamBasicDescription format = { .mSampleRate = 48000, .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        .mBytesPerPacket = 8, .mFramesPerPacket = 1, .mBytesPerFrame = 8,
        .mChannelsPerFrame = 2, .mBitsPerChannel = 32 };
    MacMixAudioTapConfiguration configs[2] = {
        {.format = format, .inputBufferOffset = 0, .inputBufferCount = 1, .initialGain = 1, .targetGain = 1},
        {.format = format, .inputBufferOffset = 1, .inputBufferCount = 1, .initialGain = 0.5, .targetGain = 0.5}
    };
    uint32_t outputIndices[] = {0,1,2};
    void *context = MacMixAudioIOContextCreate(configs, 2, outputIndices, 3);
    assert(context);
    // App A goes to two stereo outputs; App B only to the second output.
    MacMixAudioOutputChannel a[] = {
        {.format=format, .bufferIndex=0, .channelIndex=0, .sourceChannel=0},
        {.format=format, .bufferIndex=0, .channelIndex=1, .sourceChannel=1},
        {.format=format, .bufferIndex=1, .channelIndex=0, .sourceChannel=0},
        {.format=format, .bufferIndex=1, .channelIndex=1, .sourceChannel=1}
    };
    assert(MacMixAudioIOContextSetOutputChannels(context, 0, a, 4));
    assert(MacMixAudioIOContextSetOutputChannels(context, 1, a + 2, 2));
    MacMixAudioIOContextSetFrameEffect(context, 0, routingFrameEffect);
    float sourceA[] = {0.2f,0.4f,0.6f,0.8f}, sourceB[] = {0.4f,0.2f,0.2f,0.4f};
    float first[4] = {9,9,9,9}, second[4] = {9,9,9,9}, unrelated[4] = {9,9,9,9};
    struct { UInt32 count; AudioBuffer buffers[2]; } input = {2, {{2,sizeof(sourceA),sourceA},{2,sizeof(sourceB),sourceB}}};
    struct { UInt32 count; AudioBuffer buffers[3]; } output = {3, {{2,sizeof(first),first},{2,sizeof(second),second},{2,sizeof(unrelated),unrelated}}};
    AudioTimeStamp time = {0};
    routingEffectFrames = 0;
    MacMixAudioDeviceIOProc(0,&time,(AudioBufferList *)&input,&time,(AudioBufferList *)&output,&time,context);
    assert(routingEffectFrames == 2); // One effect invocation per frame, not per output.
    for (unsigned i = 0; i < 4; ++i) {
        assert(fabs(first[i] - sourceA[i] * 0.5) < 1e-6);
        assert(fabs(second[i] - (sourceA[i] + sourceB[i]) * 0.5) < 1e-6);
        assert(unrelated[i] == 0);
    }
    // All destinations disconnected: consume the tapped stream, emit nothing.
    assert(MacMixAudioIOContextSetOutputChannels(context, 0, NULL, 0));
    assert(MacMixAudioIOContextSetOutputChannels(context, 1, NULL, 0));
    MacMixAudioDeviceIOProc(0,&time,(AudioBufferList *)&input,&time,(AudioBufferList *)&output,&time,context);
    for (unsigned i = 0; i < 4; ++i) assert(first[i] == 0 && second[i] == 0 && unrelated[i] == 0);

    // Mixed output formats, mono downmix, and a truncated destination are bounded.
    AudioStreamBasicDescription mono = format;
    mono.mChannelsPerFrame = 1; mono.mBitsPerChannel = 16; mono.mBytesPerFrame = 2; mono.mBytesPerPacket = 2;
    mono.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    int16_t monoData[2] = {0};
    MacMixAudioOutputChannel monoRoute = {.format=mono,.bufferIndex=0,.sourceChannel=UINT32_MAX};
    assert(MacMixAudioIOContextSetOutputChannels(context, 0, &monoRoute, 1));
    output.buffers[0] = (AudioBuffer){1,sizeof(int16_t),monoData};
    MacMixAudioDeviceIOProc(0,&time,(AudioBufferList *)&input,&time,(AudioBufferList *)&output,&time,context);
    assert(abs(monoData[0] - (int)round(0.15 * 32768)) <= 1);
    assert(monoData[1] == 0);
    assert(!MacMixAudioIOContextSetOutputChannels(context, 0, NULL, 1));
    MacMixAudioIOContextDestroy(context);

    // Replacement graph warms silently; complementary post-DSP ramps preserve
    // the shared device's level throughout a device addition.
    for (unsigned oldWasRouted = 0; oldWasRouted < 2; ++oldWasRouted) {
    void *oldGraph = MacMixAudioIOContextCreate(configs, 1, outputIndices, 1);
    void *newGraph = MacMixAudioIOContextCreate(configs, 1, outputIndices, 1);
    assert(oldGraph && newGraph);
    if (oldWasRouted) assert(MacMixAudioIOContextSetOutputChannels(oldGraph, 0, a, 2));
    assert(MacMixAudioIOContextSetOutputChannels(newGraph, 0, a, 2));
    MacMixAudioIOContextSetFrameEffect(oldGraph, 0, routingFrameEffect);
    MacMixAudioIOContextSetFrameEffect(newGraph, 0, routingFrameEffect);
    MacMixAudioIOContextSetInitialOutputGain(newGraph, 0);
    output.buffers[0] = (AudioBuffer){2,sizeof(first),first};
    MacMixAudioDeviceIOProc(0,&time,(AudioBufferList *)&input,&time,(AudioBufferList *)&output,&time,newGraph);
    for (unsigned i = 0; i < 4; ++i) assert(first[i] == 0);
    assert(MacMixAudioIOContextRenderedFrames(newGraph) == 2);
    MacMixAudioIOContextSetOutputGain(oldGraph, 0);
    MacMixAudioIOContextSetOutputGain(newGraph, 1);
    for (unsigned block = 0; block < 1000; ++block) {
        MacMixAudioDeviceIOProc(0,&time,(AudioBufferList *)&input,&time,(AudioBufferList *)&output,&time,oldGraph);
        float previous[4]; memcpy(previous, first, sizeof(previous));
        MacMixAudioDeviceIOProc(0,&time,(AudioBufferList *)&input,&time,(AudioBufferList *)&output,&time,newGraph);
        for (unsigned i = 0; i < 4; ++i) assert(fabs(previous[i] + first[i] - sourceA[i] * 0.5) < 1e-5);
    }
    assert(MacMixAudioIOContextRenderedOutputGain(oldGraph) == 0);
    assert(MacMixAudioIOContextRenderedOutputGain(newGraph) == 1);
    assert(MacMixAudioIOContextRenderedGain(oldGraph, 0) == 1); // App volume wasn't used to fade the graph.
    MacMixAudioIOContextDestroy(oldGraph);
    MacMixAudioIOContextDestroy(newGraph);
    }
}

static void retainedDestinationTest(void) {
    AudioStreamBasicDescription f = {.mSampleRate=48000,.mFormatID=kAudioFormatLinearPCM,
        .mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,.mBytesPerPacket=8,
        .mFramesPerPacket=1,.mBytesPerFrame=8,.mChannelsPerFrame=2,.mBitsPerChannel=32};
    MacMixAudioTapConfiguration configs[2] = {
        {.format=f,.inputBufferCount=1,.initialGain=1,.targetGain=1},
        {.format=f,.inputBufferOffset=1,.inputBufferCount=1,.initialGain=1,.targetGain=1}};
    uint32_t indices[2] = {0,1};
    void *context = MacMixAudioIOContextCreate(configs,2,indices,2);
    MacMixAudioOutputChannel channels[4] = {
        {.format=f,.bufferIndex=0,.channelIndex=0,.sourceChannel=0,.destinationIndex=0},
        {.format=f,.bufferIndex=0,.channelIndex=1,.sourceChannel=1,.destinationIndex=0},
        {.format=f,.bufferIndex=1,.channelIndex=0,.sourceChannel=0,.destinationIndex=1},
        {.format=f,.bufferIndex=1,.channelIndex=1,.sourceChannel=1,.destinationIndex=1}};
    assert(MacMixAudioIOContextSetOutputChannels(context,0,channels,4));
    assert(MacMixAudioIOContextSetOutputChannels(context,1,channels,4));
    MacMixAudioIOContextSetDestinationMask(context,0,3,true);
    MacMixAudioIOContextSetDestinationMask(context,1,2,true);
    MacMixAudioIOContextSetFrameEffect(context,0,routingFrameEffect);
    float a[4]={0.25,0.25,0.25,0.25}, b[4]={0.1,0.1,0.1,0.1}, first[4], second[4];
    struct { UInt32 count; AudioBuffer buffers[2]; } input={2,{{2,sizeof(a),a},{2,sizeof(b),b}}};
    struct { UInt32 count; AudioBuffer buffers[2]; } output={2,{{2,sizeof(first),first},{2,sizeof(second),second}}};
    AudioTimeStamp stamp={0};
    for (unsigned phase=0;phase<3;++phase) {
        // Remove B, re-enable B, then remove B again without replacing context or DSP.
        MacMixAudioIOContextSetDestinationMask(context,0,phase==1?3:1,false);
        for (unsigned block=0;block<1200;++block) {
            MacMixAudioDeviceIOProc(0,&stamp,(AudioBufferList *)&input,&stamp,(AudioBufferList *)&output,&stamp,context);
            for (unsigned i=0;i<4;++i) {
                assert(first[i]==0.125f); // Retained output never fades, doubles, or skips a sample.
                assert(second[i]>=0.09999f && second[i]<=0.22501f);
            }
        }
        for (unsigned i=0;i<4;++i) assert(fabs(second[i]-(phase==1?0.225:0.1))<1e-6);
    }
    MacMixAudioIOContextDestroy(context);
    puts("Destination changes: retained output sample-exact; removed output fades; other app isolated.");
}

static void timedOutputHandoffTest(void) {
    AudioStreamBasicDescription format = {.mSampleRate=48000,.mFormatID=kAudioFormatLinearPCM,
        .mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,.mBytesPerPacket=8,
        .mFramesPerPacket=1,.mBytesPerFrame=8,.mChannelsPerFrame=2,.mBitsPerChannel=32};
    MacMixAudioTapConfiguration configuration = {.format=format,.inputBufferCount=1,.initialGain=1,.targetGain=1};
    uint32_t index = 0;
    MacMixAudioOutputChannel channels[] = {
        {.format=format,.bufferIndex=0,.channelIndex=0,.sourceChannel=0},
        {.format=format,.bufferIndex=0,.channelIndex=1,.sourceChannel=1}
    };
    float signal[4] = {0.25,0.25,0.25,0.25}, samples[4];
    AudioBufferList input = {1,{{2,sizeof(signal),signal}}}, output = {1,{{2,sizeof(samples),samples}}};
    mach_timebase_info_data_t base; mach_timebase_info(&base);
    double ticksPerFrame = 1e9 * base.denom / base.numer / 48000;
    double peaks[2] = {0};
    for (unsigned timed = 0; timed < 2; ++timed) {
        void *old = MacMixAudioIOContextCreate(&configuration,1,&index,1);
        void *next = MacMixAudioIOContextCreate(&configuration,1,&index,1);
        assert(old && next);
        assert(MacMixAudioIOContextSetOutputChannels(old,0,channels,2));
        assert(MacMixAudioIOContextSetOutputChannels(next,0,channels,2));
        MacMixAudioIOContextSetInitialOutputGain(next,0);
        uint64_t start = MacMixAudioOutputFadeStartTime(0.1);
        if (timed) {
            MacMixAudioIOContextScheduleOutputGain(old,1,0,start,0.04);
            MacMixAudioIOContextScheduleOutputGain(next,0,1,start,0.04);
        } else {
            MacMixAudioIOContextSetOutputGain(old,0);
            MacMixAudioIOContextSetOutputGain(next,1);
        }
        AudioTimeStamp stamp = {.mFlags=kAudioTimeStampHostTimeValid};
        // The incoming callback gets a 512-frame head start. The outgoing
        // callback then joins at that same presentation timestamp.
        for (unsigned frame=0; frame<512; frame+=2) {
            stamp.mHostTime=start+(uint64_t)(frame*ticksPerFrame);
            MacMixAudioDeviceIOProc(0,&stamp,&input,&stamp,&output,&stamp,next);
        }
        for (unsigned frame=512; frame<2600; frame+=2) {
            stamp.mHostTime=start+(uint64_t)(frame*ticksPerFrame);
            MacMixAudioDeviceIOProc(0,&stamp,&input,&stamp,&output,&stamp,old);
            float previous[4]; memcpy(previous,samples,sizeof(previous));
            MacMixAudioDeviceIOProc(0,&stamp,&input,&stamp,&output,&stamp,next);
            for (unsigned sample=0; sample<4; ++sample) {
                double combined=(previous[sample]+samples[sample])/signal[sample];
                peaks[timed]=fmax(peaks[timed],combined);
                if (timed) assert(fabs(combined-1)<1e-5);
            }
        }
        assert(MacMixAudioIOContextRenderedOutputGain(old)==0);
        assert(MacMixAudioIOContextRenderedOutputGain(next)==1);
        MacMixAudioIOContextDestroy(old); MacMixAudioIOContextDestroy(next);
    }
    assert(peaks[0]>1.2);
    printf("Crossfade with 512-frame skew: independent peak %.4f, shared-timeline peak %.4f\n",peaks[0],peaks[1]);
}

int main(void) {
    assert(MacMixEQCreate(0, 2) == NULL);
    assert(MacMixEQCreate(48000, 65) == NULL);
    toneAndConversionTests(); retuningContinuityTest();
    distortionTest(false, false); distortionTest(true, false); distortionTest(true, true);
    planarLinkedLimiterTest(); frameFormatRoundTripTests();
    frequencyTests(); isolationAndBypassTests(); integrationTest(); volumeBeforeLimitingTest(); boostedVolumeLimiterTest(); spectrumTests(); concurrencyTest();
    multiOutputRoutingTest();
    timedOutputHandoffTest();
    retainedDestinationTest();
    puts("EQ DSP: frequency response, unity loudness, channel isolation, bypass, IO integration, real output spectrum and concurrent updates passed.");
}
