//
//  VideoEncoder.swift
//  NeRFCapture
//
//  Created by Jad on 29/4/2023.
//

//struct PosedVideoFrame {
//    let nalus: CMSampleBuffer
//    let pose: simd_float4x4
//    let timestamp: TimeInterval
//}



import Foundation
import AVFoundation
import VideoToolbox
import CoreFoundation
import Combine
import ARKit

public struct PosedVideoFrame {
    let isKeyframe: Bool
    let nalus: Data
    let width: UInt32
    let height: UInt32
    let flX: Float
    let flY: Float
    let cx: Float
    let cy: Float
    let xWV: simd_float4x4
    let timestamp: Double
}


enum VideoError: Error {
    case sessionNotCreated
    case parameterNotCreated
}

enum VideoSource {
    case color
    case depth
}


public class VideoEncoder {
    private var width: Int = 640
    private var height: Int = 480
    private var fps: Int = 60
    private var settings: VideoSettings?
    private var forceKey = false
    private var source: VideoSource
    private var session: VTCompressionSession?
    let frame$ = PassthroughSubject<(ARFrame, Data?), Never>()
    
    init (width: Int, height: Int, fps: Int, source: VideoSource, settings: VideoSettings) throws {
        self.settings = settings
        self.width = width
        self.height = height
        self.fps = fps
        self.source = source
        
        let err = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height),
                                             codecType: settings.codec.value, encoderSpecification: nil, imageBufferAttributes: nil,
                                             compressedDataAllocator: nil, outputCallback: videoCallback, refcon: Unmanaged.passUnretained(self).toOpaque(),
                                             compressionSessionOut: &session)
        
        //VTSessionSetProperty(compressionSession!, key: kVTCompressionPropertyKey_DataRateLimits, value: [bitRate/8, 1] as CFArray)
        if err == errSecSuccess{
            guard let sess = session else { throw VideoError.sessionNotCreated }
            VTSessionSetProperties(sess, propertyDictionary: [
                kVTCompressionPropertyKey_ProfileLevel: settings.codec.profile,
                kVTCompressionPropertyKey_AverageBitRate: settings.bitrate,
                kVTCompressionPropertyKey_MaxKeyFrameInterval: settings.keyframeInterval,
                kVTCompressionPropertyKey_ExpectedFrameRate: fps,
                kVTCompressionPropertyKey_AllowFrameReordering: false,
                kVTCompressionPropertyKey_RealTime: true,
                kVTCompressionPropertyKey_Quality: 0.25,
            ] as [CFString : Any] as CFDictionary)
        }else{
            throw VideoError.sessionNotCreated
        }
    }
    
    deinit {
        if let session = self.session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: CMTime.invalid)
            VTCompressionSessionInvalidate(session)
        }
    }
    
    public func forceKeyframe() {
        forceKey = true
    }
    
    func encode(frame: ARFrame) -> OSStatus {
        let timeScale = CMTimeScale(NSEC_PER_SEC)
        let presentationTime = CMTimeMakeWithSeconds(frame.timestamp, preferredTimescale: timeScale)
        var properties: Dictionary<String, Any>?
        if (forceKey) {
            forceKey = false
            properties = [
                kVTEncodeFrameOptionKey_ForceKeyFrame as String: true
            ];
        }

        var flag:VTEncodeInfoFlags = VTEncodeInfoFlags()
        var pixelBuffer: CVPixelBuffer? = nil
        switch self.source {
        case .color:
            pixelBuffer = frame.capturedImage
        case .depth:
            pixelBuffer = frame.sceneDepth?.depthMap
        }
        
        if pixelBuffer == nil {
            print("pixelBuffer nil")
            return -1
        }
        
        let res = VTCompressionSessionEncodeFrame(
            session!,
            imageBuffer:  pixelBuffer!,
            presentationTimeStamp: presentationTime,
            duration: CMTime.invalid,
            frameProperties: properties as CFDictionary?,
            sourceFrameRefcon: Unmanaged.passRetained(frame).toOpaque(),
            infoFlagsOut: &flag)
        return res
    }
    
    
    private var videoCallback: VTCompressionOutputCallback = {(outputCallbackRefCon: UnsafeMutableRawPointer?, sourceFrameRefCon: UnsafeMutableRawPointer?,
                                                               status: OSStatus, flags: VTEncodeInfoFlags, sampleBuffer: CMSampleBuffer?) in
        
        let encoder = Unmanaged<VideoEncoder>.fromOpaque(outputCallbackRefCon!).takeUnretainedValue()
        let frame = Unmanaged<ARFrame>.fromOpaque(sourceFrameRefCon!).takeRetainedValue()
        
        if (status != noErr) {
            print("encoding failed")
            return
        }
        guard let sampleBuffer = sampleBuffer else {
            print("nil buffer")
            return
        }
        guard let refcon: UnsafeMutableRawPointer = outputCallbackRefCon else {
            print("nil pointer")
            return
        }
        if (!CMSampleBufferDataIsReady(sampleBuffer)) {
            print("data is not ready")
            return
        }
        
        if (flags == VTEncodeInfoFlags.frameDropped) {
            encoder.frame$.send((frame, nil))
            print("frame dropped")
            return
        }
        
        
        var res = convertBufferToAnnexB(sampleBuffer: sampleBuffer)
        guard var nalus = res else { print("Could not get NALUS"); return; }
        let isKeyframe = isKeyFrame(sampleBuffer: sampleBuffer)
        if(isKeyframe) {
            let parameter_nalus = getParameterData(sampleBuffer: sampleBuffer, codec: encoder.settings!.codec)
            guard let pnalus = parameter_nalus else { print("Could not get parameter NALUS"); return; }
            nalus = pnalus + nalus
        }
        encoder.frame$.send((frame, nalus))
//        let posedVideoFrame = PosedVideoFrame(
//            isKeyframe: isKeyframe,
//            nalus: nalus,
//            width: UInt32(frame.camera.imageResolution.width),
//            height: UInt32(frame.camera.imageResolution.height),
//            flX: frame.camera.intrinsics[0, 0],
//            flY: frame.camera.intrinsics[1, 1],
//            cx: frame.camera.intrinsics[2, 0],
//            cy: frame.camera.intrinsics[2, 1],
//            xWV: frame.camera.transform,
//            timestamp: frame.timestamp
//        )
//        encoder.frame$.send(posedVideoFrame)
    }
}

func getParameterData(sampleBuffer: CMSampleBuffer, codec: CodecUtil) -> Data? {
    guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    var parametersCount: Int = 0
    if (codec == .H264) {
        CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                           parameterSetSizeOut: nil, parameterSetCountOut: &parametersCount, nalUnitHeaderLengthOut: nil)
    } else if (codec == .HEVC) {
        CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                           parameterSetSizeOut: nil, parameterSetCountOut: &parametersCount, nalUnitHeaderLengthOut: nil)
    }
    if (codec == .H264 && parametersCount != 2 || codec == .HEVC && parametersCount < 3) {
        print("unexpected video parameters \(parametersCount)")
        return nil
    }
    var parameterData = Data()
    var parameterSetIndex = 0
    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    while true {
        var parameterSet: UnsafePointer<UInt8>?
        var parameterSetSize: Int = 0
        var parameterSetCount: Int = 0
        if codec == .H264 {
            CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: parameterSetIndex, parameterSetPointerOut: &parameterSet, parameterSetSizeOut: &parameterSetSize, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
        } else if codec == .HEVC {
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(description, parameterSetIndex: parameterSetIndex, parameterSetPointerOut: &parameterSet, parameterSetSizeOut: &parameterSetSize, parameterSetCountOut: &parameterSetCount, nalUnitHeaderLengthOut: nil)
        } else {
            break
        }

        parameterData.append(startCode, count: startCode.count)
        parameterData.append(parameterSet!, count: Int(parameterSetSize))
        parameterSetIndex += 1
        if parameterSetCount <= parameterSetIndex {
            break
        }
    }
    return parameterData
}

func convertBufferToAnnexB(sampleBuffer: CMSampleBuffer) -> Data? {
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        return nil
    }

    let startCode: [UInt8] = [0x00, 0x00, 0x00, 0x01]
    var lengthAtOffset: Int = 0
    var bufferOffset: Int = 0
    let avcHeaderLength = 4
    var dataPointer: UnsafeMutablePointer<Int8>?
    let totalLength = CMBlockBufferGetDataLength(dataBuffer)
    var naluData = Data(count: totalLength)
    var lengthsToDate: Int = 0

    while bufferOffset < totalLength - avcHeaderLength {
        _ = CMBlockBufferGetDataPointer(dataBuffer, atOffset: bufferOffset, lengthAtOffsetOut: &lengthAtOffset,
                                              totalLengthOut: nil, dataPointerOut: &dataPointer)
        if totalLength != lengthAtOffset {
            print("Warning: Non contiguous buffer")
        }
        while bufferOffset < lengthAtOffset - avcHeaderLength {
            var naluLength: UInt32 = 0
            memcpy(&naluLength, dataPointer?.advanced(by: bufferOffset - lengthsToDate), avcHeaderLength)
            naluLength = CFSwapInt32BigToHost(naluLength)
            naluData.withUnsafeMutableBytes { (naluDataPointer: UnsafeMutableRawBufferPointer) -> Void in
                naluDataPointer.baseAddress!.advanced(by: bufferOffset).copyMemory(from: startCode, byteCount: startCode.count)
                bufferOffset += Int(avcHeaderLength)
                CMBlockBufferCopyDataBytes(dataBuffer, atOffset: bufferOffset, dataLength: Int(naluLength), destination: naluDataPointer.baseAddress!.advanced(by: bufferOffset))
                bufferOffset += Int(naluLength)
            }
        }
        lengthsToDate += lengthAtOffset
    }
    return naluData
}

func isKeyFrame(sampleBuffer: CMSampleBuffer) -> Bool {
    guard
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
        let value = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool else {
        return true
    }
    return !value
}
