# ALVR Optimization Guide for RTX A4500 (Shadow PC) & Apple Vision Pro

## 1. Introduction

This guide provides comprehensive instructions for optimizing your ALVR (Air Light VR) setup to achieve high-quality, low-latency PC VR streaming from a Shadow PC (equipped with an NVIDIA RTX A4500) to your Apple Vision Pro. The goal is to play demanding games like Half-Life Alyx with stunning visual fidelity and acceptable latency, leveraging your high-bandwidth WiFi 6E connection.

This setup is tailored for a single-user experience, focusing on maximizing performance and visual quality by utilizing hardware-specific optimizations for the RTX A4500 and the unique capabilities of the Apple Vision Pro, including enhanced eye tracking for dynamic foveated rendering.

**Target Setup:**
*   **Cloud PC:** Shadow PC with AMD Epyc (8 vCores @ 3.7 GHz), 28 GB RAM, NVIDIA RTX A4500 20GB.
*   **Local Machine (for potential local ALVR server testing/dev):** MacBook Pro M4 Max.
*   **VR Headset:** Apple Vision Pro.
*   **Network:** WiFi 6E with up to 70 Mbps dedicated bandwidth for streaming.

## 2. Prerequisites

*   **Shadow PC:** Account active and accessible. Ensure Windows is up-to-date.
*   **Apple Vision Pro:** visionOS updated to the latest version compatible with the ALVR client.
*   **ALVR Software:**
    *   Latest ALVR server installed on the Shadow PC.
    *   The optimized VisionOS ALVR client (based on the recent updates) installed on your Apple Vision Pro.
*   **Network:**
    *   Stable WiFi 6E router configured optimally (see Network Optimization section).
    *   Shadow PC client configured for high bandwidth (up to 70 Mbps).
    *   Ensure your local network can sustain low latency and high throughput to the Shadow PC data center.
*   **Steam & SteamVR:** Installed on the Shadow PC.
*   **NVIDIA Drivers:** Latest NVIDIA drivers for RTX A4500 installed on the Shadow PC.

## 3. Server Setup (Shadow PC - RTX A4500)

### 3.1. Installing ALVR Server
1.  Download the latest ALVR server installer (`ALVR_Installer_vX.X.X.exe`) from the official ALVR GitHub releases page.
2.  Run the installer on your Shadow PC.
3.  During installation, ensure the "Add firewall rules" option is checked.
4.  Launch ALVR after installation.

### 3.2. Applying Optimized Configuration
This guide assumes you have an `optimized_rtx_a4500_settings.json` file tailored for your setup.
1.  Open the ALVR Dashboard on your Shadow PC.
2.  Navigate to the "Settings" tab.
3.  Under the "Installation" section (or similar, depending on ALVR version), find an option to "Import settings from file" or "Load preset".
4.  Select your `optimized_rtx_a4500_settings.json` file.
5.  Restart the ALVR server if prompted.

**Key settings in `optimized_rtx_a4500_settings.json` (Highlights):**
*   **Video Codec:** HEVC (H.265) for superior quality at lower bitrates.
*   **10-bit Encoding:** Enabled for better color depth, leveraging the RTX A4500's capabilities.
*   **Bitrate:** Adaptive, targeting 70 Mbps, with a minimum of 30 Mbps.
*   **NVENC Preset:** P5 (Slower, Higher Quality) for the RTX A4500.
*   **NVENC Tuning Preset:** HighQuality.
*   **Rate Control:** VBR (Variable Bitrate).
*   **GOP Length:** Increased for better compression in cloud scenarios (e.g., 120).
*   **Foveated Rendering:** Enabled and configured to work with client-side eye tracking data.
*   **Sharpening:** Enabled with moderate strength for enhanced clarity.

### 3.3. NVIDIA Control Panel Settings (RTX A4500)
Access the NVIDIA Control Panel on your Shadow PC:
1.  Right-click on the desktop -> NVIDIA Control Panel.
2.  **Manage 3D Settings:**
    *   **Global Settings:**
        *   `Power management mode`: Prefer maximum performance.
        *   `Low Latency Mode`: Ultra (if available and stable, otherwise On).
        *   `Texture filtering - Quality`: High performance or Performance.
        *   `Vertical sync`: Off (ALVR handles frame pacing).
    *   **Program Settings:**
        *   Add `vrserver.exe` (from SteamVR) and `ALVR_streamer.exe` (or similar ALVR server executable).
        *   Apply similar settings as Global, prioritizing performance.
3.  **Configure Surround, PhysX:**
    *   Ensure PhysX processor is set to your RTX A4500.

### 3.4. Windows Optimizations for Cloud Gaming
On your Shadow PC:
1.  **Power Plan:** Set to "High Performance" or "Ultimate Performance".
2.  **Game Mode:** Enable Windows Game Mode (Settings -> Gaming -> Game Mode).
3.  **Background Applications:** Minimize background applications and services consuming CPU or network bandwidth.
4.  **Shadow Client Settings:** In your local Shadow client settings (on your MacBook Pro), ensure the bandwidth limit is set to 70 Mbps or slightly higher, and prefer reliability/low latency options if available.

## 4. VisionOS Client Setup (Apple Vision Pro)

### 4.1. Installing Optimized ALVR Client
1.  Build and deploy the optimized ALVR client project (from the `VisionOS-ALVR` repository) to your Apple Vision Pro using Xcode.
2.  Ensure the client has the necessary permissions (e.g., network access, ARKit data for eye tracking).

### 4.2. Understanding Optimized GlobalSettings
The client has been enhanced with new settings in `GlobalSettings.swift`. These are typically set to optimal defaults for your setup but can be reviewed if needed (usually via in-app settings UI if implemented, or by modifying defaults in code if you are recompiling).

**Key Optimized Client Settings (Defaults):**
*   `cloudOptimizedMode`: `true`
*   `predictiveFrameGeneration`: `true`
*   `networkBufferingStrategy`: `.adaptive`
*   `preferHEVC`: `true`
*   `prefer10BitEncoding`: `true`
*   `enhancedFoveatedRendering`: `true`
*   `dynamicFoveation`: `true`
*   `foveationFollowGaze`: `true`
*   `darkSceneBitrateBoosting`: `true`
*   `motionAdaptiveQuality`: `true`
*   `maxBitrate`: `70` (Mbps)
*   `adaptiveBitrate`: `true`
*   `singleUserOptimized`: `true`
*   `aggressivePerformanceMode`: `true`

### 4.3. Connecting to ALVR Server
1.  Ensure your Apple Vision Pro is on the same WiFi 6E network as your MacBook Pro (which connects to the Shadow PC).
2.  Launch the ALVR client app on your Vision Pro.
3.  The client should automatically discover the ALVR server running on your Shadow PC via mDNS.
4.  If the server is listed, tap to connect. If not, you might need to manually add the Shadow PC's IP address (if supported by the client UI).
5.  Once connected, SteamVR should automatically launch on the server, or you may need to start it manually from the ALVR dashboard.

## 5. Network Optimization (WiFi 6E - 70 Mbps)

### 5.1. Router Configuration (WiFi 6E)
*   **Dedicated Band:** Use the 6 GHz band exclusively for your Vision Pro if possible.
*   **Channel Width:** Set to 80 MHz or 160 MHz (if supported and stable). 160 MHz offers higher throughput but can be more susceptible to interference and have shorter range.
*   **Channel Selection:** Choose a clear channel. Use a WiFi analyzer app to find the least congested channel in the 6 GHz band.
*   **Router Placement:** Ensure clear line-of-sight between your Vision Pro and the router. Minimize obstructions.
*   **QoS (Quality of Service):** Prioritize traffic for your Vision Pro's IP address or MAC address.
*   **Firmware:** Keep your router's firmware up-to-date.
*   **Disable AirDrop/Handoff on Vision Pro:** These can sometimes interfere with WiFi performance. Go to Settings > General > AirDrop/Handoff. (This is mentioned in `ALVRClientApp.swift`'s AWDL alert.)

### 5.2. Verifying Network
*   **Shadow PC Client:** Check the Shadow client's statistics for actual bandwidth usage, latency, and packet loss.
*   **ALVR Diagnostics:** The ALVR dashboard (server-side) and potentially client-side logs/stats can provide insights into network performance (e.g., round-trip time, jitter).
*   **Ping:** Ping your Shadow PC's IP address from your local network to get a baseline latency.

### 5.3. ALVR Network Settings
These are primarily managed by the `optimized_rtx_a4500_settings.json` on the server and corresponding client defaults.
*   `stream_protocol`: UDP (for low latency).
*   `packet_size`: Around 1400 bytes is a common optimal value to avoid IP fragmentation. The provided JSON uses this.
*   `aggressive_keyframe_resend`: `true` (helps with recovery from packet loss in cloud scenarios).
*   `enable_fec`: `true` (Forward Error Correction can help mitigate minor packet loss at the cost of some bandwidth overhead). The JSON sets `fec_percentage` to 15.

## 6. Eye Tracking and Foveated Rendering

This setup features enhanced dynamic foveated rendering, leveraging the Vision Pro's eye tracking.

### 6.1. How it Works
*   **Client-Side Eye Tracking:** The `RealityKitEyeTrackingSystem.swift` (with Kalman filtering and prediction) on the Vision Pro captures your gaze.
*   **Dynamic Foveation Data:** This gaze data, along with scene analysis (darkness, motion), dynamically adjusts foveation parameters.
*   **FFR Settings:** The `FFR.swift` module calculates optimal foveation parameters based on `GlobalSettings` and real-time data.
*   **Server-Side Encoding:** The ALVR server receives these foveation parameters (if `client_driven_adaptive_quality` is enabled server-side) or uses its own foveation settings, encoding the video stream with higher quality in your foveal region and lower quality in the periphery.

### 6.2. Client Settings (`GlobalSettings.swift`)
*   `enhancedFoveatedRendering`: `true` (enables the advanced foveation logic).
*   `dynamicFoveation`: `true` (allows foveation parameters to change based on gaze and scene).
*   `foveationStrength`: `2.0` (adjusts how aggressively the periphery quality is reduced; higher is more aggressive).
*   `foveationShape`: `.radial` (a common and effective shape).
*   `foveationFollowGaze`: `true` (ensures the high-quality region follows your eyes).
*   `foveationCenterSizeX/Y`: `0.4` (normalized size of the high-quality foveal region).
*   `foveationEdgeRatioX/Y`: `4.0` (ratio determining how quickly quality drops off in the periphery).

### 6.3. Server Settings (`optimized_rtx_a4500_settings.json`)
The `foveated_rendering` block in the JSON should align with or complement client capabilities:
```json
"foveated_rendering": {
  "enabled": true,
  "center_size_x": 0.4, // Matches client default
  "center_size_y": 0.4, // Matches client default
  "center_shift_x": 0.0,
  "center_shift_y": 0.0, // Vertical offset can be tuned on client
  "edge_ratio_x": 4.0, // Matches client default
  "edge_ratio_y": 4.0, // Matches client default
  "dynamic_foveation_enabled": true, // Server acknowledges dynamic capability
  "foveation_strength": 2.0 // Matches client default
}
```
The `extra.client_driven_adaptive_quality` section in the server JSON allows the client to influence these settings.

### 6.4. Calibration and Verification
*   Currently, ALVR doesn't have an explicit eye tracking calibration step within the app for this custom setup. It relies on visionOS's system-level eye calibration.
*   Visual verification: While in VR, try looking around. The perceived quality should remain high where you're looking, while the periphery might appear softer if foveation is aggressive.

## 7. Performance Tuning for Half-Life Alyx

### 7.1. In-Game Settings
*   **Resolution:** Start with SteamVR video resolution at 100%. You can adjust this later. The ALVR client uses `renderWidth` and `renderHeight` (e.g., 26PPD or 40PPD modes) which are then scaled by the server's `render_resolution` scale.
*   **Graphics Quality:** Start with "Medium" or "High" in Half-Life Alyx. Given the RTX A4500 and optimized streaming, "High" should be achievable.
    *   Prioritize Texture Quality, Model Detail.
    *   Shadows and Anti-Aliasing can be demanding; adjust as needed.
*   **Motion Smoothing/Reprojection:** Disable any in-game or SteamVR motion smoothing if possible, as ALVR aims for native frame rates. The `predictiveFrameGeneration` on the client helps with perceived smoothness.

### 7.2. ALVR Settings Adjustments for Alyx
*   **Bitrate:** If 70 Mbps is stable, this should provide excellent quality. If you experience network-related stutters, try slightly reducing `target_total_bitrate_bps` in the server JSON (e.g., to 60-65 Mbps).
*   **Foveation Strength:** For Alyx, a `foveationStrength` of 1.5 to 2.5 is usually a good balance. Higher values save more performance/bandwidth but make peripheral degradation more noticeable.
*   **Dark Scene Bitrate Boosting:** Alyx has many dark areas. Ensure `darkSceneBitrateBoosting` (client) and corresponding server settings are active to maintain detail in these scenes. The server JSON has `client_driven_adaptive_quality.dark_scene_bitrate_boosting_enabled_by_client: true`.

### 7.3. Monitoring Performance
*   **SteamVR Performance Graph:** Enable this in SteamVR settings (Developer -> Show Performance Graph in Headset). Look for consistent frame times matching your target FPS (e.g., 11.1ms for 90 FPS). Spikes indicate stutters.
*   **ALVR Stats:**
    *   Server Dashboard: Provides stats on encoding time, network latency, client latency.
    *   Client (if UI available or via logs): Can show decoding time, frame queue length.
*   **Shadow PC Performance:** Monitor CPU, GPU, and network usage on the Shadow PC via Task Manager or other monitoring tools.

## 8. Cloud Gaming Specific Optimizations

The optimized ALVR client and server configuration include several features specifically for cloud gaming:

*   **`cloudOptimizedMode` (Client):** Enables a suite of cloud-specific behaviors, including more aggressive prediction and buffering.
*   **`predictiveFrameGeneration` (Client):** The client attempts to predict future head and controller positions to compensate for network latency. This is crucial for cloud streaming. The `trackingPredictionLatency` in `WorldTracker.swift` is dynamically adjusted.
*   **`networkBufferingStrategy` (Client):** Set to `.adaptive`. The client dynamically adjusts its frame queue size based on perceived network latency and jitter to balance smoothness and responsiveness. The `EventHandler.swift` manages this.
*   **`aggressiveKeyframeRequest` (Client):** The client is more proactive in requesting keyframes if issues are detected, helping with faster recovery in unstable network conditions.
*   **Dark Scene Bitrate Boosting:** As detailed in `FFR.swift` and `EventHandler.swift`, the client analyzes frame luminance. If a dark scene is detected, it can signal the server (if `client_driven_adaptive_quality` is enabled) or the server itself can boost bitrate to preserve details.
*   **Motion-Adaptive Quality:** Similar to dark scenes, high-motion scenes might trigger bitrate adjustments to maintain clarity or save bandwidth, managed by `FFR.swift` and `EventHandler.swift`.
*   **RTX Encoder Config (`EventHandler.swift`):** The client can send an optimized NVENC configuration to the server, tailored for the RTX A4500, including settings like `gop_size`, `num_ref_frames`, and `filler_data` which are beneficial for streaming quality and latency over WAN.

These settings work together to provide a smoother and more responsive experience despite the inherent latencies of cloud VR.

## 9. Troubleshooting

*   **Stuttering/Lag:**
    *   **Network:** This is the most common cause.
        *   Verify WiFi 6E connection quality and bandwidth.
        *   Check Shadow PC connection stats for packet loss or high latency.
        *   Reduce ALVR bitrate (`target_total_bitrate_bps`).
        *   Ensure no other devices are heavily using your local network.
    *   **Server Performance:**
        *   Shadow PC CPU or GPU might be bottlenecked. Check Task Manager.
        *   Lower in-game graphics settings in Half-Life Alyx.
    *   **Client Performance:** Less likely on Vision Pro, but ensure no other demanding apps are running.
*   **Connection Issues:**
    *   Ensure ALVR server is running and not blocked by Shadow PC firewall.
    *   Verify Vision Pro is on the correct WiFi network.
    *   Restart ALVR server and client.
    *   Check mDNS: Ensure your router allows mDNS (Bonjour) traffic.
*   **Visual Artifacts (Blockiness, Smearing):**
    *   Usually due to insufficient bitrate or severe packet loss.
    *   Increase bitrate if network can handle it.
    *   Improve network stability.
*   **Eye Tracking/Foveation Not Working:**
    *   Ensure `enhancedFoveatedRendering` is enabled on the client.
    *   Verify eye tracking is active in visionOS.
    *   Check ALVR server logs for foveation-related messages.
*   **Log Files:**
    *   **Server:** Located in the ALVR installation directory on the Shadow PC (e.g., `session_log.txt`).
    *   **Client:** Access via Xcode console when debugging, or if the client implements log saving.

## 10. Advanced Tweaks

*   **Encoder Settings (Server JSON):**
    *   Experiment with `nvenc_tuning_preset` (`HighQuality`, `LowLatencyHighQuality`, `LowLatency`).
    *   Adjust `aq_strength` for adaptive quantization (0-15, higher is more aggressive).
*   **Foveation Parameters (Client `GlobalSettings` or Server JSON):**
    *   Fine-tune `foveationCenterSizeX/Y` and `foveationEdgeRatioX/Y` for your personal preference of peripheral quality vs. performance.
    *   Adjust `foveationStrength` for more or less aggressive foveation.
*   **Client Prediction (`WorldTracker.swift`):**
    *   If comfortable with Swift, you can tweak `trackingPredictionLatency` or the logic in `updateCloudGamingParameters` for how it's derived from `streamingLatencyTarget`.
*   **Network Buffering (`EventHandler.swift`):**
    *   The adaptive logic for `frameQueueOptimalSize` can be adjusted if you have specific insights into your network's behavior.

Remember that ALVR is a complex system. Changes in one area can affect others. Make incremental adjustments and test thoroughly. Good luck, and enjoy Half-Life Alyx on your Vision Pro!
