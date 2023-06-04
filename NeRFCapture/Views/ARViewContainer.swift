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
#if targetEnvironment(simulator)
#else
        arView.debugOptions = [.showWorldOrigin]
        arView.session.delegate = viewModel
        viewModel.session = arView.session
        viewModel.arView = arView
        viewModel.setup()
#endif
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {}
    
}
