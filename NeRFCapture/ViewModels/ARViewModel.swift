//
//  ARViewModel.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import Foundation
import Zip
import Combine
import ARKit
import RealityKit
import SwiftUI
import Compression


enum AppError : Error {
    case projectAlreadyExists
    case manifestInitializationFailed
    case encoderError
}



class ARViewModel : NSObject, ARSessionDelegate, ObservableObject {
    var session: ARSession? = nil
    var arView: ARView? = nil
    
    @AppStorage("startingMode") var startingMode: AppMode = .Snap
    @Published var mode: AppMode = .Snap
    @Published var error: Bool = false
    @Published var error_msg: String = ""
    
    // SETTINGS
    @Published var arSettings = ARSettings()
    @Published var ddsSettings = DDSSettings()
    @Published var videoSettings = VideoSettings()
    
    // STATE
    @Published var streamMode = StreamModeState()
    @Published var snapMode = SnapModeState()
    @Published var saveMode = SaveModeState()
    
    @Published var dds = DDSState()
    @Published var ar = ARState()
    
    // STREAMS
    let frame$ = PassthroughSubject<ARFrame, Never>()
    var cancellables = Set<AnyCancellable>()
    var stream_cancellables = Set<AnyCancellable>()
    var snap_cancellables = Set<AnyCancellable>()
    var save_cancellables = Set<AnyCancellable>()
    
    // WRITERS
    var datasetWriter: DatasetWriter?
    var ddsSnapWriter: DDSSnapWriter?
    var ddsStreamWriter: DDSStreamWriter?
    var videoEncoder: VideoEncoder?
    
    var compressionBuffer: UnsafeMutablePointer<UInt8>
    let bufferSize = 262144
    let compressionAlgorithm = COMPRESSION_ZLIB
    
    override init() {
        compressionBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        super.init()
        mode = startingMode
        frame$.first().sink { _ in
            self.setupListeners()
        }.store(in: &cancellables)
   }
   
    deinit{
        compressionBuffer.deallocate()
    }
    
    func setupListeners() {
          // Clean and Setup after every mode change
        $mode
            .prepend(mode)
           // .removeDuplicates()
            .scan((nil, nil)) { (previous, current) in
                (previous.1, current)
            }
            .sink { x in
                self.error = false
                self.error_msg = ""
                
                if let previous = x.0 {
                    switch previous {
                    case .Save: self.cleanSave()
                    case .Stream: self.cleanStream()
                    case .Snap: self.cleanSnap()
                    }
                }
                
                if let current = x.1 {
                    switch current {
                    case .Save: self.setupSave()
                    case .Stream: self.setupStream()
                    case .Snap: self.setupSnap()
                    }
                    self.startingMode = current
                }
                
            }
            .store(in: &cancellables)
       
    }
    
    func setupSave() {
        datasetWriter = DatasetWriter()
    }
    func cleanSave() {
        datasetWriter = nil
    }
    
    func setupStream() {
        streamMode = StreamModeState()
        // Setup DDS
        do {
            dds = DDSState()
            dds.domainID = ddsSettings.domainID
            ddsStreamWriter = try DDSStreamWriter(domainID: ddsSettings.domainID)
            ddsStreamWriter!.peers.sink {x in self.dds.peers = UInt32(x)}.store(in: &stream_cancellables)
        } catch let error {
            self.error_msg = "\(error)"
            self.error = true
            cleanSnap()
            return
        }
        
        // Setup Video Encoder
        do {
            try startVideoEncoders()
        } catch let error {
            videoEncoder = nil
            self.error_msg = "\(error)"
            self.error = true
            cleanSnap()
            return
        }
            
        let throttleTime = self.videoSettings.throttleTimeMs/1000.0
        var frame_stream = self.frame$.eraseToAnyPublisher()
        if videoSettings.throttle {
            frame_stream = self.frame$
                .throttle(for: RunLoop.SchedulerTimeType.Stride(throttleTime), scheduler: RunLoop.main, latest: true).eraseToAnyPublisher()
        }
        
        frame_stream
            .sink { [self] frame in
                guard self.streamMode.streaming else { return }
                guard self.ddsSettings.streamPoseTopic  else { return }
                ddsStreamWriter?.writePoseToTopic(frame: frame)
            }
            .store(in: &stream_cancellables)
            
        
        frame_stream
            .sink { [self] frame in
                guard self.streamMode.streaming else { return }
                guard self.ddsSettings.streamVideoTopic  else { return }
                _ = self.videoEncoder!.encode(frame: frame)
            }
            .store(in: &stream_cancellables)
        
        var depthStream = frame_stream
            .filter {_ in
                return self.streamMode.streaming
            }
            .map { [self] frame in
                return (frame, compressDepth(depthMap: frame.sceneDepth!.depthMap))
            }
        
        
        ddsStreamWriter!.domain.peers$.sink {
            x in
            print("Forcing Keyframe on publication match")
            self.videoEncoder!.forceKeyframe()
        }.store(in: &stream_cancellables)
        
        let videoStream = videoEncoder!.frame$.eraseToAnyPublisher()

        if self.arSettings.isDepthEnabled {
            videoStream.zip(depthStream).sink { x in
                let frameVideo = x.0.0
                let frameDepth = x.1.0
                guard frameVideo == frameDepth else {
                    print("Frames don't match")
                    return
                }
            }
            .store(in: &stream_cancellables)
        }
        else {
            videoStream
                .sink { x in
                    print("decoded frame")
                    let frame = x.0
                    let nalus = x.1
    //                self.ddsStreamWriter!.writeFrameToTopic(frame: frame)
                }
                .store(in: &stream_cancellables)
            
        }
            
    }
    
    func compressDepth(depthMap: CVPixelBuffer) -> Data {
//        let depthWidth = CVPixelBufferGetWidth(depthMap)
//        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let depthSize = CVPixelBufferGetDataSize(depthMap)
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        let baseAddress = CVPixelBufferGetBaseAddress(depthMap)
        let compressedSize = compression_encode_buffer(compressionBuffer, self.bufferSize, baseAddress!, depthSize, nil, compressionAlgorithm) // 10 ms, apple one is 3ms
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        let data = Data(bytes: compressionBuffer, count: compressedSize)
        return data
    }
    
    func cleanStream() {
        videoEncoder = nil // order matters since videoEncoder will try to publish to ddsStreamWriter
        ddsStreamWriter = nil
        stream_cancellables = Set<AnyCancellable>()
    }
    
    func setupSnap() {
        snapMode = SnapModeState()
        do {
            dds = DDSState()
            dds.domainID = ddsSettings.domainID
            ddsSnapWriter = try DDSSnapWriter(domainID: ddsSettings.domainID)
            ddsSnapWriter!.peers.sink {x in self.dds.peers = UInt32(x)}.store(in: &snap_cancellables)
        }
        catch let error {
            self.error_msg = "\(error)"
            self.error = true
            cleanSnap()
        }
        
        var frame_stream = self.frame$.eraseToAnyPublisher()
        let throttleTime = self.videoSettings.throttleTimeMs/1000.0
        if videoSettings.throttle {
            frame_stream = self.frame$
                .throttle(for: RunLoop.SchedulerTimeType.Stride(throttleTime), scheduler: RunLoop.main, latest: true).eraseToAnyPublisher()
        }
        frame_stream
            .sink { [self] frame in
                guard self.ddsSettings.streamPoseTopic  else { return }
                guard !self.ddsSettings.snapPoseOnly  else { return }
                self.ddsSnapWriter?.writePoseToTopic(frame: frame, action: self.snapMode.actionButtonState)
            }
            .store(in: &stream_cancellables)
    }
    
    func cleanSnap() {
        ddsSnapWriter = nil
        snap_cancellables = Set<AnyCancellable>()
    }
    
    func setup() {
        restartARKit()
    }
    
    func restartARKit() {
        session?.pause()
        let configuration = createARConfiguration()
#if !targetEnvironment(simulator)
        session?.run(configuration, options: [.resetTracking, .removeExistingAnchors])
#endif
    }
    
    func createARConfiguration() -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.videoFormat = ARWorldTrackingConfiguration.supportedVideoFormats[arSettings.selectedFormatIndex]
        configuration.worldAlignment = arSettings.worldAlignment
        configuration.isAutoFocusEnabled = arSettings.isAutoFocusEnabled
        if arSettings.isDepthEnabled {
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                // Activate sceneDepth
                configuration.frameSemantics = .sceneDepth
            }
        }
        return configuration
    }
    

    func startVideoEncoders() throws {
        guard let videoFormat = session?.configuration?.videoFormat else {
            throw AppError.encoderError
        }
        
        let width = videoFormat.imageResolution.width
        let height = videoFormat.imageResolution.height
        let fps = videoFormat.framesPerSecond
        
        videoEncoder = try VideoEncoder(width: Int(width), height: Int(height), fps: fps, source: .color, settings: videoSettings)
        videoEncoder?.frame$.sink {
            comressedFrame in
        }.store(in: &stream_cancellables)
        
    }
    
    func session(
        _ session: ARSession,
        didUpdate frame: ARFrame
    ) {
        frame$.send(frame)
    }
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        self.ar.trackingState = trackingStateToString(camera.trackingState)
    }
}
