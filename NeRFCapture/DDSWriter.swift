//
//  DDSWriter.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 11/1/2023.
//

import Foundation
import ARKit

struct DDSConstants {
    static let DDS_PUBLICATION_MATCHED_STATUS: UInt32 = 1 << DDS_PUBLICATION_MATCHED_STATUS_ID.rawValue
    static let DDS_INCONSISTENT_TOPIC_STATUS: UInt32 = 1 << DDS_INCONSISTENT_TOPIC_STATUS_ID.rawValue
    static let DDS_OFFERED_DEADLINE_MISSED_STATUS: UInt32 = 1 << DDS_OFFERED_DEADLINE_MISSED_STATUS_ID.rawValue
}

struct DDSState {
    var ready = false
    var domain: dds_entity_t? = nil
    var participant: dds_entity_t? = nil
    var listener: OpaquePointer! = nil

    let topic_name: String = "Frames"
    var topic: dds_entity_t? = nil
    var writer: dds_entity_t? = nil
    var qos: OpaquePointer! = nil
    
    var rc: dds_return_t = dds_return_t()
    var status:UInt32 = 0
}

class DDSWriter {
    var dds = DDSState()
    let rgbConverter = YUVToRGBFilter()
    var counter = 0
    @Published var peers: UInt32 = 0
   
    func buildConfig() -> String {
        let xml_config = """
            <General>
                <Interfaces>
                    <NetworkInterface name="en0" />
                </Interfaces>
            </General>
            <Tracing>
                <Category>
                    config
                </Category>
                <OutputFile>
                    stdout
                </OutputFile>
            </Tracing>
        """
        return xml_config
    }
    
    func setupDDS() {
        let domain_id: dds_domainid_t = 0
        let xml_config = buildConfig()
        dds.domain = dds_create_domain(domain_id, xml_config)
        
        // Create listener
        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()) // void pointer to self
        dds.listener = dds_create_listener(observer)
        dds_lset_publication_matched(dds.listener) { entity, status, observer in
            let mySelf = Unmanaged<DDSWriter>.fromOpaque(observer!).takeUnretainedValue()
                DispatchQueue.main.async {
                    mySelf.peers = status.current_count
            }
        }
        
        dds.participant = dds_create_participant(domain_id, nil, dds.listener)
        if(dds.participant! < 0) {
            print("Could not create participant")
            return
        }
        
        // Setup Project Topic
        withUnsafePointer(to: NeRFCaptureData_NeRFCaptureFrame_desc) { descPtr in
            dds.topic = dds_create_topic(dds.participant!, descPtr, dds.topic_name, nil, nil)
        }
//        dds.topic = dds_create_topic(dds.participant!, &NeRFCaptureData_NeRFCaptureFrame_desc, dds.topic_name, nil, nil)
//        dds.topic = dds_create_topic(dds.participant!, NeRFCaptureData_NeRFCaptureFrame_desc_ptr, dds.topic_name, nil, nil)
        
        if(dds.topic! < 0) {
            print("Could not create topic")
            return
        }
        
        dds.qos = dds_create_qos()
        dds_qset_resource_limits(
            dds.qos,
            2,
            2,
            2
        )
//        dds_qset_reliability(dds.qos, DDS_RELIABILITY_RELIABLE, 1 * 1000000000)
        
        dds.writer = dds_create_writer(dds.participant!, dds.topic!, dds.qos!, dds.listener)
        if(dds.writer! < 0) {
            print("Could not create writer")
            return
        }
    }
    
    func writeFrameToTopic(frame: ARFrame) {
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
            CVPixelBufferLockBaseAddress(sceneDepth.depthMap, .readOnly)
            has_depth = true
            depth_width = CVPixelBufferGetWidth(sceneDepth.depthMap)
            depth_height = CVPixelBufferGetHeight(sceneDepth.depthMap)
            depth_data._length = UInt32(CVPixelBufferGetDataSize(sceneDepth.depthMap))
            print("\(depth_width)x\(depth_height) - size = \(depth_data._length)")
            depth_data._buffer = CVPixelBufferGetBaseAddress(frame.sceneDepth!.depthMap)!.bindMemory(to: UInt8.self, capacity: 1)
        }
        counter += 1
        var msg = NeRFCaptureData_NeRFCaptureFrame(
            id: UInt32(counter),
            timestamp: frame.timestamp,
            fl_x: flX,
            fl_y: flY,
            cx: cx,
            cy: cy,
            transform_matrix: tupleFromTransform(frame.camera.transform),
            width: w,
            height: h,
            image: data,
            has_depth: has_depth,
            depth_width: UInt32(depth_width),
            depth_height: UInt32(depth_height),
            depth_scale: 1.0,
            depth_image: depth_data
        )

        dds.rc = dds_write(dds.writer!, &msg)
        if(dds.rc != DDS_RETCODE_OK) {
            let message = String(cString:dds_strretcode(dds.rc))
            print("Write Failed: \(message)")
        }
        if let sceneDepth = frame.sceneDepth {
            CVPixelBufferUnlockBaseAddress(sceneDepth.depthMap, .readOnly)
        }
    }
    
    func cleanDDS() {
        if let domain = dds.domain {
            dds.rc = dds_delete(domain)
        }
    }
}
