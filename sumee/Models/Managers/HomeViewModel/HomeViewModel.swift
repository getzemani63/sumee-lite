import SwiftUI
import Combine
import PhotosUI


enum GameLaunchMode {
    case normal
    case resume
    case restart
}

class HomeViewModel: ObservableObject {
    
    let gameController = GameControllerManager.shared
    let audioManager = AudioManager.shared
    
    // Persistence Props
    let saveLayoutSubject = PassthroughSubject<Void, Never>()
    let persistenceQueue = DispatchQueue(label: "com.sumee.persistence", qos: .background)
    
    // UI State
    @Published var gameLaunchMode: GameLaunchMode = .normal
    @Published var selectedTabIndex = 0 // Vertical Grid Page Index
    @Published var mainInterfaceIndex = 0 // Horizontal Main Logic (0 = Grid, 1+ = LiveAreas)
    @Published var liveAreaActionIndex: Int = 0 // Navigation index for LiveArea buttons
    @Published var showContent = false
    @Published var isInitialLoad = true
    @Published var showGamepadSettings = false {
        didSet {
            // Apply Universal "Disable Home Navigation" flag
            gameController.disableHomeNavigation = showGamepadSettings
        }
    }
    
    // Overlays (Zero-Touch Architecture)
    @Published var activeSystemApp: SystemApp? { // Single source of truth for open app
        didSet {
            if let app = activeSystemApp {
                if app.disablesHomeNavigation {
                    gameController.disableHomeNavigation = true
                }
            } else {
                // When app closes, ensure navigation is restored
                gameController.disableHomeNavigation = false
                AudioManager.shared.resumeBackgroundMusic()
                
                // Reset Idle Timer when returning from System App
                self.resetIdleTimer()
            }
        }
    }
    
    // Computed Bindings for Backward Compatibility & View Binding
    
    var showPhotosGallery: Bool {
        get { activeSystemApp == .photos }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .photos } }
    }
    
    var showMusicPlayer: Bool {
        get { activeSystemApp == .music }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .music } }
    }
    
    var showGameSystems: Bool {
        get { activeSystemApp == .gameSystems }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .gameSystems } }
    }
    
    var showSettings: Bool {
        get { activeSystemApp == .settings }
        set { 
            if !newValue { 
                if activeSystemApp == .settings { activeSystemApp = nil }
            } else { 
                activeSystemApp = .settings 
            } 
        }
    }
    
    var showStore: Bool {
        get { activeSystemApp == .store }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .store } }
    }
    
    var showDiscord: Bool {
        get { activeSystemApp == .discord }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .discord } }
    }
    
    // var showEENews: Bool {
    //     get { activeSystemApp == .news }
    //     set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .news } }
    // }
    
    var showMeloNX: Bool {
        get { activeSystemApp == .meloNX }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .meloNX } }
    }
    

    

    
    var showThemeManager: Bool {
        get { activeSystemApp == .themeManager }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .themeManager } }
    }


    
    var showMiBrowser: Bool {
        get { activeSystemApp == .miBrowser }
        set { if !newValue { activeSystemApp = nil } else { activeSystemApp = .miBrowser } }
    }
    
    // Derived properties removed for Sketch

    @Published var selectedFolder: AppItem?
    @Published var showingFilePicker = false
    @Published var showingImagePicker = false
    @Published var selectedPhotoItem: PhotosPickerItem?
    // @Published var showPhotosGallery = false // Replaced
    // @Published var showGameSystems = false // Replaced
    @Published var showGameSystemsHeader = false
    // @Published var showFriendsOverlay = false // Replaced
    // @Published var showMusicPlayer = false // Replaced
    // @Published var showSettings = false // Replaced
    // @Published var showStore = false // Replaced
    // @Published var showDiscord = false // Replaced

    @Published var showFullMediaControls = false 
    // @Published var showEENews = false // Replaced
    // @Published var showMeloNX = false // Replaced
    @Published var showEmulator = false {
        didSet {
            // Reset Idle Timer when closing Emulator
            if !showEmulator {
                self.resetIdleTimer()
            }
        }
    }
    @Published var selectedROM: ROMItem?
    @Published var isFolderEmulatorActive = false
    // @Published var showXbox = false // Replaced
    // @Published var showGeForceNOW = false // Replaced
    
    //Import State
    @Published var isImportingMusic = false
    
    //  Data
    @Published var pages: [[AppItem]] = []
    @Published var backupPages: [[AppItem]] = []
    @Published var draggingItem: AppItem?
    
    // TASK MANAGER (LiveArea)
    @Published var activeGameTasks: [ROMItem] = [] // List of "Open" games
    
    // Random Game Widget
    @Published var currentRandomROM: ROMItem?
    var randomTimer: Timer?

    // 3D Launch Animation State
    @Published var isAnimatingLaunch = false
    @Published var launchingROM: ROMItem?
    @Published var launchSourceRect: CGRect = .zero
    @Published var launchImage: UIImage? = nil
    
    // Delete Confirmation
    @Published var showDeleteConfirmation = false
    @Published var appToDelete: AppItem? // Item pending deletion
    @Published var newlyImportedGame: ROMItem? // Triggers animation in GameSystemsViewstants
    @Published var shakeTrigger: Bool = false // Triggers Shake Animation on Full Page
    var lastNavigationTime: TimeInterval = 0 // Manual Debounce Timestamp
    // Widgets removed for this version, maybe i will add it on the furure.
    let widgets: [AppItem] = []
    

    // Centralized widget mapping removed
    // var pageWidgets: [[AppItem]] { ... }
    
    // Computed Properties for View Optimization
    var isUIHidden: Bool {
        activeSystemApp != nil || showEmulator || isIdleMode
    }
    
    // Separates "Structural Hiding" (Apps/Emulator) from "Visual Hiding" (Idle)
    var shouldShowMainUI: Bool {
        activeSystemApp == nil && !showEmulator
    }
    
    // Idle Mode Logic
    @Published var isIdleMode: Bool = false
    private var idleTimer: Timer?
    @Published var unlockTapCount: Int = 0 // Unlock Counter
    private var lastInteractionTime: Date = .distantPast // Debounce for touch
    
    func resetIdleTimer() {
        if isIdleMode {
            // Wake Up Logic moved to HomeLockScreenView (Drag-to-Unlock)
            return
        }
        
        // Normal Timer Reset (Only if Active)
        idleTimer?.invalidate()
        unlockTapCount = 0 // Reset counter if we are active
        
        let duration = SettingsManager.shared.idleTimerDuration
        guard duration > 0 else { return } // 0 = Disabled
        
        idleTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            // Only hide if we aren't in a sub-app (which might have its own idle/input handling)
     
            if self.activeSystemApp == nil && !self.showEmulator && !self.gameController.disableHomeNavigation {
                // Fade Out: Slow and Ghostly
                withAnimation(.easeInOut(duration: 1.5)) { self.isIdleMode = true }
            }
        }
    }

    // Header should specificially persist for "Inline" folder/media views, but hide for full-screen apps
    var shouldHideHeader: Bool {
        if activeSystemApp == .gameSystems && !showGameSystemsHeader { return true }
        
        // Hide header for specific immersive apps
        if let app = activeSystemApp {
             // Use the SystemApp config
             if app == .themeManager || app == .gameSystems { return false } // Explicitly show header for these
             return app.disablesHomeNavigation || app == .store || app == .discord || app == .meloNX
        }
        
        return false
    }

    var allApps: [AppItem] {
        pages.flatMap { $0 }.filter { !$0.isWidget && !$0.isSpacer }
    }

    var allWidgets: [AppItem] {
        pages.flatMap { $0 }.filter { $0.isWidget }
    }

    
    var cancellables = Set<AnyCancellable>()
    
    init() {
        setupBindings()
        
        // Load saved layout
        loadLayout()
        
        // Initialize with default apps if empty
        if pages.isEmpty {
            let defaultApps = [
                AppItem(name: "Photos", iconName: "icon_photos", color: .blue),
                AppItem(name: "Music", iconName: "icon_music", color: .purple),
                AppItem(name: "Game Systems", iconName: "icon_gamepad", color: .red),
                AppItem(name: "Themes", iconName: "icon_theme", color: .purple, systemApp: .themeManager),
                AppItem(name: "Settings", iconName: "icon_settings", color: .gray)
            ]
            // Start with one page containing default apps
            pages = [defaultApps]
            saveLayout()
        }
        
        // LITE MODE CHECK (Optimized Startup)
        // Checks directly here to init with GameSystems open, bypassing HomeView flash
        if SettingsManager.shared.liteMode {
            print("HomeViewModel: Lite Mode Active (Init) - Launching Game Systems Immediately")
            activeSystemApp = .gameSystems
        }
        
        // React to Idle Timer Settings Changes
        SettingsManager.shared.$idleTimerDuration
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetIdleTimer()
            }
            .store(in: &cancellables)
            
        // Subscribe to Controller Input GLOBAL (Any Button) to Reset Idle
        gameController.inputPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.resetIdleTimer()
            }
            .store(in: &cancellables)

    }
    
    //  Logic (Moved to Extensions)
    
    /// Entry point for Virtual Cursor taps
    func handleAppTap(_ item: AppItem, from sourceRect: CGRect = .zero) {
        // Reset Idle Timer on interaction
        resetIdleTimer()
        
        // Check for Gift Wrapping (New Installation)
        if item.isNewInstallation {
             print("Unwrapping New Installation (Tap): \(item.name)")
             AudioManager.shared.playOpenSound()
             
             // Remove Flag & Save
             if let pageIdx = pages.firstIndex(where: { $0.contains { $0.id == item.id } }),
                let itemIdx = pages[pageIdx].firstIndex(where: { $0.id == item.id }) {
                 
                 withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                     pages[pageIdx][itemIdx].isNewInstallation = false
                 }
                 saveLayout()
             }
             return // Stop here to allow animation and prevent launch
        }
        
        // If it's a ROM (Game), launch via Task Manager (LiveArea)
        if let rom = item.romItem {
            // Play Launch Sound for Grid Item (Only for Games)
            AudioManager.shared.playStartGridSound()
            
            print("🎮 Opening Game Page for: \(rom.displayName) from rect: \(sourceRect)")
            self.launchSourceRect = sourceRect
            openGamePage(rom, animated: true)
            return
        }
        
        // Use existing navigation logic provided in HomeViewModel+Navigation.swift
        openApp(item)
    }

    //Task Manager Logic
    
    func openGamePage(_ rom: ROMItem, animated: Bool = false) {
        // 1. Check if already open
        if let index = activeGameTasks.firstIndex(where: { $0.id == rom.id }) {
            // Already open, scroll Horizontally to it
            // Using easeInOut for reliable PageTabView scrolling transition
            withAnimation(.easeInOut(duration: 0.4)) {
                mainInterfaceIndex = index + 1
            }
        } else {
            // 2. Open new task
            if animated {
                // TRIGGER 3D TRANSITION
                print("Triggering 3D Launch Animation for \(rom.displayName)")
                self.launchingROM = rom
                withAnimation { self.isAnimatingLaunch = true }
                
                // Creation Logic (Invisible at first? sure, let's do this.)
                activeGameTasks.append(rom)
                
                // TIMING SCRIPT:
            // 0.0s: Icon pops out & starts spinning (Handled by IconLaunchAnimationView - 0.8s travel + 0.3s zoom)
            // 0.5s: Scroll to LiveArea (Mid-flight)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.spring(response: 0.8, dampingFraction: 0.8)) {
                     self.mainInterfaceIndex = self.activeGameTasks.count
                }
            }
            
            // 1.15s: Animation Ends (After simple fade out)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                withAnimation {
                    self.isAnimatingLaunch = false
                    self.launchingROM = nil
                }
            }
        } else {
                // Standard Instant Open
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    activeGameTasks.append(rom)
                    mainInterfaceIndex = activeGameTasks.count
                }
            }
        }
    }
    
    func closeGamePage(_ rom: ROMItem) {
        guard let index = activeGameTasks.firstIndex(where: { $0.id == rom.id }) else { return }
        
        let targetMainIndex = index + 1
        
        // Logic: Move to the left (or Grid) immediatey effectively
        // If we are looking at this page, we move focus to the left
        var newIndex = mainInterfaceIndex
        if mainInterfaceIndex == targetMainIndex {
            newIndex = max(0, mainInterfaceIndex - 1)
        } else if mainInterfaceIndex > targetMainIndex {
            newIndex = mainInterfaceIndex - 1
        }
        
        // 1. Update Index Transition
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            mainInterfaceIndex = newIndex
        }
        
        // 2. Delayed Data Flush
        // Allow the "Scroll Away" and "Peel Off" animations to resolve visibly
        // Before modifying the source of truth which triggers TabView recreation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self = self else { return }
            if let currentIndex = self.activeGameTasks.firstIndex(where: { $0.id == rom.id }) {
                withAnimation { // Animate the layout shift (other tabs filling gap)
                    self.activeGameTasks.remove(at: currentIndex)
                }
            }
        }
    }
    
    func launchGameFromPage(_ rom: ROMItem, mode: GameLaunchMode = .normal, sourceRect: CGRect? = nil, image: UIImage? = nil) {
        if let rect = sourceRect {
            // Orientation-Aware Storage?
            // For now, simply trust the Rect provided by the tap event which is fresh.
            self.launchSourceRect = rect
        } else if mode == .normal {
            // Reset if normal launch to prevent stale rect usage
             self.launchSourceRect = .zero
        }
        self.launchImage = image
        
        selectedROM = rom
        gameLaunchMode = mode
        // Delay emulator showing to allow GameLaunchView to perform its entry animation
        // using the geometry provided.
        
        showEmulator = true
    }

    
    // Bindings
    
    // Moved to HomeViewModel+Data.swift


    
    // Lifecycle
    
    func onAppear() {
        // Delay music playback slightly to ensure audio session is ready and view is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.audioManager.playBackgroundMusic()
        }
        _ = ScreenshotManager.shared
        
        // Reset navigation state
        gameController.disableHomeNavigation = false
        gameController.isSelectingWidget = false
        gameController.widgetInternalNavigationActive = false
        
        // Load data
        loadLayout()
        
        // Ensure icons are fixed and Game Systems app exists
        fixIcons()
        
        // Preload ROMs if needed
        preloadROMs()
        
        // Preload Default GIF
        preloadDefaultGIF()
        
        // Widget Resize Action (from Controller)
        gameController.onWidgetResize = { [weak self] in
            self?.handleControllerSelect()
        }
        
        // Navigation Actions
        gameController.selectedAppIndex = 0
        gameController.currentPage = 0
        
        // Reset old widget state
        gameController.currentWidgetCount = 0
        
        // Animations handled by View observing published properties
        withAnimation {
            showContent = true
            
            // Lite Mode check moved to init() for instant launch
        }
        
        // Consolidate pages to fill new 12-item limit
        consolidatePages()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.isInitialLoad = false
        }
        
        startRandomRotation()
        resetIdleTimer()
    }
    
    func onDisappear() {
        // Do not pause background music here, as it causes restart when returning from sheets/overlays.
        // Game launch handles music fading explicitly.
        // audioManager.pauseBackgroundMusic()
        stopRandomRotation()
        idleTimer?.invalidate()
    }
    

    
    // Logic
    
    //Import Logic
    
    // Logic moved to HomeViewModel+Import.swift

}
