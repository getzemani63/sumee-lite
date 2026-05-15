import SwiftUI
import Combine
import GameController
// import AirKit

struct GBAEmulatorView: View {
    let rom: ROMItem
    let romData: Data? // GBA Core in original code used romData binding from WebEmulatorView to write temp file
    var launchMode: GameLaunchMode = .normal
    @ObservedObject var gameController: GameControllerManager
    @Binding var showMenu: Bool
    
    var onSaveState: (Data) -> Void
    var closeMenu: () -> Void
    
    @StateObject private var core = GBACore()
    @State private var isLoading = true
    @State private var isPlayingBIOS = true // Start with BIOS
    @State private var isFastForwardUIHeld = false
    @State private var isCoreFastForwarding = false
    @State private var inputTimer: Timer?
    @State private var isAirPlayConnected = false
    @State private var isPausedExternally = false // Track external pause requests
    var skipBIOS: Bool = false

    var body: some View {
        Group {
            ZStack {
                // 1. Screen Layout (Handles Video & Aspect Ratio)
                if !isAirPlayConnected {
                    GBAScreenLayout(
                        core: core,
                        aspectRatio: (rom.console == .gameboy || rom.console == .gameboyColor) ? (10.0/9.0) : (3.0/2.0),
                        logoName: (rom.console == .gameboy) ? "GB" : (rom.console == .gameboyColor ? "GBC" : "GBA")
                    )
                    .screenOverlay {
                        if isPlayingBIOS && !skipBIOS {
                            BIOSIntroView {
                                // On Finish
                                withAnimation(.easeOut(duration: 0.5)) {
                                    isPlayingBIOS = false
                                }
                                // Un-mute core audio when BIOS fades out, ONLY if not paused
                                if !isPausedExternally {
                                    core.resume()
                                }
                            }
                            .transition(.opacity)
                        }
                    }
                    .ignoresSafeArea()
                } else {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 8) {
                        Image(systemName: "tv.inset.filled")
                            .font(.system(size: 44))
                            .foregroundColor(.white.opacity(0.3))
                        Text("Playing on TV")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.3))
                    }
                }
                
                // 2. Virtual Controller (Handles Input UI & Transparency)
                if !gameController.isControllerConnected {
                    GBAVirtualController(isTransparent: true)
                        .zIndex(10)
                }
                
                // 3. Fast Forward Button (TEMPORARILY DISABLED)
                // if !showMenu && !gameController.isControllerConnected {
                //     fastForwardButton
                //         .zIndex(20)
                // }
            }
        }
        .onAppear {
            gameController.isGameplayMode = true // ENABLE PERFORMANCE MODE
            
            // Connect AirPlay Listener
            Air.connection { connected in
                DispatchQueue.main.async {
                    // Prevent redundant calls to Air.play which causes flickering (recreating the VC)
                    if self.isAirPlayConnected != connected {
                        self.isAirPlayConnected = connected
                        
                        if connected {
                            print("📺 AirPlay Connected: Starting TV Render")
                            
                            // Audio Kickstart: Force Pause -> Wait -> Resume cycle (Simulates Menu Open/Close)
                            // This resets the audio engine after the HDMI/AirPlay route change
                            core.pause()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                print("🔊 AirPlay: Re-activating Audio Session & Resuming")
                                AudioManager.shared.setupAudioSession()
                                core.resume()
                                // Ensure BIOS flag is cleared to avoid state conflicts
                                self.isPlayingBIOS = false
                            }
                            
                            // TV VIEW: Simplified Render Only (No Skins, No Layout logic)
                            let tvView = GBARenderView(renderer: core.renderer)
                                .aspectRatio((rom.console == .gameboy || rom.console == .gameboyColor) ? (10.0/9.0) : (3.0/2.0), contentMode: .fit)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color.black)
                                .edgesIgnoringSafeArea(.all)
                            
                            Air.play(AnyView(tvView))
                        } else {
                            print("📺 AirPlay Disconnected")
                            Air.stop()
                        }
                    }
                }
            }
            
            // Start Input Polling Timer
             self.inputTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                 var controllerHeld = false
                 if let gamepad = GameControllerManager.shared.currentController?.extendedGamepad {
                     controllerHeld = ControllerMappingManager.shared.isPressed(GBAAction.fastForward, gamepad: gamepad, console: rom.console.systemName)
                 }
                 
                 let newState = isFastForwardUIHeld || controllerHeld
                 if core.isFastForwarding != newState {
                     core.isFastForwarding = newState
                 }
                 self.isCoreFastForwarding = newState
             }
            
            // NEW LOGIC: Load directly from ROMStorageManager without duplication
            let fileURL = ROMStorageManager.shared.getROMFileURL(for: rom)
            
            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    print("📂 [GBAEmulatorView] Loading ROM from path: \(fileURL.path)")
                    
                    let loadAndPlay = {
                         let wasPlaying = MusicPlayerManager.shared.isPlaying
                         
                         _ = core.loadGame(url: fileURL)
                         print("🚀 Native GBA Core Started")
                         isLoading = false
                         
                         // MUTE Core initially so BIOS sound plays cleanly
                         core.pause()
                         
                         // Enforce audio session
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                             AudioManager.shared.setupAudioSession()
                             if wasPlaying {
                                 MusicPlayerManager.shared.resume()
                             }
                         }
                    }
                    
                    loadAndPlay()
                } else if let data = romData {
                    // Fallback: If for some reason file doesn't exist but we have data (unlikely for library games)
                    // Write to temp? No, try to write to correct path?
                    // Let's just write to the correct path if missing
                    try data.write(to: fileURL)
                    print("⚠️ [GBAEmulatorView] Restored missing ROM file from data")
                    
                    // Recursive call to play
                    if FileManager.default.fileExists(atPath: fileURL.path) {
                         let wasPlaying = MusicPlayerManager.shared.isPlaying
                         _ = core.loadGame(url: fileURL)
                         isLoading = false
                         core.pause()
                         DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                             AudioManager.shared.setupAudioSession()
                             if wasPlaying { MusicPlayerManager.shared.resume() }
                         }
                    }
                } else {
                    print("❌ [GBAEmulatorView] Error: ROM file not found and no data provided.")
                }
            } catch {
                print("❌ Error initializing GBA Core: \(error)")
            }
        }
        .onDisappear {
            // STOP AirPlay immediately when exiting emulator
            print("🛑 Exiting GBA Emulator - Stopping AirPlay")
            Air.stop()
            Air.clearListeners() // Drop closure references to GBACore
            self.isAirPlayConnected = false
            
            inputTimer?.invalidate()
            inputTimer = nil
            core.stopLoop()
            gameController.isGameplayMode = false
             // Reset Fast Forward
            // GBACore.isFastForwarding is instance property?
            // Original code: `gbaCore.isFastForwarding = enabled`
            core.isFastForwarding = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSaveState"))) { _ in
            if let data = core.saveState() {
                onSaveState(data)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerLoadState"))) { notification in
            if let base64 = notification.object as? String,
               let data = Data(base64Encoded: base64) {
                if core.loadState(data: data) {
                    closeMenu()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleEmulatorPause"))) { notification in
            if let shouldPause = notification.object as? Bool {
                isPausedExternally = shouldPause
                if shouldPause {
                    core.pause()
                } else {
                    core.resume()
                }
            }
        }
    }
    
    private var fastForwardButton: some View {
        Group {
            if GBASkinManager.shared.currentSkin != nil {
                EmptyView()
            } else {
                GeometryReader { geometry in
                    Button(action: {
                        isFastForwardUIHeld.toggle()
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isCoreFastForwarding ? .yellow : .white)
                            .padding(8)
                    }
                    .position(
                        x: 60,
                        y: geometry.size.height - geometry.safeAreaInsets.bottom - 0
                    )
                }
            }
        }
    }
}
