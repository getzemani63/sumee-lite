import SwiftUI
import SwiftUI
import PhotosUI

import UIKit
import UniformTypeIdentifiers

struct CustomThemeSettingsView: View {
    @Binding var isPresented: Bool
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject private var gameController = GameControllerManager.shared
    
    // Navigation State
    @State private var selectedRow: Int = 0 //
    @State private var showShareOverlay = false
    @State private var isRestarting = false
    @State private var scrollTask: Task<Void, Never>?
    
    // Media Loading State
    @State private var isImportingMedia = false
    
    // Photo Picker State
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    
    // Console Icon Picker State
    @State private var showConsoleIconPicker = false
    @State private var showConsoleList = false
    @State private var selectedConsolePhotoItem: PhotosPickerItem?
    @State private var selectedConsoleForIcon: ROMItem.Console?
    
    // System App Icon Picker State
    @State private var showSystemAppList = false
    
    @State private var selectedSystemPhotoItem: PhotosPickerItem?

    // Color Picker State
    @State private var hue: Double = 0.0
    @State private var saturation: Double = 0.8
    @State private var opacity: Double = 0.8

    
    // Music Picker State
    @State private var showMusicPicker = false
    @State private var musicSelectionIndex = 0

    // Console Picker State
    @State private var consoleSelectionIndex = 0
    // System App Selection State
    @State private var systemAppSelectionIndex = 0
    @State private var systemSlotSelectionIndex = 0 
    @State private var selectedSystemApp: SystemApp? = nil
    @State private var targetSystemSlot: SystemSelectionOverlay.IconSlot? = nil
    @State private var showSystemIconPicker = false
    
    // Share Picker State
    @State private var shareSelectionIndex = 0
    @State private var showShareFileImporter = false
    @State private var shareFileItem: ShareFile?
    
    // Filtered list of apps that allow icon customization
    private var themableConsoles: [ROMItem.Console] {
        return ROMItem.Console.allCases.filter { $0 != .psp }
    }

    private var themableApps: [SystemApp] {
        SystemApp.allCases.filter { app in
            switch app {
            case .meloNX, .tetris, .slither: return false
            default: return true
            }
        }
    }

    // Dynamic Text Color for Custom Settings UI
    private var textColor: Color {
        return settings.customThemeIsDark ? .white : .black
    }

    private var previewColor: Color {
        if hue <= -0.15 { return .black }
        if hue <= -0.05 { return .white }
        return Color(hue: max(0, hue), saturation: saturation, brightness: 1.0)
    }
    
    // Computed property for correct brightness logic to pass to settings
    private var previewBrightness: Double {
        if hue <= -0.15 { return 0.0 }
        if hue <= -0.05 { return 1.0 }
        return 1.0 // Color
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                backgroundPreview
                mainContent
                
                if showMusicPicker {
                    MusicSelectionOverlay(
                        isPresented: $showMusicPicker,
                        selectionIndex: $musicSelectionIndex,
                        settings: settings
                    )
                        .zIndex(30)
                        .transition(.opacity)
                }
                
                if showConsoleList {
                    ConsoleSelectionOverlay(
                        isPresented: $showConsoleList,
                        selectedConsole: $selectedConsoleForIcon,
                        showIconPicker: $showConsoleIconPicker,
                        selectionIndex: $consoleSelectionIndex,
                        settings: settings
                    )
                        .zIndex(30)
                        .transition(.opacity)
                }
                
                if showSystemAppList {
                    SystemSelectionOverlay(
                        isPresented: $showSystemAppList,
                        settings: settings,
                        selectionIndex: $systemAppSelectionIndex,
                        slotSelectionIndex: $systemSlotSelectionIndex,
                        selectedApp: $selectedSystemApp,
                        targetSlot: $targetSystemSlot,
                        showIconPicker: $showSystemIconPicker
                    )
                    .zIndex(30)
                    .transition(.opacity)
                }
                
                if showShareOverlay {
                    ShareImportOverlay(
                        isPresented: $showShareOverlay,
                        selectionIndex: $shareSelectionIndex,
                        settings: settings,
                        onExport: {
                            AudioManager.shared.playSelectSound()
                            exportThemeToFile()
                        },
                        onImport: {
                            AudioManager.shared.playSelectSound()
                            showShareFileImporter = true
                        }
                    )
                    .zIndex(30)
                    .transition(.opacity)
                }
            }
        }
        .fileImporter(
            isPresented: $showShareFileImporter,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
             handleShareFileImport(result)
        }
        .sheet(item: $shareFileItem) { file in
             ThemeShareSheet(activityItems: [file.url])
        }
        .onAppear(perform: setupView)
        .onDisappear(perform: teardownView)
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("ThemeImported"))) { _ in
            // Refresh local state when import happens in overlay
            self.synchronizeControlsWithSettings()
            self.settingsChangeID = UUID()
            applyTheme()
        }
        .onChange(of: hue) { _ in updateColor(hue, save: true) }
        .onChange(of: saturation) { _ in updateColor(hue, save: true) }
        .onChange(of: opacity) { _ in updateColor(hue, save: true) } // Reuse updateColor to trigger save

        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhotoItem, matching: .any(of: [.images, .videos]))
        .onChange(of: selectedPhotoItem, perform: handlePhotoSelection)
        .photosPicker(isPresented: $showConsoleIconPicker, selection: $selectedConsolePhotoItem, matching: .images)
        .onChange(of: selectedConsolePhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let console = selectedConsoleForIcon {
                    
                    await MainActor.run {
                        settings.saveCustomConsoleIcon(image: image, for: console)
                        self.selectedConsolePhotoItem = nil
                        
                        self.showConsoleList = true
                        self.settingsChangeID = UUID()
                        AudioManager.shared.playSelectSound()
                    }
                }
            }
        }
        // System App Icon Picker
        .photosPicker(isPresented: $showSystemIconPicker, selection: $selectedSystemPhotoItem, matching: .images)
        .onChange(of: selectedSystemPhotoItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let _ = UIImage(data: data),
                   let app = selectedSystemApp,
                   let slot = targetSystemSlot {
                    
                   
                    
                    let key = getKey(for: app, slot: slot)
                    
                    await MainActor.run {
                        settings.saveCustomSystemIcon(data: data, for: key)
                        self.selectedSystemPhotoItem = nil
                        self.showSystemAppList = true
                        AudioManager.shared.playSelectSound()
                    }
                }
            }
        }
        .onChange(of: GameControllerManager.shared.dpadDown) { _, newValue in
             // System App Grid Logic (Single Press)
             if showSystemAppList && selectedSystemApp != nil {
                 if newValue { handleSystemAppGridDown() }
                 return
             }
             
             // Continuous Scroll Logic (Lists)
             if newValue {
                 moveSelection(direction: 1)
                 startScrolling(direction: 1)
             } else {
                 stopScrolling()
             }
        }
        .onChange(of: GameControllerManager.shared.dpadUp) { _, newValue in
             // System App Grid Logic (Single Press)
             if showSystemAppList && selectedSystemApp != nil {
                 if newValue { handleSystemAppGridUp() }
                 return
             }
             
             // Continuous Scroll Logic (Lists)
             if newValue {
                 moveSelection(direction: -1)
                 startScrolling(direction: -1)
             } else {
                 stopScrolling()
             }
        }
        .onChange(of: GameControllerManager.shared.dpadLeft) { _ in 
             if showSystemAppList { handleSystemAppDpadLeft() }
             else if !showMusicPicker && !showConsoleList && !showShareOverlay { handleDpadLeft() }
        }
        .onChange(of: GameControllerManager.shared.dpadRight) { _ in 
             if showSystemAppList { handleSystemAppDpadRight() }
             else if !showMusicPicker && !showConsoleList && !showShareOverlay { handleDpadRight() }
        }
        .onChange(of: GameControllerManager.shared.buttonAPressed) { _ in 
             if showMusicPicker { handleMusicSelect() } 
             else if showConsoleList { handleConsoleSelect() }
             else if showSystemAppList { handleSystemAppSelect() }
             else if showShareOverlay { handleShareSelect() }
             else { handleButtonA() }
        }
        .onChange(of: GameControllerManager.shared.buttonBPressed) { _ in 
             if !GameControllerManager.shared.buttonBPressed { return }
             if showMusicPicker { 
                 withAnimation { showMusicPicker = false }
                 AudioManager.shared.playSelectSound()
             } else if showConsoleList {
                 withAnimation { showConsoleList = false }
                 AudioManager.shared.playSelectSound()
             } else if showSystemAppList {
                 if selectedSystemApp != nil {
                     // Back from Detail -> List
                     withAnimation { 
                         selectedSystemApp = nil 
                         targetSystemSlot = nil
                     }
                     AudioManager.shared.playSelectSound()
                 } else {
                     // Back from List -> Main Menu
                     withAnimation { showSystemAppList = false }
                     AudioManager.shared.playSelectSound()
                 }
             } else if showShareOverlay {
                 withAnimation { showShareOverlay = false }
                 AudioManager.shared.playBackMusic()
             } else { handleButtonB() }
        }
        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
        .zIndex(20)
        // REMOVED OLD IMPORTER/SHEET MODIFIERS
        
        if isRestarting {
            ZStack {
                Color.black.opacity(0.8).ignoresSafeArea()
                VStack(spacing: 20) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(2)
                    Text("Restarting App...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Applying new theme...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .zIndex(100)
            .zIndex(100)
            .transition(.opacity)
        }
        
        if isImportingMedia {
             ZStack {
                 Color.black.opacity(0.8).ignoresSafeArea()
                 VStack(spacing: 20) {
                     ProgressView()
                         .progressViewStyle(CircularProgressViewStyle(tint: .white))
                         .scaleEffect(2)
                     Text("Processing Media...")
                         .font(.title2)
                         .fontWeight(.bold)
                         .foregroundColor(.white)
                     Text("Downloading from iCloud may take a moment")
                         .font(.subheadline)
                         .foregroundColor(.white.opacity(0.7))
                 }
             }
             .zIndex(100)
             .transition(.opacity)
        }
    }
    
    //  Input Handlers
    
    private func updateColor(_ newHue: Double, save: Bool = true) {
        var h: Double = 0
        var s: Double = 0
        
        if newHue <= -0.15 {
             h = 0; s = 0 
        } else if newHue <= -0.05 {
             h = 0; s = 0
        } else {
             h = newHue
             s = saturation
        }
        
        // Ephemeral Update to SettingsManager (Memory Only)
    
        settings.setCustomBubbleColor(hue: h, saturation: s, brightness: previewBrightness)
        settings.customBubbleOpacity = opacity
        
        // Force preview update via ID if needed (or rely on setting change if save=true)
        settingsChangeID = UUID()
    }
    

    
    private func getKey(for app: SystemApp, slot: SystemSelectionOverlay.IconSlot) -> String {
        let baseName: String
        switch slot {
        case .set1, .set1Click:
            baseName = app.iconName(for: 1)
        case .set2, .set2Click:
            baseName = app.iconName(for: 2)
        }
        switch slot {
        case .set1Click, .set2Click:
            let components = baseName.components(separatedBy: "_")
            if components.count > 1 {
                var newComp = components
                newComp.insert("OnClick", at: 1)
                return newComp.joined(separator: "_")
            } else {
                return baseName + "_OnClick"
            }
        default:
            return baseName
        }
    }

    private func startScrolling(direction: Int) {
        stopScrolling()
        scrollTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s delay
            while !Task.isCancelled {
                await MainActor.run { moveSelection(direction: direction) }
                try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s speed
            }
        }
    }
    
    private func stopScrolling() {
        scrollTask?.cancel()
        scrollTask = nil
    }
    
    private func moveSelection(direction: Int) {
        // 1. Music Picker
        if showMusicPicker {
             let maxIndex = MusicPlayerManager.shared.systemSongs.count - 1
             let newIndex = musicSelectionIndex + direction
             if newIndex >= 0 && newIndex <= maxIndex {
                 musicSelectionIndex = newIndex
                 AudioManager.shared.playMoveSound()
             }
             return
        }
        
        // 2. Console Picker
        if showConsoleList {
             let maxIndex = themableConsoles.count - 1
             let newIndex = consoleSelectionIndex + direction
             if newIndex >= 0 && newIndex <= maxIndex {
                 consoleSelectionIndex = newIndex
                 AudioManager.shared.playMoveSound()
             }
             return
        }
        
        // 3. System App Picker (List Mode Only)
        // Grid mode handled separately in onChange
        if showSystemAppList {
             let maxIndex = themableApps.count - 1
             let newIndex = systemAppSelectionIndex + direction
             if newIndex >= 0 && newIndex <= maxIndex {
                 systemAppSelectionIndex = newIndex
                 AudioManager.shared.playMoveSound()
             }
             return
        }
        
        // 4. Share Overlay
        if showShareOverlay {
             let newIndex = shareSelectionIndex + direction
             if newIndex >= 0 && newIndex <= 1 {
                 shareSelectionIndex = newIndex
                 AudioManager.shared.playMoveSound()
             }
             return
        }
        
        // 5. Main Menu
        let newRow = selectedRow + direction
        guard newRow >= 0 && newRow <= 14 else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            selectedRow = newRow
        }
        AudioManager.shared.playMoveSound()
    }
    
    private func handleDpadLeft() {
        if GameControllerManager.shared.dpadLeft {
            if showSystemAppList && selectedSystemApp != nil {
                 // Grid Navigation Left
                 if systemSlotSelectionIndex == 1 || systemSlotSelectionIndex == 3 {
                     systemSlotSelectionIndex -= 1
                     AudioManager.shared.playMoveSound()
                     return
                 }
            }
            
            if showMusicPicker || showConsoleList || showSystemAppList || showShareOverlay { return }
            
            if selectedRow == 1 {
                // Range extended to -0.2 (Black) -> -0.1 (White) -> 0.0 (Red)
                hue = max(-0.2, hue - 0.05)
            }
            if selectedRow == 2 {
                saturation = max(0.0, saturation - 0.1)
            }
            if selectedRow == 3 {
                opacity = max(0.0, opacity - 0.1)
            }
            if selectedRow == 4 {
                settings.customBubbleBlurBubbles.toggle()
            }
            if selectedRow == 5 {
                 settings.customShowDots.toggle()
            }
            if selectedRow == 6 {
                settings.useTransparentIcons.toggle()
            }
            if selectedRow == 7 {
                toggleDarken()
            }
            if selectedRow == 8 {
                toggleBlur()
            }
            if selectedRow == 10 {
                toggleTextColor()
            }
        }
    }
    
    private func handleDpadRight() {
        if GameControllerManager.shared.dpadRight {
             if showSystemAppList && selectedSystemApp != nil {
                  // Grid Navigation Right
                  if systemSlotSelectionIndex == 0 || systemSlotSelectionIndex == 2 {
                      systemSlotSelectionIndex += 1
                      AudioManager.shared.playMoveSound()
                      return
                  }
             }
             
             if selectedRow == 1 {
                 hue = min(1.0, hue + 0.05)
             }
             if selectedRow == 2 {
                 saturation = min(1.0, saturation + 0.1)
             }
            if selectedRow == 3 {
                 opacity = min(1.0, opacity + 0.1)
            }
            if selectedRow == 4 {
                 settings.customBubbleBlurBubbles.toggle()
            }
             if selectedRow == 5 {
                 settings.customShowDots.toggle()
             }
             if selectedRow == 6 {
                 settings.useTransparentIcons.toggle()
             }
              if selectedRow == 7 {
                  toggleDarken()
              }
              if selectedRow == 8 {
                  toggleBlur()
              }
              if selectedRow == 10 {
                  toggleTextColor()
              }
         }
    }
    
    private func handleButtonA() {
        if GameControllerManager.shared.buttonAPressed {
            if selectedRow == 0 { showPhotoPicker = true }
            if selectedRow == 1 { AudioManager.shared.playSelectSound() }
            if selectedRow == 2 { AudioManager.shared.playSelectSound() } // Saturation
            if selectedRow == 3 { AudioManager.shared.playSelectSound() } // Opacity
            if selectedRow == 4 {
                AudioManager.shared.playSelectSound()
                settings.customBubbleBlurBubbles.toggle()
            }
            if selectedRow == 5 {
                AudioManager.shared.playSelectSound()
                settings.customShowDots.toggle()
            }
            if selectedRow == 6 {
                AudioManager.shared.playSelectSound()
                toggleIcons()
            }
            if selectedRow == 7 {
                AudioManager.shared.playSelectSound()
                toggleDarken()
            }
            if selectedRow == 8 {
                AudioManager.shared.playSelectSound()
                toggleBlur()
            }
            if selectedRow == 9 {
                AudioManager.shared.playSelectSound()
                withAnimation { showMusicPicker = true }
            }
            if selectedRow == 10 {
                AudioManager.shared.playSelectSound()
                toggleTextColor()
            }
            if selectedRow == 11 {
                AudioManager.shared.playSelectSound()
                withAnimation { showConsoleList = true }
            }
            if selectedRow == 12 { // New ID for System Icons
                AudioManager.shared.playSelectSound()
                withAnimation { showSystemAppList = true }
            }
            if selectedRow == 13 {
                applyTheme()
            }
            if selectedRow == 14 {
                handleExportImport()
            }
        }
    }
    
    private func handleButtonB() {
         if GameControllerManager.shared.buttonBPressed {
             withAnimation { isPresented = false }
         }
    }
    
    // Photo Helper
    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }
        
        isImportingMedia = true
        
        Task {
            // Retrieve RAW Data to support GIFs
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    settings.saveCustomBackgroundImage(data: data)
                    AppStatusManager.shared.show("Background Updated", icon: "photo")
                    settingsChangeID = UUID() // Force Refresh
                    isImportingMedia = false
                }
            } else {
                await MainActor.run {
                     isImportingMedia = false
                }
            }
        }
    }
    
    // Logic Helpers
    
    var customBackgroundIsVideo: Bool {
        return settings.customBackgroundIsVideo
    }
    
    private func saveCustomBackgroundVideo(data: Data) {
        settings.saveCustomBackgroundImage(data: data)
    }

    private func cycleStyle(reverse: Bool = false) {
        let current = settings.customBubbleStyle.rawValue
        let newRaw: Int
        if reverse {
            newRaw = (current - 1 + 3) % 3
        } else {
            newRaw = (current + 1) % 3
        }
        settings.customBubbleStyle = SettingsManager.CustomBubbleStyle(rawValue: newRaw) ?? .blur
        AudioManager.shared.playSelectSound()
    }
    
    private func toggleDots() {
        settings.customShowDots.toggle()
        AudioManager.shared.playSelectSound()
        settingsChangeID = UUID() // Force Refresh
    }
    
    private func toggleIcons() {
        settings.useTransparentIcons.toggle()
        AudioManager.shared.playSelectSound()
        settingsChangeID = UUID() // Force Refresh
    }
    
    private func toggleDarken() {
        settings.customDarkenBackground.toggle()
        AudioManager.shared.playSelectSound()
        settingsChangeID = UUID() // Force Refresh
    }

    private func toggleBlur() {
        settings.customBlurBackground.toggle()
        AudioManager.shared.playSelectSound()
        settingsChangeID = UUID() // Force Refresh
    }
    
    private func toggleTextColor() {
        settings.customThemeIsDark.toggle()
        AudioManager.shared.playSelectSound()
        settingsChangeID = UUID() // Force Refresh
    }
    
    private func applyTheme() {
        AudioManager.shared.playSelectSound()
        
        // EXPLICIT SAVE COMMIT FIRST

        
        var finalHue = hue
        var finalSat = saturation
        var finalBri: Double = 1.0
        
        if hue <= -0.15 { 
            // Black
            finalHue = 0; finalSat = 0; finalBri = 0.0 
        } else if hue <= -0.05 { 
            // White
            finalHue = 0; finalSat = 0; finalBri = 1.0 
        }
        
        SettingsManager.shared.commitCustomTheme(
            hue: finalHue,
            saturation: finalSat,
            opacity: opacity,
            showDots: settings.customShowDots,
            blurBubbles: settings.customBubbleBlurBubbles,
            darkenBG: settings.customDarkenBackground, 
            blurBG: settings.customBlurBackground,
            brightness: finalBri,
            transparentIcons: settings.useTransparentIcons,
            isDark: settings.customThemeIsDark
        )
        
        // Ensure custom theme is active (triggers reload from newly saved JSON)
        SettingsManager.shared.activeThemeID = "custom_photo"
        
        // Debug Verification
        print(" Applying Theme - Verification (After Commit):")
        print("   - Color Hue: \(SettingsManager.shared.customBubbleHue)")
        print("   - Color Sat: \(SettingsManager.shared.customBubbleSaturation)")
        print("   - Opacity: \(SettingsManager.shared.customBubbleOpacity)")
        print("   - Dots: \(SettingsManager.shared.customShowDots)")
        print("   - Blur Bubbles: \(SettingsManager.shared.customBubbleBlurBubbles)")
        
        withAnimation {
             isRestarting = true
        }
        
        // Delay exit to show animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
             exit(0)
        }
    }
    
    //  Legacy / Manual Handlers
    
    // Grid Handlers
    private func handleSystemAppGridDown() {
         // Grid Navigation (0,1 -> 2,3 -> 4)
         if systemSlotSelectionIndex < 2 {
             systemSlotSelectionIndex += 2 
             AudioManager.shared.playMoveSound()
         } else if systemSlotSelectionIndex < 4 {
             systemSlotSelectionIndex = 4
             AudioManager.shared.playMoveSound()
         }
    }
    
    private func handleSystemAppGridUp() {
         if systemSlotSelectionIndex == 4 {
             systemSlotSelectionIndex = 2 
             AudioManager.shared.playMoveSound()
         } else if systemSlotSelectionIndex >= 2 {
             systemSlotSelectionIndex -= 2
             AudioManager.shared.playMoveSound()
         }
    }
    
    // Stubbed legacy handlers (replaced by moveSelection)
    private func handleMusicDpadDown() {}
    private func handleMusicDpadUp() {}
    private func handleConsoleDpadDown() {}
    private func handleConsoleDpadUp() {}
    private func handleShareDpadDown() {}
    private func handleShareDpadUp() {}
    private func handleSystemAppDpadDown() {}
    private func handleSystemAppDpadUp() {}

    // Selection Handlers
    
    private func handleMusicSelect() {
        if GameControllerManager.shared.buttonAPressed {
             let songs = MusicPlayerManager.shared.systemSongs
             if songs.indices.contains(musicSelectionIndex) {
                 let song = songs[musicSelectionIndex]
                 settings.customThemeMusic = song.fileName
                 AudioManager.shared.playSelectSound()
                 withAnimation { showMusicPicker = false }
             }
        }
    }
    
    private func handleConsoleSelect() {
        if GameControllerManager.shared.buttonAPressed {
             let consoles = themableConsoles
             if consoles.indices.contains(consoleSelectionIndex) {
                 let console = consoles[consoleSelectionIndex]
                 selectedConsoleForIcon = console
                 showConsoleIconPicker = true
                 AudioManager.shared.playSelectSound()
                 // Keep list open for continuous editing
                 // withAnimation { showConsoleList = false }
             }
        }
    }

    // Grid System Handlers
    private func handleSystemAppDpadLeft() {
        if !GameControllerManager.shared.dpadLeft { return }
        
        if selectedSystemApp != nil {
             if systemSlotSelectionIndex == 1 || systemSlotSelectionIndex == 3 {
                 systemSlotSelectionIndex -= 1
                 AudioManager.shared.playMoveSound()
             }
        }
    }

    private func handleSystemAppDpadRight() {
        if !GameControllerManager.shared.dpadRight { return }
        
        if selectedSystemApp != nil {
             if systemSlotSelectionIndex == 0 || systemSlotSelectionIndex == 2 {
                 systemSlotSelectionIndex += 1
                 AudioManager.shared.playMoveSound()
             }
        }
    }
    
    private func handleSystemAppSelect() {
        if !GameControllerManager.shared.buttonAPressed { return }
        
        if let app = selectedSystemApp {
            // In Slots
            if systemSlotSelectionIndex == 4 {
                // Reset
                settings.resetCustomSystemIcon(for: getKey(for: app, slot: .set1))
                settings.resetCustomSystemIcon(for: getKey(for: app, slot: .set1Click))
                settings.resetCustomSystemIcon(for: getKey(for: app, slot: .set2))
                settings.resetCustomSystemIcon(for: getKey(for: app, slot: .set2Click))
                AudioManager.shared.playSelectSound()
            } else {
                // Select Slot
                let slots: [SystemSelectionOverlay.IconSlot] = [.set1, .set1Click, .set2, .set2Click]
                if systemSlotSelectionIndex < slots.count {
                    targetSystemSlot = slots[systemSlotSelectionIndex]
                    showSystemIconPicker = true
                    AudioManager.shared.playSelectSound()
                }
            }
        } else {
            // In App List
            let apps = themableApps
            if apps.indices.contains(systemAppSelectionIndex) {
                 selectedSystemApp = apps[systemAppSelectionIndex]
                 systemSlotSelectionIndex = 0 // Reset slot index
                 AudioManager.shared.playSelectSound()
            }
        }
    }

    // Share Picker Logic
    
    // Legacy handlers stubbed
    // private func handleShareDpadDown() {} 
    // private func handleShareDpadUp() {}
    
    private func handleShareSelect() {
        if GameControllerManager.shared.buttonAPressed {
             AudioManager.shared.playSelectSound()
             if shareSelectionIndex == 0 {
                 exportThemeToFile()
             } else {
                 showShareFileImporter = true
             }
        }
    }
    
    private func exportThemeToFile() {
        guard let jsonString = settings.exportTheme() else {
             AppStatusManager.shared.show("Export Failed", icon: "xmark.circle")
             return
        }
        
        // Clean filename from music/content
        let fileName = "MyCustomTheme.json"
        
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = dir.appendingPathComponent(fileName)
            
            do {
                try jsonString.write(to: fileURL, atomically: true, encoding: .utf8)
                AppStatusManager.shared.show("Theme Saved!", icon: "checkmark.circle")
                self.shareFileItem = ShareFile(url: fileURL)
            } catch {
                print("Failed to write theme file: \(error)")
                AppStatusManager.shared.show("Write Failed", icon: "xmark.octagon")
            }
        }
    }
    
    private func handleShareFileImport(_ result: Result<[URL], Error>) {
        do {
            guard let selectedFile: URL = try result.get().first else { return }
            
            if selectedFile.startAccessingSecurityScopedResource() {
                defer { selectedFile.stopAccessingSecurityScopedResource() }
                
                let data = try Data(contentsOf: selectedFile)
                if let jsonString = String(data: data, encoding: .utf8) {
                    // Pass original filename to preserve identity
                    if settings.importTheme(jsonString: jsonString, filename: selectedFile.lastPathComponent) {
                        AppStatusManager.shared.show("Theme Imported!", icon: "checkmark.circle")
                        
                        // Trigger local refresh via Notification (or direct update)
                        NotificationCenter.default.post(name: Notification.Name("ThemeImported"), object: nil)
                        
                        // Close overlay
                        withAnimation { showShareOverlay = false }
                        
                    } else {
                         AppStatusManager.shared.show("Import Logic Failed", icon: "xmark.circle")
                    }
                }
            } else {
                 AppStatusManager.shared.show("Access Denied", icon: "lock.fill")
            }
        } catch {
            print(" Import Error: \(error)")
            AppStatusManager.shared.show("Import Error", icon: "exclamationmark.triangle")
        }
    }
    
    //  Subviews
    
    
    @State private var settingsChangeID = UUID()
    
    private var backgroundPreview: some View {
        CustomThemeView()
            .ignoresSafeArea()
            .id(settingsChangeID)
    }



    
    private var mainContent: some View {
        GeometryReader { geo in
            let isLandscape = geo.size.width > geo.size.height
            
            if isLandscape {
                // Landscape Layout
                HStack(spacing: 20) {
                    ScrollViewReader { scroller in
                        ScrollView(.vertical, showsIndicators: false) {
                            optionsColumn
                                .padding(.vertical, 40)
                                .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: 300)
                        .onChange(of: selectedRow) { _, newRow in
                            withAnimation { scroller.scrollTo(newRow, anchor: .center) }
                        }
                    }
                    
                    ZStack(alignment: .bottomTrailing) {
                        VStack {
                            Spacer()
                            previewColumn
                                .scaleEffect(0.9)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                        footer
                            .padding(.bottom, 4)
                            .padding(.trailing, 20)
                            .onTapGesture {
                                withAnimation { isPresented = false }
                            }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal)
            } else {
                // Portrait Layout - Scrollable & Centered
                ScrollViewReader { scroller in
                    ZStack {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 24) {
                                Spacer().frame(height: 40)
                                optionsColumn
                                Spacer().frame(height: 100) // Space for footer
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: geo.size.height, alignment: .center)
                        }
                        
                        // Floating Footer
                        VStack {
                            Spacer()
                            footer
                                .scaleEffect(1.3) // Make it bigger
                                .onTapGesture {
                                    withAnimation { isPresented = false }
                                }
                        }
                    }
                    .onChange(of: selectedRow) { _, newRow in
                        withAnimation { scroller.scrollTo(newRow, anchor: .center) }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var optionsColumn: some View {
        VStack(spacing: 16) {
            photoOptionButton.id(0)
            colorOptionSlider.id(1)
            saturationOptionSlider.id(2)
            opacityOptionSlider.id(3)
            blurBubblesOptionButton.id(4)
            dotsOptionButton.id(5)
            iconsOptionButton.id(6)
            darkenOptionButton.id(7)
            blurOptionButton.id(8)
            musicOptionButton.id(9)
            textColorOptionButton.id(10)
            consoleIconsOptionButton.id(11)
            systemIconsOptionButton.id(12)
            applyThemeButton.id(13)
            exportImportButton.id(14)
        }
        .foregroundColor(textColor)
    }
    
    private var photoOptionButton: some View {
        Button(action: {
            selectedRow = 0
            showPhotoPicker = true
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                VStack {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                    Text("Wallpaper")
                        .font(.subheadline)
                        .opacity(0.9)
                }
            }
            .frame(width: 200, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 0 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 0 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var colorOptionSlider: some View {
        VStack {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                VStack(spacing: 8) {
                    Text("Bubble Color")
                        .font(.subheadline)
                    
                    hueSliderVisual
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedRow = 1
                                    let location = value.location.x
                                    let sliderWidth: CGFloat = 180
                                    let gradientStart: CGFloat = 44
                                    let gradientWidth: CGFloat = 136 - 10
                                    
                                    if location < 20 {
                                        hue = -0.2
                                    } else if location < 44 {
                                        hue = -0.1
                                    } else {
                                        let progress = (location - gradientStart) / gradientWidth
                                        hue = min(max(Double(progress), 0.0), 1.0)
                                    }
                                    // Live update color for preview without saving
                                    updateColor(hue, save: false)
                                }
                                .onEnded { _ in
                                    // Save on release
                                    updateColor(hue, save: true)
                                }
                        )
                }
            }
            .frame(width: 200, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 1 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 1 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
            .onTapGesture { selectedRow = 1 }
        }
    }
    
    private var saturationOptionSlider: some View {
        VStack {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                VStack(spacing: 8) {
                    Text("Saturation")
                        .font(.subheadline)
                    
                    saturationSliderVisual
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedRow = 2
                                    let location = value.location.x
                                    let sliderWidth: CGFloat = 180
                                    let progress = location / sliderWidth
                                    saturation = min(max(Double(progress), 0.0), 1.0)
                                    // Live update color for preview without saving
                                    updateColor(hue, save: false)
                                }
                                .onEnded { _ in
                                    // Save on release
                                    updateColor(hue, save: true)
                                }
                        )
                }
            }
            .frame(width: 200, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 2 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 2 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
            .onTapGesture { selectedRow = 2 }
        }
    }

    private var opacityOptionSlider: some View {
        VStack {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor, 
                    overrideShowDots: settings.customShowDots,
                    overrideOpacity: opacity,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                        .id(settingsChangeID)
                VStack(spacing: 8) {
                    Text("Opacity")
                        .font(.subheadline)
                    
                    opacitySliderVisual
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    selectedRow = 3
                                    let location = value.location.x
                                    let sliderWidth: CGFloat = 180
                                    let progress = location / sliderWidth
                                    opacity = min(max(Double(progress), 0.0), 1.0)
                                    // Live update
                                    updateColor(hue, save: false)
                                }
                                .onEnded { _ in
                                    updateColor(hue, save: true)
                                }
                        )
                }
            }
            .frame(width: 200, height: 80)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 3 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 3 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
            .onTapGesture { selectedRow = 3 }
        }
    }
    
    private var blurBubblesOptionButton: some View {
        Button(action: {
            selectedRow = 4
            settings.customBubbleBlurBubbles.toggle()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    Text("Blur Bubbles")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: settings.customBubbleBlurBubbles ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(settings.customBubbleBlurBubbles ? .green : .gray)
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 4 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 4 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var opacitySliderVisual: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(textColor.opacity(0.3))
                .frame(width: 180, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(textColor.opacity(0.3), lineWidth: 1))
            
            // Fill
            RoundedRectangle(cornerRadius: 8)
                .fill(textColor)
                .frame(width: CGFloat(opacity) * 180, height: 20)
        }
        .frame(width: 180)
    }

    private var dotsOptionButton: some View {
        Button(action: {
            selectedRow = 5
            toggleDots()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    Text("Dots Pattern")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: settings.customShowDots ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(settings.customShowDots ? .green : .gray)
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 5 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 5 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconsOptionButton: some View {
        Button(action: {
            selectedRow = 6
            toggleIcons()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Icons Style")
                            .font(.subheadline)
                        Text(settings.useTransparentIcons ? "Transparent" : "Solid")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: settings.useTransparentIcons ? "square.dashed" : "square.fill")
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 6 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 6 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var darkenOptionButton: some View {
        Button(action: {
            selectedRow = 7
            toggleDarken()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    Text("Darken Background")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: settings.customDarkenBackground ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(settings.customDarkenBackground ? .green : .gray)
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 7 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 7 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var blurOptionButton: some View {
        Button(action: {
            selectedRow = 8
            toggleBlur()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    Text("Blur Background")
                        .font(.subheadline)
                    Spacer()
                    Image(systemName: settings.customBlurBackground ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(settings.customBlurBackground ? .green : .gray)
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 8 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 8 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var musicOptionButton: some View {
        Button(action: {
            selectedRow = 9
            withAnimation { showMusicPicker = true }
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Background Music")
                            .font(.subheadline)
                        Text(settings.customThemeMusic?.replacingOccurrences(of: "_", with: " ").capitalized ?? "Default")
                            .font(.caption2)
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "music.note")
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 9 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 9 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var textColorOptionButton: some View {
        Button(action: {
            selectedRow = 10
            toggleTextColor()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Text Color")
                            .font(.subheadline)
                        Text(settings.customThemeIsDark ? "White (Dark Mode)" : "Black (Light Mode)")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: settings.customThemeIsDark ? "moon.fill" : "sun.max.fill")
                        .foregroundColor(settings.customThemeIsDark ? .white : .yellow)
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 10 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 10 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var consoleIconsOptionButton: some View {
        Button(action: {
            selectedRow = 11
            withAnimation { showConsoleList = true }
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Console Icons")
                            .font(.subheadline)
                        Text("Customize")
                            .font(.caption2)
                            .opacity(0.7)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "gamecontroller")
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 11 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 11 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // NEW SYSTEM ICON BUTTON
    private var systemIconsOptionButton: some View {
        Button(action: {
            selectedRow = 12
            withAnimation { showSystemAppList = true }
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("App Icons")
                            .font(.subheadline)
                        Text("Custom Symbols")
                            .font(.caption2)
                            .opacity(0.7)
                    }
                    Spacer()
                    Image(systemName: "square.grid.2x2")
                }
                .padding(.horizontal)
            }
            .frame(width: 200, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 12 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 12 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var applyThemeButton: some View {
        Button(action: {
            selectedRow = 13
            applyTheme()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                
                HStack(spacing: 12) {
                    Image(systemName: "power.circle.fill")
                        .font(.title3)
                        .foregroundColor(.red)
                    Text("Restart Required")
                        .font(.headline)
                        // Inherits textColor from optionsColumn
                }
            }
            .frame(width: 200, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 13 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 13 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var exportImportButton: some View {
        Button(action: {
            selectedRow = 14
            handleExportImport()
        }) {
            ZStack {
                BubbleBackground(
                    cornerRadius: 16, 
                    theme: ThemeRegistry.customTheme, 
                    overrideColor: previewColor,
                    overrideShowDots: settings.customShowDots,
                    overrideBlurBubbles: settings.customBubbleBlurBubbles
                )
                    .id(settingsChangeID)
                
                HStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                    Text("Share / Import Theme")
                        .font(.headline)
                }
            }
            .frame(width: 200, height: 60)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(textColor, lineWidth: selectedRow == 14 ? 4 : 0)
            )
            .scaleEffect(selectedRow == 14 ? 1.05 : 1.0)
            .animation(.spring(), value: selectedRow)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func handleExportImport() {
        AudioManager.shared.playSelectSound()
        withAnimation { showShareOverlay = true }
    }

    // Helper for Share Sheet
    struct ShareSheet: UIViewControllerRepresentable {
        var activityItems: [Any]
        var applicationActivities: [UIActivity]? = nil

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
            return controller
        }

        func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
    }

    private var hueSliderVisual: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 2) {
                // Black Option
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black)
                    .frame(width: 20, height: 20)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.3), lineWidth: 1))
                
                // White Option
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                
                // Hue Gradient (Reduced width from 170 to 124 to fit 20+2+20+2 = 44px of new buttons within ~170 total)
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(gradient: Gradient(colors: [
                            Color(hue: 0, saturation: 1, brightness: 1),
                            Color(hue: 0.1, saturation: 1, brightness: 1),
                            Color(hue: 0.2, saturation: 1, brightness: 1),
                            Color(hue: 0.3, saturation: 1, brightness: 1),
                            Color(hue: 0.4, saturation: 1, brightness: 1),
                            Color(hue: 0.5, saturation: 1, brightness: 1),
                            Color(hue: 0.6, saturation: 1, brightness: 1),
                            Color(hue: 0.7, saturation: 1, brightness: 1),
                            Color(hue: 0.8, saturation: 1, brightness: 1),
                            Color(hue: 0.9, saturation: 1, brightness: 1),
                            Color(hue: 1.0, saturation: 1, brightness: 1)
                        ]), startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(height: 20)
            }
            .frame(width: 180) // Slightly wider overall
            
            // Indicator
            // Mapping:
            // -0.2 -> Black Center (approx x=10)
            // -0.1 -> White Center (approx x=32)
            // 0.0 -> Gradient Start (approx x=54)
            // 1.0 -> Gradient End (approx x=180)
            
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white, lineWidth: 2)
                .background(Color.white)
                .frame(width: 10, height: 26)
                .offset(x: indicatorOffset)
        }
        .frame(width: 180)
    }
    
    private var indicatorOffset: CGFloat {
        if hue <= -0.15 { return 5 } // Center of first block (20px wide) -> 10px, minus half indicator (5) -> 5
        if hue <= -0.05 { return 27 } // 20 + 2 + 10 -> 32, minus 5 -> 27
        // Gradient starts at 20 + 2 + 20 + 2 = 44
        // Gradient width ~ 136 (180 - 44)
        // Hue 0.0 -> 44 + 5 (margin?) -> 49 minus 5 -> 44
        let gradientStart: CGFloat = 44
        let gradientWidth: CGFloat = 136 - 10 // Minus indicator width
        return gradientStart + (CGFloat(max(0, hue)) * gradientWidth)
    }

    private var saturationSliderVisual: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(gradient: Gradient(colors: [
                        Color(hue: max(0, hue), saturation: 0, brightness: 1), // Gray (Desaturated)
                        Color(hue: max(0, hue), saturation: 1, brightness: 1)  // Full Color
                    ]), startPoint: .leading, endPoint: .trailing)
                )
                .frame(width: 180, height: 20)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.3), lineWidth: 1))
            
            // Indicator
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white, lineWidth: 2)
                .background(Color.white)
                .frame(width: 10, height: 26)
                .offset(x: CGFloat(saturation) * (180 - 10))
        }
        .frame(width: 180)
    }

    private var previewColumn: some View {
        VStack {
            Text("Preview")
                .font(.caption)
                .opacity(0.7)
                .padding(.bottom, 4)
            
            ZStack {
                // Simulate a UI Card
                BubbleBackground(cornerRadius: 16, theme: ThemeRegistry.customTheme, overrideColor: previewColor)
                    .id(settingsChangeID) // FORCE REFRESH
                    .frame(width: 240, height: 140)
                    .overlay(
                        VStack {
                            HStack {
                                Circle().fill(textColor.opacity(0.3)).frame(width: 30, height: 30)
                                RoundedRectangle(cornerRadius: 4).fill(textColor.opacity(0.3)).frame(height: 12)
                                Spacer()
                            }
                            Spacer()
                            RoundedRectangle(cornerRadius: 4).fill(textColor.opacity(0.2)).frame(height: 8)
                            RoundedRectangle(cornerRadius: 4).fill(textColor.opacity(0.2)).frame(height: 8)
                        }
                        .padding()
                    )
            }
        }
        .foregroundColor(textColor)
    }
    
    private var footer: some View {
        ControlCard(actions: [
            ControlAction(icon: "b.circle", label: "Back", action: { withAnimation { isPresented = false } })
        ])
        .padding(.bottom, 40)
    }
    
    // Lifecycle & Logic
    
    private func setupView() {
        synchronizeControlsWithSettings()
        gameController.disableHomeNavigation = true
    }
    
    private func synchronizeControlsWithSettings() {
        // Load directly from saved HSB values
        let savedHue = settings.customBubbleHue
        let savedSat = settings.customBubbleSaturation
        let savedBri = settings.customBubbleBrightness
        
        // Reverse mapping for Black/White "Special Zones"

        if savedBri < 0.1 {
            // Restore Black Slider Position
            self.hue = -0.2
            self.saturation = savedSat
        } else if savedSat < 0.05 && savedBri > 0.9 && savedHue == 0 {
             // Restore White Slider Position (Only if Hue is 0, otherwise it might be a desaturated color)
             // Prioritize "White Mode" for pure white
            self.hue = -0.1
            self.saturation = savedSat
        } else {
             // Restore Color Position
             self.hue = savedHue
             self.saturation = savedSat
        }
        
        self.opacity = settings.customBubbleOpacity // Load Saved Opacity
    }
    
    private func teardownView() {
        // Do not re-enable home navigation here. 
        // The parent view (ThemeManagerView) handles this state and needs it to remain disabled.
    }
}
