//
//  DDSWriter.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 11/1/2023.
//

import Foundation
import ARKit
import VideoToolbox
import Combine

struct DDSConstants {
    static let DDS_PUBLICATION_MATCHED_STATUS: UInt32 = 1 << DDS_PUBLICATION_MATCHED_STATUS_ID.rawValue
    static let DDS_INCONSISTENT_TOPIC_STATUS: UInt32 = 1 << DDS_INCONSISTENT_TOPIC_STATUS_ID.rawValue
    static let DDS_OFFERED_DEADLINE_MISSED_STATUS: UInt32 = 1 << DDS_OFFERED_DEADLINE_MISSED_STATUS_ID.rawValue
}

enum DDSError: Error {
    case domainAlreadyCreated
    case domainCreationFailed
    case domainNotYetCreated
    case domainCouldNotbeDeleted
    case participantCouldNotBeCreated
    case publisherCouldNotBeCreated
}


class DDSDomain {
    private let domainId: UInt32
    private var domain: dds_entity_t!
    private var participant: dds_entity_t!
    private var listener: OpaquePointer!
    private var xmlConfig: String
    private var created: Bool
    public var peers$ = CurrentValueSubject<UInt32, Never>(0)
    
    init(domainId: UInt32) {
        self.created = false
        self.domainId = domainId
        self.xmlConfig = """
            <General>
                <Interfaces>
                    <NetworkInterface name="en0" />
                </Interfaces>
            </General>
            <Internal>
              <MultipleReceiveThreads>false</MultipleReceiveThreads>
            </Internal>
        """
    }
    
//    <Tracing>
//        <Category>
//            config
//        </Category>
//        <OutputFile>
//            stdout
//        </OutputFile>
//    </Tracing>
    
    func setConfig(xml_config: String) {
        self.xmlConfig = xml_config
    }
    
    func create() throws {
        guard !created else {
            throw DDSError.domainAlreadyCreated
        }
        
        domain = dds_create_domain(domainId, xmlConfig)
        guard domain > 0 else {
            throw DDSError.domainCreationFailed
        }
        
        // Create listener
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()) // void pointer to self
        listener = dds_create_listener(observer)
        dds_lset_publication_matched(listener) { entity, status, observer in
            let mySelf = Unmanaged<DDSDomain>.fromOpaque(observer!).takeUnretainedValue()
            mySelf.peers$.send(status.current_count)
        }
        
        participant = dds_create_participant(domainId, nil, listener)
        guard participant > 0 else {
            throw DDSError.participantCouldNotBeCreated
        }
        
        created = true
    }
    
    func destroy() throws {
        print("Destroying")
        guard created else {
            throw DDSError.domainNotYetCreated
        }
        dds_delete_listener(listener)
        dds_delete(participant)
        
        let result = dds_delete(domain)
        guard result == DDS_RETCODE_OK else {
            throw DDSError.domainCouldNotbeDeleted
        }
        created = false
    }
    
    func createPublisher<T>(topic: String, topicDescriptor: dds_topic_descriptor_t, qos: OpaquePointer? = nil) throws -> Publisher<T> {
        guard created else {
            throw DDSError.domainNotYetCreated
        }
        
        let writer = Publisher<T>(participant: participant, topicName: topic, topicDescriptor: topicDescriptor, qos: qos)
        return writer
    }
    
    deinit {
        if(created) {
            try? destroy()
        }
    }
}


class Publisher<T> {
    private var topicName: String
    private var topicDescriptor: dds_topic_descriptor_t!
    private var topic: dds_entity_t!
    private var writer: dds_entity_t!
    private var publisher: dds_entity_t!
    private var participant: dds_entity_t!
    private var qos: OpaquePointer! = nil
    private var rc: dds_return_t = dds_return_t()
    private var started: Bool = false
    
    public init(participant: dds_entity_t, topicName: String, topicDescriptor: dds_topic_descriptor_t, qos: OpaquePointer? = nil) {
        self.participant = participant
        self.topicName = topicName
        self.topicDescriptor = topicDescriptor
        self.qos = qos
        self.start()
    }
    
    public func start() -> Bool {
        guard !started else { return true }
        
        // Create a DDS topic
        withUnsafePointer(to: topicDescriptor) { descPtr in
            topic = dds_create_topic(participant, descPtr, topicName, nil, nil)
        }
        guard topic > 0 else { return false }
        
        // Create a DDS publisher
        publisher = dds_create_publisher(participant, qos, nil)
        guard publisher > 0 else { return false }
        
        // Create a DDS writer
        writer = dds_create_writer(publisher, topic, qos, nil)
        guard writer > 0 else { return false }
        
        started = true
        return true
    }
    
    public func stop() {
        guard !started else { return }
        guard participant != nil else { return }
        
        if let topic = topic {
            dds_delete(topic) // Deletes all childern of topic
        }
        
    }
    
    public func publish(_ data: inout T) -> Bool {
        guard started else { return false }
        guard writer != nil else { return false }
        
        rc = dds_write(writer, &data)
        if(rc != DDS_RETCODE_OK) {
            let message = String(cString:dds_strretcode(rc))
            print("Write Failed: \(message)")
            return false
        }
        
        return true
    }
}

let rgbConverter = YUVToRGBFilter()

func convertARFrameToMsg(frame_id: UInt32, frame: ARFrame) -> NeRFCaptureData_NeRFCaptureFrame {
    let w = UInt32(frame.camera.imageResolution.width)
    let h = UInt32(frame.camera.imageResolution.height)
    let flX =  frame.camera.intrinsics[0, 0]
    let flY =  frame.camera.intrinsics[1, 1]
    let cx =  frame.camera.intrinsics[2, 0]
    let cy =  frame.camera.intrinsics[2, 1]
    
    rgbConverter.applyFilter(frame: frame)
    var data = dds_sequence_octet()
    data._length = UInt32(rgbConverter.rgbBuffer.length)
    data._buffer = rgbConverter.rgbBuffer.contents().bindMemory(to: UInt8.self, capacity: 1)
    
    var depth_width = 0
    var depth_height = 0
    var has_depth = false
    var depth_data = dds_sequence_octet()
    if let sceneDepth = frame.sceneDepth {
        has_depth = true
        depth_width = CVPixelBufferGetWidth(sceneDepth.depthMap)
        depth_height = CVPixelBufferGetHeight(sceneDepth.depthMap)
        depth_data._length = UInt32(CVPixelBufferGetDataSize(sceneDepth.depthMap))
        print("\(depth_width)x\(depth_height) - size = \(depth_data._length)")
        depth_data._buffer = CVPixelBufferGetBaseAddress(frame.sceneDepth!.depthMap)!.bindMemory(to: UInt8.self, capacity: 1)
    }
    
    var msg = NeRFCaptureData_NeRFCaptureFrame(
        id: frame_id,
        timestamp: frame.timestamp,
        fl_x: flX,
        fl_y: flY,
        cx: cx,
        cy: cy,
        transform_matrix: tupleFromTransform(frame.camera.transform),
        width: w,
        height: h,
        format: NeRFCaptureData_RGB,
        image: data,
        has_depth: has_depth,
        depth_width: UInt32(depth_width),
        depth_height: UInt32(depth_height),
        depth_scale: 1.0,
        depth_image: depth_data
    )
    
    return msg
}

func convertARFrameToPoseMsg(frame_id: UInt32, frame: ARFrame, action: Float32 = 1.0) -> NeRFCaptureData_Pose {
    let w = UInt32(frame.camera.imageResolution.width)
    let h = UInt32(frame.camera.imageResolution.height)
    let flX =  frame.camera.intrinsics[0, 0]
    let flY =  frame.camera.intrinsics[1, 1]
    let cx =  frame.camera.intrinsics[2, 0]
    let cy =  frame.camera.intrinsics[2, 1]
    
    
    var msg = NeRFCaptureData_Pose(
        id: frame_id,
        timestamp: frame.timestamp,
        fl_x: flX,
        fl_y: flY,
        cx: cx,
        cy: cy,
        transform_matrix: tupleFromTransform(frame.camera.transform),
        action: action
    )
    
    return msg
}

class DDSSnapWriter {
    let domain: DDSDomain
    let framePublisher: Publisher<NeRFCaptureData_NeRFCaptureFrame>
    let posePublisher: Publisher<NeRFCaptureData_Pose>
    let peers = CurrentValueSubject<UInt32, Never>(0)
    private var counter = 0
    private var pose_counter = 0
    private var cancellable: AnyCancellable?
    
    
    
    init(domainID: Int = 0) throws {
        let qos = dds_create_qos()
        dds_qset_resource_limits(qos, 1 /*max samples*/, 1 /*max instances*/, 1 /*max samples per instance*/)
        dds_qset_destination_order(qos, DDS_DESTINATIONORDER_BY_SOURCE_TIMESTAMP)
        
        domain = DDSDomain(domainId: UInt32(domainID))
        try domain.create()
        framePublisher = try domain.createPublisher(topic: "Frames", topicDescriptor: NeRFCaptureData_NeRFCaptureFrame_desc)
        posePublisher = try domain.createPublisher(topic: "Pose", topicDescriptor: NeRFCaptureData_Pose_desc, qos: qos)
        cancellable = domain.peers$.sink { [weak self] peers in
            self?.peers.send(peers)
        }
    }
    
    deinit {
        framePublisher.stop()
        posePublisher.stop()
        try? domain.destroy()
    }
    
    func writePoseToTopic(frame: ARFrame, action: Float32 = 1.0) {
        var msg = convertARFrameToPoseMsg(frame_id: UInt32(pose_counter), frame: frame, action: action)
        pose_counter += 1
        _ = posePublisher.publish(&msg)
    }
    
    func writeFrameToTopic(frame: ARFrame) {
        if let sceneDepth = frame.sceneDepth {
            CVPixelBufferLockBaseAddress(sceneDepth.depthMap, .readOnly)
        }
        let frame_id = UInt32(counter)
        var msg = convertARFrameToMsg(frame_id: frame_id, frame: frame)
        counter += 1
        _ = framePublisher.publish(&msg)
        var pose_msg = convertARFrameToPoseMsg(frame_id: frame_id , frame: frame)
        //_ = posePublisher.publish(&pose_msg)
        
        if let sceneDepth = frame.sceneDepth {
            CVPixelBufferUnlockBaseAddress(sceneDepth.depthMap, .readOnly)
        }
    }
}

func convertPosedVideoFrameToMsg(frame: PosedVideoFrame) -> VideoMessages_PosedVideoFrame {
    var data = dds_sequence_octet()
    data._length = UInt32(frame.nalus.count)
    var unsafePointer = frame.nalus.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> UnsafePointer<UInt8> in
        return bytes.baseAddress!.assumingMemoryBound(to: UInt8.self)
    }
    data._buffer = UnsafeMutablePointer(mutating: unsafePointer)
    var msg = VideoMessages_PosedVideoFrame(
        stream_id: 7,
        is_keyframe: frame.isKeyframe,
        timestamp: frame.timestamp,
        nalus: data,
        transform_matrix: tupleFromTransform(frame.xWV),
        fl_x: frame.flX,
        fl_y: frame.flY,
        cx: frame.cx,
        cy: frame.cy,
        width: frame.width,
        height: frame.height,
        has_depth: false,
        depth_zlib: dds_sequence_octet(),
        depth_width: 0,
        depth_height: 0
    )
    return msg
}

class DDSStreamWriter {
    let domain: DDSDomain
    let videoPublisher: Publisher<VideoMessages_PosedVideoFrame>
    let posePublisher: Publisher<NeRFCaptureData_Pose>
    let peers = CurrentValueSubject<UInt32, Never>(0)
    private var counter = 0
    private var pose_counter = 0
    private var cancellable: AnyCancellable?
    
    
    init(domainID: Int = 0) throws {
        let qos = dds_create_qos()
        dds_qset_resource_limits(qos, 1 /*max samples*/, 1 /*max instances*/, 1 /*max samples per instance*/)
        dds_qset_destination_order(qos, DDS_DESTINATIONORDER_BY_SOURCE_TIMESTAMP)
 
        domain = DDSDomain(domainId: UInt32(domainID))
        try domain.create()
        videoPublisher = try domain.createPublisher(topic: "PosedVideo", topicDescriptor: VideoMessages_PosedVideoFrame_desc, qos: qos)
        posePublisher = try domain.createPublisher(topic: "Pose", topicDescriptor: NeRFCaptureData_Pose_desc, qos: qos)
        cancellable = domain.peers$.sink { [weak self] peers in
            self?.peers.send(peers)
        }
    }
    
    deinit {
        videoPublisher.stop()
        posePublisher.stop()
        try? domain.destroy()
    }
    
    func writePoseToTopic(frame: ARFrame) {
        var msg = convertARFrameToPoseMsg(frame_id: UInt32(pose_counter), frame: frame)
        pose_counter += 1
        _ = posePublisher.publish(&msg)
    }
    
    func writeFrameToTopic(frame: PosedVideoFrame) {
        var msg = convertPosedVideoFrameToMsg(frame: frame)
        //print("Frame Size: \(msg.nalus._length) - Keyframe: \(msg.is_keyframe)")
        _ = videoPublisher.publish(&msg)
    }
}
