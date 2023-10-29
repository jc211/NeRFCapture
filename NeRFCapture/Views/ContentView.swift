//
//  ContentView.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import SwiftUI
import ARKit
import RealityKit

struct VideoSettingsView: View {
   @ObservedObject var viewModel: ARViewModel
   var body: some View {
       HStack() {
           //NumberTextField("Keyframe Interval", value: viewModel.videoSettings.$keyframeInterval)
           Stepper("Keyframe Interval \t \(viewModel.videoSettings.keyframeInterval)", value: $viewModel.videoSettings.keyframeInterval)
       }
       Toggle("Throttle", isOn: $viewModel.videoSettings.throttle)
       if viewModel.videoSettings.throttle {
           NumberTextField("Throttle (frame per ms)", value: $viewModel.videoSettings.throttleTimeMs)
       }
       Button("Reset") {
           viewModel.mode = viewModel.mode
           let impactMed = UIImpactFeedbackGenerator(style: .medium)
           impactMed.impactOccurred()
       }
   }
}

struct NumberTextField<T>: View {
    @Binding var valueBinding: T
    @State private var isEditing = false
    private let numberFormatter = NumberFormatter()
    private let textLabel: String
    init(_ label: String, value: Binding<T>) {
        textLabel = label
        _valueBinding = value
    }
    
    var body: some View {
        HStack() {
            Text(textLabel)
                .frame(width: 200, alignment: .leading)
                .lineLimit(1)
            
            TextField(textLabel, value: $valueBinding, formatter: numberFormatter, onEditingChanged: { editing in
                isEditing = editing
            }, onCommit: {})
            .keyboardType(.numberPad)
            .onAppear {
                numberFormatter.numberStyle = .decimal
            }
            if isEditing {
                Button(action: {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }) {
                    Text("Done")
                }
            }
        }
    }
}

struct DDSSettingsView: View {
    @ObservedObject var viewModel: ARViewModel
    @State private var isEditing = false
    private let numberFormatter = NumberFormatter()
    
    var body: some View {

        //NumberTextField("Stream ID", value: $viewModel.ddsSettings.streamID)
        //NumberTextField("Domain ID", value: $viewModel.ddsSettings.domainID)
        Stepper("Stream ID \t \(viewModel.ddsSettings.streamID)", value: $viewModel.ddsSettings.streamID)
        Stepper("Domain ID \t \(viewModel.ddsSettings.domainID)", value: $viewModel.ddsSettings.domainID)
        Toggle("Pose Topic", isOn: $viewModel.ddsSettings.streamPoseTopic)
        Toggle("Video Topic", isOn: $viewModel.ddsSettings.streamVideoTopic)
        Toggle("Snap Pose Only", isOn: $viewModel.ddsSettings.snapPoseOnly)
        Toggle("Action Button", isOn: $viewModel.ddsSettings.actionButtonEnabled)
        Button("Reset") {
            viewModel.mode = viewModel.mode
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        }
    }
}

struct VideoFormatsView: View {
    @ObservedObject var viewModel: ARViewModel
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Video Format", selection: $viewModel.arSettings.selectedFormatIndex) {
#if targetEnvironment(simulator)
                let formats = ["640x480 @ 30", "1920x1080 @ 30", "1280x720 @ 30"]
                ForEach(0..<3, id: \.self) { index in
                    let format = formats[index]
                    Text(format)
                        .tag(index)
                }
#else
        ForEach(0..<ARWorldTrackingConfiguration.supportedVideoFormats.count, id: \.self) { index in
            let format = ARWorldTrackingConfiguration.supportedVideoFormats[index]
            Text(String(format: "%.0fx%.0f @ %d fps", format.imageResolution.width, format.imageResolution.height, format.framesPerSecond))
                .tag(index)
        }
#endif

            }
            .pickerStyle(.menu)
            

            Picker("Alignment", selection: $viewModel.arSettings.worldAlignment) {
                Text("Gravity").tag(ARConfiguration.WorldAlignment.gravity)
                Text("Heading").tag(ARConfiguration.WorldAlignment.gravityAndHeading)
                Text("Camera").tag(ARConfiguration.WorldAlignment.camera)
            }
            .pickerStyle(.menu)
            Toggle("Auto Focus", isOn: $viewModel.arSettings.isAutoFocusEnabled)
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                Toggle("Enable Depth", isOn: $viewModel.arSettings.isDepthEnabled)
            }
            
            Button("Reset ARKit") {
                viewModel.restartARKit()
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
            }
        }
    }
}

struct StreamButtonsView: View {
    @ObservedObject var viewModel: ARViewModel
    
    var body: some View {
        HStack(spacing: 20) {
            Spacer()
            Button(action: {
                viewModel.restartARKit()
                let imapct = UIImpactFeedbackGenerator(style: .medium)
                imapct.impactOccurred()
            }) {
                Text("Reset")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            
            
            if !viewModel.streamMode.streaming {
                Button(action: {
                    viewModel.streamMode.streaming = true
                    UIApplication.shared.isIdleTimerDisabled = true

                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                }) {
                    Text("Start")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            else {
                Button(action: {
                    viewModel.streamMode.streaming = false
                    UIApplication.shared.isIdleTimerDisabled = false
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                }) {
                    Text("Stop")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            
            
        }
        .padding()
    }
}

struct SnapButtonsView: View {
    @ObservedObject var viewModel: ARViewModel
    
    var body: some View {
        HStack(spacing: 20) {
            Spacer()
            Button(action: {
                viewModel.restartARKit()
                let impactMed = UIImpactFeedbackGenerator(style: .medium)
                impactMed.impactOccurred()
            }) {
                Text("Reset")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            Button(action: {
                if let frame = viewModel.session?.currentFrame {
                    if viewModel.ddsSettings.snapPoseOnly {
                        viewModel.ddsSnapWriter?.writePoseToTopic(frame: frame, action: viewModel.snapMode.actionButtonState)
                    }
                    if viewModel.ddsSettings.streamVideoTopic {
                        viewModel.ddsSnapWriter?.writeFrameToTopic(frame: frame)
                    }
                }
            }) {
                Text("Send")
                    .padding(.horizontal, 20)
                    .padding(.vertical, 5)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
        }
        .padding()
    }
}

struct SaveButtonsView: View {
    @ObservedObject var viewModel: ARViewModel
    
    var body: some View {
        if viewModel.saveMode.writerState == .SessionNotStarted {
            HStack(spacing: 20) {
                Spacer()
                
                Button(action: {
                    viewModel.restartARKit()
                    let impactMed = UIImpactFeedbackGenerator(style: .medium)
                    impactMed.impactOccurred()
                }) {
                    Text("Reset")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                
                Button(action: {
                    do {
                        try viewModel.datasetWriter?.initializeProject()
                        viewModel.saveMode.writerState = .SessionStarted
                    }
                    catch {
                        print("\(error)")
                    }
                }) {
                    Text("Start")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .padding()
        }
        
        if viewModel.saveMode.writerState == .SessionStarted {
            HStack(spacing: 20) {
                Spacer()
                Button(action: {
                    viewModel.datasetWriter?.finalizeProject()
                    viewModel.saveMode.writerState = .SessionNotStarted
                }) {
                    Text("End")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                Button(action: {
                    if let frame = viewModel.session?.currentFrame {
                        viewModel.datasetWriter?.writeFrameToDisk(frame: frame)
                    }
                }) {
                    Text("Save Frame")
                        .padding(.horizontal, 20)
                        .padding(.vertical, 5)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            .padding()
        }
    }
}

struct StreamInformationOverlay: View {
    @ObservedObject var viewModel: ARViewModel
    var body: some View {
        VStack(alignment:.leading) {
            Text("\(viewModel.ar.trackingState)")
            Text("\(viewModel.dds.peers) Connection(s)")
        }.padding()
    }
}

struct SnapInformationOverlay: View {
    @ObservedObject var viewModel: ARViewModel
    var body: some View {
        VStack(alignment:.leading) {
            Text("\(viewModel.ar.trackingState)")
            Text("\(viewModel.dds.peers) Connection(s)")
        }.padding()
    }
}

struct SaveInformationOverlay: View {
    @ObservedObject var viewModel: ARViewModel
    var body: some View {
        VStack(alignment:.leading) {
            Text("\(viewModel.ar.trackingState)")
            //if case .SessionStarted = viewModel.appState.writerState {
            //    Text("\(viewModel.datasetWriter.currentFrameCounter) Frames")
            //}
        }.padding()
    }
}

struct ActionButton: View {
    @ObservedObject var viewModel: ARViewModel
    var body: some View {
        var actionValue = viewModel.mode == .Snap ? viewModel.snapMode.actionButtonState : viewModel.streamMode.actionButtonState
        ZStack {
            Text("Action \(actionValue, specifier: "%.1f")")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
            /*
            Button(action: {
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
                if viewModel.mode == .Snap {
                    viewModel.snapMode.actionButtonState = viewModel.snapMode.actionButtonState == 1.0 ? 0.0 : 1.0
                    
                    if let frame = viewModel.session?.currentFrame {
                        viewModel.ddsSnapWriter?.writePoseToTopic(frame: frame, action: viewModel.snapMode.actionButtonState)
                    }
                } else if viewModel.mode == .Stream {
                    viewModel.streamMode.actionButtonState = viewModel.streamMode.actionButtonState == 1.0 ? 0.0 : 1.0
                }
            }) {
                // Make button fit screen
                if viewModel.mode == .Snap {
                    Text("Action \(viewModel.snapMode.actionButtonState, specifier: "%.1f")")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.mode == .Stream {
                    Text("Action \(viewModel.streamMode.actionButtonState, specifier: "%.1f")")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
            .contentShape(Rectangle())
             */
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 25, coordinateSpace: .local).onEnded {
            val in
            if viewModel.mode == .Snap {
                viewModel.snapMode.actionButtonState = actionValue == 1.0 ? 0.0 : 1.0
                if let frame = viewModel.session?.currentFrame {
                    viewModel.ddsSnapWriter?.writePoseToTopic(frame: frame, action: viewModel.snapMode.actionButtonState)
                }
            }
            if viewModel.mode == .Stream {
                viewModel.streamMode.actionButtonState = actionValue == 1.0 ? 0.0 : 1.0
            }
            
            let impact = UIImpactFeedbackGenerator(style: .medium)
            impact.impactOccurred()
        })
        .onTapGesture {
            if viewModel.mode == .Snap {
                if let frame = viewModel.session?.currentFrame {
                    viewModel.ddsSnapWriter?.writePoseToTopic(frame: frame, action: viewModel.snapMode.actionButtonState)
                }
                let impact = UIImpactFeedbackGenerator(style: .light)
                impact.impactOccurred()
            }
        }
    }
}

struct SettingsSheet: View {
    @ObservedObject var viewModel: ARViewModel
    @State private var showSheet: Bool = false
    var body: some View {
        
        Button() {
            showSheet.toggle()
            let imapct = UIImpactFeedbackGenerator(style: .light)
            imapct.impactOccurred()
        } label: {
            Image(systemName: "gearshape.fill")
                .imageScale(.large)
                .contentShape(Rectangle())
                .frame(width:50, height:50)
        }
        .padding(.leading, 5)
        .buttonStyle(.borderless)

        .sheet(isPresented: $showSheet) {
            Form {
                Section(header: Text("Video"),
                        footer: Text("Settings used by the video encoder")) {
                    VideoSettingsView(viewModel: viewModel)
                }
                Section(header: Text("DDS"),
                        footer: Text("Settings used by CycloneDDS")) {
                    DDSSettingsView(viewModel: viewModel)
                }
                Section(header: Text("ARKit"),
                        footer: Text("Settings used by the SLAM system")) {
                    VideoFormatsView(viewModel: viewModel)
                }
            }
            .navigationTitle("Settings")
            .cornerRadius(16)
            .shadow(radius: 8)
            .presentationDetents([.medium])
        }
    }
}

struct ModeSelector : View {
    @ObservedObject var viewModel: ARViewModel
    var body: some View {
        HStack() {
            Spacer()
            Picker("Mode", selection: $viewModel.mode) {
                Text("Stream").tag(AppMode.Stream)
                Text("Snap").tag(AppMode.Snap)
                Text("Save").tag(AppMode.Save)
            }
            .frame(maxWidth: 200)
            .padding(0)
            .pickerStyle(.segmented)
            Spacer()
        }
    }
}

struct ContentView : View {
    @StateObject private var viewModel: ARViewModel
    
    init(viewModel vm: ARViewModel) {
        _viewModel = StateObject(wrappedValue: vm)
    }
    
    var body: some View {
        ZStack{
            ZStack(alignment: .topTrailing) {
                ARViewContainer(viewModel).edgesIgnoringSafeArea(.all)
                VStack() {
                    ZStack() {
                        HStack() {
                            SettingsSheet(viewModel: viewModel)
                            Spacer()
                        }
                        ModeSelector(viewModel: viewModel)
                    }.padding([.top, .leading, .trailing], 10)
                    HStack() {
                        Spacer()
                        if case .Snap = viewModel.mode {
                            SnapInformationOverlay(viewModel: viewModel)
                        }
                        if case .Save = viewModel.mode {
                            SaveInformationOverlay(viewModel: viewModel)
                        }
                        if case .Stream = viewModel.mode {
                            StreamInformationOverlay(viewModel: viewModel)
                        }
                    }
                    Spacer()
                    // add invisible button on screen
                    if viewModel.ddsSettings.actionButtonEnabled {
                        ActionButton(viewModel: viewModel)
                    }
                    if viewModel.error {
                        Label("\(viewModel.error_msg)", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .bold()
                            .foregroundColor(.red)
                        Spacer()
                    }
                    VStack {
                        if case .Snap = viewModel.mode {
                            SnapButtonsView(viewModel: viewModel)
                        }
                        if case .Save = viewModel.mode {
                            SaveButtonsView(viewModel: viewModel)
                        }
                        if case .Stream = viewModel.mode {
                            StreamButtonsView(viewModel: viewModel)
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

#if DEBUG
struct ContentView_Previews : PreviewProvider {
    static var previews: some View {
        ContentView(viewModel: ARViewModel())
            .previewInterfaceOrientation(.portrait)
    }
}
#endif
