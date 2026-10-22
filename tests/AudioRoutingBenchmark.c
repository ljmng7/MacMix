#include "MacMixAudioIOProc.h"
#include "MacMixEQDSP.h"
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
static double clockSeconds(void) {struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec/1e9;}
int main(void) {
 AudioStreamBasicDescription f={.mSampleRate=48000,.mFormatID=kAudioFormatLinearPCM,.mFormatFlags=kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,.mBytesPerPacket=8,.mFramesPerPacket=1,.mBytesPerFrame=8,.mChannelsPerFrame=2,.mBitsPerChannel=32};
 MacMixAudioTapConfiguration config={.format=f,.inputBufferCount=1,.initialGain=0.7,.targetGain=0.7};
 uint32_t indices[2]={0,1}; MacMixAudioOutputChannel channels[4]={
 {.format=f,.bufferIndex=0,.channelIndex=0,.sourceChannel=0,.destinationIndex=0},
 {.format=f,.bufferIndex=0,.channelIndex=1,.sourceChannel=1,.destinationIndex=0},
 {.format=f,.bufferIndex=1,.channelIndex=0,.sourceChannel=0,.destinationIndex=1},
 {.format=f,.bufferIndex=1,.channelIndex=1,.sourceChannel=1,.destinationIndex=1}};
 float input[1024],a[1024],b[1024];for(int i=0;i<1024;i++)input[i]=(i%17-8)*0.025f;
 AudioBufferList in={1,{{2,sizeof(input),input}}};struct{UInt32 count;AudioBuffer buffers[2];}out={2,{{2,sizeof(a),a},{2,sizeof(b),b}}};AudioTimeStamp time={0};
 for(int effect=0;effect<3;effect++) {
 void*c=MacMixAudioIOContextCreate(&config,1,indices,2);MacMixAudioIOContextSetOutputChannels(c,0,channels,4);
 if(effect){void*eq=MacMixEQCreate(48000,2);double gains[10]={0};gains[5]=effect==2?6:0;MacMixEQSetGains(eq,gains,effect==2);MacMixAudioIOContextSetEffect(c,0,eq,MacMixEQBeginBlock,NULL,MacMixEQDestroy);MacMixAudioIOContextSetFrameEffect(c,0,MacMixEQProcessFrame);}
 double start=clockSeconds();for(int i=0;i<20000;i++)MacMixAudioDeviceIOProc(0,&time,&in,&time,(AudioBufferList*)&out,&time,c);
 printf("effect=%d 10.24M frames %.4f s checksum=%f\n",effect,clockSeconds()-start,a[100]+b[100]);MacMixAudioIOContextDestroy(c);
 }
}
