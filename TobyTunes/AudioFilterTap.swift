//
//  AudioFilterTap.swift
//  TobyTunes
//
//  Created by Toby Nelson on 09/08/2016.
//  Copyright © 2016 Agent Lobster. All rights reserved.
//
//  Automatic gain control, applied to playback through an MTAudioProcessingTap.
//  Algorithm based on code from
//  http://freesourcecode.net/matlabprojects/70700/automatic-gain-control-in-matlab
//
//  tap_ProcessCallback runs on a real-time audio thread: it must not allocate
//  memory, take locks or call into Objective-C.
//

import Foundation
import MediaToolbox
import Accelerate

/// Strength of the effect, 0 (off) ... 1 (full). Set from the About screen and saved as "agc".
var audioEffectAmount: Float = 0.0

/// Set while fast-forwarding / rewinding. Not currently used by the filter.
var isFastPlaying = false

/// Target average power of the output (about -10 dB).
private let outputPowerNormal: Float = 0.1

/// Never boost a buffer by more than this factor.
private let maximumGain: Float = 5.0

func tap_ProcessCallback(_ tap: MTAudioProcessingTap,
                         _ numberFrames: CMItemCount,
                         _ flags: MTAudioProcessingTapFlags,
                         _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                         _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                         _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    // Fetch the audio for processing (and for output)
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, flagsOut, nil, numberFramesOut)
    guard status == noErr else { return }

    let amount = audioEffectAmount
    guard amount > 0.0 else { return }

    for buffer in UnsafeMutableAudioBufferListPointer(bufferListInOut) {
        guard let data = buffer.mData else { continue }
        let samplesCount = vDSP_Length(buffer.mDataByteSize) / vDSP_Length(MemoryLayout<Float>.size)
        guard samplesCount > 0 else { continue }
        let samples = data.assumingMemoryBound(to: Float.self)

        // Average energy of the signal (mean of the squares of the samples)
        var energy: Float = 0.0
        vDSP_measqv(samples, 1, &energy, samplesCount)

        // Multiplier that brings the buffer to the target power, capped
        var gain: Float = 1.0
        if energy > 0.0 {
            gain = sqrtf(outputPowerNormal / energy)
        }
        gain = min(gain, maximumGain)

        // Scale by the effect amount
        gain = 1.0 + (gain - 1.0) * amount

        // Multiply every sample by the gain, in place
        vDSP_vsmul(samples, 1, &gain, samples, 1, samplesCount)
    }
}
