import SwiftUI
import Combine
import GameController

struct SNESEmulatorView: View {
    let rom: ROMItem
    @ObservedObject var gameController: GameControllerManager
    @Binding var showMenu: Bool
    
    var onSaveState: (Data) -> Void
    var closeMenu: () -> Void
    
    @StateObject private var core = SNESCore()
    @State private var isFastForwardUIHeld = false
    @State private var isCoreFastForwarding = false
    @State private var inputTimer: Timer?
    @State private var isLoading = true
    @State private var isPlayingBIOS = true
    @State private var isPausedExternally = false
    @State private var isAirPlayConnected = false
    
    var body: some View {
        Group {
            ZStack {
                if !isAirPlayConnected {
                    SNESScreenLayout(core: core)
                        .screenOverlay {
                            if isPlayingBIOS {
                                BIOSIntroView {
                                    // On Finish
                                    withAnimation(.easeOut(duration: 0.5)) {
                                        isPlayingBIOS = false
                                    }
                                    // Only resume if not externally paused (e.g. by ResumePrompt)
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
                
                if !gameController.isControllerConnected {
                    SNESVirtualController(isTransparent: true)
                        .zIndex(10)
                }
                
                // Fast Forward Button (TEMPORARILY DISABLED)
                // if !showMenu && !gameController.isControllerConnected {
                //     fastForwardButton
                //         .zIndex(20)
                // }
            }
        }
        .onAppear {
            gameController.isGameplayMode = true
            
            Air.connection { connected in
                DispatchQueue.main.async {
                    if self.isAirPlayConnected != connected {
                        self.isAirPlayConnected = connected
                        
                        if connected {
                            print(" AirPlay Connected: Starting SNES Render")
                            
                            core.pause()
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                print(" AirPlay: Re-activating Audio Session & Resuming")
                                AudioManager.shared.setupAudioSession()
                                core.resume()
                                self.isPlayingBIOS = false
                            }
                            
                            let tvView = SNESRenderView(renderer: core.renderer)
                                            .aspectRatio(4.0/3.0, contentMode: .fit)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(Color.black)
                                            .edgesIgnoringSafeArea(.all)
                            Air.play(AnyView(tvView))
                        } else {
                            print(" AirPlay Disconnected")
                            Air.stop()
                        }
                    }
                }
            }
            
            // Start Input Polling Timer
             self.inputTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                 var controllerHeld = false
                 if let gamepad = GameControllerManager.shared.currentController?.extendedGamepad {
                     controllerHeld = ControllerMappingManager.shared.isPressed(SNESAction.fastForward, gamepad: gamepad, console: rom.console.systemName)
                 }
                 
                 let newState = isFastForwardUIHeld || controllerHeld
                 if SNESCore.fastForward != newState {
                     SNESCore.fastForward = newState
                 }
                 self.isCoreFastForwarding = newState
             }
            
            let fileURL = ROMStorageManager.shared.getROMFileURL(for: rom)
            print(" [SNESEmulatorView] Loading SNES: \(fileURL.path)")
            
            let wasPlaying = MusicPlayerManager.shared.isPlaying
            
            if core.loadGame(url: fileURL) {
                print(" Native SNES Core Started")
                isLoading = false
                
                // Mute Core initially for BIOS
                core.pause()
            } else {
                print(" Native SNES Failed")
            }
            // Enforce audio session
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AudioManager.shared.setupAudioSession()
                if wasPlaying {
                    MusicPlayerManager.shared.resume()
                }
            }
        }
        .onDisappear {
            // STOP AirPlay immediately when exiting emulator
            print(" Exiting SNES Emulator - Stopping AirPlay")
            Air.stop()
            Air.clearListeners()
            self.isAirPlayConnected = false
            
            core.stopLoop()
            gameController.isGameplayMode = false
            inputTimer?.invalidate()
            inputTimer = nil
            SNESCore.fastForward = false
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSaveState"))) { _ in
            if let data = core.saveState() { onSaveState(data) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("TriggerLoadState"))) { nn in
            if let b64 = nn.object as? String, let data = Data(base64Encoded: b64) {
                if core.loadState(data: data) { closeMenu() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleEmulatorPause"))) { notification in
            if let shouldPause = notification.object as? Bool {
                isPausedExternally = shouldPause // Update state tracking
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
            if SNESSkinManager.shared.currentSkin != nil {
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
