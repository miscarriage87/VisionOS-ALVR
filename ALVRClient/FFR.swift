//
//  FFR.swift
//
// Foveation vars as read from the Streamer's JSON config.
// Enhanced with dynamic eye tracking and adaptive foveation for Vision Pro
//

import Foundation
import Metal
import CoreVideo
import simd
import QuartzCore // Added for CACurrentMediaTime

// Original basic foveation settings from ALVR JSON config
struct FoveationSettings: Codable {
    var centerSizeX: Float = 0
    var centerSizeY: Float = 0
    var centerShiftX: Float = 0
    var centerShiftY: Float = 0
    var edgeRatioX: Float = 0
    var edgeRatioY: Float = 0

    enum CodingKeys: String, CodingKey {
        case centerSizeX = "center_size_x"
        case centerSizeY = "center_size_y"
        case centerShiftX = "center_shift_x"
        case centerShiftY = "center_shift_y"
        case edgeRatioX = "edge_ratio_x"
        case edgeRatioY = "edge_ratio_y"
    }
}

// Enhanced foveation settings with dynamic parameters
struct EnhancedFoveationSettings {
    var baseSettings: FoveationSettings
    var dynamicFoveation: Bool
    var foveationStrength: Float
    var foveationShape: FoveationShape
    var foveationVerticalOffset: Float
    var foveationFollowGaze: Bool
    var eyePosition: simd_float2 // Normalized eye gaze position (0,0 center, ±1 edges)
    var motionFactor: Float // 0.0 = static, 1.0 = high motion
    var darknessFactor: Float // 0.0 = bright scene, 1.0 = dark scene
    var predictedPosition: simd_float2 // Predicted future eye position
    
    init(from globalSettings: GlobalSettings) {
        let baseSettings = FoveationSettings(
            centerSizeX: globalSettings.foveationCenterSizeX,
            centerSizeY: globalSettings.foveationCenterSizeY,
            centerShiftX: 0.0,
            centerShiftY: globalSettings.foveationVerticalOffset,
            edgeRatioX: globalSettings.foveationEdgeRatioX,
            edgeRatioY: globalSettings.foveationEdgeRatioY
        )
        
        self.baseSettings = baseSettings
        self.dynamicFoveation = globalSettings.dynamicFoveation
        self.foveationStrength = globalSettings.foveationStrength
        self.foveationShape = globalSettings.foveationShape
        self.foveationVerticalOffset = globalSettings.foveationVerticalOffset
        self.foveationFollowGaze = globalSettings.foveationFollowGaze
        self.eyePosition = simd_float2(0, 0)
        self.motionFactor = 0.0
        self.darknessFactor = 0.0
        self.predictedPosition = simd_float2(0, 0)
    }
}

// Original foveation runtime variables
struct FoveationVars {
    let enabled: Bool
    
    let targetEyeWidth: UInt32
    let targetEyeHeight: UInt32
    let optimizedEyeWidth: UInt32
    let optimizedEyeHeight: UInt32

    let eyeWidthRatio: Float
    let eyeHeightRatio: Float

    let centerSizeX: Float
    let centerSizeY: Float
    let centerShiftX: Float
    let centerShiftY: Float
    let edgeRatioX: Float
    let edgeRatioY: Float
}

// Scene analysis result for adaptive foveation
struct SceneAnalysisResult {
    var averageLuminance: Float = 0.5
    var motionMagnitude: Float = 0.0
    var complexityScore: Float = 0.5
    
    // Detect if this is a dark scene that needs bitrate boosting
    var isDarkScene: Bool {
        return averageLuminance < ALVRClientApp.gStore.settings.darkSceneDetectionThreshold
    }
    
    // Detect if there's significant motion that needs quality adjustment
    var hasSignificantMotion: Bool {
        return motionMagnitude > ALVRClientApp.gStore.settings.motionDetectionThreshold
    }
}

// Eye tracking history for prediction
class EyeTrackingHistory {
    private var positions: [simd_float2] = []
    private var timestamps: [Double] = []
    private let maxHistoryLength = 10
    private var velocities: [simd_float2] = []
    
    func addSample(position: simd_float2, timestamp: Double) {
        positions.append(position)
        timestamps.append(timestamp)
        
        if positions.count > 1 {
            let deltaTime = timestamps.last! - timestamps[timestamps.count - 2]
            if deltaTime > 0.0001 { // Avoid division by zero or very small numbers
                let deltaPosition = positions.last! - positions[positions.count - 2]
                let velocity = deltaPosition / Float(deltaTime)
                velocities.append(velocity)
                
                if velocities.count > maxHistoryLength {
                    velocities.removeFirst()
                }
            }
        }
        
        if positions.count > maxHistoryLength {
            positions.removeFirst()
            timestamps.removeFirst()
        }
    }
    
    func predictPosition(forTimeAhead timeAhead: Double) -> simd_float2 {
        guard !positions.isEmpty else { return simd_float2(0, 0) }
        
        if velocities.isEmpty {
            return positions.last!
        }
        
        // Calculate average velocity from recent samples
        var avgVelocity = simd_float2(0, 0)
        let count = min(velocities.count, 5) // Use last 5 velocities for smoother prediction
        if count > 0 {
           for i in 0..<count {
               avgVelocity += velocities[velocities.count - 1 - i]
           }
           avgVelocity /= Float(count)
        } else {
            return positions.last! // Not enough velocity data
        }
        
        // Predict future position
        let predictedPosition = positions.last! + (avgVelocity * Float(timeAhead))
        
        // Clamp to reasonable range (-1 to 1)
        return simd_float2(
            max(-1.0, min(1.0, predictedPosition.x)),
            max(-1.0, min(1.0, predictedPosition.y))
        )
    }
    
    func reset() {
        positions.removeAll()
        timestamps.removeAll()
        velocities.removeAll()
    }
}

struct FFR {
    private init() {}
    
    // Singleton for tracking eye position history
    private static let eyeTrackingHistory = EyeTrackingHistory()
    
    // Scene analysis cache
    private static var lastSceneAnalysis = SceneAnalysisResult()
    private static var lastAnalysisTime: Double = 0
    
    // Update eye tracking data and predict future position
    public static func updateEyeTrackingData(currentPosition: simd_float2) {
        let currentTime = CACurrentMediaTime()
        eyeTrackingHistory.addSample(position: currentPosition, timestamp: currentTime)
    }
    
    // Analyze frame content for adaptive quality
    public static func analyzeFrameContent(imageBuffer: CVImageBuffer) -> SceneAnalysisResult {
        let currentTime = CACurrentMediaTime()
        
        // Only analyze every 100ms to avoid performance impact
        if currentTime - lastAnalysisTime < 0.1 {
            return lastSceneAnalysis
        }
        
        // Lock base address
        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }
        
        var result = SceneAnalysisResult()
        
        // Simple luminance sampling for dark scene detection
        // For performance, we'll sample a sparse grid rather than every pixel
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let format = CVPixelBufferGetPixelFormatType(imageBuffer)
        
        // We'll only do basic analysis on standard formats
        if format == kCVPixelFormatType_32BGRA || 
           format == kCVPixelFormatType_32RGBA ||
           format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
           format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
            
            // For YUV formats, just sample the Y plane for luminance
            if format == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
               format == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange {
                
                if let baseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) {
                    var totalLuminance: Float = 0
                    let samplesX = 10
                    let samplesY = 10
                    let stepX = width / samplesX
                    let stepY = height / samplesY
                    //let planeWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 0) // Not directly used in loop logic below
                    let planeHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
                    let planeBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
                    var sampleCount: Float = 0
                    
                    for y_idx in 0..<samplesY {
                        for x_idx in 0..<samplesX {
                            let currentY = y_idx * stepY
                            let currentX = x_idx * stepX
                            // Ensure sample points are within plane dimensions
                            if currentY < planeHeight && currentX < CVPixelBufferGetWidthOfPlane(imageBuffer, 0) {
                                let pixelPos = currentY * planeBytesPerRow + currentX
                                // Bounds check for advanced(by:)
                                if pixelPos < planeHeight * planeBytesPerRow {
                                    let pixelPtr = baseAddress.advanced(by: pixelPos).assumingMemoryBound(to: UInt8.self)
                                    let yValue = Float(pixelPtr.pointee) / 255.0
                                    totalLuminance += yValue
                                    sampleCount += 1
                                }
                            }
                        }
                    }
                    if sampleCount > 0 {
                         result.averageLuminance = totalLuminance / sampleCount
                    }
                }
            }
            // For RGB formats, calculate luminance from RGB
            else if let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer) {
                var totalLuminance: Float = 0
                let samplesX = 10
                let samplesY = 10
                let stepX = width / samplesX
                let stepY = height / samplesY
                var sampleCount: Float = 0
                
                for y_idx in 0..<samplesY {
                    for x_idx in 0..<samplesX {
                        let currentY = y_idx * stepY
                        let currentX = x_idx * stepX * 4 // 4 bytes per pixel for RGBA/BGRA
                         // Ensure sample points are within buffer dimensions
                        if currentY < height && currentX < bytesPerRow {
                            let pixelPos = currentY * bytesPerRow + currentX
                            // Bounds check for advanced(by:)
                            if pixelPos + 3 < height * bytesPerRow { // +3 to ensure we can read R,G,B,A
                                let pixelPtr = baseAddress.advanced(by: pixelPos).assumingMemoryBound(to: UInt8.self)
                                // BGRA or RGBA format
                                let isRGBA = (format == kCVPixelFormatType_32RGBA)
                                let r = Float(pixelPtr.advanced(by: isRGBA ? 0 : 2).pointee) / 255.0
                                let g = Float(pixelPtr.advanced(by: 1).pointee) / 255.0
                                let b = Float(pixelPtr.advanced(by: isRGBA ? 2 : 0).pointee) / 255.0
                                
                                // Standard luminance calculation
                                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                                totalLuminance += luminance
                                sampleCount += 1
                            }
                        }
                    }
                }
                if sampleCount > 0 {
                    result.averageLuminance = totalLuminance / sampleCount
                }
            }
        }
        
        // Motion detection would ideally compare consecutive frames
        // For simplicity, we'll use a placeholder implementation
        // In a real implementation, this would compare the current frame with the previous one
        result.motionMagnitude = 0.1 // Placeholder
        
        lastSceneAnalysis = result
        lastAnalysisTime = currentTime
        
        return result
    }
    
    // Enhanced foveation calculation with dynamic eye tracking
    public static func calculateEnhancedFoveationVars(
        alvrEvent: StreamingStarted_Body,
        foveationSettings: FoveationSettings?,
        enhancedSettings: EnhancedFoveationSettings?,
        sceneAnalysis: SceneAnalysisResult?
    ) -> FoveationVars {
        // If enhanced settings aren't available, fall back to original calculation
        guard let enhancedSettings = enhancedSettings else {
            return calculateFoveationVars(alvrEvent: alvrEvent, foveationSettings: foveationSettings)
        }
        
        // Start with base settings
        var centerSizeX = enhancedSettings.baseSettings.centerSizeX
        var centerSizeY = enhancedSettings.baseSettings.centerSizeY
        var centerShiftX = enhancedSettings.baseSettings.centerShiftX
        var centerShiftY = enhancedSettings.baseSettings.centerShiftY
        var edgeRatioX = enhancedSettings.baseSettings.edgeRatioX
        var edgeRatioY = enhancedSettings.baseSettings.edgeRatioY
        
        // Apply eye tracking if enabled
        if enhancedSettings.foveationFollowGaze {
            // Use predicted position if available, otherwise use current
            let eyePos = enhancedSettings.predictedPosition
            
            // Apply eye position to center shift
            // Scale by strength factor (higher = more aggressive foveation)
            let eyeShiftScale = 0.3 * enhancedSettings.foveationStrength
            centerShiftX = eyePos.x * eyeShiftScale
            centerShiftY = eyePos.y * eyeShiftScale + enhancedSettings.foveationVerticalOffset
        }
        
        // Apply scene analysis adaptations if available
        if let sceneAnalysis = sceneAnalysis {
            // For dark scenes, increase quality (reduce foveation)
            if sceneAnalysis.isDarkScene && ALVRClientApp.gStore.settings.darkSceneBitrateBoosting {
                let darknessFactor = 1.0 - sceneAnalysis.averageLuminance / ALVRClientApp.gStore.settings.darkSceneDetectionThreshold
                let qualityBoost = min(0.3, darknessFactor * 0.3)
                centerSizeX += qualityBoost
                centerSizeY += qualityBoost
            }
            
            // For high motion scenes, adjust foveation to save bandwidth
            if sceneAnalysis.hasSignificantMotion && ALVRClientApp.gStore.settings.motionAdaptiveQuality {
                let motionFactor = min(1.0, sceneAnalysis.motionMagnitude / 0.5)
                let motionAdjustment = motionFactor * 0.2
                centerSizeX = max(0.2, centerSizeX - motionAdjustment)
                centerSizeY = max(0.2, centerSizeY - motionAdjustment)
                edgeRatioX = min(6.0, edgeRatioX + motionFactor * 1.0)
                edgeRatioY = min(6.0, edgeRatioY + motionFactor * 1.0)
            }
        }
        
        // Apply foveation shape adjustments
        switch enhancedSettings.foveationShape {
            case .radial:
                // Radial foveation has equal parameters in X and Y
                let avgSize = (centerSizeX + centerSizeY) / 2.0
                centerSizeX = avgSize
                centerSizeY = avgSize
                let avgRatio = (edgeRatioX + edgeRatioY) / 2.0
                edgeRatioX = avgRatio
                edgeRatioY = avgRatio
            case .rectangular:
                // Rectangular foveation keeps X and Y parameters separate
                // Already the default behavior
                break
            case .adaptive:
                // Adaptive adjusts based on content (more aggressive in X than Y for horizontal motion)
                if let sceneAnalysis = sceneAnalysis, sceneAnalysis.hasSignificantMotion {
                    // Make horizontal foveation more aggressive for motion
                    edgeRatioX = edgeRatioX * 1.2
                    centerSizeX = centerSizeX * 0.9
                }
                break
        }
        
        // Ensure values are in valid ranges
        centerSizeX = max(0.1, min(0.9, centerSizeX))
        centerSizeY = max(0.1, min(0.9, centerSizeY))
        centerShiftX = max(-0.5, min(0.5, centerShiftX))
        centerShiftY = max(-0.5, min(0.5, centerShiftY))
        edgeRatioX = max(1.0, min(10.0, edgeRatioX))
        edgeRatioY = max(1.0, min(10.0, edgeRatioY))
        
        // Create a temporary FoveationSettings with our calculated values
        let calculatedSettings = FoveationSettings(
            centerSizeX: centerSizeX,
            centerSizeY: centerSizeY,
            centerShiftX: centerShiftX,
            centerShiftY: centerShiftY,
            edgeRatioX: edgeRatioX,
            edgeRatioY: edgeRatioY
        )
        
        // Use the original calculation logic with our enhanced parameters
        return calculateFoveationVars(alvrEvent: alvrEvent, foveationSettings: calculatedSettings)
    }
    
    // Original foveation calculation (kept for compatibility)
    public static func calculateFoveationVars(alvrEvent: StreamingStarted_Body, foveationSettings: FoveationSettings?) -> FoveationVars {
        guard let settings = foveationSettings else {
            return FoveationVars(
                enabled: false,
                targetEyeWidth: 0,
                targetEyeHeight: 0,
                optimizedEyeWidth: 0,
                optimizedEyeHeight: 0,
                eyeWidthRatio: 0,
                eyeHeightRatio: 0,
                centerSizeX: 0,
                centerSizeY: 0,
                centerShiftX: 0,
                centerShiftY: 0,
                edgeRatioX: 0,
                edgeRatioY: 0
            )
        }

        let targetEyeWidth = Float(alvrEvent.view_width)
        let targetEyeHeight = Float(alvrEvent.view_height)
        
        let centerSizeX = settings.centerSizeX
        let centerSizeY = settings.centerSizeY
        let centerShiftX = settings.centerShiftX
        let centerShiftY = settings.centerShiftY
        let edgeRatioX = settings.edgeRatioX
        let edgeRatioY = settings.edgeRatioY

        let edgeSizeX = targetEyeWidth - centerSizeX * targetEyeWidth
        let edgeSizeY = targetEyeHeight - centerSizeY * targetEyeHeight

        let centerSizeXAligned = 1 - ceil(edgeSizeX / (edgeRatioX * 2)) * (edgeRatioX * 2) / targetEyeWidth
        let centerSizeYAligned = 1 - ceil(edgeSizeY / (edgeRatioY * 2)) * (edgeRatioY * 2) / targetEyeHeight

        let edgeSizeXAligned = targetEyeWidth - centerSizeXAligned * targetEyeWidth
        let edgeSizeYAligned = targetEyeHeight - centerSizeYAligned * targetEyeHeight

        let centerShiftXAligned = ceil(centerShiftX * edgeSizeXAligned / (edgeRatioX * 2)) * (edgeRatioX * 2) / edgeSizeXAligned
        let centerShiftYAligned = ceil(centerShiftY * edgeSizeYAligned / (edgeRatioY * 2)) * (edgeRatioY * 2) / edgeSizeYAligned

        let foveationScaleX = (centerSizeXAligned + (1 - centerSizeXAligned) / edgeRatioX)
        let foveationScaleY = (centerSizeYAligned + (1 - centerSizeYAligned) / edgeRatioY)

        let optimizedEyeWidth = foveationScaleX * targetEyeWidth
        let optimizedEyeHeight = foveationScaleY * targetEyeHeight

        // round the frame dimensions to a number of pixel multiple of 32 for the encoder
        let optimizedEyeWidthAligned = UInt32(ceil(optimizedEyeWidth / 32) * 32)
        let optimizedEyeHeightAligned = UInt32(ceil(optimizedEyeHeight / 32) * 32)
        
        let eyeWidthRatioAligned = optimizedEyeWidth / Float(optimizedEyeWidthAligned)
        let eyeHeightRatioAligned = optimizedEyeHeight / Float(optimizedEyeHeightAligned)
        
        return FoveationVars(
            enabled: true,
            targetEyeWidth: alvrEvent.view_width,
            targetEyeHeight: alvrEvent.view_height,
            optimizedEyeWidth: optimizedEyeWidthAligned,
            optimizedEyeHeight: optimizedEyeHeightAligned,
            eyeWidthRatio: eyeWidthRatioAligned,
            eyeHeightRatio: eyeHeightRatioAligned,
            centerSizeX: centerSizeXAligned,
            centerSizeY: centerSizeYAligned,
            centerShiftX: centerShiftXAligned,
            centerShiftY: centerShiftYAligned,
            edgeRatioX: edgeRatioX,
            edgeRatioY: edgeRatioY
        )
    }
    
    // Create enhanced foveation settings from global settings and current eye position
    public static func createEnhancedFoveationSettings(
        globalSettings: GlobalSettings,
        currentEyePosition: simd_float2,
        predictTimeAhead: Double = 0.05 // 50ms prediction by default
    ) -> EnhancedFoveationSettings {
        // Update eye tracking history
        updateEyeTrackingData(currentPosition: currentEyePosition)
        
        // Create enhanced settings
        var settings = EnhancedFoveationSettings(from: globalSettings)
        
        // Set current eye position
        settings.eyePosition = currentEyePosition
        
        // Calculate predicted position if enabled
        if globalSettings.predictiveFrameGeneration {
            settings.predictedPosition = eyeTrackingHistory.predictPosition(forTimeAhead: predictTimeAhead)
        } else {
            settings.predictedPosition = currentEyePosition
        }
        
        return settings
    }
    
    // Create Metal function constants for shader
    public static func makeFunctionConstants(_ vars: FoveationVars) -> MTLFunctionConstantValues {
        let constants = MTLFunctionConstantValues()
        var boolValue = vars.enabled
        constants.setConstantValue(&boolValue, type: .bool, index: ALVRFunctionConstant.ffrEnabled.rawValue)
        
        var float2Value: [Float32] = [vars.eyeWidthRatio, vars.eyeHeightRatio]
        constants.setConstantValue(&float2Value, type: .float2, index: ALVRFunctionConstant.ffrCommonShaderEyeSizeRatio.rawValue)
        
        float2Value = [vars.centerSizeX, vars.centerSizeY]
        constants.setConstantValue(&float2Value, type: .float2, index: ALVRFunctionConstant.ffrCommonShaderCenterSize.rawValue)
        
        float2Value = [vars.centerShiftX, vars.centerShiftY]
        constants.setConstantValue(&float2Value, type: .float2, index: ALVRFunctionConstant.ffrCommonShaderCenterShift.rawValue)
        
        float2Value = [vars.edgeRatioX, vars.edgeRatioY]
        constants.setConstantValue(&float2Value, type: .float2, index: ALVRFunctionConstant.ffrCommonShaderEdgeRatio.rawValue)
        
        return constants
    }
    
    // Enhanced function constants with additional parameters for advanced shaders
    public static func makeEnhancedFunctionConstants(_ vars: FoveationVars, _ enhancedSettings: EnhancedFoveationSettings?) -> MTLFunctionConstantValues {
        let constants = makeFunctionConstants(vars)
        
        // Add enhanced settings if available
        if let enhancedSettings = enhancedSettings {
            var boolValue = enhancedSettings.dynamicFoveation
            constants.setConstantValue(&boolValue, type: .bool, index: ALVRFunctionConstant.enhancedFoveationEnabled!.rawValue) // Fixed: Force unwrap
            
            var float2Value: [Float32] = [enhancedSettings.eyePosition.x, enhancedSettings.eyePosition.y]
            constants.setConstantValue(&float2Value, type: .float2, index: ALVRFunctionConstant.eyeGazePosition!.rawValue) // Fixed: Force unwrap
            
            var floatValue = enhancedSettings.foveationStrength
            constants.setConstantValue(&floatValue, type: .float, index: ALVRFunctionConstant.foveationStrength!.rawValue) // Fixed: Force unwrap
            
            var intValue = enhancedSettings.foveationShape.rawValue == "Radial" ? 0 : 
                           enhancedSettings.foveationShape.rawValue == "Rectangular" ? 1 : 2
            constants.setConstantValue(&intValue, type: .int, index: ALVRFunctionConstant.foveationShape!.rawValue) // Fixed: Force unwrap
        }
        
        return constants
    }
    
    // Generate server configuration for foveated rendering
    public static func generateServerConfig(from globalSettings: GlobalSettings) -> [String: Any] {
        var config: [String: Any] = [:]
        
        // Basic FFR settings
        var ffrConfig: [String: Any] = [
            "enabled": globalSettings.enhancedFoveatedRendering,
            "center_size_x": globalSettings.foveationCenterSizeX,
            "center_size_y": globalSettings.foveationCenterSizeY,
            "center_shift_x": 0.0,
            "center_shift_y": globalSettings.foveationVerticalOffset,
            "edge_ratio_x": globalSettings.foveationEdgeRatioX,
            "edge_ratio_y": globalSettings.foveationEdgeRatioY
        ]
        
        // Add dynamic foveation settings
        if globalSettings.dynamicFoveation {
            ffrConfig["dynamic"] = true
            ffrConfig["strength"] = globalSettings.foveationStrength
        }
        
        config["foveated_rendering"] = ffrConfig
        
        return config
    }
}

// Extension to ALVRFunctionConstant for enhanced foveation
extension ALVRFunctionConstant {
    // Additional constants for enhanced foveation
    static let enhancedFoveationEnabled = ALVRFunctionConstant(rawValue: 100)
    static let eyeGazePosition = ALVRFunctionConstant(rawValue: 101)
    static let foveationStrength = ALVRFunctionConstant(rawValue: 102)
    static let foveationShape = ALVRFunctionConstant(rawValue: 103)
    static let motionFactor = ALVRFunctionConstant(rawValue: 104)
    static let darknessFactor = ALVRFunctionConstant(rawValue: 105)
}
