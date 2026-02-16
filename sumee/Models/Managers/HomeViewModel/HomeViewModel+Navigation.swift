import SwiftUI
import Combine

// HomeViewModel+Navigation.swift

extension HomeViewModel {
    
    // Navigation Logic
    
    func handleControllerMove(_ direction: GameControllerManager.Direction) {
        
        // IDLE MODE GUARD
        if isIdleMode {
            resetIdleTimer()
            return
        }
        
        // Prevent background navigation
        guard !showSettings, !showStore, !showDiscord, !showPhotosGallery, !showMusicPlayer else { return }
        guard !gameController.isSelectingWidget else { return }
        
        // Only allow Grid Navigation if we are on the Grid Page (0)
        guard mainInterfaceIndex == 0 else { return }
        
        resetIdleTimer()
        
        let currentPageIndex = selectedTabIndex
        guard currentPageIndex < pages.count else { return }
        
        let currentApps = pages[currentPageIndex]
        let currentIndex = gameController.selectedAppIndex
        
        // 1. Calculate Geometry for Smart Navigation
        let pos = VitaGridHelper.getPosition(for: currentIndex)
        let rowCapacity = VitaGridHelper.itemsPerRow(pos.row)
        
        // 2. Intercept RIGHT -> Move to LiveArea (Any Row)
        if direction == .right {
            // Logic: If at end of ANY row, or absolute last item
            let isAtRowEnd = (pos.col == rowCapacity - 1)
            let isLastItem = (currentIndex == currentApps.count - 1)
            
            if isAtRowEnd || isLastItem {
                // Trigger Live Area Transition (L1/R1 Logic)
                let now = Date().timeIntervalSince1970
                if now - lastNavigationTime > 0.25 {
                    if mainInterfaceIndex < activeGameTasks.count {
                        withAnimation(.easeInOut(duration: 0.3)) {
                             mainInterfaceIndex += 1
                        }
                        lastNavigationTime = now
                        AudioManager.shared.playSelectSound()
                        liveAreaActionIndex = 0
                    }
                }
                return
            }
        }
        
        // 3. Intercept DOWN -> Move to Next Grid Page (Bottom of Any Column)
        if direction == .down {
            // Check if a next row exists on THIS page
            let nextRowFirstIndex = VitaGridHelper.getIndex(row: pos.row + 1, col: 0)
            let isLastRow = nextRowFirstIndex >= currentApps.count
            
            if isLastRow {
                // Attempt to go to Next Page
                if currentPageIndex < pages.count - 1 {
                    selectedTabIndex += 1

                    let newCol = min(pos.col, 2) // Row 0 max col is 2
                    gameController.selectedAppIndex = newCol
                    
                    AudioManager.shared.playNavigationSound()
                }
                return
            }
        }
        
        // 3.5 Intercept UP -> Move to Prev Grid Page (Top of Any Column)
        if direction == .up {
            if pos.row == 0 {
                if currentPageIndex > 0 {
                    selectedTabIndex -= 1
                    // Go to bottom of previous page
                    let prevPageCount = pages[currentPageIndex - 1].count
                    gameController.selectedAppIndex = max(0, prevPageCount - 1)
                    AudioManager.shared.playNavigationSound()
                }
                return
            }
        }
        
        // 4. Default Navigation (Within Page)
        let targetIndex = VitaGridHelper.navigate(from: currentIndex, direction: direction, totalItems: currentApps.count)
        
        // 5. Handle standard Left Page Walls (Optional, keep existing logic for Left)
        if targetIndex == currentIndex {
            if direction == .left && currentIndex == 0 {
                // Attempt Prev Page
                if currentPageIndex > 0 {
                    selectedTabIndex -= 1
                    // Go to last item or bottom row? Standard is last item.
                    let prevPageCount = pages[currentPageIndex - 1].count
                    gameController.selectedAppIndex = max(0, prevPageCount - 1)
                    AudioManager.shared.playNavigationSound()
                }
            }
            return
        }
        
        // 6. Apply Move
        if targetIndex != currentIndex {
            gameController.selectedAppIndex = targetIndex
            AudioManager.shared.playNavigationSound()
        }
        
        gameController.lastInputTimestamp = Date().timeIntervalSince1970
    }

    
    // Logic: SWAP (Fixed Grid)
    func handleEditOperation(item: AppItem, fromIndex: Int, fromPage: Int, toIndex: Int, toPage: Int, direction: GameControllerManager.Direction) {
        
        guard fromPage < pages.count, fromIndex < pages[fromPage].count else { return }
        
        // 1. Validate Target Page Exists
        if toPage >= pages.count {
             // Create new page if needed (only if moving Right from last page)
             pages.append([])
        }
        
        guard toPage < pages.count else { return }
        
        // 2. Validate Target Index range
        if pages[toPage].isEmpty {
             // Fill with empty slots - MUST use map to generate unique IDs
             pages[toPage] = (0..<VitaGridHelper.itemsPerPage).map { _ in 
                 AppItem(name: "Empty", iconName: "", color: .clear, isWidget: false, isSpacer: true)
             }
        }
        
        let targetIndex = min(toIndex, pages[toPage].count - 1)
        
        // 3. Check Optimization (Fast Path)
        // If both items are simple 1x1 blocks (height=1 & width=1), we can skip heavy reflow.
        let targetItem = pages[toPage][targetIndex]
        let sourceItem = pages[fromPage][fromIndex]
        
        let isSimpleSwap = (sourceItem.width == 1 && sourceItem.height == 1) &&
                           (targetItem.width == 1 && targetItem.height == 1)
        
        // 4. Perform Swap
        // Tuning: Response 0.3 for snappier feel (was 0.4 or 0.5)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { // Snappier!
            
            if fromPage == toPage {
                // Same Page Swap
                pages[fromPage].swapAt(fromIndex, targetIndex)
            } else {
                // Cross Page Swap
                pages[toPage][targetIndex] = sourceItem
                pages[fromPage][fromIndex] = targetItem
            }
            
            // Update Selection
            if selectedTabIndex != toPage {
                selectedTabIndex = toPage
            }
            gameController.selectedAppIndex = targetIndex
            AudioManager.shared.playNavigationSound()
        }
        
        // 5. Consolidate vs Fast Path
        if isSimpleSwap {
             // Optimization: Skip consolidatePages() for simple 1x1 swaps.
             // Just trigger a background save.
             saveLayout()
        } else {
             // Complex Swap involving Widgets -> Must reflow to ensure integrity
             consolidatePages()
             func reSyncSelection() {
                 if let newItemPageIdx = pages.firstIndex(where: { p in p.contains(where: { $0.id == item.id }) }),
                    let newItemIdx = pages[newItemPageIdx].firstIndex(where: { $0.id == item.id }) {
                     
                     withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                         if selectedTabIndex != newItemPageIdx {
                             selectedTabIndex = newItemPageIdx
                         }
                     }
                     gameController.selectedAppIndex = newItemIdx
                 }
             }
             reSyncSelection()
             saveLayout()
        }
    }
    
    func openApp(_ item: AppItem?) {
        guard let item = item else { return }
        
        // Ignore if any overlay already open
        guard !showPhotosGallery && !showMusicPlayer && !showSettings && !showGameSystems && !showStore && !showDiscord && !showMeloNX else { return }
        
        print(" openApp called for: \(item.name) (SystemApp: \(String(describing: item.systemApp)))")
        
        // 0. New Installation Handling
        if item.isNewInstallation {
            print(" Unwrapping New Installation: \(item.name)")
            
            // 1. Play Sound
            AudioManager.shared.playOpenSound()
            
            // 2. Remove Flag & Save
            if let pageIdx = pages.firstIndex(where: { $0.contains { $0.id == item.id } }),
               let itemIdx = pages[pageIdx].firstIndex(where: { $0.id == item.id }) {
                
                withAnimation(.spring(response: 0.8, dampingFraction: 0.6)) {
                    pages[pageIdx][itemIdx].isNewInstallation = false
                }
                saveLayout()
            }
            return
        }
        
        // 1. System App Handling (Unified & Zero-Touch)
        if let systemApp = item.systemApp {
            print("Launching SystemApp: \(systemApp.defaultName)")
            
            // Apply Configurations
            if systemApp.pausesAudio {
                AudioManager.shared.pauseAllAudioForAppEntry()
            }
            
            if systemApp.disablesHomeNavigation {
                gameController.disableHomeNavigation = true
            }
            
            // Set State (Triggers View)
            withAnimation(.easeOut(duration: systemApp.transitionDuration)) {
                activeSystemApp = systemApp
            }
            
            // Play Sound (Generic)
            // AudioManager.shared.playSelectSound()
            
            return
        }
        
        // 2. Legacy / Special Case Handling (Widgets, Manual Names)
        
        
        if item.name == "Last Played" {
            openLastPlayedGame()
            return
        }
        
        if item.name == "Random Game" {
            if let rom = currentRandomROM {
                selectedROM = rom
                showEmulator = true
            }
            return
        }
        
        // if item.name == "News Widget" {
        //     AudioManager.shared.pauseAllAudioForAppEntry()
        //     gameController.disableHomeNavigation = true
        //     withAnimation(.easeOut(duration: 0.3)) { showEENews = true }
        //     return
        // }
        
        // Handle ROM items from Home Grid
        if item.isROM, let rom = item.romItem {
             // Controller selection should open LiveArea (Game Page), not launch emulator immediately
      
             openGamePage(rom, animated: true)
            return
        }
        
        // AudioManager.shared.playSelectSound()
    }
    
    func handleControllerSelect() {
        // IDLE MODE GUARD: Consume input to wake UI, but do not select.
        if isIdleMode {
            resetIdleTimer()
            return
        }
        
        // Prevent background navigation if System App is open or in LiveArea
        guard activeSystemApp == nil, mainInterfaceIndex == 0 else { return }
        
        resetIdleTimer()
        
        // Widget resizing removed
        /* if gameController.isEditingLayout {
             resizeSelectedWidget()
             return
        } */
        
        // Unified selection logic
        guard selectedTabIndex < pages.count else { return }
        let currentApps = pages[selectedTabIndex]
        let appIndex = gameController.selectedAppIndex
        
        if appIndex < currentApps.count {
            let app = currentApps[appIndex]
            openApp(app)
        }
    }
    
    func handleButtonXPress() {
        if isIdleMode { resetIdleTimer(); return }
        
        // Only allow deletion if in Edit Mode
        guard gameController.isEditingLayout else { return }
        
        // Only allow deletion if not in specific modes
        guard !showPhotosGallery, !showMusicPlayer, !showSettings, !showEmulator, !showStore, !showDiscord else { return }
        
        if let selectedApp = getCurrentSelectedApp() {
            // Allow deleting ROMs, Custom Images, AND Store-Installed System Apps
            let isStoreApp = selectedApp.systemApp.map { !$0.isPreinstalled } ?? false
            
            if selectedApp.isROM || selectedApp.isCustomImage || isStoreApp {
                appToDelete = selectedApp
                showDeleteConfirmation = true
                // AudioManager.shared.playSelectSound()
            }
        }
    }
    
    func deleteApp(_ item: AppItem) {
        // Find and remove the item
        for (pageIndex, page) in pages.enumerated() {
            if let itemIndex = page.firstIndex(where: { $0.id == item.id }) {
                pages[pageIndex].remove(at: itemIndex)
                
                // If page becomes empty and it's not the first page, remove it
                // (Optional: Keep empty pages if desired, but cleaning up is usually better)
                if pages[pageIndex].isEmpty && pages.count > 1 {
                    pages.remove(at: pageIndex)
                    // Adjust selectedTabIndex if needed
                    if selectedTabIndex >= pages.count {
                        selectedTabIndex = max(0, pages.count - 1)
                    }
                    // Reset app index since page changed
                    gameController.selectedAppIndex = 0
                } else {
                     // Verify and Fix Selection Index if it became out of bounds
                     if gameController.selectedAppIndex >= pages[pageIndex].count {
                         gameController.selectedAppIndex = max(0, pages[pageIndex].count - 1)
                     }
                }
                
                triggerSaveLayout()
                AppStatusManager.shared.show("Deleted", icon: "trash")
                
                // Exit Edit Mode after deleting to restore normal navigation
                // Important: This re-enables normal navigation logic
                DispatchQueue.main.async { [weak self] in
                    self?.gameController.isEditingLayout = false
                     // Ensure focus is refreshed
                    self?.gameController.lastInputTimestamp = Date().timeIntervalSince1970
                }
                return
            }
        }
    }
    
    func openLastPlayedGame() {
        if let lastPlayed = ROMStorageManager.shared.getLastPlayedROM() {
            selectedROM = lastPlayed
            showEmulator = true
            // AudioManager.shared.playSelectSound()
        } else {
            // Optional: Play error sound or show alert if no game found
            print("No last played game found")
        }
    }
    
    func getCurrentSelectedApp() -> AppItem? {
        guard selectedTabIndex < pages.count else { return nil }
        let currentApps = pages[selectedTabIndex]
        guard gameController.selectedAppIndex < currentApps.count else { return nil }
        return currentApps[gameController.selectedAppIndex]
    }
    
    // LiveArea & Global Input
    
    func handleGameInput(_ event: GameControllerManager.GameInputEvent) {
        if isIdleMode { resetIdleTimer(); return }
        
        // Prevent if system app is open
        guard activeSystemApp == nil, !showEmulator else { return }

        switch event {
        case .l1:
            // Navigate Left: LiveArea -> Previous LiveArea -> Grid
            let now = Date().timeIntervalSince1970
            guard now - lastNavigationTime > 0.25 else { return }
            
            if mainInterfaceIndex > 0 {
                // Simplified animation to rely on View modifier or standard context
                withAnimation(.easeInOut(duration: 0.3)) {
                     mainInterfaceIndex -= 1
                }
                lastNavigationTime = now
                AudioManager.shared.playSelectSound()
                liveAreaActionIndex = 0 // Reset local cursor
            }
            
        case .r1:
            // Navigate Right: Grid -> LiveArea -> Next LiveArea
            let now = Date().timeIntervalSince1970
            guard now - lastNavigationTime > 0.25 else { return }
            
            if mainInterfaceIndex < activeGameTasks.count {
                withAnimation(.easeInOut(duration: 0.3)) {
                     mainInterfaceIndex += 1
                }
                lastNavigationTime = now
                AudioManager.shared.playSelectSound()
                liveAreaActionIndex = 0 // Reset local cursor
            }
            
        // Live Area Navigation
        case .up, .down:
             handleLiveAreaLogistics(event)

        case .left:
            // Back to previous LiveArea or Grid
            let now = Date().timeIntervalSince1970
            guard now - lastNavigationTime > 0.25 else { return }
            
            if mainInterfaceIndex > 0 {
                withAnimation(.easeInOut(duration: 0.3)) {
                     mainInterfaceIndex -= 1
                }
                lastNavigationTime = now
                AudioManager.shared.playSelectSound()
                liveAreaActionIndex = 0
            }
            
        case .right:
             // Move to Next LiveArea
             let now = Date().timeIntervalSince1970
             guard now - lastNavigationTime > 0.25 else { return }
             
             if mainInterfaceIndex > 0 {
                 if mainInterfaceIndex < activeGameTasks.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                         mainInterfaceIndex += 1
                    }
                    lastNavigationTime = now
                    AudioManager.shared.playSelectSound()
                    liveAreaActionIndex = 0
                 }
             }
             
        default: break
        }
    }
    
    private func handleLiveAreaLogistics(_ event: GameControllerManager.GameInputEvent) {
        guard mainInterfaceIndex > 0 else { return }
        
        // Determine max index based on ROM state
        let taskIndex = mainInterfaceIndex - 1
        guard taskIndex < activeGameTasks.count else { return }
        let rom = activeGameTasks[taskIndex]
        
        let hasSave = FileManager.default.fileExists(atPath: rom.autoSaveScreenshotURL?.path ?? "")
        // If has save: Index 0 = Resume, Index 1 = Restart
        // If no save: Index 0 = Start
        
        let maxIndex = hasSave ? 1 : 0
        
        if case .up(let repeated) = event, !repeated {
            if liveAreaActionIndex > 0 {
                liveAreaActionIndex -= 1
                AudioManager.shared.playNavigationSound()
            }
        } else if case .down(let repeated) = event, !repeated {
            if liveAreaActionIndex < maxIndex {
                liveAreaActionIndex += 1
                AudioManager.shared.playNavigationSound()
            }
        }
    }
    
    func handleLiveAreaAction() {
        guard mainInterfaceIndex > 0 else { return }
        let taskIndex = mainInterfaceIndex - 1
        guard taskIndex < activeGameTasks.count else { return }
        let rom = activeGameTasks[taskIndex]
        
        let hasSave = FileManager.default.fileExists(atPath: rom.autoSaveScreenshotURL?.path ?? "")
        
        if hasSave {
            if liveAreaActionIndex == 0 {
                // Delegate to View for coordinate-aware launch
                liveAreaLaunchSignal.send(.resume)
            } else {
                liveAreaLaunchSignal.send(.restart)
            }
        } else {
            liveAreaLaunchSignal.send(.normal)
        }
    }
}

extension HomeViewModel {
    var selectedAppTitle: String? {
        // If editing, let HeaderView handle "Edit Mode" text
        if gameController.isEditingLayout { return nil }
        
        // Only show name when in Grid Mode or LiveArea

        if mainInterfaceIndex == 0 {
            // Grid Mode
            guard pages.indices.contains(selectedTabIndex) else { return nil }
            let page = pages[selectedTabIndex]
            guard page.indices.contains(gameController.selectedAppIndex) else { return nil }
            return page[gameController.selectedAppIndex].name
        }
        return nil
    }
}
