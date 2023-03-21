//
//  ARView.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import SwiftUI
import RealityKit
import ARKit

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var viewModel: ARViewModel
    
    init(_ vm: ARViewModel) {
        viewModel = vm
    }
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        let configuration = viewModel.createARConfiguration()
        configuration.worldAlignment = .gravity
        configuration.isAutoFocusEnabled = true
//        configuration.videoFormat = ARWorldTrackingConfiguration.supportedVideoFormats[4] // 1280x720
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            viewModel.appState.supportsDepth = true
        }
        arView.debugOptions = [.showWorldOrigin]
        #if !targetEnvironment(simulator)
        arView.session.run(configuration)
        #endif
        arView.session.delegate = viewModel
        viewModel.session = arView.session
        viewModel.arView = arView
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}
