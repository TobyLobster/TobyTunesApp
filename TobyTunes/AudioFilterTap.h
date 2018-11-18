//
//  AudioFilterTap.h
//  TobyTunes
//
//  Created by Toby Nelson on 09/08/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//

#include "CoreMedia/CoreMedia.h"
#include "MediaToolbox/MediaToolbox.h"

extern void tap_ProcessCallback(MTAudioProcessingTapRef tap, CMItemCount numberFrames, MTAudioProcessingTapFlags flags, AudioBufferList *bufferListInOut, CMItemCount *numberFramesOut, MTAudioProcessingTapFlags *flagsOut);
extern float audioEffectAmount;
extern BOOL isFastPlaying;