import SwiftUI
import Combine
import GameController
// import AirKit

struct PSXEmulatorView: View {
    let rom: ROMItem
    var launchMode: GameLaunchMode = .normal
    @ObservedObject var gameController: GameControllerManager
    @Binding var showMenu: Bool
    
    // Callbacks for Dispatcher
    var onSaveState: (Data) -> Void
    var closeMenu: () -> Void
    
    @StateObject private var core = PSXCore()
    @State private var isLoading = true
    @State private var isPlayingBIOS = true // Start with BIOS
    @State private var isFastForwardUIHeld = false
    @State private var isCoreFastForwarding = false
    @State private var inputTimer: Timer?
    @State private var isAirPlayConnected = false
    @State private var isPausedExternally = false // Track external pause
    
    var body: some View {
        Group {
            ZStack {
                // 1. Screen Layout (Handles Video & Aspect Ratio)
                if !isAirPlayConnected {
                    PSXScreenLayout(core: core)
                        .screenOverlay {
                            if isPlayingBIOS {
                                BIOSIntroView {
                                    // On Finish
                                    withAnimation(.easeOut(duration: 0.5)) {
                                        isPlayingBIOS = false
                                    }
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
                    PSXVirtualController(isTransparent: true)
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
            // Direct File Path Loading for Efficiency (Avoids 700MB RAM usage)
            gameController.isGameplayMode = true
            
            Air.connection { connected in
                DispatchQueue.main.async {
                    // Prevent redundant calls which cause black screen flickers
                    if self.isAirPlayConnected != connected {
                        self.isAirPlayConnected = connected
                        
                        if connected {
                            print("📺 AirPlay Connected: Starting PSX Render")
                            
                            // Audio Kickstart: Force Pause -> Wait -> Resume cycle
                            core.pause()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                print("🔊 AirPlay: Re-activating Audio Session & Resuming")
                                AudioManager.shared.setupAudioSession()
                                core.resume()
                                // Ensure BIOS flag is cleared
                                self.isPlayingBIOS = false
                            }
                            
                            // TV VIEW: Simplified Render Only
                            let tvView = PSXRenderView(renderer: core.renderer)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
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
                     controllerHeld = ControllerMappingManager.shared.isPressed(PSXAction.fastForward, gamepad: gamepad, console: rom.console.systemName)
                 }
                 
                 let newState = isFastForwardUIHeld || controllerHeld
                 if PSXCore.fastForward != newState {
                     PSXCore.fastForward = newState
                 }
                 self.isCoreFastForwarding = newState
             }
            
            // Get the real file URL from storage
            let fileURL = ROMStorageManager.shared.getROMFileURL(for: rom)
            
            print("📂 [PSXEmulatorView] Loading PSX: \(fileURL.path)")
            
            // Check music state
            let wasPlaying = MusicPlayerManager.shared.isPlaying
            
            // Load Game directly from storage path
            if core.loadGame(url: fileURL) {
                print("🚀 Native PSX Core Started")
                isLoading = false
                
                 // Mute Core initially for BIOS
                core.pause()
            } else {
                print("❌ Native PSX Failed")
            }
            
            // Enforce audio session to keep music playing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AudioManager.shared.setupAudioSession()
                if wasPlaying {
                    MusicPlayerManager.shared.resume()
                }
            }
        }
        .onDisappear {
            // STOP AirPlay immediately when exiting emulator
            print("🛑 Exiting PSX Emulator - Stopping AirPlay")
            Air.stop()
            Air.clearListeners()
            self.isAirPlayConnected = false
            
            core.stopLoop()
            gameController.isGameplayMode = false
            // Reset Fast Forward just in case
            inputTimer?.invalidate()
            inputTimer = nil
            PSXCore.fastForward = false
        }
        // Listen for Save State Trigger
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSaveState"))) { _ in
            print("🎮 PSXEmulatorView: TriggerSaveState received")
            if let data = core.saveState() {
                onSaveState(data)
            } else {
                print("❌ PSXEmulatorView: Failed to create save state")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerLoadState"))) { notification in
            print("🎮 PSXEmulatorView: TriggerLoadState received")
            if let base64 = notification.object as? String,
               let data = Data(base64Encoded: base64) {
                if core.loadState(data: data) {
                    print("✅ PSXEmulatorView: State Loaded")
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
    
    // Local Fast Forward Button
    private var fastForwardButton: some View {
        Group {
            if PSXSkinManager.shared.currentSkin != nil {
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
