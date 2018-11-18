//
//  AudioFilterTap.m
//  TobyTunes
//
//  Created by Toby Nelson on 09/08/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

#import "AudioFilterTap.h"
@import Accelerate;

#define CHANNEL_LEFT 0
#define CHANNEL_RIGHT 1
#define NUM_CHANNELS 2

BOOL processAudio = YES;
BOOL isNonInterleaved = YES;
float gain_level = -10.0;     // output power level in db
float audioEffectAmount = 0.0;
float output_power_normal = 0.1;        //
BOOL isFastPlaying = NO;

void tap_ProcessCallback(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags, AudioBufferList *bufferListInOut, CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut) {
    // this fetches the audio for processing (and for output)
    OSStatus status;
    status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, NULL, numberFramesOut);

    if (processAudio && (audioEffectAmount>0.0)/* && (!isFastPlaying)*/) {

        // Algorithm based on code from http://freesourcecode.net/matlabprojects/70700/automatic-gain-control-in-matlab

        if (output_power_normal < 0.0) {
            output_power_normal = powf(10,gain_level/10);
        }

        for (UInt32 i = 0; i < bufferListInOut->mNumberBuffers; i++) {
            AudioBuffer* pBuffer = &bufferListInOut->mBuffers[i];

            CMItemCount samplesCount = pBuffer->mDataByteSize / sizeof(float);
            float * sample = (float*) pBuffer->mData;

            // Calculate average energy of the signal (the average of the square of each value)
            float energy = 0.0;
            vDSP_measqv( sample, 1, &energy, samplesCount );

            /* For reference - The above function (vDSP_measqv) is equivalent to:
            float energy = 0.0;
            for (UInt32 j = 0; j < samplesCount; j++) {
                energy += sample[j] * sample[j];
            }
            energy /= samplesCount;
            */

            // Calculate multiplier for samples
            float K = 1.0;
            if (energy > 0) {
                K = sqrtf(output_power_normal / energy);
            }
            // Don't boost too much
            K = MIN(K, 5.0f);

            // Scale by the effect amount
            K = 1 + (K-1)*audioEffectAmount;

            // Multiply each sample by K
            vDSP_vsmul( sample, 1, &K, sample, 1, samplesCount );

            /* For reference - the above function (vDSP_vsmul) is equivalent to:
            for (UInt32 j = 0; j < samplesCount; j++) {
                sample[j] = sample[j] * K;
            }
            */
        }
    }
}
