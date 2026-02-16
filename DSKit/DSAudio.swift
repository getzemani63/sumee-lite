import Foundation
import AVFoundation

class DSAudio {
    static let shared = DSAudio()
    
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    
    private var audioFormat: AVAudioFormat?
    
    private let queueLock = NSLock()
    private var buffersInFlight = 0
    private let maxBuffersInFlight = 4 // Reduced from 6 to 4 to lower latency
    
    init() {
        setupObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(handleRouteChange), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleInterruption), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(handleEngineConfigChange), name: .AVAudioEngineConfigurationChange, object: engine)
    }

    @objc private func handleEngineConfigChange(notification: Notification) {
        print("🔊 [DSAudio] Engine Configuration Change Detected")
        // The engine might have stopped itself
        if !engine.isRunning && audioFormat != nil {
             restartEngine()
        }
    }

    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        
        print("🔊 [DSAudio] Route Change Detected: \(reason)")
        
        // If we are actively using the engine, we might need to kick it
        guard audioFormat != nil else { return }

        switch reason {
        case .newDeviceAvailable, .oldDeviceUnavailable, .categoryChange:
             // Wait a tiny bit for the OS to settle the route
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                 self?.restartEngine()
             }
        default:
            break
        }
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
              
        if type == .began {
            print(" [DSAudio] Interruption Began")
            // Engine usually pauses automatically
        } else if type == .ended {
            print(" [DSAudio] Interruption Ended")
            if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                if options.contains(.shouldResume) {
                    restartEngine()
                }
            }
        }
    }
    
    private func restartEngine() {
        guard let format = audioFormat else { return }
        print(" [DSAudio] Restarting Engine to adapt to new route...")
        
        if engine.isRunning { engine.stop() }
        
        // Re-connect
        engine.detach(playerNode)
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        if !engine.isRunning {
            do {
                try engine.start()
                if !playerNode.isPlaying { playerNode.play() }
                print(" [DSAudio] Engine Restarted Successfully.")
            } catch {
                 print("[DSAudio] Engine Restart Failed: \(error)")
            }
        }
    }
    
    // ...
    
    func start(rate: Double) {
        print("🔊 [DSAudio] Iniciando Audio Engine a \(rate) Hz")
        
        queueLock.lock()
        buffersInFlight = 0
        tempBuffer.removeAll() // Ensure buffer is clear on start
        queueLock.unlock()
        
        // If engine is already configured correctly and just paused, simply resume
        if engine.isRunning && audioFormat?.sampleRate == rate {
            print(" [DSAudio] Resuming existing engine (Fast Path)")
            playerNode.play()
            return
        }
        
        audioFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)
        
        guard let format = audioFormat else {
             print("[DSAudio] Error creando formato de audio")
             return
        }
        
        let session = AVAudioSession.sharedInstance()
        do {
            // [FIX] Use Playback Category to ensure High Quality Bluetooth Audio (A2DP).
            // Previous use of .playAndRecord forced Bluetooth into Hands-Free Profile (Mono/Low Quality).
            // Since Microphone is currently disabled in DSCore, we prioritize output quality.
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowAirPlay])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            print("[DSAudio] Session configured: Playback (High Quality A2DP, No Mic)")
        } catch {
            print("[DSAudio] Critical: Audio Session configuration failed: \(error)")
        }

        if engine.isRunning { engine.stop() } // Full reset if format changed

        engine.detach(playerNode) 
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: format)
        
        playerNode.volume = 1.0
        engine.mainMixerNode.outputVolume = 1.0
        
        do {
            try engine.start()
            // [FIX] Audio Pop: Do NOT play immediately.
            // Wait for first buffer in writeAudio() to trigger playback.
            playerNode.reset()
            print("[DSAudio] Audio Engine configured. Waiting for data...")
        } catch {
            print("[DSAudio] Error iniciando audio: \(error)")
        }
    }
    
    func stop() {
        if engine.isRunning {
            playerNode.pause() // Use pause instead of stop to keep engine warm if possible
            if engine.isRunning { engine.pause() } // Pause engine instead of full stop to keep graph intact
            print("[DSAudio] Audio Engine Pausado")
        }
    }
    
    func shutdown() {
        if engine.isRunning {
             playerNode.stop()
             engine.stop()
             engine.reset()
             print("[DSAudio] Audio Engine Apagado Completamente")
        }
    }
    
    func clearBuffer() {
        queueLock.lock()
        tempBuffer.removeAll(keepingCapacity: false)
        buffersInFlight = 0
        queueLock.unlock()
        
        if engine.isRunning {
             // Stop the player immediately to drop any scheduled buffers
             playerNode.stop() 
             // IMPORTANT: Check if we need to restart playback immediately or wait?
             // Usually cleared buffer means we want silence until new data arrives.
        }
        print(" [DSAudio] Audio buffers cleared.")
    }
    
    private var tempBuffer: [Int16] = []
    private let bufferFrameThreshold = 2048 // Reduced from 4096 to 2048 for lower latency 
    
    func writeAudio(data: UnsafePointer<Int16>, frames: Int) {
        if frames == 0 { return }
        
        queueLock.lock()
        let count = frames * 2
        for i in 0..<count {
            tempBuffer.append(data[i])
        }
        
        if tempBuffer.count < (bufferFrameThreshold * 2) {
            queueLock.unlock()
            return
        }
        
        let processingData = Array(tempBuffer)
        tempBuffer.removeAll(keepingCapacity: true)
        let processingFrames = processingData.count / 2
        
        if buffersInFlight > maxBuffersInFlight {
            queueLock.unlock()
            return 
        }
        buffersInFlight += 1
        queueLock.unlock()
        
        guard let format = audioFormat else { return }
        
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(processingFrames)) else {
            queueLock.lock()
            buffersInFlight -= 1
            queueLock.unlock()
            return 
        }
        buffer.frameLength = AVAudioFrameCount(processingFrames)
        
        let scale: Float = 1.0 / 32768.0
        let leftChannel = buffer.floatChannelData![0]
        let rightChannel = buffer.floatChannelData![1]
        
        for i in 0..<processingFrames {
            leftChannel[i] = Float(processingData[i*2]) * scale
            rightChannel[i] = Float(processingData[i*2 + 1]) * scale
        }
        
        if engine.isRunning {
             playerNode.scheduleBuffer(buffer) { [weak self] in
                 guard let self = self else { return }
                 self.queueLock.lock()
                 self.buffersInFlight -= 1
                 self.queueLock.unlock()
             }
             if !playerNode.isPlaying { playerNode.play() }
        } else {
             queueLock.lock()
             buffersInFlight -= 1
             queueLock.unlock()
             try? engine.start()
             
             // [FIX] Crash Safety: Only play if engine successfully started.
             // If another app (Music/Spotify) owns the session, start() might fail silently.
             if engine.isRunning {
                 playerNode.play()
             } else {
                 print("[DSAudio] Engine failed to start. Skipping playback to prevent crash.")
             }
        }
    }
}
