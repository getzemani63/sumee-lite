import SwiftUI
import Combine

class GameSystemsViewModel: ObservableObject {
    @Published var placeholder: Bool = false
    
    // Add logic specific to Game Systems here
    // For example:
    // @Published var selectedSystem: System?
    // @Published var availableSystems: [System] = []
    
    @ObservedObject var storage = ROMStorageManager.shared
    @ObservedObject var gameController = GameControllerManager.shared
    
    @Published var filteredROMs: [ROMItem] = []
    
    // Console Navigation
    @Published var availableConsoles: [ROMItem.Console] = []
    @Published var selectedConsoleIndex: Int = 0 {
        didSet {
            if !isControllerScrolling && oldValue != selectedConsoleIndex {
                 AudioManager.shared.playMoveSound()
            }
        }
    }
    @Published var selectedConsole: ROMItem.Console?
    @Published var isSelectingConsole: Bool = true // Start at console selection
    @Published var isGlobalMode: Bool = false // New: Show all games
    
    // Smooth Scrolling State
    @Published var isRapidScrolling: Bool = false
    @Published var isControllerScrolling: Bool = false // Guard for ScrollView binding conflicts
    
    // Performance Optimization: Cache game counts to avoid O(N) filter in View loop
    @Published var consoleCounts: [ROMItem.Console: Int] = [:]
    
    @Published var selectedIndex: Int = 0 {
        didSet {
            // Play sound for Touch Navigation (Controller handles its own sound)
            if !isControllerScrolling && oldValue != selectedIndex {
                 AudioManager.shared.playMoveSound()
            }
        }
    }
    @Published var showContent: Bool = false
    // View Refresh Trigger (Forcing "Restart" of view on updates)
    @Published var refreshID = UUID()
    @Published var isRefreshing: Bool = false // Loading state for smooth transitions
    @Published var isReloading: Bool = false // Manual Opacity Fade State
    
    // Emulator State
    @Published var showEmulator: Bool = false {
        didSet {
            handleEmulatorStateChange()
        }
    }
    @Published var selectedROM: ROMItem?
    
    // Play Time Tracking
    private var emulatorStartTime: Date?
    
    private func handleEmulatorStateChange() {
        if showEmulator {
            // Started
            emulatorStartTime = Date()
        } else {
            // Stopped
            if let start = emulatorStartTime, let rom = selectedROM {
                let duration = Date().timeIntervalSince(start)
                // Threshold: 10 seconds to count as play session
                if duration > 10 {
                    DispatchQueue.global(qos: .utility).async {
                        ROMStorageManager.shared.addPlayTime(duration, to: rom)
                    }
                }
            }
            emulatorStartTime = nil
        }
    }
    
    // Auto-scroll Timer

    
    private var cancellables = Set<AnyCancellable>()

    init() {
        print(" GameSystemsViewModel initialized")
        
        // Initialize View State based on saved preference to prevent flicker
        let savedMode = UserDefaults.standard.string(forKey: "gameSystemViewMode") ?? "vertical"
        if savedMode == "grid" {
            self.isGlobalMode = true
            self.isSelectingConsole = false
            print(" Init in Grid Mode")
        }
        
        updateData()
        setupControllerObservers()
        
        // Debug: Print available consoles
        print(" Available Consoles: \(availableConsoles.map { $0.systemName })")
        
        // Subscribe to Storage Changes to auto-update UI
        storage.$roms
            .dropFirst() // Ignore initial emission since we call updateData() manually
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                print(" Storage updated - Refreshing Game Systems UI")
                self?.updateROMs()
            }
            .store(in: &cancellables)
            
        // Subscribe to User Profile Changes (Playtime updates)
        UserProfileManager.shared.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    func updateData() {
        // 1. Get supported consoles
        // TEMP: Hide MeloNX from carousel/navigation for now.
        let allConsoles = ROMItem.Console.allCases.filter { $0 != .psp && $0 != .meloNX }
        
        // Check for saved custom order
        if let savedOrder = UserDefaults.standard.stringArray(forKey: "consoleCustomOrder") {
            var ordered: [ROMItem.Console] = []
            var remaining = allConsoles
            
            // Apply saved order
            for raw in savedOrder {
                if let console = ROMItem.Console(rawValue: raw), remaining.contains(console) {
                    ordered.append(console)
                    remaining.removeAll { $0 == console }
                }
            }
            
            // Append any remaining/new consoles (Alphabetical)
            let sortedRemaining = remaining.sorted { $0.systemName < $1.systemName }
            ordered.append(contentsOf: sortedRemaining)
            
            self.availableConsoles = ordered
        } else {
            // Default Sort: iOS first, then alphabetical
            self.availableConsoles = allConsoles.sorted {
                if $0 == .ios { return true }
                if $1 == .ios { return false }
                return $0.systemName < $1.systemName
            }
        }
        
        // 2. Filter ROMs based on state
        updateROMsList()
        
        // 3. Pre-calculate counts for performance
        var counts: [ROMItem.Console: Int] = [:]
        for console in availableConsoles {
            counts[console] = storage.roms.filter { $0.console == console }.count
        }
        self.consoleCounts = counts
    }
    
    private func updateROMsList() {
        if isGlobalMode {
            // Show ALL games sorted by Console then Name
            // Prioritize iOS games first
            self.filteredROMs = storage.roms.sorted {
                // 1. Sort by Console Order (using availableConsoles which respects custom reordering)
                let consoleIndex1 = self.availableConsoles.firstIndex(of: $0.console) ?? 999
                let consoleIndex2 = self.availableConsoles.firstIndex(of: $1.console) ?? 999
                
                if consoleIndex1 != consoleIndex2 {
                    return consoleIndex1 < consoleIndex2
                }
                
                // 2. Sort by Name within Console
                return $0.displayName < $1.displayName
            }
        } else if let console = selectedConsole {
            self.filteredROMs = storage.roms
                .filter { $0.console == console }
                .sorted { $0.displayName < $1.displayName }
        } else {
            self.filteredROMs = []
        }
        
        // Validate indices
        if selectedIndex >= filteredROMs.count {
            selectedIndex = max(0, filteredROMs.count - 1)
        }
        if selectedConsoleIndex >= availableConsoles.count {
            selectedConsoleIndex = max(0, availableConsoles.count - 1)
        }
    }
    
    // Public method to refresh standard data
    func updateROMs() {
        // Controlled "Wipe" Animation
        // 1. Fade Out
        withAnimation(.easeOut(duration: 0.2)) {
            isReloading = true
        }
        
        // 2. Wait for fade out, then Update Data & ID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.updateData()
            self.refreshID = UUID() // Hard Refresh (Invisible while opacity is 0)
            
            // 3. Fade In
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.isReloading = false
                }
            }
        }
    }
    
    private func setupControllerObservers() {
        // We will handle logic in the View's onChange for simplicity regarding State updates,
        // but we can also subscribe here if needed.
        // For now, the View will drive the inputs to this Model.
    }
    
    // Navigation Logic
    
    func enterGlobalGrid() {
        withAnimation {
            isGlobalMode = true
            isSelectingConsole = false // Hide consoles, show games (grid)
            selectedIndex = 0
            updateROMsList()
        }
    }
    
    func exitGlobalGrid() {
        withAnimation {
            isGlobalMode = false
            // Return to Console Selection default
            isSelectingConsole = true
            selectedConsole = nil
            filteredROMs = [] // Clear games
            updateROMsList()
        }
    }
    
    func selectConsole(_ console: ROMItem.Console, enter: Bool = true) {
        withAnimation {
            isGlobalMode = false // Ensure we are not in global mode
            selectedConsole = console
            
            // Fix: Only update index if it's different. 
            // This prevents conflict when called from scroll binding/onChange where index is already set.
            if let index = availableConsoles.firstIndex(of: console), index != selectedConsoleIndex {
                selectedConsoleIndex = index
            }
            
            updateROMsList()
            if enter {
                isSelectingConsole = false
                selectedIndex = 0 // Reset game selection
            }
        }
    }
    
    func backToConsoles() {
        withAnimation {
            isGlobalMode = false
            isSelectingConsole = true
            selectedConsole = nil
            updateROMsList() // Will clear filteredROMs
        }
    }
    
    // Input Throttling

    
    func moveSelection(delta: Int) {
        var newConsoleIndex: Int?
        var newGameIndex: Int?
        var shouldUpdate = false
        
        // 1. Calculate potential changes (Preview)
        if isSelectingConsole {
            guard !availableConsoles.isEmpty else { return }
            let nextIndex = selectedConsoleIndex + delta
            if nextIndex >= 0 && nextIndex < availableConsoles.count {
                newConsoleIndex = nextIndex
                shouldUpdate = true
            }
        } else {
            guard !filteredROMs.isEmpty else { return }
            let currentIndex = selectedIndex
            let nextIndex = max(0, min(currentIndex + delta, filteredROMs.count - 1))
            if nextIndex != currentIndex {
                newGameIndex = nextIndex
                shouldUpdate = true
            }
        }
        
        // 2. Apply if valid
        if shouldUpdate {
            // A. Play Sound (Since we confirmed it's a valid move)
            AudioManager.shared.playMoveSound()
            
            // B. Lock Observers (Prevent didSet from playing sound again)
            isControllerScrolling = true
            
            // C. Update State
            if let idx = newConsoleIndex {
                selectedConsoleIndex = idx
            }
            if let idx = newGameIndex {
                selectedIndex = idx
            }
            
            // D. Unlock Observers
            DispatchQueue.main.async {
                self.isControllerScrolling = false
            }
        }
    }

    
    func getPlaytime(for rom: ROMItem) -> String {
        let totalSeconds = Int(UserProfileManager.shared.getPlayTime(for: rom.id))
        if totalSeconds == 0 {
            return "New"
        }
        
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        
        if hours > 0 {
            // e.g. "5h 20m"
            return "\(hours)h \(minutes)m"
        } else {
            // e.g. "45m"
            return "\(minutes)m"
        }
    }
    
    func getGameCount(for console: ROMItem.Console) -> Int {
        return consoleCounts[console] ?? 0
    }
    
    //  iOS App Import Logic
    // Logic moved to ROMStorageManager for better background/foreground handling

    //  Reordering Logic
    
    func updateConsoleOrder(_ newOrder: [ROMItem.Console]) {
        withAnimation {
            self.availableConsoles = newOrder
        }
        // Save to UserDefaults
        let rawValues = newOrder.map { $0.rawValue }
        UserDefaults.standard.set(rawValues, forKey: "consoleCustomOrder")
    }
}
