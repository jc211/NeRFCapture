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
    
    override init() {
        super.init()
        mode = startingMode
        // Clean and Setup after every mode change
        $mode
            .prepend(mode)
           // .removeDuplicates()
            .scan((nil, nil)) { (previous, current) in
                (previous.1, current)
            }
            .sink { x in
                
                print(x)
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
        
    }
    func cleanSave() {
        
    }
    
    func setupStream() {
        do {
            streamMode = StreamModeState()
            dds = DDSState()
            dds.domainID = ddsSettings.domainID
            ddsStreamWriter = try DDSStreamWriter(domainID: ddsSettings.domainID)
            ddsStreamWriter!.peers.sink {x in self.dds.peers = UInt32(x)}.store(in: &stream_cancellables)
            try startVideoEncoder()
           
            let throttleTime = videoSettings.throttleTimeMs/1000.0
            if videoSettings.throttle {
                frame$
                    .throttle(for: RunLoop.SchedulerTimeType.Stride(throttleTime), scheduler: RunLoop.main, latest: true)
                    .sink { frame in
                        if self.streamMode.streaming {
                            let res = self.videoEncoder!.encode(frame: frame)
                        }
                    }
                    .store(in: &stream_cancellables)
            } else {
                frame$
                    .sink { frame in
                        if self.streamMode.streaming {
                            let res = self.videoEncoder!.encode(frame: frame)
                        }
                    }
                    .store(in: &stream_cancellables)
            }

            
            ddsStreamWriter?.domain.peers$.sink {
                x in
                print("Forcing Keyframe on publication match")
                self.videoEncoder!.forceKeyframe()
            }.store(in: &stream_cancellables)
            
            videoEncoder?.frame$
                .sink { frame in
                    self.ddsStreamWriter?.writeFrameToTopic(frame: frame)
                }
                .store(in: &stream_cancellables)
        }
        catch let error {
            videoEncoder = nil
            self.error_msg = "\(error)"
            self.error = true
            cleanSnap()
        }
    }
    
    func cleanStream() {
        videoEncoder = nil // order matters since videoEncoder will try to publish to ddsStreamWriter
        ddsStreamWriter = nil
        stream_cancellables = Set<AnyCancellable>()
    }
    
    func setupSnap() {
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
    
    func startVideoEncoder() throws {
        guard let videoFormat = session?.configuration?.videoFormat else {
            throw AppError.encoderError
        }
        
        let width = videoFormat.imageResolution.width
        let height = videoFormat.imageResolution.height
        let fps = videoFormat.framesPerSecond
        
        videoEncoder = try VideoEncoder(width: Int(width), height: Int(height), fps: fps, settings: videoSettings)
        
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
