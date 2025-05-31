//
//  GlobalSettings.swift
//
// Client-side settings and defaults
//

import Foundation
import SwiftUI

struct GlobalSettings: Codable {
    // Original settings
    var keepSteamVRCenter: Bool = true
    var showHandsOverlaid: Bool = false
    var disablePersistentSystemOverlays: Bool = true
    var streamFPS: String = "90"
    var experimental40ppd: Bool = false
    var chromaKeyEnabled: Bool = false
    var chromaKeyDistRangeMin: Float = 0.35
    var chromaKeyDistRangeMax: Float = 0.7
    var chromaKeyColorR: Float = 16.0 / 255.0
    var chromaKeyColorG: Float = 124.0 / 255.0
    var chromaKeyColorB: Float = 16.0 / 255.0
    var dismissWindowOnEnter: Bool = true
    var emulatedPinchInteractions: Bool = false
    var dontShowAWDLAlertAgain: Bool = false
    var fovRenderScale: Float = 1.0
    var forceMipmapEyeTracking = false
    var targetHandsAtRoundtripLatency = false
    var lastUsedAppVersion = "never launched"
    
    // Cloud gaming optimizations
    var cloudOptimizedMode: Bool = true
    var predictiveFrameGeneration: Bool = true
    var networkBufferingStrategy: NetworkBufferingStrategy = .adaptive
    var frameQueueSize: Int = 2
    var aggressiveKeyframeRequest: Bool = true
    var streamingLatencyTarget: Float = 50.0 // ms
    
    // RTX A4500 + H.265 10-bit encoding preferences
    var preferHEVC: Bool = true
    var prefer10BitEncoding: Bool = true
    var encoderPreset: EncoderPreset = .p5
    var encoderProfile: EncoderProfile = .high
    var encoderRateControl: EncoderRateControl = .vbr
    var encoderQualityPreset: EncoderQualityPreset = .quality
    
    // Enhanced eye tracking foveated rendering
    var enhancedFoveatedRendering: Bool = true
    var dynamicFoveation: Bool = true
    var foveationStrength: Float = 2.0
    var foveationShape: FoveationShape = .radial
    var foveationVerticalOffset: Float = 0.0
    var foveationFollowGaze: Bool = true
    var foveationCenterSizeX: Float = 0.4
    var foveationCenterSizeY: Float = 0.4
    var foveationEdgeRatioX: Float = 4.0
    var foveationEdgeRatioY: Float = 4.0
    
    // Dark scene bitrate boosting
    var darkSceneBitrateBoosting: Bool = true
    var darkSceneDetectionThreshold: Float = 0.3
    var darkSceneBitrateMultiplier: Float = 1.5
    
    // Motion-adaptive quality settings
    var motionAdaptiveQuality: Bool = true
    var motionBitrateMultiplier: Float = 1.3
    var staticSceneBitrateMultiplier: Float = 0.8
    var motionDetectionThreshold: Float = 0.15
    
    // WiFi 6E bandwidth utilization
    var bandwidthOptimization: BandwidthOptimization = .highQuality
    var maxBitrate: Int = 70 // Mbps
    var minBitrate: Int = 30 // Mbps
    var adaptiveBitrate: Bool = true
    var packetSize: Int = 1400
    
    // Single-user optimizations
    var singleUserOptimized: Bool = true
    var aggressivePerformanceMode: Bool = true
    
    init() {}
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Original settings
        self.keepSteamVRCenter = try container.decodeIfPresent(Bool.self, forKey: .keepSteamVRCenter) ?? self.keepSteamVRCenter
        self.showHandsOverlaid = try container.decodeIfPresent(Bool.self, forKey: .showHandsOverlaid) ?? self.showHandsOverlaid
        self.disablePersistentSystemOverlays = try container.decodeIfPresent(Bool.self, forKey: .disablePersistentSystemOverlays) ?? self.disablePersistentSystemOverlays
        self.streamFPS = try container.decodeIfPresent(String.self, forKey: .streamFPS) ?? self.streamFPS
        self.experimental40ppd = try container.decodeIfPresent(Bool.self, forKey: .experimental40ppd) ?? self.experimental40ppd
        self.chromaKeyEnabled = try container.decodeIfPresent(Bool.self, forKey: .chromaKeyEnabled) ?? self.chromaKeyEnabled
        self.chromaKeyDistRangeMin = try container.decodeIfPresent(Float.self, forKey: .chromaKeyDistRangeMin) ?? self.chromaKeyDistRangeMin
        self.chromaKeyDistRangeMax = try container.decodeIfPresent(Float.self, forKey: .chromaKeyDistRangeMax) ?? self.chromaKeyDistRangeMax
        self.chromaKeyColorR = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorR) ?? self.chromaKeyColorR
        self.chromaKeyColorG = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorG) ?? self.chromaKeyColorG
        self.chromaKeyColorB = try container.decodeIfPresent(Float.self, forKey: .chromaKeyColorB) ?? self.chromaKeyColorB
        self.dismissWindowOnEnter = try container.decodeIfPresent(Bool.self, forKey: .dismissWindowOnEnter) ?? self.dismissWindowOnEnter
        self.emulatedPinchInteractions = try container.decodeIfPresent(Bool.self, forKey: .emulatedPinchInteractions) ?? self.emulatedPinchInteractions
        self.dontShowAWDLAlertAgain = try container.decodeIfPresent(Bool.self, forKey: .dontShowAWDLAlertAgain) ?? self.dontShowAWDLAlertAgain
        self.fovRenderScale = try container.decodeIfPresent(Float.self, forKey: .fovRenderScale) ?? self.fovRenderScale
        self.forceMipmapEyeTracking = try container.decodeIfPresent(Bool.self, forKey: .forceMipmapEyeTracking) ?? self.forceMipmapEyeTracking
        self.targetHandsAtRoundtripLatency = try container.decodeIfPresent(Bool.self, forKey: .targetHandsAtRoundtripLatency) ?? self.targetHandsAtRoundtripLatency
        self.lastUsedAppVersion = try container.decodeIfPresent(String.self, forKey: .lastUsedAppVersion) ?? self.lastUsedAppVersion
        
        // Cloud gaming optimizations
        self.cloudOptimizedMode = try container.decodeIfPresent(Bool.self, forKey: .cloudOptimizedMode) ?? self.cloudOptimizedMode
        self.predictiveFrameGeneration = try container.decodeIfPresent(Bool.self, forKey: .predictiveFrameGeneration) ?? self.predictiveFrameGeneration
        self.networkBufferingStrategy = try container.decodeIfPresent(NetworkBufferingStrategy.self, forKey: .networkBufferingStrategy) ?? self.networkBufferingStrategy
        self.frameQueueSize = try container.decodeIfPresent(Int.self, forKey: .frameQueueSize) ?? self.frameQueueSize
        self.aggressiveKeyframeRequest = try container.decodeIfPresent(Bool.self, forKey: .aggressiveKeyframeRequest) ?? self.aggressiveKeyframeRequest
        self.streamingLatencyTarget = try container.decodeIfPresent(Float.self, forKey: .streamingLatencyTarget) ?? self.streamingLatencyTarget
        
        // RTX A4500 + H.265 10-bit encoding preferences
        self.preferHEVC = try container.decodeIfPresent(Bool.self, forKey: .preferHEVC) ?? self.preferHEVC
        self.prefer10BitEncoding = try container.decodeIfPresent(Bool.self, forKey: .prefer10BitEncoding) ?? self.prefer10BitEncoding
        self.encoderPreset = try container.decodeIfPresent(EncoderPreset.self, forKey: .encoderPreset) ?? self.encoderPreset
        self.encoderProfile = try container.decodeIfPresent(EncoderProfile.self, forKey: .encoderProfile) ?? self.encoderProfile
        self.encoderRateControl = try container.decodeIfPresent(EncoderRateControl.self, forKey: .encoderRateControl) ?? self.encoderRateControl
        self.encoderQualityPreset = try container.decodeIfPresent(EncoderQualityPreset.self, forKey: .encoderQualityPreset) ?? self.encoderQualityPreset
        
        // Enhanced eye tracking foveated rendering
        self.enhancedFoveatedRendering = try container.decodeIfPresent(Bool.self, forKey: .enhancedFoveatedRendering) ?? self.enhancedFoveatedRendering
        self.dynamicFoveation = try container.decodeIfPresent(Bool.self, forKey: .dynamicFoveation) ?? self.dynamicFoveation
        self.foveationStrength = try container.decodeIfPresent(Float.self, forKey: .foveationStrength) ?? self.foveationStrength
        self.foveationShape = try container.decodeIfPresent(FoveationShape.self, forKey: .foveationShape) ?? self.foveationShape
        self.foveationVerticalOffset = try container.decodeIfPresent(Float.self, forKey: .foveationVerticalOffset) ?? self.foveationVerticalOffset
        self.foveationFollowGaze = try container.decodeIfPresent(Bool.self, forKey: .foveationFollowGaze) ?? self.foveationFollowGaze
        self.foveationCenterSizeX = try container.decodeIfPresent(Float.self, forKey: .foveationCenterSizeX) ?? self.foveationCenterSizeX
        self.foveationCenterSizeY = try container.decodeIfPresent(Float.self, forKey: .foveationCenterSizeY) ?? self.foveationCenterSizeY
        self.foveationEdgeRatioX = try container.decodeIfPresent(Float.self, forKey: .foveationEdgeRatioX) ?? self.foveationEdgeRatioX
        self.foveationEdgeRatioY = try container.decodeIfPresent(Float.self, forKey: .foveationEdgeRatioY) ?? self.foveationEdgeRatioY
        
        // Dark scene bitrate boosting
        self.darkSceneBitrateBoosting = try container.decodeIfPresent(Bool.self, forKey: .darkSceneBitrateBoosting) ?? self.darkSceneBitrateBoosting
        self.darkSceneDetectionThreshold = try container.decodeIfPresent(Float.self, forKey: .darkSceneDetectionThreshold) ?? self.darkSceneDetectionThreshold
        self.darkSceneBitrateMultiplier = try container.decodeIfPresent(Float.self, forKey: .darkSceneBitrateMultiplier) ?? self.darkSceneBitrateMultiplier
        
        // Motion-adaptive quality settings
        self.motionAdaptiveQuality = try container.decodeIfPresent(Bool.self, forKey: .motionAdaptiveQuality) ?? self.motionAdaptiveQuality
        self.motionBitrateMultiplier = try container.decodeIfPresent(Float.self, forKey: .motionBitrateMultiplier) ?? self.motionBitrateMultiplier
        self.staticSceneBitrateMultiplier = try container.decodeIfPresent(Float.self, forKey: .staticSceneBitrateMultiplier) ?? self.staticSceneBitrateMultiplier
        self.motionDetectionThreshold = try container.decodeIfPresent(Float.self, forKey: .motionDetectionThreshold) ?? self.motionDetectionThreshold
        
        // WiFi 6E bandwidth utilization
        self.bandwidthOptimization = try container.decodeIfPresent(BandwidthOptimization.self, forKey: .bandwidthOptimization) ?? self.bandwidthOptimization
        self.maxBitrate = try container.decodeIfPresent(Int.self, forKey: .maxBitrate) ?? self.maxBitrate
        self.minBitrate = try container.decodeIfPresent(Int.self, forKey: .minBitrate) ?? self.minBitrate
        self.adaptiveBitrate = try container.decodeIfPresent(Bool.self, forKey: .adaptiveBitrate) ?? self.adaptiveBitrate
        self.packetSize = try container.decodeIfPresent(Int.self, forKey: .packetSize) ?? self.packetSize
        
        // Single-user optimizations
        self.singleUserOptimized = try container.decodeIfPresent(Bool.self, forKey: .singleUserOptimized) ?? self.singleUserOptimized
        self.aggressivePerformanceMode = try container.decodeIfPresent(Bool.self, forKey: .aggressivePerformanceMode) ?? self.aggressivePerformanceMode
    }
}

// Network buffering strategy enum
enum NetworkBufferingStrategy: String, Codable, CaseIterable {
    case minimal = "Minimal"
    case balanced = "Balanced"
    case adaptive = "Adaptive"
    case aggressive = "Aggressive"
}

// Encoder preset enum
enum EncoderPreset: String, Codable, CaseIterable {
    case p1 = "P1 (Fastest)"
    case p2 = "P2"
    case p3 = "P3"
    case p4 = "P4"
    case p5 = "P5"
    case p6 = "P6"
    case p7 = "P7 (Highest Quality)"
}

// Encoder profile enum
enum EncoderProfile: String, Codable, CaseIterable {
    case main = "Main"
    case high = "High"
    case main10 = "Main10"
}

// Encoder rate control enum
enum EncoderRateControl: String, Codable, CaseIterable {
    case cbr = "CBR"
    case vbr = "VBR"
    case cqp = "CQP"
}

// Encoder quality preset enum
enum EncoderQualityPreset: String, Codable, CaseIterable {
    case speed = "Speed"
    case balanced = "Balanced"
    case quality = "Quality"
}

// Foveation shape enum
enum FoveationShape: String, Codable, CaseIterable {
    case radial = "Radial"
    case rectangular = "Rectangular"
    case adaptive = "Adaptive"
}

// Bandwidth optimization enum
enum BandwidthOptimization: String, Codable, CaseIterable {
    case lowLatency = "Low Latency"
    case balanced = "Balanced"
    case highQuality = "High Quality"
    case custom = "Custom"
}

extension GlobalSettingsStore {
    static let sampleData: GlobalSettingsStore =
    GlobalSettingsStore()
}

class GlobalSettingsStore: ObservableObject {
    @Published var settings: GlobalSettings = GlobalSettings()
    
    private static func fileURL() throws -> URL {
        try FileManager.default.url(for: .documentDirectory,
                                    in: .userDomainMask,
                                    appropriateFor: nil,
                                    create: true)
        .appendingPathComponent("globalsettings.data")
    }
    
    func load() throws {
        let fileURL = try Self.fileURL()
        guard let data = try? Data(contentsOf: fileURL) else {
            return self.settings = GlobalSettings()
        }
        let globalSettings = try JSONDecoder().decode(GlobalSettings.self, from: data)
        self.settings = globalSettings
    }
    
    func save(settings: GlobalSettings) throws {
        let data = try JSONEncoder().encode(settings)
        let outfile = try Self.fileURL()
        try data.write(to: outfile)
    }
}
