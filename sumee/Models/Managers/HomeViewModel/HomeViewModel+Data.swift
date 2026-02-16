import SwiftUI
import Combine

// HomeViewModel+Data.swift

extension HomeViewModel {
    
    // MARK: - Bindings & Input Handling
    
    func setupBindings() {
        // Observers
        NotificationCenter.default.publisher(for: NSNotification.Name("ROMDeleted"))
            .compactMap { $0.object as? ROMItem }
            .receive(on: RunLoop.main)
            .sink { [weak self] rom in
                guard let self = self else { return }
                print("🗑️ HomeViewModel received ROM deletion: \(rom.displayName) - Removing from grid...")
                
                var removed = false
                for (pageIndex, page) in self.pages.enumerated() {
                    if let index = page.firstIndex(where: { $0.isROM && $0.romItem?.id == rom.id }) {
                        self.pages[pageIndex].remove(at: index)
                        removed = true
                        
                        // Clean empty pages
                        if self.pages[pageIndex].isEmpty && self.pages.count > 1 {
                             self.pages.remove(at: pageIndex)
                             // Adjust current page if needed
                             if self.selectedTabIndex >= self.pages.count {
                                 self.selectedTabIndex = max(0, self.pages.count - 1)
                             }
                        }
                        
                        self.triggerSaveLayout()
                        break
                    }
                }
                
                if !removed {
                    // Fallback: Check strictly by name just in case of weird ID mismatch (legacy data)
                     for (pageIndex, page) in self.pages.enumerated() {
                        if let index = page.firstIndex(where: { $0.isROM && $0.name == rom.displayName && $0.romItem == nil }) {
                            // Only remove if it looks like an orphan ROM shortcut
                             self.pages[pageIndex].remove(at: index)
                             if self.pages[pageIndex].isEmpty && self.pages.count > 1 {
                                 self.pages.remove(at: pageIndex)
                             }
                             self.triggerSaveLayout()
                             break
                        }
                     }
                }
            }
            .store(in: &cancellables)

        // Button A - Select App
        gameController.$buttonAPressed
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.handleButtonAPress()
            }
            .store(in: &cancellables)
    
            
        // Button X - Delete App (ROMs)
        gameController.$buttonXPressed
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.handleButtonXPress()
            }
            .store(in: &cancellables)
            
        // Page Navigation (Optimized)
        // L1/R1 Handled centrally in handleGameInput() for LiveArea switching
        // Grid Page navigation is now handled via D-Pad edge scrolling
            
        // Button B - Back/Close
        gameController.$buttonBPressed
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                self?.handleButtonBPress()
            }
            .store(in: &cancellables)
            
        // Button Y - Custom Image (Empty Slot)
        gameController.$buttonYPressed
            .dropFirst()
            .filter { $0 }
            .throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                self?.handleButtonYPress()
            }
            .store(in: &cancellables)
            
        // Button X - Delete (Throttle)
        // Note: Duplicate subscription above?
        // Line 266 adds a sink. Line 311 adds ANOTHER sink to handleButtonXPress.
        // This causes double firing. I should consolidate.
        // I will keep only the Throttled one below.
        
        /*
        gameController.$buttonXPressed
            .dropFirst()
            .filter { $0 }
            .throttle(for: .milliseconds(300), scheduler: RunLoop.main, latest: false)
            .sink { [weak self] _ in
                self?.handleButtonXPress()
            }
            .store(in: &cancellables)
        */
         
        // Actually, let's just keep ONE subscription for X.
        // The previous code had two. I'll rely on the earlier one or combine.
        // I'll skip the second block in this new file to fix the bug.
            
        // Save Layout when exiting Edit Mode (Y or A action)
        gameController.$isEditingLayout
            .dropFirst()
            .removeDuplicates()
            .filter { !$0 } // Only when turning OFF (saving)
            .sink { [weak self] _ in
                self?.cleanupTrailingEmptyPages()
                self?.saveLayout()
                print("💾 Saved layout upon exiting Edit Mode")
            }
            .store(in: &cancellables)
            
        // Persistence Debounce
        saveLayoutSubject
            .debounce(for: .seconds(1.0), scheduler: persistenceQueue)
            .sink { [weak self] _ in
                guard let self = self else { return }
                // Need to access pages from main thread because it's @Published
                Task { @MainActor in
                    let pagesToSave = self.pages
                    // Move to background for encoding/writing
                    Task.detached(priority: .background) {
                        do {
                            let data = try JSONEncoder().encode(pagesToSave)
                            UserDefaults.standard.set(data, forKey: "savedLayout")
                            // Verify what was saved
                            if let json = String(data: data, encoding: .utf8) {
                                print("✅ Layout Saved to UserDefaults logic: \(pagesToSave.count) pages. JSON Size: \(data.count) bytes.")
                                // Debug: check first widget size
                                if let firstPage = pagesToSave.first, let firstWidget = firstPage.first(where: { $0.isWidget }) {
                                    print("🔍 Debug Save: First Widget (\(firstWidget.name)) Size: \(firstWidget.widgetSize)")
                                }
                            }
                        } catch {
                            print("❌ Failed to save layout: \(error)")
                        }
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func handleButtonYPress() {
        if isIdleMode { resetIdleTimer(); return }
        
        guard !gameController.disableHomeNavigation else { return }
        guard !gameController.isSelectingWidget else { return }
        
        let currentPageIndex = selectedTabIndex
        guard currentPageIndex < pages.count else { return }
        
        let currentApps = pages[currentPageIndex]
        let selectedIndex = gameController.selectedAppIndex
        
        // Check if selected index is an empty slot (index >= app count) OR explicit "Empty" item
        var isEmptySlot = false
        if selectedIndex >= currentApps.count {
            isEmptySlot = true
        } else {
            let item = currentApps[selectedIndex]
            if item.name == "Empty" {
                isEmptySlot = true
            }
        }

        if isEmptySlot {
            // Trigger Image Picker (Allowed even in Edit Mode)
            showingImagePicker = true
            // AudioManager.shared.playSelectSound()
        } else if gameController.isEditingLayout {
            // If in Edit Mode and NOT on empty slot, Y acts as "Save/Exit"
            gameController.isEditingLayout = false
            // AudioManager.shared.playSelectSound()
        } else {
            // Normal mode behavior (Enter Edit Mode)
            gameController.isEditingLayout = true
            // AudioManager.shared.playSelectSound()
        }
    }
    
    func handleButtonAPress() {
        if isIdleMode { resetIdleTimer(); return }
        
        guard !gameController.disableHomeNavigation else { return }
        
        // 1. Live Area Action (Priority)
        if mainInterfaceIndex > 0 {
             AudioManager.shared.playSelectSound()
             handleLiveAreaAction()
             return
        }
        
        // 2. Grid Action
        // Prevent background navigation if System App is open or in LiveArea (Redundant check but safe)
        guard activeSystemApp == nil, mainInterfaceIndex == 0 else { return }
        
        // Check if we are in a special state (e.g. editing)
        if gameController.isEditingLayout {
            saveLayout()
            return
        }
        
        // If selecting widget
        if gameController.isSelectingWidget {
            // Special case for Sketch widget (Page 1, Widget 0)
            if selectedTabIndex == 1 && gameController.selectedWidgetIndex == 0 {
                AudioManager.shared.pauseAllAudioForAppEntry()
                gameController.isSelectingWidget = false
                gameController.widgetInternalNavigationActive = false
                gameController.disableHomeNavigation = true
                
            }
            

            
            // Add other widget interactions here if needed
            return
        }

        // Normal app selection
        let selectedApp = getCurrentSelectedApp()
        
        // Start sound (Only for Games)
        if let app = selectedApp, app.isROM {
            AudioManager.shared.playStartGridSound()
        }
        
        openApp(selectedApp)
    }
    
    func handleLeftTriggerPress() {
        if isIdleMode { resetIdleTimer(); return }
        
        if !showPhotosGallery && !showMusicPlayer && !showSettings && !showGameSystems {
            // AudioManager.shared.playSelectSound()
            // Friends overlay removed
        }
    }
    
    func handleButtonBPress() {
        if isIdleMode { resetIdleTimer(); return }
        
        // Edit Mode - Discard Changes
        if gameController.isEditingLayout {
            if !backupPages.isEmpty {
                pages = backupPages
                backupPages.removeAll()
                saveLayout()
            }
            return
        }
        
        // Close overlays
   
    }
    
    //  Random Game Logic
    
    func startRandomRotation() {
        pickRandomROM()
        stopRandomRotation()
        randomTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            withAnimation(.easeInOut(duration: 1.5)) {
                self?.pickRandomROM()
            }
        }
    }
    
    func stopRandomRotation() {
        randomTimer?.invalidate()
        randomTimer = nil
    }
    
    func pickRandomROM() {
        let allROMs = ROMStorageManager.shared.roms
        guard !allROMs.isEmpty else {
            currentRandomROM = nil
            return
        }
        
        var newROM = allROMs.randomElement()
        if allROMs.count > 1 && newROM?.id == currentRandomROM?.id {
            newROM = allROMs.filter { $0.id != currentRandomROM?.id }.randomElement()
        }
        currentRandomROM = newROM
    }
    
    // MARK: - Store / App Installation
    func installApp(_ systemApp: SystemApp) {
        // Check if already exists
        if pages.flatMap({ $0 }).contains(where: { $0.systemApp == systemApp }) {
            print("⚠️ \(systemApp.defaultName) is already installed.")
            return
        }
        
        var newApp = AppItem(
            name: systemApp.defaultName,
            iconName: systemApp.iconName,
            color: systemApp.defaultColor,
            folderType: systemApp.folderType,
            systemApp: systemApp
        )
        newApp.isNewInstallation = true
        
        addAppToFirstAvailableSlot(newApp)
        
        // Ensure persistence and layout integrity
        saveLayout()
        
        // Force UI refresh if needed (usually @Published pages handles it, but consolidate ensures grid alignment)
        consolidatePages()
        
        print("📥 Installed \(systemApp.defaultName) from Store")
    }
    
    // MARK: - Navigation Helpers
    private func resetSelectionOnPageChange() {
        gameController.isSelectingWidget = false
        gameController.selectedWidgetIndex = 0
        gameController.currentWidgetCount = 0
        gameController.selectedAppIndex = 0 // Reset focus to top-left
    }
    
    private func changePage(by delta: Int) {
        if isIdleMode { resetIdleTimer(); return }
        
        // Prevent navigation if disabled
        guard !gameController.disableHomeNavigation else { return }
        
        let now = Date().timeIntervalSince1970
        guard now - lastNavigationTime > 0.1 else { return } // Simple 100ms debounce
        lastNavigationTime = now
        
        guard !pages.isEmpty else { return }
        
        let count = pages.count
        // Cyclic Math: (current + delta + count) % count handles negative wrapping correctly
        var targetIndex = (selectedTabIndex + delta) % count
        if targetIndex < 0 { targetIndex += count } // Swift's % operator can return negative for negative dividends
        
        if targetIndex != selectedTabIndex {
            // Valid Navigation
            audioManager.playMoveSound()
            // Instant snap for buttons, effectively skipping the slide transition
            // The "Dance" animation in AppGridPage will still trigger on arrival
            selectedTabIndex = targetIndex
            resetSelectionOnPageChange()
        }
    }
}
