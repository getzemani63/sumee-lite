import SwiftUI
import Combine
import GameController

struct DSEmulatorView: View {
    let rom: ROMItem
    @ObservedObject var gameController: GameControllerManager
    @Binding var showMenu: Bool
    
    // Callbacks for Dispatcher
    var onSaveState: (Data) -> Void
    var closeMenu: () -> Void
    var dismiss: DismissAction? // Optional if we need to dismiss from here (for bios/firmware fail)
    
    @StateObject private var core = DSCore.shared
    @State private var isFastForwardUIHeld = false
    @State private var isCoreFastForwarding = false
    @State private var inputTimer: Timer?
    @State private var showBiosImporter = false
    @State private var showFirmwareConfig = false
    @State private var isLoading = true
    @State private var isAirPlayConnected = false
    @State private var isPausedExternally = false // Track external pause requests
    
    var body: some View {
        Group {
            if true { // Desmume HLE: No BIOS required
                ZStack {
                    if !isAirPlayConnected {
                        Color.black
                        // Standard Rendering (Standard Layout)
                        DSScreensLayout(core: core)
                            .ignoresSafeArea()
                    } else {
                        Color.black.ignoresSafeArea()
                        
                     
                        VStack(spacing: 0) {
                            Spacer()
                            
                            DSRenderView(renderer: core.renderer, screenMode: .bottomOnly)
                                .aspectRatio(256.0/192.0, contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                            
                            Spacer()
                                .frame(height: 50)
                            
                            Text("Touch Screen Active")
                                .font(.caption2)
                                .foregroundColor(.gray)
                                .padding(.bottom, 20)
                        }
                    }
                    
                    // Controls Overlay (Always active, handles visibility internally)
                    DSVirtualController(isTransparent: true, showInputControls: !gameController.isControllerConnected)
                        .zIndex(10)
                    
                    // Fast Forward Button (TEMPORARILY DISABLED)
                    // if !showMenu && !gameController.isControllerConnected {
                    //     fastForwardButton
                    //         .zIndex(20)
                    // }
                }
            }
        }
        .onAppear {
            if true { // Desmume HLE: skip BIOS check
                // Connect AirPlay Listener
                Air.connection { connected in
                    DispatchQueue.main.async {
                        if self.isAirPlayConnected != connected {
                            self.isAirPlayConnected = connected
                            
                            if connected {
                                print(" AirPlay Connected: Split Screen Mode (DS)")
                                
                                // Audio Kickstart - ONLY if game is already loaded.
                                // If game is loading, loadDSGame will handle this to avoid race conditions.
                                if !self.isLoading {
                                    print(" DS (Running): AirPlay connected, restarting audio...")
                                    core.pause()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        AudioManager.shared.setupAudioSession()
                                        core.resume()
                                    }
                                }
                                
                                // TOP SCREEN to TV
                                let tvView = DSRenderView(renderer: core.renderer, screenMode: .topOnly)
                                    .aspectRatio(256.0/192.0, contentMode: .fit)
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
                         controllerHeld = ControllerMappingManager.shared.isPressed(DSAction.fastForward, gamepad: gamepad, console: rom.console.systemName)
                     }
                     
                     let newState = isFastForwardUIHeld || controllerHeld
                     if DSCore.fastForward != newState {
                         DSCore.fastForward = newState
                     }
                     self.isCoreFastForwarding = newState
                 }
                checkAndLoadDS()
            }
        }
        .onDisappear {
            // STOP AirPlay immediately when exiting emulator
            print(" Exiting DS Emulator - Stopping AirPlay")
            Air.stop()
            Air.clearListeners()
            self.isAirPlayConnected = false
            
            core.unloadGameSession()
            gameController.isGameplayMode = false
            inputTimer?.invalidate()
            inputTimer = nil
            DSCore.fastForward = false
        }
        .fullScreenCover(isPresented: $showBiosImporter, onDismiss: {
            // Re-check after closing importer
            if DSBiosManager.shared.areAllBiosPresent {
                checkAndLoadDS()
            } else {
                // User cancelled, exit emulator
                dismiss?() 
            }
        }) {
            DSBiosImporterView()
        }
        .fullScreenCover(isPresented: $showFirmwareConfig) {
            DSFirmwareConfigView(onFinish: {
                showFirmwareConfig = false
                // Now safe to load
                loadDSGame()
            })
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
    
    private func checkAndLoadDS() {
        // Desmume uses HLE BIOS by default, so we can skip the strict firmware check.
        // If we switch back to MelonDS later, we might enable this again.
        loadDSGame()
    }
    
    private func loadDSGame() {
        gameController.isGameplayMode = true
        
        let fileURL = ROMStorageManager.shared.getROMFileURL(for: rom)
        print(" [DSEmulatorView] Loading DS via Path: \(fileURL.path)")
        
        let wasPlaying = MusicPlayerManager.shared.isPlaying
        
        // [CRITICAL] Setup Audio Session BEFORE loading the Core so it detects correct Sample Rate/Route
        AudioManager.shared.setupAudioSession()
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            _ = core.loadGame(url: fileURL)
            print(" Native DS Core Started from Storage Path")
            isLoading = false
            
            // Resume Music Player if needed
            if wasPlaying {
                MusicPlayerManager.shared.resume()
            }
            
            // [FIX] Audio Session is now handled correctly by DSAudio.swift with .allowAirPlay.
            // A simple session activation is enough here.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                 if self.isAirPlayConnected {
                     print(" DS (Load): AirPlay detected. Refreshing Audio Session.")
                     // Just forcing a quick pause/resume to latch the new route if needed, 
                     // but without the massive delays from before.
                     self.core.pause()
                     DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                         self.core.resume()
                     }
                 }
            }
        } else {
             print(" DS ROM File not found at path: \(fileURL.path)")
        }
    }
    
    private var fastForwardButton: some View {
        Group {
            if DSSkinManager.shared.currentSkin != nil {
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
