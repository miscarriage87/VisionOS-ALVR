//
//  EventHandler.swift
//
// ALVR client framework glue code, this thread is basically
// always running and includes a self-managing watchdog to
// ensure it is always running.
//
// Other notable things include:
// - mDNS/Bonjour management (handleMdnsBroadcasts)
// - Connection flavor text and versioning info for Entry UI
// - AWDL detection (pollNALs)
// - The main event thread (handleAlvrEvents)
//
// Enhanced with cloud gaming optimizations for Shadow PC + Vision Pro setup
//

import Foundation
import Metal
import VideoToolbox
import Combine
import AVKit
import Foundation
import Network
import UIKit

class EventHandler: ObservableObject {
    static let shared = EventHandler()

    var eventsThread : Thread?
    var eventsWatchThread : Thread?
        
    var alvrInitialized = false
    var streamingActive = false
    
    
    @Published var connectionState: ConnectionState = .disconnected
    @Published var hostname: String = ""
    @Published var IP: String = ""
    @Published var alvrVersion: String = ""
    @Published var hostAlvrVersion: String = ""
    @Published var connectionFlavorText: String = ""
    
    var hostAlvrMajor = 20
    var hostAlvrMinor = 11
    var hostAlvrRevision = 0
    
    var renderStarted = false
    
    var inputRunning = false
    var vtDecompressionSession:VTDecompressionSession? = nil
    var videoFormat:CMFormatDescription? = nil
    var frameQueueLock = NSObject()

    var frameQueue = [QueuedFrame]()
    var frameQueueLastTimestamp: UInt64 = 0
    var frameQueueLastImageBuffer: CVImageBuffer? = nil
    var lastQueuedFrame: QueuedFrame? = nil
    var lastQueuedFramePose: simd_float4x4? = nil
    var lastRequestedTimestamp: UInt64 = 0
    var lastSubmittedTimestamp: UInt64 = 0
    var lastIpd: Float = -1
    var viewTransforms: [simd_float4x4] = [matrix_identity_float4x4, matrix_identity_float4x4]
    var viewFovs: [AlvrFov] = [AlvrFov(left: -1.0471973, right: 0.7853982, up: 0.7853982, down: -0.8726632), AlvrFov(left: -0.7853982, right: 1.0471973, up: 0.7853982, down: -0.8726632)]

    var framesSinceLastIDR:Int = 0
    var framesSinceLastDecode:Int = 0

    var streamEvent: AlvrEvent? = nil
    
    var framesRendered:Int = 0
    var totalFramesRendered:Int = 0
    var eventHeartbeat:Int = 0
    var lastEventHeartbeat:Int = -1
    
    var timeLastSentPeriodicUpdatedValues: Double = 0.0
    var timeLastSentMdnsBroadcast: Double = 0.0
    var timeLastAlvrEvent: Double = 0.0
    var timeLastFrameGot: Double = 0.0
    var timeLastFrameSent: Double = 0.0
    var timeLastFrameDecoded: Double = 0.0
    var numberOfEventThreadRestarts: Int = 0
    var mdnsListener: NWListener? = nil
    
    var stutterSampleStart = 0.0
    var stutterEventsCounted = 0
    var lastStutterTime = 0.0
    var awdlAlertPresented = false
    var audioIsOff = false
    var needsEncoderReset = true
    var encodingGamma: Float = 1.0
    var enableHdr = false
    
    // Cloud gaming optimizations
    var cloudOptimizedMode = true
    var adaptiveBitrateEnabled = true
    var currentBitrate: Int = 70 // Mbps
    var targetBitrate: Int = 70 // Mbps
    var minBitrate: Int = 30 // Mbps
    var maxBitrate: Int = 70 // Mbps
    var bitrateAdjustmentInterval = 1.0 // seconds
    var lastBitrateAdjustment = 0.0
    var bitrateAdjustmentFactor: Float = 1.0
    var currentSceneAnalysis: SceneAnalysisResult?
    var lastSceneAnalysisTime = 0.0
    var sceneAnalysisInterval = 0.1 // seconds
    var predictiveFrameGenerationEnabled = true
    var frameQueueOptimalSize = 2
    var frameLatencyHistory = [Double]()
    var frameLatencyHistoryMaxSize = 30
    var averageFrameLatency = 0.0
    var networkBufferingStrategy: NetworkBufferingStrategy = .adaptive
    var rtxOptimizationsEnabled = true
    var hevcEncodingEnabled = true
    var tenBitEncodingEnabled = true
    var darkSceneBitrateBoostingEnabled = true
    var motionAdaptiveQualityEnabled = true
    var singleUserOptimized = true
    var wifiBandwidthOptimized = true
    var enhancedFoveatedRenderingEnabled = true
    
    // RTX A4500 specific optimization settings
    var rtxEncoderPreset = "P5"
    var rtxEncoderProfile = "high"
    var rtxRateControlMode = "vbr"
    var rtxQualityPreset = "quality"
    
    init() {
        // Load settings from global store
        updateCloudGamingSettings()
    }
    
    // Update cloud gaming settings from global store
    func updateCloudGamingSettings() {
        let settings = ALVRClientApp.gStore.settings
        
        cloudOptimizedMode = settings.cloudOptimizedMode
        adaptiveBitrateEnabled = settings.adaptiveBitrate
        predictiveFrameGenerationEnabled = settings.predictiveFrameGeneration
        
        // Set bandwidth parameters
        maxBitrate = settings.maxBitrate
        minBitrate = settings.minBitrate
        targetBitrate = maxBitrate
        currentBitrate = targetBitrate
        
        // Set network buffering strategy
        networkBufferingStrategy = settings.networkBufferingStrategy
        frameQueueOptimalSize = settings.frameQueueSize
        
        // Set encoder preferences
        hevcEncodingEnabled = settings.preferHEVC
        tenBitEncodingEnabled = settings.prefer10BitEncoding
        
        // Set RTX A4500 optimizations
        rtxOptimizationsEnabled = true
        
        switch settings.encoderPreset {
        case .p1: rtxEncoderPreset = "P1"
        case .p2: rtxEncoderPreset = "P2"
        case .p3: rtxEncoderPreset = "P3"
        case .p4: rtxEncoderPreset = "P4"
        case .p5: rtxEncoderPreset = "P5"
        case .p6: rtxEncoderPreset = "P6"
        case .p7: rtxEncoderPreset = "P7"
        }
        
        switch settings.encoderProfile {
        case .main: rtxEncoderProfile = "main"
        case .high: rtxEncoderProfile = "high"
        case .main10: rtxEncoderProfile = "main10"
        }
        
        switch settings.encoderRateControl {
        case .cbr: rtxRateControlMode = "cbr"
        case .vbr: rtxRateControlMode = "vbr"
        case .cqp: rtxRateControlMode = "cqp"
        }
        
        switch settings.encoderQualityPreset {
        case .speed: rtxQualityPreset = "speed"
        case .balanced: rtxQualityPreset = "balanced"
        case .quality: rtxQualityPreset = "quality"
        }
        
        // Scene analysis features
        darkSceneBitrateBoostingEnabled = settings.darkSceneBitrateBoosting
        motionAdaptiveQualityEnabled = settings.motionAdaptiveQuality
        
        // Foveated rendering integration
        enhancedFoveatedRenderingEnabled = settings.enhancedFoveatedRendering
        
        // Single-user optimization
        singleUserOptimized = settings.singleUserOptimized
        
        // WiFi 6E optimization
        wifiBandwidthOptimized = true
        
        // Configure network buffer size based on strategy
        switch networkBufferingStrategy {
        case .minimal:
            frameQueueOptimalSize = 1
        case .balanced:
            frameQueueOptimalSize = 2
        case .adaptive:
            frameQueueOptimalSize = 2 // Will be adjusted dynamically
        case .aggressive:
            frameQueueOptimalSize = 3
        }
    }
    
    func initializeAlvr() {
        fixAudioForDirectStereo()
        if !alvrInitialized {
            print("Initialize ALVR")
            alvrInitialized = true
            
            // Update cloud gaming settings
            updateCloudGamingSettings()
            
            // Configure refresh rates based on settings
            let refreshRates:[Float]
            let refreshRateStr = ALVRClientApp.gStore.settings.streamFPS
            if let fps = Float(refreshRateStr) {
                refreshRates = [fps]
            } else {
                refreshRates = [90, 72, 60] // Default refresh rates
            }
            
            // Enhanced capabilities for RTX A4500 + Vision Pro setup
            let capabilities = AlvrClientCapabilities(
                default_view_width: UInt32(renderWidth*2),
                default_view_height: UInt32(renderHeight*2),
                refresh_rates: refreshRates,
                refresh_rates_count: UInt64(refreshRates.count),
                foveated_encoding: enhancedFoveatedRenderingEnabled,
                encoder_high_profile: rtxEncoderProfile == "high",
                encoder_10_bits: tenBitEncodingEnabled,
                encoder_av1: VTIsHardwareDecodeSupported(kCMVideoCodecType_AV1),
                prefer_10bit: tenBitEncodingEnabled,
                prefer_full_range: true,
                preferred_encoding_gamma: 1.5,
                prefer_hdr: false
            )
            
            alvr_initialize(/*capabilities=*/capabilities)
            alvr_initialize_logging()
            alvr_set_decoder_input_callback(nil, { data in return EventHandler.shared.handleNals(frameData: data) })
            alvr_resume()
        }
    }
    
    // Starts the EventHandler thread.
    func start() {
        alvr_resume()

        fixAudioForDirectStereo()
        if !inputRunning {
            print("Starting event thread")
            inputRunning = true
            eventsThread = Thread {
                self.handleAlvrEvents()
            }
            eventsThread?.name = "Events Thread"
            eventsThread?.start()
            
            eventsWatchThread = Thread {
                self.eventsWatchdog()
            }
            eventsWatchThread?.name = "Events Watchdog Thread"
            eventsWatchThread?.start()
        }
    }
    
    // Stops the EventHandler thread stream.
    func stop() {
        print("EventHandler.Stop")
        streamingActive = false
        vtDecompressionSession = nil
        videoFormat = nil
        lastRequestedTimestamp = 0
        lastSubmittedTimestamp = 0
        framesRendered = 0
        framesSinceLastIDR = 0
        framesSinceLastDecode = 0
        lastIpd = -1
        lastQueuedFrame = nil
        
        // Reset cloud gaming optimization state
        frameLatencyHistory.removeAll()
        averageFrameLatency = 0.0
        currentSceneAnalysis = nil
        
        updateConnectionState(.disconnected)
    }
    
    // Currently unused
    func handleHeadsetRemovedOrReentry() {
        print("EventHandler.handleHeadsetRemovedOrReentry")
        lastIpd = -1
        framesRendered = 0
        framesSinceLastIDR = 0
        framesSinceLastDecode = 0
        lastRequestedTimestamp = 0
        lastSubmittedTimestamp = 0
        lastQueuedFrame = nil
    }
    
    // Various hacks to be performed when the headset is removed or the app is exiting.
    func handleHeadsetRemoved() {
        preventAudioCracklingOnExit()
    }
    
    // Various hacks to be performed when the headset is donned and VR is entering.
    func handleHeadsetEntered() {
        fixAudioForDirectStereo()
    }
    
    // To be called when rendering is starting
    func handleRenderStarted() {
        // Prevent event thread rebooting if we can
        timeLastAlvrEvent = CACurrentMediaTime()
        timeLastFrameGot = CACurrentMediaTime()
        timeLastFrameSent = CACurrentMediaTime()
        timeLastFrameDecoded = CACurrentMediaTime()
    }

    // Ensure that the audio session is direct stereo, so that SteamVR can handle
    // all the fancy effects as it pleases.
    // Also ensures that the microphone uses the right noise cancellation.
    func fixAudioForDirectStereo() {
        audioIsOff = false
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothA2DP, .allowAirPlay])
            try audioSession.setMode(.voiceChat)
            try audioSession.setPreferredOutputNumberOfChannels(2)
            try audioSession.setIntendedSpatialExperience(.bypassed)
        } catch {
            print("Failed to set the audio session configuration?")
        }
    }
    
    // On visionOS 1, the app would have audio crackling on exiting, so
    // we avoid it by quickly shutting off the audio on exit.
    func preventAudioCracklingOnExit() {
        if audioIsOff {
            return
        }
        audioIsOff = true
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false)
        } catch {
            print("Failed to set the audio session configuration? \(error)")
        }
    }

    // Handle mDNS broadcasts, should be called periodically (1-5s)
    func handleMdnsBroadcasts() {
        // HACK: Some mDNS clients seem to only see edge updates (ie, when a client appears/disappears)
        // so we just create/destroy this every 2s until we're streaming.
        timeLastSentMdnsBroadcast = CACurrentMediaTime()
        if mdnsListener != nil {
            mdnsListener!.cancel()
            mdnsListener = nil
        }

        if mdnsListener == nil && !streamingActive {
            do {
                mdnsListener = try NWListener(using: .tcp)
            } catch {
                mdnsListener = nil
                print("Failed to create mDNS NWListener?")
            }
            
            if let listener = mdnsListener {
                let txtRecord = NWTXTRecord([
                    "protocol" : getMdnsProtocolId(),
                    "device_id" : getHostname(),
                    // Add cloud gaming optimization flags
                    "cloud_optimized": cloudOptimizedMode ? "1" : "0",
                    "hevc_enabled": hevcEncodingEnabled ? "1" : "0",
                    "10bit_enabled": tenBitEncodingEnabled ? "1" : "0",
                    "rtx_optimized": rtxOptimizationsEnabled ? "1" : "0",
                    "foveated_rendering": enhancedFoveatedRenderingEnabled ? "1" : "0",
                    "wifi_optimized": wifiBandwidthOptimized ? "1" : "0"
                ])
                listener.service = NWListener.Service(name: "ALVR Apple Vision Pro", type: getMdnsService(), txtRecord: txtRecord)

                // Handle errors if any
                listener.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        print("mDNS listener is ready")
                    case .waiting(let error):
                        print("mDNS listener is waiting with error: \(error)")
                    case .failed(let error):
                        print("mDNS listener failed with error: \(error)")
                    default:
                        break
                    }
                }
                listener.serviceRegistrationUpdateHandler = { change in
                    print("mDNS registration updated:", change)
                }
                listener.newConnectionHandler = { connection in
                    connection.cancel()
                }

                listener.start(queue: DispatchQueue.main)
            }
        }
    }

    // Data which only needs to be sent periodically, such as battery percentage
    func handlePeriodicUpdatedValues() {
        if !UIDevice.current.isBatteryMonitoringEnabled {
            UIDevice.current.isBatteryMonitoringEnabled = true
        }
        let batteryLevel = UIDevice.current.batteryLevel
        let isCharging = UIDevice.current.batteryState == .charging
        if streamingActive {
            alvr_send_battery(WorldTracker.deviceIdHead, batteryLevel, isCharging)
        }
        
        timeLastSentPeriodicUpdatedValues = CACurrentMediaTime()
        
        // Update cloud gaming settings periodically
        updateCloudGamingSettings()
        
        // Send enhanced foveated rendering parameters if enabled
        if streamingActive && enhancedFoveatedRenderingEnabled && WorldTracker.shared.eyeTrackingEnhanced {
            sendEnhancedFoveationParameters()
        }
        
        // Adjust bitrate based on scene analysis if adaptive bitrate is enabled
        if streamingActive && adaptiveBitrateEnabled {
            adjustBitrateBasedOnSceneAnalysis()
        }
    }
    
    // Send enhanced foveation parameters to the server
    func sendEnhancedFoveationParameters() {
        if let enhancedSettings = WorldTracker.shared.enhancedFoveationSettings {
            // Generate server config from enhanced settings
            let config = FFR.generateServerConfig(from: ALVRClientApp.gStore.settings)
            
            // Convert to JSON
            if let jsonData = try? JSONSerialization.data(withJSONObject: config, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                // Send to server
                alvr_send_foveation_parameters(jsonString)
            }
        }
    }
    
    // Adjust bitrate based on scene analysis
    func adjustBitrateBasedOnSceneAnalysis() {
        let currentTime = CACurrentMediaTime()
        
        // Only adjust bitrate periodically
        if currentTime - lastBitrateAdjustment < bitrateAdjustmentInterval {
            return
        }
        
        lastBitrateAdjustment = currentTime
        
        // Start with base multiplier
        var bitrateMultiplier: Float = 1.0
        
        // Apply dark scene boosting if enabled
        if darkSceneBitrateBoostingEnabled, let sceneAnalysis = currentSceneAnalysis, sceneAnalysis.isDarkScene {
            // Calculate darkness factor (0-1)
            let darknessFactor = 1.0 - sceneAnalysis.averageLuminance / ALVRClientApp.gStore.settings.darkSceneDetectionThreshold
            
            // Apply dark scene bitrate boost
            let darkSceneBoost = darknessFactor * (ALVRClientApp.gStore.settings.darkSceneBitrateMultiplier - 1.0)
            bitrateMultiplier += darkSceneBoost
            
            print("Dark scene detected, boosting bitrate by factor: \(1.0 + darkSceneBoost)")
        }
        
        // Apply motion-adaptive quality if enabled
        if motionAdaptiveQualityEnabled, let sceneAnalysis = currentSceneAnalysis {
            if sceneAnalysis.hasSignificantMotion {
                // High motion scene - increase bitrate
                let motionFactor = min(1.0, sceneAnalysis.motionMagnitude / 0.5)
                let motionBoost = motionFactor * (ALVRClientApp.gStore.settings.motionBitrateMultiplier - 1.0)
                bitrateMultiplier += motionBoost
                
                print("High motion detected, adjusting bitrate by factor: \(motionBoost)")
            } else {
                // Static scene - can reduce bitrate
                bitrateMultiplier *= ALVRClientApp.gStore.settings.staticSceneBitrateMultiplier
                
                print("Static scene detected, reducing bitrate")
            }
        }
        
        // Calculate new target bitrate
        let newTargetBitrate = Int(Float(maxBitrate) * bitrateMultiplier)
        
        // Clamp to min/max range
        targetBitrate = max(minBitrate, min(maxBitrate, newTargetBitrate))
        
        // Gradually adjust current bitrate towards target
        if currentBitrate < targetBitrate {
            currentBitrate = min(targetBitrate, currentBitrate + 5)
        } else if currentBitrate > targetBitrate {
            currentBitrate = max(targetBitrate, currentBitrate - 5)
        }
        
        // Send bitrate update to server
        if streamingActive {
            alvr_send_bitrate_update(Int32(currentBitrate * 1_000_000)) // Convert Mbps to bps
        }
    }
    
    // Make sure the event thread is always running, sometimes it gets lost.
    func eventsWatchdog() {
        while true {
            if eventHeartbeat == lastEventHeartbeat {
                if (renderStarted && numberOfEventThreadRestarts > 3) || numberOfEventThreadRestarts > 10 {
                    print("Event thread is MIA, exiting")
                    exit(0)
                }
                else {
                    print("Event thread is MIA, restarting event thread")
                    /*eventsThread = Thread {
                        self.handleAlvrEvents()
                    }
                    eventsThread?.name = "Events Thread"
                    eventsThread?.start()
                    numberOfEventThreadRestarts += 1*/
                }
            }
            
            DispatchQueue.main.async {
                let state = UIApplication.shared.applicationState
                if state == .background {
                    print("App in background, exiting")
                    if let service = self.mdnsListener {
                        service.cancel()
                        self.mdnsListener = nil
                    }
                    exit(0)
                }
            }
            
            lastEventHeartbeat = eventHeartbeat
            for _ in 0...5 {
                usleep(1000*1000)
            }
        }
    }
    
    func resetEncoding() {
        needsEncoderReset = true
    }
    
    // Analyze frame content for adaptive quality
    func analyzeFrame(imageBuffer: CVImageBuffer) {
        let currentTime = CACurrentMediaTime()
        
        // Only analyze frames periodically to save performance
        if currentTime - lastSceneAnalysisTime < sceneAnalysisInterval {
            return
        }
        
        lastSceneAnalysisTime = currentTime
        
        // Perform scene analysis
        currentSceneAnalysis = FFR.analyzeFrameContent(imageBuffer: imageBuffer)
    }
    
    // Track frame latency for adaptive buffering
    func trackFrameLatency(timestamp: UInt64) {
        let currentTime = CACurrentMediaTime()
        
        // Calculate frame latency in milliseconds
        let frameTimestampMs = Double(timestamp) / 1_000_000.0
        let currentTimeMs = currentTime * 1000.0
        let latency = currentTimeMs - frameTimestampMs
        
        // Add to history
        frameLatencyHistory.append(latency)
        
        // Limit history size
        if frameLatencyHistory.count > frameLatencyHistoryMaxSize {
            frameLatencyHistory.removeFirst()
        }
        
        // Calculate average latency
        if !frameLatencyHistory.isEmpty {
            averageFrameLatency = frameLatencyHistory.reduce(0, +) / Double(frameLatencyHistory.count)
        }
        
        // Adjust frame queue size based on network buffering strategy
        if networkBufferingStrategy == .adaptive {
            if averageFrameLatency > 80 {
                // High latency - increase buffer
                frameQueueOptimalSize = min(4, frameQueueOptimalSize + 1)
            } else if averageFrameLatency < 40 && frameQueueOptimalSize > 1 {
                // Low latency - decrease buffer
                frameQueueOptimalSize = max(1, frameQueueOptimalSize - 1)
            }
        }
    }
    
    // Create NVENC configuration for RTX A4500
    func createRTXEncoderConfig() -> [String: Any] {
        var config: [String: Any] = [:]
        
        // Basic encoder settings
        config["codec"] = hevcEncodingEnabled ? "hevc" : "h264"
        config["encoder_preset"] = rtxEncoderPreset
        config["encoder_quality"] = rtxQualityPreset
        config["rate_control_mode"] = rtxRateControlMode
        config["bitrate_bps"] = currentBitrate * 1_000_000 // Mbps to bps
        config["max_bitrate_bps"] = maxBitrate * 1_000_000 // Mbps to bps
        config["use_10bit"] = tenBitEncodingEnabled
        config["use_full_range"] = true
        
        // RTX A4500 specific optimizations
        config["nvenc_tuning_preset"] = "hq" // High quality preset for RTX
        config["nvenc_multi_pass"] = "qres" // Quality optimized multi-pass
        config["nvenc_low_delay_key_frame_scale"] = 1 // Optimize for low latency
        config["nvenc_enable_weighted_prediction"] = true
        
        // HEVC specific settings
        if hevcEncodingEnabled {
            config["hevc_cusize"] = "16x16" // Optimal for RTX A4500
            config["hevc_temporal_aq"] = true
            config["hevc_spatial_aq"] = true
            config["hevc_aq_strength"] = 15 // 1-15, higher means more aggressive quality adaptation
        }
        
        // Cloud gaming optimizations
        if cloudOptimizedMode {
            config["gop_size"] = 120 // Larger GOP for better compression
            config["num_ref_frames"] = 4 // More reference frames for better quality
            config["filler_data"] = false // Disable filler data for lower latency
            config["slice_mode"] = 0 // Single slice per frame for better compression
        } else {
            config["gop_size"] = 90 // Standard GOP size
            config["num_ref_frames"] = 1 // Fewer reference frames for lower latency
        }
        
        // WiFi 6E optimizations
        if wifiBandwidthOptimized {
            config["max_packet_size"] = ALVRClientApp.gStore.settings.packetSize
            config["network_buffer_size"] = frameQueueOptimalSize
        }
        
        return config
    }
    
    // Send RTX encoder configuration to server
    func sendRTXEncoderConfig() {
        if streamingActive && rtxOptimizationsEnabled {
            let config = createRTXEncoderConfig()
            
            // Convert to JSON
            if let jsonData = try? JSONSerialization.data(withJSONObject: config, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                // Send to server
                alvr_send_encoder_config(jsonString)
            }
        }
    }
    
    // Poll for NALs and and, when decoded, add them to the frameQueue
    func handleNals(frameData: AlvrVideoFrameData) -> Bool {
        var retVal = true
        self.timeLastFrameGot = CACurrentMediaTime()
        
        // Prevent NAL buildup
        if !self.renderStarted {
            //VideoHandler.abandonAllPendingNals()
            retVal = true
            return retVal
        }
        
        if self.needsEncoderReset {
            self.needsEncoderReset = false
            
            // Send RTX encoder configuration when resetting encoder
            if rtxOptimizationsEnabled {
                sendRTXEncoderConfig()
            }
            
            print("Resetting encoder")
            retVal = false
            return retVal
        }
        
        let timestamp = frameData.timestamp_ns
        let nal = UnsafeMutableBufferPointer<UInt8>(start: UnsafeMutablePointer(mutating: frameData.buffer_ptr), count: Int(frameData.buffer_size))
        
        objc_sync_enter(self.frameQueueLock)
        self.framesSinceLastIDR += 1

        // If we're receiving NALs timestamped from >400ms ago, stop decoding them
        // to prevent a cascade of needless decoding lag
        let ns_diff_from_last_req_ts = self.lastRequestedTimestamp > timestamp ? self.lastRequestedTimestamp &- timestamp : 0
        let lagSpiked = (ns_diff_from_last_req_ts > 1000*1000*600 && self.framesSinceLastIDR > 90*2)
        
        if CACurrentMediaTime() - self.stutterSampleStart >= 60.0 {
            print("Stuttter events in the last minute:", self.stutterEventsCounted)
            self.stutterSampleStart = CACurrentMediaTime()
            
            if self.stutterEventsCounted >= 50 {
                print("AWDL detected!")
                if ALVRClientApp.gStore.settings.dontShowAWDLAlertAgain {
                    print("User doesn't want to see the alert.")
                }
                else {
                    DispatchQueue.main.async {
                        if self.awdlAlertPresented {
                            return
                        }
                        self.awdlAlertPresented = true
                        
                        // Not super kosher but I don't see another way.
                        ALVRClientApp.shared.openWindow(id: "AWDLAlert")
                    }
                }
            }
            
            self.stutterEventsCounted = 0
        }
        if ns_diff_from_last_req_ts > 1000*1000*40 {
            if (CACurrentMediaTime() - self.lastStutterTime > 0.25 && CACurrentMediaTime() - self.lastStutterTime < 10.0) || ns_diff_from_last_req_ts > 1000*1000*100 {
                self.stutterEventsCounted += 1
                //print(ns_diff_from_last_req_ts, CACurrentMediaTime() - lastStutterTime)
            }
            self.lastStutterTime = CACurrentMediaTime()
        }
        // TODO: adjustable framerate
        // TODO: maybe also call this if we fail to decode for too long.
        if self.lastRequestedTimestamp != 0 && (lagSpiked || self.framesSinceLastDecode > 90*2) {
            objc_sync_exit(self.frameQueueLock)

            print("Handle spike! lagSpiked=\(lagSpiked) lastRequestedTimestamp=\(self.lastRequestedTimestamp), timestamp=\(timestamp), framesSinceLastDecode=\(self.framesSinceLastDecode) framesSinceLastIDR=\(self.framesSinceLastIDR) ns_diff_from_last_req_ts=\(ns_diff_from_last_req_ts)")

            // We have to request an IDR to resume the video feed
            
            self.framesSinceLastIDR = 0
            self.framesSinceLastDecode = 0

            retVal = false
            return retVal
        }
        objc_sync_exit(self.frameQueueLock)
        
        self.framesSinceLastDecode = 0
        
        let startedDecodeTime = CACurrentMediaTime()

        if let vtDecompressionSession = self.vtDecompressionSession {
            VideoHandler.feedVideoIntoDecoder(decompressionSession: vtDecompressionSession, nals: nal, timestamp: timestamp, videoFormat: self.videoFormat!) { [self] imageBuffer in
                guard let imageBuffer = imageBuffer else {
                    //print("Frame not decoded")
                    return
                }
                //print("Frame decoded")
                
                if (CACurrentMediaTime() - startedDecodeTime > Double(50*MSEC_PER_SEC)) {
                    objc_sync_enter(frameQueueLock)

                    print("Handle decode overrun!", CACurrentMediaTime() - startedDecodeTime, framesSinceLastDecode, framesSinceLastIDR, ns_diff_from_last_req_ts)

                    // We have to request an IDR to resume the video feed
                    resetEncoding()
                    
                    framesSinceLastIDR = 0
                    framesSinceLastDecode = 0
                    objc_sync_exit(frameQueueLock)

                    return
                }
                
                //print(timestamp, (CACurrentMediaTime() - timeLastFrameDecoded) * 1000.0)
                timeLastFrameDecoded = CACurrentMediaTime()

                //let imageBufferPtr = Unmanaged.passUnretained(imageBuffer).toOpaque()
                //print("finish decode: \(timestamp), \(framesSinceLastDecode)")

                // Analyze frame content for adaptive quality if enabled
                if cloudOptimizedMode && (darkSceneBitrateBoostingEnabled || motionAdaptiveQualityEnabled) {
                    analyzeFrame(imageBuffer: imageBuffer)
                }
                
                // Track frame latency for adaptive buffering
                if cloudOptimizedMode && networkBufferingStrategy == .adaptive {
                    trackFrameLatency(timestamp: timestamp)
                }
                
                objc_sync_enter(frameQueueLock)
                framesSinceLastDecode = 0
                if frameQueueLastTimestamp != timestamp || true
                {
                    alvr_report_frame_decoded(timestamp)
                    
                    let dummyPose = AlvrPose()
                    let viewParamsDummy = [AlvrViewParams(pose: dummyPose, fov: viewFovs[0]), AlvrViewParams(pose: dummyPose, fov: viewFovs[1])]

                    // TODO: For some reason, really low frame rates seem to decode the wrong image for a split second?
                    // But for whatever reason this is fine at high FPS.
                    // From what I've read online, the only way to know if an H264 frame has actually completed is if
                    // the next frame is starting, so keep this around for now just in case.
                    if frameQueueLastImageBuffer != nil {
                        //frameQueue.append(QueuedFrame(imageBuffer: frameQueueLastImageBuffer!, timestamp: frameQueueLastTimestamp))
                        frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp, viewParamsValid: false, viewParams: viewParamsDummy))
                    }
                    else {
                        frameQueue.append(QueuedFrame(imageBuffer: imageBuffer, timestamp: timestamp, viewParamsValid: false, viewParams: viewParamsDummy))
                    }
                    
                    // Limit frame queue size based on optimal size for network conditions
                    if frameQueue.count > frameQueueOptimalSize + 1 {
                        frameQueue.removeFirst(frameQueue.count - frameQueueOptimalSize)
                    }

                    frameQueueLastTimestamp = timestamp
                    frameQueueLastImageBuffer = imageBuffer
                    timeLastFrameSent = CACurrentMediaTime()
                }

                // Pull the very last imageBuffer for a given timestamp
                if frameQueueLastTimestamp == timestamp {
                    frameQueueLastImageBuffer = imageBuffer
                }

                objc_sync_exit(frameQueueLock)
                //print("End VT callback")
            }
        } else {
            let nalViewsPtrDiscarded = UnsafeMutablePointer<AlvrViewParams>.allocate(capacity: 2)
            defer { nalViewsPtrDiscarded.deallocate() }

            alvr_report_frame_decoded(timestamp)
            alvr_report_compositor_start(timestamp, nalViewsPtrDiscarded)
            alvr_report_submit(timestamp, 0)
            
            print("Force reset decoder")
            
            //return false
            retVal = false
            return retVal
        }
        
        //print("Return from callback")
        
        if self.needsEncoderReset {
            self.needsEncoderReset = false
            //print("Resetting encoder (post)")
            return false
        }
        
        return retVal
    }
    
    func getHostVersion() -> String {
        var byteArray = [UInt8](repeating: 0, count: 256)

        byteArray.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Void in
            let cStringPtr = ptr.bindMemory(to: CChar.self).baseAddress
            
            alvr_get_server_version(cStringPtr)
        }
        
        if let utf8String = String(bytes: byteArray, encoding: .utf8) {
            let ret = utf8String.trimmingCharacters(in: ["\0"]);
            return ret;
        } else {
            print("Unable to decode alvr_get_server_version into a UTF-8 string.")
            return "failed to decode host version";
        }
    }
    
    // Returns the ALVR hostname in the format "NNNN.client.alvr"
    func getHostname() -> String {
        var byteArray = [UInt8](repeating: 0, count: 256)

        byteArray.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Void in
            let cStringPtr = ptr.bindMemory(to: CChar.self).baseAddress
            
            alvr_hostname(cStringPtr)
        }
        
        if let utf8String = String(bytes: byteArray, encoding: .utf8) {
            let ret = utf8String.trimmingCharacters(in: ["\0"]);
            return ret + ".alvr"; // Hack: runtime needs to fix this D:
        } else {
            print("Unable to decode alvr_hostname into a UTF-8 string.")
            return "unknown.client.alvr";
        }
    }
    
    // Gets the mDNS service name from the client framework, usually "_alvr._tcp"
    func getMdnsService() -> String {
        var byteArray = [UInt8](repeating: 0, count: 256)

        byteArray.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Void in
            let cStringPtr = ptr.bindMemory(to: CChar.self).baseAddress
            
            alvr_mdns_service(cStringPtr)
        }
        
        if let utf8String = String(bytes: byteArray, encoding: .utf8) {
            let ret = utf8String.trimmingCharacters(in: ["\0"]);
            return ret.replacing(".local", with: "", maxReplacements: 1);
        } else {
            print("Unable to decode alvr_mdns_service into a UTF-8 string.")
            return "_alvr._tcp";
        }
    }
    
    // Gets the mDNS protocol ID, used to identify the client version to the Streamer
    // and ensure the protocol versions match.
    func getMdnsProtocolId() -> String {
        var byteArray = [UInt8](repeating: 0, count: 256)

        byteArray.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> Void in
            let cStringPtr = ptr.bindMemory(to: CChar.self).baseAddress
            
            alvr_protocol_id(cStringPtr)
        }
        
        if let utf8String = String(bytes: byteArray, encoding: .utf8) {
            let ret = utf8String.trimmingCharacters(in: ["\0"]);
            return ret;
        } else {
            print("Unable to decode alvr_protocol_id into a UTF-8 string.")
            return "unknown";
        }
    }
    
    // Restart the ALVR client framework's event thread if it's unresponsive.
    func kickAlvr() {
        stop()
        alvrInitialized = false
        alvr_destroy()
        initializeAlvr()
        
        timeLastAlvrEvent = CACurrentMediaTime()
        timeLastFrameGot = CACurrentMediaTime()
        timeLastFrameSent = CACurrentMediaTime()
        
        clearHostVersion()
    }

    // The main event thread
    func handleAlvrEvents() {
        print("Start event thread...")
        var currentCodec = -1
        while inputRunning {
            eventHeartbeat += 1
            // Send periodic updated values, such as battery percentage, once every five seconds
            let currentTime = CACurrentMediaTime()
            if currentTime - timeLastSentPeriodicUpdatedValues >= 5.0 {
                handlePeriodicUpdatedValues()
            }
            if currentTime - timeLastSentMdnsBroadcast >= 5.0 {
                handleMdnsBroadcasts()
            }
            
            DispatchQueue.main.async {
                let state = UIApplication.shared.applicationState
                if state == .background {
                    print("App in background, exiting")
                    if let service = self.mdnsListener {
                        service.cancel()
                        self.mdnsListener = nil
                    }
                    exit(0)
                }
            }
            
            let diffSinceLastEvent = 0.0//currentTime - timeLastAlvrEvent
            let diffSinceLastNal = currentTime - timeLastFrameGot
            let diffSinceLastDecode = currentTime - timeLastFrameSent
            /*if (!renderStarted && timeLastAlvrEvent != 0 && timeLastFrameGot != 0 && (diffSinceLastEvent >= 20.0 || diffSinceLastNal >= 20.0))
               || (renderStarted && timeLastAlvrEvent != 0 && timeLastFrameGot != 0 && (diffSinceLastEvent >= 30.0 || diffSinceLastNal >= 30.0))
               || (renderStarted && timeLastFrameSent != 0 && (diffSinceLastDecode >= 30.0)) {
                EventHandler.shared.updateConnectionState(.disconnected)
                
                print("Kick ALVR...")
                print("diffSinceLastEvent:", diffSinceLastEvent)
                print("diffSinceLastNal:", diffSinceLastNal)
                print("diffSinceLastDecode:", diffSinceLastDecode)
                kickAlvr()
            }*/
            
            if (!renderStarted && timeLastAlvrEvent != 0 && timeLastFrameGot != 0 && (diffSinceLastEvent >= 20.0 || diffSinceLastNal >= 20.0))
               || (renderStarted && timeLastAlvrEvent != 0 && timeLastFrameGot != 0 && (diffSinceLastEvent >= 30.0 || diffSinceLastNal >= 30.0))
               || (renderStarted && timeLastFrameSent != 0 && (diffSinceLastDecode >= 30.0)) {
                EventHandler.shared.updateConnectionState(.disconnected)
                
                print("Kick ALVR...")
                print("diffSinceLastEvent:", diffSinceLastEvent)
                print("diffSinceLastNal:", diffSinceLastNal)
                print("diffSinceLastDecode:", diffSinceLastDecode)
                
                alvr_report_fatal_decoder_error("Gimme frames >:(")
                
                timeLastAlvrEvent = CACurrentMediaTime()
                timeLastFrameGot = CACurrentMediaTime()
                timeLastFrameSent = CACurrentMediaTime()
            }
            
            if alvrInitialized && (diffSinceLastNal >= 5.0) {
                print("Request IDR")
                resetEncoding()
                timeLastFrameGot = CACurrentMediaTime()
            }

            var alvrEvent = AlvrEvent()
            let res = alvr_poll_event(&alvrEvent)
            if !res {
                Thread.sleep(forTimeInterval: 0.001)
                continue
            }
            timeLastAlvrEvent = CACurrentMediaTime()
            switch UInt32(alvrEvent.tag) {
            case ALVR_EVENT_HUD_MESSAGE_UPDATED.rawValue:
                print("hud message updated")
                if !renderStarted {
                    let hudMessageBuffer = UnsafeMutableBufferPointer<CChar>.allocate(capacity: 1024)
                    alvr_hud_message(hudMessageBuffer.baseAddress)
                    let message = String(cString: hudMessageBuffer.baseAddress!, encoding: .utf8)!
                    parseMessage(message)
                    print(message)
                    hudMessageBuffer.deallocate()
                }
                Settings.clearSettingsCache()
                updateHostVersion()
            case ALVR_EVENT_STREAMING_STARTED.rawValue:
                print("streaming started \(alvrEvent.STREAMING_STARTED)")
                updateHostVersion()
                numberOfEventThreadRestarts = 0
                encodingGamma = alvrEvent.STREAMING_STARTED.encoding_gamma
                enableHdr = alvrEvent.STREAMING_STARTED.enable_hdr
                if !streamingActive {
                    streamEvent = alvrEvent
                    streamingActive = true
                    resetEncoding()
                    framesSinceLastIDR = 0
                    framesSinceLastDecode = 0
                    lastIpd = -1
                    currentCodec = -1
                    EventHandler.shared.updateConnectionState(.connected)
                    
                    // Send RTX encoder configuration
                    if rtxOptimizationsEnabled {
                        sendRTXEncoderConfig()
                    }
                    
                    // Send enhanced foveation parameters if enabled
                    if enhancedFoveatedRenderingEnabled && WorldTracker.shared.eyeTrackingEnhanced {
                        sendEnhancedFoveationParameters()
                    }
                }
                if !renderStarted {
                    WorldTracker.shared.sendFakeTracking(viewFovs: viewFovs, targetTimestamp: CACurrentMediaTime() - 1.0)
                }
                Settings.clearSettingsCache()
            case ALVR_EVENT_STREAMING_STOPPED.rawValue:
                print("streaming stopped")
                if streamingActive {
                    streamingActive = false
                    stop()
                    timeLastAlvrEvent = CACurrentMediaTime()
                    timeLastFrameSent = CACurrentMediaTime()
                    currentCodec = -1
                }
                Settings.clearSettingsCache()
                clearHostVersion()
            case ALVR_EVENT_HAPTICS.rawValue:
                //print("haptics: \(alvrEvent.HAPTICS)")
                let haptics = alvrEvent.HAPTICS
                var duration = Double(haptics.duration_s)
                
                // Hack: Controllers can't do 10ms vibrations.
                if duration < 0.032 {
                    duration = 0.032
                }
                if haptics.device_id == WorldTracker.deviceIdLeftHand {
                    WorldTracker.shared.leftHapticsStart = CACurrentMediaTime()
                    WorldTracker.shared.leftHapticsEnd = CACurrentMediaTime() + duration
                    WorldTracker.shared.leftHapticsFreq = haptics.frequency
                    WorldTracker.shared.leftHapticsAmplitude = haptics.amplitude
                }
                else {
                    WorldTracker.shared.rightHapticsStart = CACurrentMediaTime()
                    WorldTracker.shared.rightHapticsEnd = CACurrentMediaTime() + duration
                    WorldTracker.shared.rightHapticsFreq = haptics.frequency
                    WorldTracker.shared.rightHapticsAmplitude = haptics.amplitude
                }
            case ALVR_EVENT_DECODER_CONFIG.rawValue:
                streamingActive = true
                currentCodec = Int(alvrEvent.DECODER_CONFIG.codec)
                print("create decoder \(alvrEvent.DECODER_CONFIG) codec ID: \(currentCodec)")
                Settings.clearSettingsCache()
                updateHostVersion()

                // Don't reinstantiate the decoder if it's already created.
                if vtDecompressionSession == nil {
                    let numBytes = alvr_get_decoder_config(nil)
                    var nalBuffer: UnsafeMutableBufferPointer<UInt8>? = nil
                    if numBytes > 0 {
                        nalBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(numBytes))
                    }
                    else {
                        nalBuffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: Int(1))
                    }
                    defer { nalBuffer?.deallocate() }
                    alvr_get_decoder_config(nalBuffer?.baseAddress)

                    (vtDecompressionSession, videoFormat) = VideoHandler.createVideoDecoder(initialNals: nalBuffer!, codec: currentCodec)
                }

                EventHandler.shared.updateConnectionState(.connected)
             default:
                 print("msg")
             }
             Thread.sleep(forTimeInterval: 0.0001)
        }
        
        print("Events thread stopped")
    }
    
    func updateConnectionState(_ newState: ConnectionState) {
        if renderStarted || self.connectionState == newState {
            return
        }
        DispatchQueue.main.async {
            self.connectionState = newState
        }
    }

    func parseMessage(_ message: String) {
        var flavorText = ""
        let lines = message.components(separatedBy: "\n")
        for line in lines {
            if line == "" {
                continue
            }
            if line.starts(with: "ALVR") {
                let split = line.split(separator: " ")
                if split.count == 2 {
                    updateVersion(split[1].trimmingCharacters(in: .whitespaces))
                    continue
                }
            }
            let keyValuePair = line.split(separator: ":")
            if keyValuePair.count == 2 {
                let key = keyValuePair[0].trimmingCharacters(in: .whitespaces)
                let value = keyValuePair[1].trimmingCharacters(in: .whitespaces)
                
                if key == "hostname" {
                    updateHostname(getHostname())
                } else if key == "IP" {
                    updateIP(value)
                }
            }
            else {
                flavorText += line + "\n"
            }
        }
        
        if flavorText == "The stream will begin soon\nPlease wait...\n" {
            flavorText = "The stream is ready."
        }
        
        DispatchQueue.main.async {
            self.connectionFlavorText = flavorText
        }
    }

    func updateHostname(_ newHostname: String) {
        DispatchQueue.main.async {
            self.hostname = newHostname
        }
    }

    func updateIP(_ newIP: String) {
        DispatchQueue.main.async {
            self.IP = newIP
        }
    }

    func updateVersion(_ newVersion: String) {
        DispatchQueue.main.async {
            self.alvrVersion = newVersion
        }
    }
    
    func updateHostVersion() {
        DispatchQueue.main.async {
            self.hostAlvrVersion = self.getHostVersion()
            let majorMinorRev = self.hostAlvrVersion.split(separator: ".")
            if majorMinorRev.count >= 3 {
                self.hostAlvrMajor = Int(majorMinorRev[0]) ?? 20
                self.hostAlvrMinor = Int(majorMinorRev[1]) ?? 11
                self.hostAlvrRevision = Int(majorMinorRev[2]) ?? 0
                print("Host version: v\(self.hostAlvrMajor).\(self.hostAlvrMinor).\(self.hostAlvrRevision), raw: \(self.hostAlvrVersion)")
            }
        }
    }
    
    func clearHostVersion() {
        DispatchQueue.main.async {
            self.hostAlvrVersion = ""
        }
    }
}

enum ConnectionState {
    case connected, disconnected, connecting
}

struct QueuedFrame {
    let imageBuffer: CVImageBuffer
    let timestamp: UInt64
    let viewParamsValid: Bool
    let viewParams: [AlvrViewParams]
}

// Function to send foveation parameters to server
func alvr_send_foveation_parameters(_ jsonString: String) {
    // This is a placeholder function - in a real implementation, this would be a C function
    // exported from the ALVR client library
    print("Sending foveation parameters: \(jsonString)")
}

// Function to send bitrate update to server
func alvr_send_bitrate_update(_ bitrate: Int32) {
    // This is a placeholder function - in a real implementation, this would be a C function
    // exported from the ALVR client library
    print("Sending bitrate update: \(bitrate) bps")
}

// Function to send encoder configuration to server
func alvr_send_encoder_config(_ jsonString: String) {
    // This is a placeholder function - in a real implementation, this would be a C function
    // exported from the ALVR client library
    print("Sending encoder config: \(jsonString)")
}
