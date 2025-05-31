//
//  RealityKitEyeTrackingSystem.swift
//
// This file is a fully self-contained and modular eye tracking addition
// which makes it easy to add eye tracking to any RealityKit environment with
// three lines added to a RealityKit View:
//
// await RealityKitEyeTrackingSystem.setup(content)
// MagicRealityKitEyeTrackingSystemComponent.registerComponent()
// RealityKitEyeTrackingSystem.registerSystem()
//
// Then, any Broadcast extension can read out the eye tracking data and send it
// back to this module via the CFNotificationCenter shift registers.
// (See ALVREyeBroadcast for more details on that)
//

import SwiftUI
import RealityKit
import QuartzCore
import simd

let eyeTrackWidth = Int(Float(renderWidth) * 2.5)
let eyeTrackHeight = Int(Float(renderHeight) * 2.5)

// Kalman filter for eye tracking smoothing
class EyeTrackingKalmanFilter {
    // State variables
    private var x: simd_float2 = simd_float2(0, 0) // Position
    private var v: simd_float2 = simd_float2(0, 0) // Velocity
    
    // Covariance matrix P
    private var P: simd_float2x2 = simd_float2x2(
        diagonal: simd_float2(1.0, 1.0) // Initial uncertainty
    )
    
    // Process noise (how much we trust the model vs. measurements)
    private var processNoise: Float = 0.01
    
    // Measurement noise (how much we trust the measurements)
    private var measurementNoise: Float = 0.1
    
    // Last update time
    private var lastUpdateTime: Double = CACurrentMediaTime()
    
    // Configure filter parameters based on settings
    func configure(processNoise: Float, measurementNoise: Float) {
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }
    
    // Reset the filter
    func reset() {
        x = simd_float2(0, 0)
        v = simd_float2(0, 0)
        P = simd_float2x2(diagonal: simd_float2(1.0, 1.0))
        lastUpdateTime = CACurrentMediaTime()
    }
    
    // Update the filter with a new measurement
    func update(measurement: simd_float2) -> simd_float2 {
        let currentTime = CACurrentMediaTime()
        let dt = Float(currentTime - lastUpdateTime)
        lastUpdateTime = currentTime
        
        if dt <= 0.0001 || dt > 0.1 { // Avoid division by zero or too large dt
            // If time step is invalid or too large, reset or just use measurement
            x = measurement // Or consider a reset if dt is too large
            // P might also need resetting or scaling if dt is too large
            return x
        }
        
        // --- Prediction Step ---
        // Predicted state: x_predicted = x + v * dt
        let x_predicted = x + v * dt
        
        // Predicted covariance: P_predicted = P + Q
        // Q is process noise covariance matrix
        let Q_scalar = processNoise * dt // Simplified process noise scaling
        let Q_matrix = simd_float2x2(diagonal: simd_float2(Q_scalar, Q_scalar))
        let P_predicted = P + Q_matrix
        
        // --- Update Step ---
        // Measurement noise covariance matrix R
        let R_matrix = simd_float2x2(diagonal: simd_float2(measurementNoise, measurementNoise))
        
        // Innovation (or residual) covariance: S = H * P_predicted * H_transpose + R
        // Assuming H (observation matrix) is identity (simd_float2x2(1.0))
        // So, S = P_predicted + R_matrix
        let S = P_predicted + R_matrix
        
        // Optimal Kalman gain: K = P_predicted * H_transpose * S_inverse
        // Assuming H is identity, K = P_predicted * S_inverse
        let S_inverse = simd_inverse(S) // This might fail if S is singular
        let K = P_predicted * S_inverse
        
        // Updated state estimate: x_updated = x_predicted + K * (measurement - H * x_predicted)
        // Assuming H is identity, innovation = measurement - x_predicted
        let innovation = measurement - x_predicted
        x = x_predicted + K * innovation // K is 2x2, innovation is 2x1. Result is 2x1.
        
        // Update velocity estimate (heuristic, as v is not formally in the state vector x for this simple KF)
        // v_updated = v + some_factor * K * (innovation / dt - v_current_or_predicted)
        // The (innovation / dt) term is a rough estimate of the velocity "correction" implied by the measurement.
        if dt > 0.0001 { // Avoid division by zero
             v = v + (K * (innovation / dt - v)) * Float(0.5) // K*(vec-vec) -> K*vec -> vec. vec * scalar.
        }

        // Updated covariance: P_updated = (I - K * H) * P_predicted
        // Assuming H is identity, P_updated = (I - K) * P_predicted
        let I_matrix = simd_float2x2(1.0) // Identity matrix for 2x2
        P = (I_matrix - K) * P_predicted
        
        return x
    }
    
    // Get predicted position for a future time
    func predict(timeAhead: Float) -> simd_float2 {
        return x + v * timeAhead
    }
}

// Enhanced eye tracking configuration
struct EnhancedEyeTrackingConfig {
    var enabled: Bool = true
    var useKalmanFilter: Bool = true
    var usePrediction: Bool = true
    var predictionTimeAhead: Float = 0.05 // 50ms prediction
    var adaptiveSmoothing: Bool = true
    var processNoiseMin: Float = 0.005
    var processNoiseMax: Float = 0.05
    var measurementNoiseMin: Float = 0.05
    var measurementNoiseMax: Float = 0.5
    var saccadeThreshold: Float = 0.1 // Threshold for detecting rapid eye movements
    var fixationDamping: Float = 0.9 // Damping factor for fixations
    
    // Initialize from global settings
    init(from settings: GlobalSettings) {
        self.enabled = settings.enhancedFoveatedRendering
        self.usePrediction = settings.predictiveFrameGeneration
        self.predictionTimeAhead = settings.cloudOptimizedMode ? 0.05 : 0.03
        self.adaptiveSmoothing = true
        
        // Adjust smoothing based on network conditions
        if settings.cloudOptimizedMode {
            // More aggressive smoothing for cloud gaming
            self.processNoiseMin = 0.003
            self.processNoiseMax = 0.03
            self.measurementNoiseMin = 0.08
            self.measurementNoiseMax = 0.6
        }
    }
}

class NotificationShiftRegisterVar {
    var raw: UInt32 = 0
    var bits = 0
    var latchedRaw: UInt32 = 0
    var asFloat: Float = 0.0
    var asU32: UInt32 = 0
    var asS32: Int32 = 0
    
    var finalizeCallback: (()->Void)? = nil
    
    // Latch the raw value and finalize the different representations
    private func finalize() {
        self.latchedRaw = raw
        self.asFloat = Float(bitPattern: self.latchedRaw)
        self.asU32 = self.latchedRaw
        self.asS32 = Int32(bitPattern: self.latchedRaw)

        self.finalizeCallback?()
    }

    init(_ baseName: String) {
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque(), { (center, observer, name, object, userInfo) in
            let us = Unmanaged<NotificationShiftRegisterVar>.fromOpaque(observer!).takeUnretainedValue()
            us.raw = 0
            us.bits = 0
        }, baseName + "Start" as CFString, nil, .deliverImmediately)
        
        CFNotificationCenterAddObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque(), { (center, observer, name, object, userInfo) in
            let us = Unmanaged<NotificationShiftRegisterVar>.fromOpaque(observer!).takeUnretainedValue()
            us.raw >>= 1
            us.raw |= 0
            us.bits += 1
            
            if us.bits >= 32 {
                us.finalize()
            }
        }, baseName + "0" as CFString, nil, .deliverImmediately)
        
        CFNotificationCenterAddObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque(), { (center, observer, name, object, userInfo) in
            let us = Unmanaged<NotificationShiftRegisterVar>.fromOpaque(observer!).takeUnretainedValue()
            us.raw >>= 1
            us.raw |= 0x80000000
            us.bits += 1
            
            if us.bits >= 32 {
                us.finalize()
            }
        }, baseName + "1" as CFString, nil, .deliverImmediately)
    }
}

class NotificationManager: ObservableObject {
    @Published var message: String? = nil
    
    var lastHeartbeat = 0.0
    
    var xReg = NotificationShiftRegisterVar("EyeTrackingInfoX")
    var yReg = NotificationShiftRegisterVar("EyeTrackingInfoY")
    
    // Kalman filter for eye position smoothing
    private let kalmanFilter = EyeTrackingKalmanFilter()
    
    // Configuration for eye tracking
    private var config = EnhancedEyeTrackingConfig(from: ALVRClientApp.gStore.settings)
    
    // Eye movement statistics for adaptive filtering
    private var lastEyePosition = simd_float2(0, 0)
    private var eyeVelocity = simd_float2(0, 0)
    private var lastUpdateTime = CACurrentMediaTime()
    private var isSaccade = false
    private var fixationDuration = 0.0
    private var lastConfigUpdate = 0.0
    
    func updateSingleton() {
        // Get raw eye position
        let rawX = (self.xReg.asFloat - 0.5) * 1.0
        let rawY = ((1.0 - self.yReg.asFloat) - 0.5) * 1.0
        let rawPosition = simd_float2(rawX, rawY)
        
        // Calculate time since last update
        let currentTime = CACurrentMediaTime()
        let dt = currentTime - lastUpdateTime
        // lastUpdateTime is updated within kalmanFilter.update or here if not using filter
        
        // Update configuration periodically
        if currentTime - lastConfigUpdate > 5.0 {
            config = EnhancedEyeTrackingConfig(from: ALVRClientApp.gStore.settings)
            lastConfigUpdate = currentTime
        }
        
        // Apply filtering
        var filteredPosition = rawPosition
        if config.useKalmanFilter && dt > 0 && dt < 0.1 { // dt check before calling update
            filteredPosition = kalmanFilter.update(measurement: rawPosition)
            // lastUpdateTime is updated inside kalmanFilter.update
        } else {
            lastUpdateTime = currentTime // Update time if filter not used or dt is out of bounds
        }

        // Calculate eye velocity for adaptive filtering (based on filtered position)
        if dt > 0.0001 && dt < 0.1 { // Use a small epsilon for dt
            let newVelocity = (filteredPosition - lastEyePosition) / Float(dt)
            eyeVelocity = simd_mix(eyeVelocity, newVelocity, simd_float2(Float(0.3), Float(0.3))) // Smooth velocity calculation
            
            // Detect if this is a saccade (rapid eye movement)
            let velocityMagnitude = simd_length(eyeVelocity)
            let newIsSaccade = velocityMagnitude > config.saccadeThreshold
            
            if newIsSaccade != isSaccade {
                isSaccade = newIsSaccade
                if isSaccade {
                    fixationDuration = 0.0
                    
                    // During saccades, increase process noise to follow movements more quickly
                    kalmanFilter.configure(
                        processNoise: config.processNoiseMax,
                        measurementNoise: config.measurementNoiseMin
                    )
                }
            }
            
            if !isSaccade {
                fixationDuration += dt
                
                // During fixations, reduce process noise for stability
                let fixationFactor = min(1.0, Float(fixationDuration) * 2.0) // Ensure Float cast for dt
                let processNoise = max(config.processNoiseMin, 
                                      config.processNoiseMax * (1.0 - fixationFactor))
                let measurementNoise = min(config.measurementNoiseMax,
                                         config.measurementNoiseMin + (config.measurementNoiseMax - config.measurementNoiseMin) * fixationFactor)
                
                kalmanFilter.configure(
                    processNoise: processNoise,
                    measurementNoise: measurementNoise
                )
            }
        }
        
        // Store for next update
        lastEyePosition = filteredPosition
        
        // Update world tracker with filtered position
        WorldTracker.shared.eyeX = filteredPosition.x
        WorldTracker.shared.eyeY = filteredPosition.y
        
        // Create enhanced foveation settings if enabled
        if config.enabled && ALVRClientApp.gStore.settings.enhancedFoveatedRendering {
            // Get predicted position if enabled
            var predictedGazePosition = filteredPosition
            if config.usePrediction {
                predictedGazePosition = kalmanFilter.predict(timeAhead: config.predictionTimeAhead)
            }
            
            // Update FFR with eye tracking data
            let enhancedSettings = FFR.createEnhancedFoveationSettings(
                globalSettings: ALVRClientApp.gStore.settings,
                currentEyePosition: predictedGazePosition, // Use predicted gaze for FFR
                predictTimeAhead: Double(config.predictionTimeAhead)
            )
            
            // Store enhanced settings for foveated rendering
            WorldTracker.shared.enhancedFoveationSettings = enhancedSettings
            WorldTracker.shared.eyeTrackingEnhanced = true
        } else {
            WorldTracker.shared.eyeTrackingEnhanced = false
        }
    }

    init() {
        print("NotificationManager init")
        
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque(), { (center, observer, name, object, userInfo) in
            let us = Unmanaged<NotificationManager>.fromOpaque(observer!).takeUnretainedValue()
            us.lastHeartbeat = CACurrentMediaTime()
        }, "EyeTrackingInfoServerHeartbeat" as CFString, nil, .deliverImmediately)
        
        // Eye Y gets shifted last, so use it to sync with WorldTracker
        yReg.finalizeCallback = updateSingleton
        
        // Initialize Kalman filter with default settings
        kalmanFilter.configure(
            processNoise: config.processNoiseMin,
            measurementNoise: config.measurementNoiseMax
        )
    }
    
    func send(_ msg: String) {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(msg as CFString), nil, nil, true)
    }

    deinit {
        print("NotificationManager deinit")
        let notificationCenter = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(notificationCenter, Unmanaged.passUnretained(self).toOpaque())
    }
}

struct MagicRealityKitEyeTrackingSystemComponent : Component {}
// Every WindowGroup technically counts as a Scene, which means
// we have to do Shenanigans to make sure that only the correct Scenes
// get associated with our per-frame system.
class RealityKitEyeTrackingSystem : System {
    static var howManyScenesExist = 0
    static var notificationManager = NotificationManager()
    var which = 0
    var timesTried = 0
    var s: RealityKitEyeTrackingSystemCorrectlyAssociated? = nil

    required init(scene: RealityKit.Scene) {
        which = RealityKitEyeTrackingSystem.howManyScenesExist
        RealityKitEyeTrackingSystem.howManyScenesExist += 1
    }
    
    static func setup(_ content: RealityViewContent) async {
        var hoverEffectTrackerMat: ShaderGraphMaterial? = nil
        
        if #available(visionOS 2.0, *) {
            hoverEffectTrackerMat = try! await ShaderGraphMaterial(
                named: "/Root/HoverEdgeTracker",
                from: "EyeTrackingMats.usda"
            )
        }
        else {
            hoverEffectTrackerMat = try! await ShaderGraphMaterial(
                named: "/Root/LeftEyeOnly",
                from: "EyeTrackingMats.usda"
            )
        }
        
        let leftEyeOnlyMat = try! await ShaderGraphMaterial(
            named: "/Root/LeftEyeOnly",
            from: "EyeTrackingMats.usda"
        )
            
        await MainActor.run { [hoverEffectTrackerMat] in
            let planeMesh = MeshResource.generatePlane(width: 1.0, depth: 1.0)

            let eyeXPlane = ModelEntity(mesh: planeMesh, materials: [leftEyeOnlyMat])
            eyeXPlane.name = "eye_x_plane"
            eyeXPlane.scale = simd_float3(0.0, 0.0, 0.0)
            eyeXPlane.components.set(MagicRealityKitEyeTrackingSystemComponent())
            
            let eyeYPlane = ModelEntity(mesh: planeMesh, materials: [leftEyeOnlyMat])
            eyeYPlane.name = "eye_y_plane"
            eyeYPlane.scale = simd_float3(0.0, 0.0, 0.0)
            eyeYPlane.components.set(MagicRealityKitEyeTrackingSystemComponent())

            let eye2Plane = ModelEntity(mesh: planeMesh, materials: [hoverEffectTrackerMat!])
            eye2Plane.name = "eye_2_plane"
            eye2Plane.scale = simd_float3(0.0, 0.0, 0.0)
            eye2Plane.components.set(MagicRealityKitEyeTrackingSystemComponent())
            eye2Plane.components.set(InputTargetComponent())
            eye2Plane.components.set(CollisionComponent(shapes: [ShapeResource.generateConvex(from: planeMesh)]))
                
            let anchor = AnchorEntity(.head)
            anchor.anchoring.trackingMode = .continuous
            anchor.name = "HeadAnchor"
            anchor.position = simd_float3(0.0, 0.0, 0.0)
            
            anchor.addChild(eyeXPlane)
            anchor.addChild(eyeYPlane)
            anchor.addChild(eye2Plane)
            content.add(anchor)
        }
    }
    
    func update(context: SceneUpdateContext) {
        if s != nil {
            s?.update(context: context)
            return
        }
        
        if timesTried > 10 {
            return
        }
        
        // Was hoping that the Window scenes would update slower if I avoided the weird
        // magic enable-90Hz-mode calls, but this at least has one benefit of not relying
        // on names
        
        var hasMagic = false
        let query = EntityQuery(where: .has(MagicRealityKitEyeTrackingSystemComponent.self))
        for _ in context.entities(matching: query, updatingSystemWhen: .rendering) {
            hasMagic = true
            break
        }
        
        if !hasMagic {
            timesTried += 1
            return
        }
        
        if s == nil {
            s = RealityKitEyeTrackingSystemCorrectlyAssociated(scene: context.scene)
        }
    }
}

class RealityKitEyeTrackingSystemCorrectlyAssociated : System {
    private(set) var surfaceMaterialX: ShaderGraphMaterial? = nil
    private(set) var surfaceMaterialY: ShaderGraphMaterial? = nil
    private var textureResourceX: TextureResource? = nil
    private var textureResourceY: TextureResource? = nil
    var lastHeartbeat = 0.0
    
    // Performance optimization: Skip some frames in cloud gaming mode
    private var frameCounter = 0
    private var frameSkip = 0
    
    required init(scene: RealityFoundation.Scene) {
        // Adjust frame skip based on cloud gaming mode
        if ALVRClientApp.gStore.settings.cloudOptimizedMode {
            frameSkip = 1 // Process every other frame in cloud mode
        }
        
        let eyeColors = [
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.125, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0625, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0), // 7
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0), // 11, this is where 1920x1080 goes to
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0),
            MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0), // 15
        ]
        
        Task {
            self.textureResourceX = createTextureResourceWithColors(colors: eyeColors, baseSize: CGSize(width: eyeTrackWidth, height: 1))
            self.textureResourceY = createTextureResourceWithColors(colors: eyeColors, baseSize: CGSize(width: 1, height: eyeTrackHeight))
            
            self.surfaceMaterialX = try! await ShaderGraphMaterial(
                named: "/Root/LeftEyeOnly",
                from: "EyeTrackingMats.usda"
            )
            
            self.surfaceMaterialY = try! await ShaderGraphMaterial(
                named: "/Root/LeftEyeOnly",
                from: "EyeTrackingMats.usda"
            )
        
            try! self.surfaceMaterialX!.setParameter(
                name: "texture",
                value: .textureResource(self.textureResourceX!)
            )
            try! self.surfaceMaterialY!.setParameter(
                name: "texture",
                value: .textureResource(self.textureResourceY!)
            )
        }
    }
    
    func createTextureResourceWithColors(colors: [MTLClearColor], baseSize: CGSize) -> TextureResource? {
        var mipdata: [TextureResource.Contents.MipmapLevel] = []
        
        for level in 0..<colors.count {
            var size = CGSize(width: Int(baseSize.width) / (1<<level), height: Int(baseSize.height) / (1<<level))
            if size.width <= 0 {
                size.width = 1
            }
            if size.height <= 0 {
                size.height = 1
            }
            
            let color = colors[level]
            
            let r8 = UInt8(color.red * 255)
            let g8 = UInt8(color.green * 255)
            let b8 = UInt8(color.blue * 255)
            let a8 = UInt8(color.alpha * 255)
            
            var data8 = [UInt8](repeating: 0, count: 4*Int(size.width)*Int(size.height))
            for i in 0..<Int(size.width)*Int(size.height) {
                data8[(i*4)+0] = b8
                data8[(i*4)+1] = g8
                data8[(i*4)+2] = r8
                data8[(i*4)+3] = a8
            }
            let data = Data(data8)
            let mip = TextureResource.Contents.MipmapLevel.mip(data: data, bytesPerRow: 4*Int(size.width))
            
            mipdata.append(mip)
            
            if size.width == 1 && size.height == 1 {
                break
            }
        }
        
        do
        {
            return try TextureResource(
                dimensions: .dimensions(width: Int(baseSize.width), height: Int(baseSize.height)),
                format: .raw(pixelFormat: .bgra8Unorm_srgb),
                contents: .init(
                    mipmapLevels: mipdata
                )
            )
        }
        catch {
            return nil
        }
    }
    
    func update(context: SceneUpdateContext) {
        // Performance optimization for cloud gaming: skip some frames
        frameCounter += 1
        if frameSkip > 0 && (frameCounter % (frameSkip + 1) != 0) {
            return
        }
        
        // RealityKit automatically calls this every frame for every scene.
        guard let eyeXPlane = context.scene.findEntity(named: "eye_x_plane") as? ModelEntity else {
            return
        }
        guard let eyeYPlane = context.scene.findEntity(named: "eye_y_plane") as? ModelEntity else {
            return
        }
        guard let eye2Plane = context.scene.findEntity(named: "eye_2_plane") as? ModelEntity else {
            return
        }
        
        // Leave eye tracking overlays and such off if we haven't heard from the server.
        if CACurrentMediaTime() - RealityKitEyeTrackingSystem.notificationManager.lastHeartbeat < 5.0 {
#if XCODE_BETA_16
            if #available(visionOS 2.0, *) {
                eye2Plane.components.set(HoverEffectComponent(.shader(.default)))
                if ALVRClientApp.gStore.settings.forceMipmapEyeTracking {
                    eyeXPlane.isEnabled = true
                    eyeYPlane.isEnabled = true
                    eye2Plane.isEnabled = false
                }
                else {
                    eyeXPlane.isEnabled = false
                    eyeYPlane.isEnabled = false
                    eye2Plane.isEnabled = true
                }
            }
            else {
                eyeXPlane.isEnabled = true
                eyeYPlane.isEnabled = true
                eye2Plane.isEnabled = false
            }
#else
            eyeXPlane.isEnabled = true
            eyeYPlane.isEnabled = true
            eye2Plane.isEnabled = false
#endif
            WorldTracker.shared.eyeTrackingActive = true
        }
        else {
            eyeXPlane.isEnabled = false
            eyeYPlane.isEnabled = false
            eye2Plane.isEnabled = false
            WorldTracker.shared.eyeTrackingActive = false
        }
        
        if !eyeXPlane.isEnabled && !eyeYPlane.isEnabled && !eye2Plane.isEnabled {
            return
        }
        
        if CACurrentMediaTime() - lastHeartbeat > 1.0 {
            if eye2Plane.isEnabled {
                WorldTracker.shared.eyeIsMipmapMethod = false
                RealityKitEyeTrackingSystem.notificationManager.send("EyeTrackingInfo_UseHoverEffectMethod")
            }
            else {
                WorldTracker.shared.eyeIsMipmapMethod = true
                RealityKitEyeTrackingSystem.notificationManager.send("EyeTrackingInfo_UseMipmapMethod")
            }
            lastHeartbeat = CACurrentMediaTime()
        }

        //
        // start eye track
        //
        
        let rk_eye_panel_depth: Float = rk_panel_depth * 0.5
        let transform = matrix_identity_float4x4 // frame.transform
        var planeTransformX = matrix_identity_float4x4// frame.transform
        planeTransformX.columns.3 -= transform.columns.2 * rk_eye_panel_depth
        planeTransformX.columns.3 += transform.columns.2 * rk_eye_panel_depth * 0.001
        planeTransformX.columns.3 += transform.columns.1 * rk_eye_panel_depth * (DummyMetalRenderer.renderTangents[0].z + DummyMetalRenderer.renderTangents[0].w) * 0.724
        
        var planeTransformY = transform
        planeTransformY.columns.3 -= transform.columns.2 * rk_eye_panel_depth
        planeTransformY.columns.3 += transform.columns.0 * rk_eye_panel_depth * (DummyMetalRenderer.renderTangents[0].x + DummyMetalRenderer.renderTangents[0].y) * 0.8125
        
        var planeTransform2 = transform
        planeTransform2.columns.3 -= transform.columns.2 * rk_eye_panel_depth
        
        var scaleX = simd_float3(DummyMetalRenderer.renderTangents[0].x + DummyMetalRenderer.renderTangents[0].y, 1.0, DummyMetalRenderer.renderTangents[0].z + DummyMetalRenderer.renderTangents[0].w)
        scaleX *= rk_eye_panel_depth
        scaleX.z = 5.0
        planeTransformX.columns.3 -= transform.columns.1 * rk_eye_panel_depth * (DummyMetalRenderer.renderTangents[0].z + DummyMetalRenderer.renderTangents[0].w) * 0.724
        planeTransformX.columns.3 += transform.columns.1 * rk_eye_panel_depth * (DummyMetalRenderer.renderTangents[0].z + DummyMetalRenderer.renderTangents[0].w) * 0.22625
        
        var scaleY = simd_float3(DummyMetalRenderer.renderTangents[0].x + DummyMetalRenderer.renderTangents[0].y, 1.0, DummyMetalRenderer.renderTangents[0].z + DummyMetalRenderer.renderTangents[0].w)
        scaleY *= rk_eye_panel_depth
        
        var scale2 = simd_float3(max(DummyMetalRenderer.renderTangents[0].x, DummyMetalRenderer.renderTangents[1].x) + max(DummyMetalRenderer.renderTangents[0].y, DummyMetalRenderer.renderTangents[1].y), 1.0, max(DummyMetalRenderer.renderTangents[0].z, DummyMetalRenderer.renderTangents[1].z) + max(DummyMetalRenderer.renderTangents[0].w, DummyMetalRenderer.renderTangents[1].w))
        //var scale2 = simd_float3(DummyMetalRenderer.renderTangents[0].x + DummyMetalRenderer.renderTangents[0].y, 1.0, DummyMetalRenderer.renderTangents[0].z + DummyMetalRenderer.renderTangents[0].w)
        scale2 *= rk_eye_panel_depth

        let orientationXY = /*simd_quatf(frame.transform) **/ simd_quatf(angle: 1.5708, axis: simd_float3(1,0,0))
        
        if let surfaceMaterial = surfaceMaterialX {
            eyeXPlane.model?.materials = [surfaceMaterial]
        }
        
        if let surfaceMaterial = surfaceMaterialY {
            eyeYPlane.model?.materials = [surfaceMaterial]
        }
        
        eyeXPlane.position = simd_float3(planeTransformX.columns.3.x, planeTransformX.columns.3.y, planeTransformX.columns.3.z)
        eyeXPlane.orientation = orientationXY
        eyeXPlane.scale = scaleX
        
        eyeYPlane.position = simd_float3(planeTransformY.columns.3.x, planeTransformY.columns.3.y, planeTransformY.columns.3.z)
        eyeYPlane.orientation = orientationXY
        eyeYPlane.scale = scaleY
        
        eye2Plane.position = simd_float3(planeTransform2.columns.3.x, planeTransform2.columns.3.y, planeTransform2.columns.3.z)
        eye2Plane.orientation = orientationXY
        eye2Plane.scale = scale2
            
        //
        // end eye track
        //
    }
}
