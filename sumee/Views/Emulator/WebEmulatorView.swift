import SwiftUI
import WebKit
import Combine
import GameController


struct WebEmulatorView: View {
    let romData: Data?
    let rom: ROMItem
    var launchMode: GameLaunchMode = .normal
    @Environment(\.dismiss) var dismiss
    var onDismiss: (() -> Void)? // Custom dismissal closure
    @ObservedObject private var gameController = GameControllerManager.shared
    
    @State private var isLoading: Bool = true // Kept for Web Version compat
    @State private var showBackButton: Bool = false
    @State private var hideButtonTask: DispatchWorkItem?
    
    // Notifications
    @State private var showDoubleTapNotification: Bool = true
    @State private var showStartSelectNotification: Bool = false
    
    // Menu States
    @State private var showMenu = false
    @State private var menuContentVisible = false
    @State private var selectedMenuIndex = 0
    @State private var activeMenuPage: MenuPage = .main
    @State private var selectedLoadStateIndex = 0
    @State private var saveStates: [URL] = []
    
    // Deprecated but kept for binding compatibility
    @State private var showLoadStateSheet = false 
    @State private var showControllerOptions = false

    // Action States
    @State private var showDeleteConfirmation = false
    @State private var stateToDelete: URL?
    @State private var showRenameAlert = false
    @State private var stateToRename: URL?
    @State private var newRenameText = ""
    
    @State private var isSaving = false
    @State private var showSaveSuccess = false // For Save Animation
    
    // Auto-Resume Logic
    @State private var isAutoSavingMode = false
    @State private var showResumeAlert = false
    
    // Custom Transition Logic
  
    @State private var transitionOffset: CGFloat = UIScreen.main.bounds.height 
    @State private var isTransitionActive: Bool = false
    

    
    @State private var useNativeCore: Bool = false
    @State private var romURL: URL?
    
    // Navigation Logic
    
    
    // Auto-Hide Profile Icon Logic
    @State private var showProfileIcon = true
    @State private var profileIconTimer: DispatchWorkItem?
    
    // processNavigation removed - handled entirely by onReceive events
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()
            
                // Custom Wipe Transition Overlay moved to .overlay to cover ResumePrompt
            
                Group {
                    coreView
                }
                .onAppear {
                    // Determine Core
                    if rom.console == .gameboy || rom.console == .gameboyColor || rom.console == .gameboyAdvance || rom.console == .nintendoDS || rom.console == .playstation || rom.console == .snes || rom.console == .nes || rom.console == .segaGenesis {
                        useNativeCore = true
                    } else {
                        useNativeCore = false // N64, PSP, etc use Web (or unused?)
                    }

                    // Allow rotation in emulator ONLY if controller is NOT connected
              
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if self.gameController.isControllerConnected && self.rom.console != .nintendoDS {
                            AppDelegate.orientationLock = .landscape
                        } else {
                            AppDelegate.orientationLock = .all
                        }
                        
                        // Force orientation update
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootViewController = window.rootViewController {
                            rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                        }
                    }
                    
                    // Safety timeout for loading spinner (Web only really)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                        if isLoading { isLoading = false }
                    }
                    
                    // Hide double tap notification
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            showDoubleTapNotification = false
                        }
                    }
                    
                    // Show Controller Notification
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation { showStartSelectNotification = true }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
                        withAnimation { showStartSelectNotification = false }
                    }
                    
                    // Start Profile Auto-Hide Logic
                    startProfileIconTimer()
                    
                    // Track Emulator Activity (Persistent)
                    gameController.isEmulatorActive = true
                    
                    // Refresh Skins Cleanly
                 
                    DispatchQueue.global(qos: .userInitiated).async {
                     
                        switch rom.console {
                        case .playstation: PSXSkinManager.shared.scanForSkins()
                        case .nintendoDS: DSSkinManager.shared.scanForSkins()
                        case .gameboyAdvance, .gameboy, .gameboyColor: GBASkinManager.shared.scanForSkins()
                        case .snes: SNESSkinManager.shared.scanForSkins()
                        case .nes: NESSkinManager.shared.scanForSkins()
                        case .segaGenesis: MDSkinManager.shared.scanForSkins()
                        default: break
                        }
                    }
                    
         
                    let delay: Double = (launchMode == .resume) ? 0.2 : 1.5
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                        // 1. Handle Forced Modes
                        switch launchMode {
                        case .restart:
                            print(" LaunchMode: Restart. Ignoring autosave.")
                            return // Exit, letting fresh state persist
                        case .resume:
                            if let url = autoSaveURL, FileManager.default.fileExists(atPath: url.path) {
                                print(" LaunchMode: Resume. Loading immediately.")
                                if rom.console == .nintendoDS {
                                    // DS: Give audio engine a long "breather" to prevent audio stutter
                                    // 4.0s allows core to stabilize and fill initial buffers
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                                        loadState(from: url)
                                    }
                                } else {
                                    loadState(from: url)
                                }
                                return
                            }
                        case .normal:
                            // 2. Normal Logic (Prompt if exists)
                            if SettingsManager.shared.enableAutoSave,
                               let url = autoSaveURL, FileManager.default.fileExists(atPath: url.path) {
                                print(" Found autosave, prompting resume...")
                                
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    self.showResumeAlert = true
                                }
                            }
                        }
                    }
                }

                .onDisappear {
                    if gameController.isControllerConnected {
                        AppDelegate.orientationLock = .landscape
                        if #available(iOS 16.0, *) {
                            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
                            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                        }
                    } else {
                        AppDelegate.orientationLock = .all
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let window = windowScene.windows.first,
                           let rootViewController = window.rootViewController {
                            rootViewController.setNeedsUpdateOfSupportedInterfaceOrientations()
                        }
                    }
                    
                    print("WebEmulatorView: onDisappear called")
                    DispatchQueue.main.async {
                        print(" WebEmulatorView: Restoring gameController states")
                        gameController.disableMenuSounds = false
                        gameController.isEmulatorActive = false
                    }
                }
                
                // Floating Menu Button (Restored)
                menuButtonView(geo: geo)

                // Refined In-Game Menu
                if showMenu {
                    EmulatorMenuView(
                        isVisible: $menuContentVisible,
                        selectedIndex: $selectedMenuIndex,
                        showLoadStateSheet: $showLoadStateSheet, // Unused now
                        activePage: $activeMenuPage,
                        selectedLoadStateIndex: $selectedLoadStateIndex,
                        saveStates: saveStates,
                        onLoadState: { url in
                            loadState(from: url)
                            closeMenu()
                        },
                        onDelete: { url in
                            stateToDelete = url
                            withAnimation { showDeleteConfirmation = true }
                        },
                        onRename: { url in
                            stateToRename = url
                            newRenameText = url.deletingPathExtension().lastPathComponent
                            showRenameAlert = true
                        },
                        showDeleteConfirmation: $showDeleteConfirmation,
                        stateToDelete: $stateToDelete,
                        isSaving: $isSaving, // Pass binding
                        showSaveSuccess: $showSaveSuccess, // Pass binding
                        rom: rom,
                        onResume: closeMenu,
                        onSave: {
                            print(" WebEmulatorView: Triggering Save State (Touch)")
                            // Resume input immediately
                            NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorInput"), object: true)
                            
                            if !isSaving {
                                isSaving = true
                                triggerSaveState()
                                
                                // Reset after animation
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                    isSaving = false
                                }
                            }
                        },
                        onExit: {
                            performExitSequence()
                        },
                        isControllerConnected: gameController.isControllerConnected,
                        controllerName: gameController.controllerName,
                        showControllerOptions: $showControllerOptions
                    )
                    .onAppear {
                        // Load states when menu opens
                        loadSaveStates()
                        withAnimation {
                            menuContentVisible = true
                        }
                    }
                }
            }
            .alert("Rename Save State", isPresented: $showRenameAlert) {
                TextField("New Name", text: $newRenameText)
                Button("Cancel", role: .cancel) { }
                Button("Rename") {
                    if let url = stateToRename {
                        renameState(url, to: newRenameText)
                    }
                }
            } message: {
                Text("Enter a new name for this save state.")
            }
            // Custom Resume Prompt Overlay (Replaces Alert)
            .overlay(
                Group {
                    if showResumeAlert {
                        ResumePromptView(
                            screenshotURL: getAutoSaveScreenshotURL(),
                            onResume: {
                                if let url = autoSaveURL {
                                    // 1. Start Wipe In (Upwards)
                                    isTransitionActive = true
                                    // Reset offset to bottom just in case
                                    transitionOffset = geo.size.height 
                                    
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        transitionOffset = 0 // Cover screen
                                    }
                                    
                                    // 2. Load State (Hidden behind curtain)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                        showResumeAlert = false // Hide prompt
                                        
                                        if rom.console == .nintendoDS {
                                            // DS: Give audio engine a "breather" before slamming state load
                                            // 3.5s allows core to stabilize and fill initial buffers
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                                                loadState(from: url)
                                                
                                                // 3. Wipe Out (continue Upwards)
                                                withAnimation(.easeInOut(duration: 0.5)) {
                                                    transitionOffset = -geo.size.height // Exit top
                                                }
                                                
                                                // 4. Cleanup
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                    isTransitionActive = false
                                                    transitionOffset = geo.size.height // Reset for next time
                                                }
                                            }
                                        } else {
                                            // Other Systems: Delay 1.5s before resuming
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                loadState(from: url)
                                                
                                                // 3. Wipe Out (continue Upwards)
                                                withAnimation(.easeInOut(duration: 0.5)) {
                                                    transitionOffset = -geo.size.height
                                                }
                                                
                                                // 4. Cleanup
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                                    isTransitionActive = false
                                                    transitionOffset = geo.size.height
                                                }
                                            }
                                        }
                                    }
                                } else {
                                     withAnimation { showResumeAlert = false }
                                }
                            },
                            onNewGame: {
                                withAnimation { showResumeAlert = false }
                            }
                        )
                        // Transition kept simple as internal view handles entrance
                        .transition(.identity) 
                    }
                }
            )
            .onChange(of: showResumeAlert) { _, isVisible in
                // Lock/Unlock Emulator Input based on Alert Visibility
                print(" WebEmulatorView: Resume Alert Changed -> \(isVisible) (Toggling Input)")
                NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorInput"), object: !isVisible)
                
                // Pause/Unpause Core to prevent background execution
                NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorPause"), object: isVisible)
                
                // Toggle Gameplay Mode to redirect controller inputs to UI
                gameController.isGameplayMode = !isVisible
            }
            // Transition Curtain (Topmost Overlay)
            .overlay(
                Group {
                    if isTransitionActive {
                        Color.black
                            .ignoresSafeArea()
                            .zIndex(4000) // Strictly on top of ResumePrompt
                            .offset(y: transitionOffset)
                    }
                }
            )
            .onChange(of: gameController.showMenu) { _, newValue in
                if newValue {
                    // MODIFIED: Start+Select now triggers Auto-Save & Exit instead of Menu
                    print(" WebEmulatorView: Start+Select detected. Initiating Exit Sequence.")
                    performExitSequence()
                    
                    // Reset flag immediately to avoid sticking
                    DispatchQueue.main.async {
                        gameController.showMenu = false
                    }
                } else {
                     // Handled in closeMenu() usually, but safe fallback
                    closeMenu()
                }
            }
            // Consolidated Menu Navigation
            // Consolidated Menu Navigation via Publisher
            .onReceive(gameController.inputPublisher) { event in
                handleInputEvent(event)
            }
            .statusBar(hidden: true)
        }
    }
    
    // Helper Properties
    private var isWebApp: Bool {
        return rom.console == .web
    }

    private func handleInputEvent(_ event: GameControllerManager.GameInputEvent) {
        // Prevent input if menu is closed or if controller options are showing
        guard showMenu, !showControllerOptions else { return }
        
        // Handle Delete Confirmation Overlay
        if showDeleteConfirmation {
            switch event {
            case .a:
                // Confirm Delete
                if let url = stateToDelete {
                    deleteState(url)
                }
                withAnimation { showDeleteConfirmation = false }
                stateToDelete = nil
            case .b:
                // Cancel Delete
                withAnimation { showDeleteConfirmation = false }
                stateToDelete = nil
            default: break
            }
            return // Block other input
        }
        
        // --- NAVIGATION LOGIC ---
        switch event {
        case .up(let repeated):
            if activeMenuPage == .main {
                if selectedMenuIndex > 0 {
                    selectedMenuIndex -= 1
                    if !repeated { AudioManager.shared.playMoveSound() }
                }
            } else if activeMenuPage == .loadState {
                if selectedLoadStateIndex > 0 {
                    selectedLoadStateIndex -= 1
                    if !repeated { AudioManager.shared.playMoveSound() }
                }
            }
            
        case .down(let repeated):
            if activeMenuPage == .main {
                // 0..5 (Resume, Save, Load, Skins, Controller, Exit)
                let limit = isWebApp ? 1 : 5
                if selectedMenuIndex < limit {
                    selectedMenuIndex += 1
                    if !repeated { AudioManager.shared.playMoveSound() }
                }
            } else if activeMenuPage == .loadState {
                 // Index 0 is Back, 1..Count are files
                if selectedLoadStateIndex < saveStates.count { // Max index is count (Back + files)
                    selectedLoadStateIndex += 1
                    if !repeated { AudioManager.shared.playMoveSound() }
                }
            }
            
        case .left(let repeated):
             if activeMenuPage == .main {
                 if selectedMenuIndex > 0 {
                     selectedMenuIndex -= 1
                     if !repeated { AudioManager.shared.playMoveSound() }
                 }
             }
            
        case .right(let repeated):
             if activeMenuPage == .main {
                 let limit = isWebApp ? 1 : 5
                 if selectedMenuIndex < limit {
                     selectedMenuIndex += 1
                     if !repeated { AudioManager.shared.playMoveSound() }
                 }
             }
            
        case .a:
            if activeMenuPage == .main {
                print(" WebEmulatorView: Button A Pressed (Main Menu)")
                AudioManager.shared.playSelectSound()
                switch selectedMenuIndex {
                case 0: closeMenu() // Resume
                case 1: // Save / Exit (WebApp)
                    if isWebApp {
                         performExitSequence()
                    } else {
                        // Save State
                        print(" WebEmulatorView: Triggering Save State")
                        NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorInput"), object: true)
                        
                        if !isSaving {
                            isSaving = true
                            triggerSaveState()
                            
                            withAnimation { showSaveSuccess = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                isSaving = false
                                withAnimation { showSaveSuccess = false }
                            }
                        }
                    }
                case 2: // Load State
                    withAnimation {
                        activeMenuPage = .loadState
                        selectedLoadStateIndex = 0
                    }
                case 3: // Skins
                    withAnimation {
                        activeMenuPage = .skinsManager
                    }
                case 4: // Controller Options
                    showControllerOptions = true
                case 5: // Exit (Native)
                    performExitSequence()
                default: break
                }
            } else if activeMenuPage == .loadState {
                print(" WebEmulatorView: Button A Pressed (Load State)")
                AudioManager.shared.playSelectSound()
                
                if selectedLoadStateIndex == 0 {
                    // Back
                    withAnimation { activeMenuPage = .main }
                } else {
                    // File
                    let fileIndex = selectedLoadStateIndex - 1
                    if fileIndex < saveStates.count {
                        let url = saveStates[fileIndex]
                        loadState(from: url)
                        closeMenu()
                    }
                }
            }
            
        case .b:
            print(" WebEmulatorView: Button B Pressed")
            if activeMenuPage == .main {
                closeMenu()
            } else {
                AudioManager.shared.playMoveSound()
                withAnimation { activeMenuPage = .main }
            }
            
        case .x:
            // Delete
            if activeMenuPage == .loadState && selectedLoadStateIndex > 0 {
                let fileIndex = selectedLoadStateIndex - 1
                if fileIndex < saveStates.count {
                    stateToDelete = saveStates[fileIndex]
                    withAnimation { showDeleteConfirmation = true }
                }
            }
            
        case .y:
            // Rename
            if activeMenuPage == .loadState && selectedLoadStateIndex > 0 {
                let fileIndex = selectedLoadStateIndex - 1
                if fileIndex < saveStates.count {
                    stateToRename = saveStates[fileIndex]
                    newRenameText = stateToRename?.deletingPathExtension().lastPathComponent ?? ""
                    showRenameAlert = true
                }
            }
            
        default: break
        }
    }

    
    // Helpers
    private func closeMenu() {
        guard showMenu else { return }
        
        withAnimation(.easeIn(duration: 0.3)) {
            menuContentVisible = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showMenu = false
            gameController.showMenu = false
            gameController.isGameplayMode = true // RE-ENABLE PERFORMANCE MODE
            
            // Re-enable emulator input AND Resume Emulation
            NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorInput"), object: true)
            NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorPause"), object: false) // Resume
            
            print(" WebEmulatorView: Menu closed, input re-enabled")
            
            // Re-show Profile Icon and start timer
            withAnimation { showProfileIcon = true }
            startProfileIconTimer()
        }
    }
    
    private func startProfileIconTimer() {
        // Cancel existing timer
        profileIconTimer?.cancel()
        
        // Create new timer to hide icon after 3 seconds
        let workItem = DispatchWorkItem {
             withAnimation(.easeOut(duration: 0.5)) {
                 showProfileIcon = false
             }
        }
        
        profileIconTimer = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: workItem)
    }
    
    // Extracted Subviews
    
    @ViewBuilder
    private var coreView: some View {
        if useNativeCore {
            // --- CORE DISPATCHER ---
            if rom.console == .playstation {
                PSXEmulatorView(
                    rom: rom,
                    gameController: gameController,
                    showMenu: $showMenu,
                    onSaveState: handleSaveState,
                    closeMenu: closeMenu
                )
            } else if rom.console == .nintendoDS {
                DSEmulatorView(
                    rom: rom,
                    gameController: gameController,
                    showMenu: $showMenu,
                    onSaveState: handleSaveState,
                    closeMenu: closeMenu,
                    dismiss: dismiss
                )
            } else if rom.console == .gameboy || rom.console == .gameboyColor || rom.console == .gameboyAdvance {
                 GBAEmulatorView(
                    rom: rom,
                    romData: romData,
                    gameController: gameController,
                    showMenu: $showMenu,
                    onSaveState: handleSaveState,
                    closeMenu: closeMenu
                )
            } else if rom.console == .snes {
                SNESEmulatorView(
                    rom: rom,
                    gameController: gameController,
                    showMenu: $showMenu,
                    onSaveState: handleSaveState,
                    closeMenu: closeMenu
                )
            } else if rom.console == .nes {
                NESEmulatorView(
                    rom: rom,
                    gameController: gameController,
                    showMenu: $showMenu,
                    onSaveState: handleSaveState,
                    closeMenu: closeMenu
                )
            } else if rom.console == .segaGenesis {
                GenesisEmulatorView(
                    rom: rom,
                    gameController: gameController,
                    showMenu: $showMenu,
                    onSaveState: handleSaveState,
                    closeMenu: closeMenu
                )
            } else {
                 Text("Unsupported Native Core")
                    .foregroundColor(.white)
            }
            
        } else {
            // --- LEGACY WEB EMULATOR ---
            GeometryReader { geo in
                WebViewRepresentable(
                    romData: romData ?? Data(),
                    romName: rom.fileName,
                    console: rom.console,
                    gameController: gameController,
                    isLoading: $isLoading,
                    onSaveState: { data in
                        print(" Web State saved: \(data.count) bytes")
                        self.handleSaveState(data: data)
                    }
                )
                .ignoresSafeArea(edges: geo.size.height > geo.size.width ? [.horizontal, .bottom] : [.vertical])
            }
        }
    }
    
    @ViewBuilder
    private func menuButtonView(geo: GeometryProxy) -> some View {
        VStack {
            HStack {
                if geo.size.height > geo.size.width {
                    // Portrait: Left
                    HStack(spacing: 12) {
                        // Menu Button
                        ControlCard(actions: [
                            ControlAction(
                                icon: "line.3.horizontal",
                                label: showProfileIcon ? "EXIT" : "", // Changed label to reflect action
                                action: {
                                    // MODIFIED: Menu Button triggers Exit
                                    performExitSequence()
                                }
                            )
                        ], position: .left)
                        
                        // Controller Notification
                        if showStartSelectNotification && gameController.isControllerConnected {
                            Text("Press Select + Start to open menu")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .transition(.opacity)
                        }
                        
                        // Profile Picture
                        if showProfileIcon {
                            Button(action: {
                                // Action for profile if needed, or just visual
                            }) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.pink, Color.pink.opacity(0.8)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Group {
                                            if let profileImage = ProfileManager.shared.profileImage {
                                                Image(uiImage: profileImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } else {
                                                Image("icono_perfil")
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            }
                                        }
                                        .clipShape(Circle())
                                    )
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 40)
                    .padding(.leading, 20)
                    
                    Spacer()
                } else {
                    // Landscape: Left
                    HStack(spacing: 12) {
                        // Menu Button
                        ControlCard(actions: [
                            ControlAction(
                                icon: "line.3.horizontal",
                                label: showProfileIcon ? "EXIT" : "", // Changed label to reflect action
                                action: {
                                    // MODIFIED: Menu Button triggers Exit
                                    performExitSequence()
                                }
                            )
                        ], position: .left)
                        
                        // Controller Notification
                        if showStartSelectNotification && gameController.isControllerConnected {
                            Text("Press Select + Start to open menu")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .transition(.opacity)
                        }
                        
                        // Profile Picture
                        if showProfileIcon {
                            Button(action: {
                                // Action for profile if needed, or just visual
                            }) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.pink, Color.pink.opacity(0.8)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Group {
                                            if let profileImage = ProfileManager.shared.profileImage {
                                                Image(uiImage: profileImage)
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            } else {
                                                Image("icono_perfil")
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                            }
                                        }
                                        .clipShape(Circle())
                                    )
                                    .overlay(
                                        Circle().stroke(Color.white, lineWidth: 2)
                                    )
                                    .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.top, 40)
                    .padding(.leading, 20)
                    
                    Spacer()
                }
            }
            .opacity(gameController.showMenu ? 0 : 1) // Fade out when menu open
            .scaleEffect(gameController.showMenu ? 0.8 : 1) // Scale down
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: gameController.showMenu)
            
            Spacer()
        }
        .opacity(showMenu ? 0 : 1) // Hide button when menu is open
    }
    
    // Save State Logic
    
    private func getStatesDirectory() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let statesDir = documents.appendingPathComponent("states").appendingPathComponent(rom.displayName)
        try? FileManager.default.createDirectory(at: statesDir, withIntermediateDirectories: true)
        return statesDir
    }
    
    private var autoSaveURL: URL? {
        guard let dir = getStatesDirectory() else { return nil }
        return dir.appendingPathComponent("autosave.state")
    }
    
    // Helper for visual resume
    private func getAutoSaveScreenshotURL() -> URL? {
        guard let dir = getStatesDirectory() else { return nil }
        return dir.appendingPathComponent("autosave.png")
    }
    
    private func loadAutoSaveScreenshot() -> UIImage? {
        guard let url = getAutoSaveScreenshotURL() else { return nil }
        return UIImage(contentsOfFile: url.path)
    }
    
    private func captureAndSaveScreenshot() {
        DispatchQueue.main.async {
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first?.windows
                .first(where: { $0.isKeyWindow }) else { return }
            
            let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
            let image = renderer.image { context in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            }
            
            if let url = getAutoSaveScreenshotURL(),
               let data = image.pngData() {
                try? data.write(to: url)
                print("📸 Auto-save screenshot captured")
            }
        }
    }
    
    private func triggerSaveState() {
        NotificationCenter.default.post(name: NSNotification.Name("TriggerSaveState"), object: nil)
    }
    
    private func handleSaveState(data: Data) {
        guard let dir = getStatesDirectory() else { return }
        
        // Auto-Save Logic
        if isAutoSavingMode {
             let url = dir.appendingPathComponent("autosave.state")
             do {
                 try data.write(to: url)
                 print(" Auto-save successful to: \(url.lastPathComponent)")
             } catch {
                 print(" Failed to auto-save: \(error)")
             }
             // Reset mode
             isAutoSavingMode = false
             return
        }
        
        // Manual Save Logic
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "State_\(formatter.string(from: Date())).state"
        let url = dir.appendingPathComponent(filename)
        
        do {
            try data.write(to: url)
            print("State saved to: \(url.path)")
        } catch {
            print(" Failed to save state: \(error)")
        }
    }
    
    private func deleteState(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            print(" Deleted save state: \(url.lastPathComponent)")
            loadSaveStates() // Refresh list
            
            // Adjust selection if needed
            if selectedLoadStateIndex > saveStates.count {
                selectedLoadStateIndex = max(0, saveStates.count)
            }
        } catch {
            print(" Error deleting save state: \(error)")
        }
    }
    
    func renameState(_ url: URL, to newName: String) {
        let cleanName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }
        
        let newURL = url.deletingLastPathComponent().appendingPathComponent(cleanName).appendingPathExtension("state")
        
        do {
            try FileManager.default.moveItem(at: url, to: newURL)
            print(" Renamed save state to: \(cleanName)")
            loadSaveStates() // Refresh list
        } catch {
            print("Error renaming save state: \(error)")
        }
    }
    
    private func loadSaveStates() {
        guard let dir = getStatesDirectory() else { 
            saveStates = []
            return 
        }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: .skipsHiddenFiles)
            saveStates = files.filter { 
                $0.pathExtension == "state" && 
                $0.lastPathComponent != "autosave.state" // Exclude System Autosave
            }.sorted(by: {
                ($0.creationDate ?? Date.distantPast) > ($1.creationDate ?? Date.distantPast)
            })
            print(" Loaded \(saveStates.count) save states")
        } catch {
            print("Failed to list states: \(error)")
            saveStates = []
        }
    }
    
    private func loadState(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { 
            print(" Failed to read state file: \(url.lastPathComponent)")
            return 
        }
        let base64 = data.base64EncodedString()
        NotificationCenter.default.post(name: NSNotification.Name("TriggerLoadState"), object: base64)
        print(" State loaded: \(url.lastPathComponent)")
    }
    
    private func performExitSequence() {
        print("WebEmulatorView: Starting Polished Exit Sequence...")
        
        // 1. PAUSE EMULATOR IMMEDIATELY
        // This stops audio stutter and visuals while we save
        NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorPause"), object: true)
        
        // Check Setting
        guard SettingsManager.shared.enableAutoSave else {
             print(" WebEmulatorView: Auto-Save disabled, exiting normally.")
             // Slight delay to allow pause to take effect visually
             DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                 if let onDismiss = onDismiss {
                     onDismiss()
                 } else {
                     dismiss()
                 }
             }
             return
        }
        
        print(" WebEmulatorView: Auto-saving before exit...")
        
        // 2. WAIT FOR PAUSE TO SETTLE (0.2s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            
            // 3. CAPTURE SCREENSHOT (Now that screen is static)
            self.captureAndSaveScreenshot()
            
            // 4. TRIGGER SAVE STATE
            // Ensure input is enabled for the save command to work (if needed by core)
            NotificationCenter.default.post(name: NSNotification.Name("ToggleEmulatorInput"), object: true)
            
            self.isAutoSavingMode = true
            self.triggerSaveState()
            
            // 5. WAIT FOR SAVE TO COMPLETE (0.8s - 1.0s)
            // Give the file system time to write the state
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                print(" WebEmulatorView: Save sequence complete, dismissing...")
                
                // 6. DISMISS (Triggers GameLaunchView animation)
                if let onDismiss = self.onDismiss {
                    onDismiss()
                } else {
                    self.dismiss()
                }
            }
        }
    }
}



extension URL {
    var creationDate: Date? {
        return (try? resourceValues(forKeys: [.creationDateKey]))?.creationDate
    }
}

struct WebViewRepresentable: UIViewRepresentable {
    let romData: Data
    let romName: String
    let console: ROMItem.Console
    @ObservedObject var gameController: GameControllerManager
    @Binding var isLoading: Bool
    var onSaveState: ((Data) -> Void)?
    
    // Input Control
    func setInputEnabled(_ enabled: Bool, in webView: WKWebView?) {
        let script = "window.setInputEnabled(\(enabled));"
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
    
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // Force stop any running JS and clear memory
        uiView.stopLoading()
        uiView.load(URLRequest(url: URL(string: "about:blank")!))
        uiView.configuration.userContentController.removeAllUserScripts()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "emulatorController")
        uiView.removeFromSuperview()
        print("WebEmulatorView dismantled and cleaned up")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        context.coordinator.webViewConfiguration.defaultWebpagePreferences = prefs
        
        // Usar GamepadWebView personalizado en lugar de WKWebView estándar
        let webView = GamepadWebView(frame: .zero, configuration: context.coordinator.webViewConfiguration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never // Ignore safe area insets
        webView.isOpaque = false
        webView.backgroundColor = .black
        
        // Asignar webView al Coordinator para que pueda ejecutar JavaScript
        context.coordinator.webView = webView
        
        // Load Emulator
        let html = generateEmulatorHTML(romData: romData, romName: romName, console: console)
        webView.loadHTMLString(html, baseURL: Bundle.main.bundleURL)
        
        // Forzar el foco para que capture los eventos del control
        DispatchQueue.main.async {
            webView.becomeFirstResponder()
        }
        
        // Iniciar la búsqueda de controles inalámbricos a nivel de sistema
        GCController.startWirelessControllerDiscovery {
            print(" Controller discovery started")
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {}
    
    private func getSaveFileURL() -> URL? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let savesDir = documents.appendingPathComponent("saves")
        try? FileManager.default.createDirectory(at: savesDir, withIntermediateDirectories: true)
        return savesDir.appendingPathComponent("\(romName).srm")
    }

    private func loadSaveData() -> String? {
        guard let url = getSaveFileURL(),
              let data = try? Data(contentsOf: url) else { return nil }
        return data.base64EncodedString()
    }

    private func saveSaveData(_ base64String: String) {
        guard let url = getSaveFileURL(),
              let data = Data(base64Encoded: base64String) else { return }
        do {
            try data.write(to: url)
            print(" Save file written to: \(url.path)")
        } catch {
            print("Failed to write save file: \(error)")
        }
    }

    private func generateEmulatorHTML(romData: Data, romName: String, console: ROMItem.Console) -> String {
        let base64ROM = romData.base64EncodedString()
        let initialSaveData = loadSaveData() ?? ""
        
        var core = "mgba"
        switch console {
        case .nes:
            core = "nes"
        case .snes:
            core = "snes"
        case .nintendoDS:
            core = "nds"
        case .nintendo64:
            core = "n64"
        case .playstation:
            core = "psx"
        case .psp:
            core = "psp"
        default:
            core = "mgba"
        }
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
            <title>\(romName)</title>
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    background: #000;
                    width: 100vw;
                    height: 100vh;
                    overflow: hidden;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                }
                #game {
                    width: 100%;
                    height: 100%;
                    display: flex;
                    justify-content: center;
                    align-items: center;
                    position: relative;
                }
                canvas {
                    max-width: 100vw;
                    max-height: 100vh;
                    object-fit: contain;
                    z-index: 1;
                }
                
                .ejs-controls-candidate, .virtual-gamepad, #gp, #dpad, #menu, #fpad {
                    display: none !important;
                    opacity: 0 !important;
                    pointer-events: none !important;
                }
            </style>
            <script>
                // Input Control Proxy
                window.gamepadInputEnabled = true;
                
                // Wait for navigator.getGamepads to be available
                const originalGetGamepads = navigator.getGamepads ? navigator.getGamepads.bind(navigator) : function() { return []; };
                
                // Cache the zeroed gamepad to avoid garbage collection overhead
                const zeroedGamepad = {
                    index: 0,
                    id: "Virtual Zeroed Gamepad",
                    connected: true,
                    timestamp: 0,
                    mapping: "standard",
                    axes: [0, 0, 0, 0],
                    buttons: Array(17).fill().map(() => ({ pressed: false, touched: false, value: 0 }))
                };
                const zeroedGamepads = [zeroedGamepad, null, null, null];

                navigator.getGamepads = function() {
                    if (!window.gamepadInputEnabled) {
                        // Update timestamp to keep it "alive" if needed, though usually not strictly required for zeroed
                        zeroedGamepad.timestamp = performance.now();
                        return zeroedGamepads;
                    }
                    return originalGetGamepads();
                };
                
                window.setInputEnabled = function(enabled) {
                    console.log(' Input enabled:', enabled);
                    window.gamepadInputEnabled = enabled;
                    // Removed pause/resume logic to prevent freezing
                };
            </script>
        </head>
        <body>
            <div id="game"></div>
            
            <script>
                const base64ROM = '\(base64ROM)';
                const initialSaveData = '\(initialSaveData)';
                
                function base64ToUint8Array(base64) {
                    var binary_string = window.atob(base64);
                    var len = binary_string.length;
                    var bytes = new Uint8Array(len);
                    for (var i = 0; i < len; i++) {
                        bytes[i] = binary_string.charCodeAt(i);
                    }
                    return bytes;
                }
                
                const romBytes = base64ToUint8Array(base64ROM);
                const blob = new Blob([romBytes], { type: 'application/octet-stream' });
                const blobUrl = URL.createObjectURL(blob);
                
                window.EJS_player = '#game';
                window.EJS_core = '\(core)';
                window.EJS_gameUrl = blobUrl;
                window.EJS_pathtodata = 'https://cdn.emulatorjs.org/stable/data/';
                window.EJS_startOnLoaded = true;
                
                // Custom Core Options for DS
                if (window.EJS_core === 'nds') {
                    window.EJS_defaultOptions = {
                        'desmume_screens_layout': 'left/right', // Try forcing side-by-side
                        'desmume_screens_gap': 0
                    };
                }
                
                window.EJS_onLoad = function() {
                    console.log(' EmulatorJS Loaded');
                    
                    if (initialSaveData) {
                        try {
                            const data = base64ToUint8Array(initialSaveData);
                            const savesDir = '/home/web_user/retroarch/userdata/saves';
                            if (window.FS) {
                                try { window.FS.mkdir('/home'); } catch(e){}
                                try { window.FS.mkdir('/home/web_user'); } catch(e){}
                                try { window.FS.mkdir('/home/web_user/retroarch'); } catch(e){}
                                try { window.FS.mkdir('/home/web_user/retroarch/userdata'); } catch(e){}
                                try { window.FS.mkdir(savesDir); } catch(e){}
                                window.FS.writeFile(savesDir + '/game.srm', data);
                                console.log('Save data injected');
                            }
                        } catch (e) {
                            console.error(' Error injecting save:', e);
                        }
                    }
                    
                    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.emulatorController) {
                        window.webkit.messageHandlers.emulatorController.postMessage({ type: 'ready' });
                    }
                };
                
                // Save hooks
                window.EJS_onSaveUpdate = function() {
                    try {
                        if (window.FS) {
                            const savesDir = '/home/web_user/retroarch/userdata/saves';
                            if (window.FS.analyzePath(savesDir).exists) {
                                const files = window.FS.readdir(savesDir);
                                for (let file of files) {
                                    if (file.endsWith('.srm')) {
                                        const data = window.FS.readFile(savesDir + '/' + file);
                                        const base64 = uint8ArrayToBase64(data);
                                        if (window.webkit?.messageHandlers?.emulatorController) {
                                            window.webkit.messageHandlers.emulatorController.postMessage({ type: 'saveData', data: base64 });
                                        }
                                        break;
                                    }
                                }
                            }
                        }
                    } catch (e) {}
                };
                
                window.EJS_onSaveState = function(data) {
                    if (data) {
                         var stateData = data.state || data; 
                         const base64State = uint8ArrayToBase64(stateData);
                         if (window.webkit?.messageHandlers?.emulatorController) {
                            window.webkit.messageHandlers.emulatorController.postMessage({ type: 'stateSaved', data: base64State });
                        }
                    }
                };

                window.triggerSaveState = function() {
                    console.log(' triggerSaveState called');
                    try {
                        // Método 1: Intentar con EJS_emulator.gameManager.getState (Común en N64/híbridos)
                        if (window.EJS_emulator && window.EJS_emulator.gameManager && typeof window.EJS_emulator.gameManager.getState === 'function') {
                             console.log(' Using gameManager.getState()');
                             const stateData = window.EJS_emulator.gameManager.getState();
                             if (stateData) {
                                 console.log(' State data retrieved:', stateData.length, 'bytes');
                                 const base64State = uint8ArrayToBase64(stateData);
                                 if (window.webkit?.messageHandlers?.emulatorController) {
                                     window.webkit.messageHandlers.emulatorController.postMessage({ type: 'stateSaved', data: base64State });
                                     console.log(' State sent to Swift via gameManager.getState');
                                 }
                                 return;
                             }
                        }

                        // Método 2: Intentar con EJS_emulator.saveState (API Standard)
                        if (window.EJS_emulator && typeof window.EJS_emulator.saveState === 'function') {
                            console.log(' Using EJS_emulator.saveState()');
                            window.EJS_emulator.saveState();
                            return;
                        }
                        
                         // Método 3: Intentar con EJS_emulator.gameManager.saveState (Variante)
                        if (window.EJS_emulator && window.EJS_emulator.gameManager && typeof window.EJS_emulator.gameManager.saveState === 'function') {
                                console.log(' Using gameManager.saveState()');
                                window.EJS_emulator.gameManager.saveState();
                                return;
                        }
                        
                        // Método 4: Intentar invocar un evento de teclado para guardar (Hack F2/Shift+F2)
                        // Muchos emuladores web usan F2 para guardar estado.
                        console.log(' Attempting Keyboard Event Hack (F2/Save)');
                        // Esto es especulativo, pero N64 a veces no expone la API pública correctamente
                        
                        console.error(' No save state method available found for this Core');
                    } catch(e) {
                        console.error(' Error in triggerSaveState:', e);
                    }
                };
                
                window.triggerLoadState = function(base64Data) {
                    console.log(' triggerLoadState called');
                    try {
                        const data = base64ToUint8Array(base64Data);
                        console.log(' State data decoded:', data.length, 'bytes');
                        
                        // Método 1: Intentar con EJS_emulator
                        if (window.EJS_emulator && typeof window.EJS_emulator.loadState === 'function') {
                            console.log(' Using EJS_emulator.loadState()');
                            window.EJS_emulator.loadState(data);
                            console.log(' State loaded successfully');
                            return;
                        }
                        
                        // Método 2: Intentar con gameManager
                        if (window.EJS_emulator && window.EJS_emulator.gameManager) {
                            console.log(' EJS_emulator.gameManager exists');
                            if (window.EJS_emulator.gameManager.loadState) {
                                console.log(' loadState function exists');
                                window.EJS_emulator.gameManager.loadState(data);
                                console.log(' State loaded successfully');
                                return;
                            }
                        }
                        
                        console.error(' No load state method available');
                    } catch(e) {
                        console.error(' Error in triggerLoadState:', e);
                    }
                };

                function uint8ArrayToBase64(bytes) {
                    var binary = '';
                    var len = bytes.byteLength;
                    for (var i = 0; i < len; i++) {
                        binary += String.fromCharCode(bytes[i]);
                    }
                    return window.btoa(binary);
                }
                
                // Fallback ready check
                setTimeout(() => {
                     if (window.webkit?.messageHandlers?.emulatorController) {
                        window.webkit.messageHandlers.emulatorController.postMessage({ type: 'ready' });
                    }
                }, 3000);

            </script>
            <script src="https://cdn.emulatorjs.org/stable/data/loader.js"></script>
        </body>
        </html>
        """
    }
    
    // Fast Forward button moved to WebEmulatorView struct
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebViewRepresentable
        var webViewConfiguration: WKWebViewConfiguration
        var cancellables = Set<AnyCancellable>()
        var webView: WKWebView? // Referencia para ejecutar JS
        
        init(parent: WebViewRepresentable) {
            self.parent = parent
            self.webViewConfiguration = WKWebViewConfiguration()
            super.init()
            
            let userContentController = WKUserContentController()
            userContentController.add(self, name: "emulatorController")
            self.webViewConfiguration.userContentController = userContentController
            
            // Allow auto-play audio
            self.webViewConfiguration.mediaTypesRequiringUserActionForPlayback = []
            self.webViewConfiguration.allowsInlineMediaPlayback = true
            
            // Add Notification Observers
            NotificationCenter.default.addObserver(self, selector: #selector(handleSaveStateTrigger), name: NSNotification.Name("TriggerSaveState"), object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(handleLoadStateTrigger), name: NSNotification.Name("TriggerLoadState"), object: nil)
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func handleSaveStateTrigger() {
            print(" WebEmulatorView: Received TriggerSaveState notification")
            let script = "window.triggerSaveState()"
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print(" Error executing triggerSaveState: \(error)")
                    }
                }
            }
        }
        
        @objc func handleLoadStateTrigger(_ notification: Notification) {
            print(" WebEmulatorView: Received TriggerLoadState notification")
            guard let base64 = notification.object as? String else { return }
            let script = "window.triggerLoadState('\(base64)')"
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript(script) { result, error in
                    if let error = error {
                        print(" Error executing triggerLoadState: \(error)")
                    }
                }
            }
        }
        
        // WKScriptMessageHandler
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "emulatorController", let body = message.body as? [String: Any] {
                if let type = body["type"] as? String {
                    if type == "ready" {
                        DispatchQueue.main.async {
                            self.parent.isLoading = false
                        }
                    } else if type == "saveData", let base64 = body["data"] as? String {
                        DispatchQueue.global(qos: .background).async {
                            self.parent.saveSaveData(base64)
                        }
                    } else if type == "stateSaved", let base64 = body["data"] as? String {
                        if let data = Data(base64Encoded: base64) {
                            DispatchQueue.main.async {
                                self.parent.onSaveState?(data)
                            }
                        }
                    }
                }
            }
        }
    }
}
