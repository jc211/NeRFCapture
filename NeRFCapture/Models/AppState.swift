//
//  AppState.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import Foundation
import Metal
import MetalKit
import SwiftUI
import ARKit
import VideoToolbox

enum AppMode: Int, Codable {
    case Stream
    case Snap
    case Save
}

struct ARSettings {
    @AppStorage("selectedFormatIndex") var selectedFormatIndex: Int = 0
    @AppStorage("isDepthEnabled") var isDepthEnabled: Bool = false
    @AppStorage("isAutoFocusEnabled") var isAutoFocusEnabled: Bool = true
    @AppStorage("worldAlignment") var worldAlignment: ARConfiguration.WorldAlignment = .gravity
}

struct DDSSettings {
    @AppStorage("domainID") var domainID: Int = 0 {
        didSet {
            if domainID < 0 || domainID > 300 {
                domainID = 0
            }
        }
    }
    
    @AppStorage("streamID") var streamID: Int = 0 {
        didSet {
            if streamID < 0 {
                streamID = 0
            }
        }
    }
}

struct VideoSettings {
    var codec = CodecUtil.HEVC
    @AppStorage("bitRate") var bitrate: Int = 1500 * 1000 {
        didSet {
            if bitrate < 100 * 1000 {
                bitrate = 100 * 1000
            }
        }
    }
    @AppStorage("keyframeInterval") var keyframeInterval: Int = 2 {
        didSet {
            if keyframeInterval < 0 {
                keyframeInterval = 0
            }
        }
    }
    @AppStorage("throttle") var throttle: Bool = false
        
    @AppStorage("throttleTimeMs") var throttleTimeMs = 0.0 {
        didSet {
            if throttleTimeMs < 0.0 {
                throttleTimeMs = 0.0
                throttle = false
            }
        }
    }
}

struct AppState {
    var numFrames = 0
}

struct ARState {
    var trackingState = ""
    var supportsDepth = false
}

struct StreamModeState {
    var streaming = false
}

struct SnapModeState {
    
}

struct SaveModeState {
    var writerState: DatasetWriter.SessionState = .SessionNotStarted
    var projectName = ""
}

struct DDSState {
    var domainID: Int = 0
    var peers: UInt32 = 0
    var ready = false
}


struct MetalState {
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!
    var sharedUniformBuffer: MTLBuffer!
    var imagePlaneVertexBuffer: MTLBuffer!
    var capturedImagePipelineState: MTLRenderPipelineState!
    var capturedImageTextureY: CVMetalTexture?
    var capturedImageTextureCbCr: CVMetalTexture?
    var capturedImageTextureCache: CVMetalTextureCache!
}

public enum CodecUtil {
    case H264
    case HEVC

    var value: CMVideoCodecType {
        switch self {
        case .H264:
            return kCMVideoCodecType_H264
        case .HEVC:
            return kCMVideoCodecType_HEVC
        }
    }

    var profile: CFString {
        switch self {
        case .H264:
            return kVTProfileLevel_H264_Baseline_AutoLevel
        case .HEVC:
            return kVTProfileLevel_HEVC_Main_AutoLevel
        }
    }
}
