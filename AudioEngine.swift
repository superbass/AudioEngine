//
//  AudioEngine.swift
//  SaladBox
//
//  Created by Taewook Kim on 07/05/2019.
//  Copyright © 2019 SaladBox. All rights reserved.
//

import Foundation
import AVKit
import CoreAudio

class AudioEngine {
    var audioEngine: AVAudioEngine!
    var inputNode: AVAudioInputNode!
    var outputNode: AVAudioOutputNode!
    var outputFormat: AVAudioFormat!
    var audioConverter: AVAudioConverter!
    
    var completionHandler: ((CMSampleBuffer) -> Void)? = nil
    
    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        outputNode = audioEngine.outputNode
        outputFormat = outputNode.outputFormat(forBus: 0)
        audioEngine.connect(inputNode, to: outputNode, format: outputFormat)

        let inputFormat = inputNode.outputFormat(forBus: 0)
        var asbd = aacAsbd(sampleRate: inputFormat.sampleRate)
        let aacAudioFormat = AVAudioFormat(streamDescription: &asbd)
        
        audioConverter = AVAudioConverter(from: inputFormat, to: aacAudioFormat!)
        
        let compressedBuffer: AVAudioCompressedBuffer = AVAudioCompressedBuffer(format: aacAudioFormat!, packetCapacity: 5, maximumPacketSize: self.audioConverter.maximumOutputPacketSize)

        let frameCount: UInt32 = UInt32(inputFormat.sampleRate * 0.1)
        inputNode.installTap(onBus: 0, bufferSize: frameCount, format: inputFormat) { (pcmBuffer, audioTime) in
            let milliSeconds = AVAudioTime.seconds(forHostTime: audioTime.hostTime) * 1000
            let time = CMTimeMake(value: Int64(milliSeconds), timescale: 1000)
            
            let inputBlock: AVAudioConverterInputBlock = { (inPacketCount, outStatus) -> AVAudioBuffer? in
                if frameCount <= inPacketCount {
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return pcmBuffer
                }

                outStatus.pointee = AVAudioConverterInputStatus.noDataNow
                return nil
            }
            
            var error: NSError? = nil
            self.audioConverter.convert(to: compressedBuffer, error: &error, withInputFrom: inputBlock)
            
            let dataSize: Int = Int(compressedBuffer.audioBufferList.pointee.mBuffers.mDataByteSize) // for iOS 8.0
            
            let dataCopy = UnsafeMutableRawPointer.allocate(byteCount: dataSize, alignment: MemoryLayout<UInt8>.stride)
            dataCopy.copyMemory(from: compressedBuffer.data, byteCount: dataSize)

            var blockBuffer: CMBlockBuffer? = nil
            if kCMBlockBufferNoErr != CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: dataCopy, blockLength: Int(dataSize), blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: Int(dataSize), flags: 0, blockBufferOut: &blockBuffer) {
                return
            }

            var sampleBuffer: CMSampleBuffer? = nil
            CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: blockBuffer!, formatDescription: compressedBuffer.format.formatDescription, sampleCount: CMItemCount(compressedBuffer.packetCount), presentationTimeStamp: time, packetDescriptions: compressedBuffer.packetDescriptions, sampleBufferOut: &sampleBuffer)
            
            if sampleBuffer != nil {
                self.completionHandler?(sampleBuffer!)
            }
        }
    }
    
    func aacAsbd(sampleRate: Double) -> AudioStreamBasicDescription {
        let asbd = AudioStreamBasicDescription(mSampleRate: sampleRate,
                                               mFormatID: kAudioFormatMPEG4AAC,
                                               mFormatFlags: AudioFormatFlags(MPEG4ObjectID.AAC_LC.rawValue),
                                               mBytesPerPacket: 0,
                                               mFramesPerPacket: 1024,
                                               mBytesPerFrame: 0,
                                               mChannelsPerFrame: 1,
                                               mBitsPerChannel: 0,
                                               mReserved: 0)
        
        return asbd
    }
    
    func start() {
        audioEngine.prepare()
        try! audioEngine.start()
    }
    
    func stop() {
        audioEngine.stop()
    }
}
