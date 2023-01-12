//
//  Manifest.swift
//  NeRFCapture
//
//  Created by Jad Abou-Chakra on 13/7/2022.
//

import Foundation

struct Manifest : Codable {
    struct Frame : Codable {
        let filePath: String
        let depthPath: String?
        let transformMatrix: [[Float]]
        let timestamp: TimeInterval
        let flX: Float
        let flY: Float
        let cx: Float
        let cy: Float
        let w: Int
        let h: Int
    }
    var w: Int = 0
    var h: Int = 0
    var flX: Float = 0
    var flY: Float = 0
    var cx: Float = 0
    var cy: Float = 0
    var depthIntegerScale : Float?
    var depthSource: String?
    var frames: [Frame] = [Frame]()
}
