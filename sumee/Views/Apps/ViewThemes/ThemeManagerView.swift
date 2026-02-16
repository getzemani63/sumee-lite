import SwiftUI
import PhotosUI

struct ThemeManagerView: View {
    @Binding var isPresented: Bool
    @ObservedObject private var gameController = GameControllerManager.shared
    @ObservedObject private var settings = SettingsManager.shared
    
    @Environment(\.colorScheme) var colorScheme

    @State private var selectedIndex: Int = 0
    @State private var scrollID: Int?
    @State private var showContent = false
    
    // Custom Settings State
    @State private var showCustomSettings = false
    @State private var scrollTask: Task<Void, Never>?
    @State private var isInitialLoad = true
   
    
    // Data Source
    @State private var cachedThemes: [AppTheme] = []
    
    private var themes: [AppTheme] {
        return cachedThemes
    }
    
    var body: some View {
        GeometryReader { mainGeo in
            let isPortrait = mainGeo.size.height > mainGeo.size.width
            
            ZStack(alignment: .top) {
                // 1. Main Interaction Content
                attachInputHandlers(
                    to: mainContent(isPortrait: isPortrait, size: mainGeo.size)
                )
                
                // 2. HUD Overlay (Controls)
                // Positioned absolutely on top of everything
                ThemeControlsView(
                    isPortrait: isPortrait,
                    isPresented: $isPresented,
                    showContent: $showContent,
                    showCustomSettings: $showCustomSettings,
                    settings: settings
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea() // Ensure overlay extends to screen edges
                .allowsHitTesting(true) // Ensure buttons receive touches
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .fullScreenCover(isPresented: $showCustomSettings) {
             CustomThemeSettingsView(isPresented: $showCustomSettings)
        }

        .onAppear {
            loadThemes()
        }
        .onChange(of: isPresented) { _, presented in
            if presented { loadThemes() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ThemeImported"))) { _ in
            loadThemes()
        }
    }
    
    // Subviews
    
    private func mainContent(isPortrait: Bool, size: CGSize) -> some View {
        let cardWidth = min(size.width - 40, isPortrait ? 420 : 480)
        let listHeight = isPortrait ? (size.height * 0.55) : (size.height * 0.7)
        
        let themeList = VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(themes.indices, id: \.self) { index in
                            let theme = themes[index]
                            let isActive = isThemeActive(theme)
                            let isFocused = (selectedIndex == index)
                            
                            // Visual Separator Logic
                            let isFirstImported = theme.id.hasPrefix("imported_") && 
                                                  (index == 0 || !themes[index - 1].id.hasPrefix("imported_"))
                            
                            VStack(spacing: 12) {
                                if isFirstImported {
                                    HStack {
                                        Text("Imported Themes")
                                            .font(.system(size: 14, weight: .bold, design: .rounded))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 8)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 4)
                                }
                                
                                Button(action: {
                                    guard isPresented else { return }
                                    selectedIndex = index
                                    applyTheme(themes[index])
                                }) {
                                    HStack {
                                        // Icon
                                        ZStack {
                                            Image(systemName: isActive ? "paintbrush.fill" : theme.icon)
                                                .foregroundColor(isFocused ? focusedContrastColor(for: theme) : (isActive ? theme.color : .gray))
                                        }
                                        .frame(width: 24, height: 24)
                                        
                                        // Text
                                        Text(theme.displayName)
                                            .font(.system(size: 16, weight: .bold, design: .rounded))
                                            .foregroundColor(isFocused ? focusedContrastColor(for: theme) : .primary)
                                            .lineLimit(1)
                                        
                                        Spacer()
                                        
                                        if isActive {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(isFocused ? focusedContrastColor(for: theme) : theme.color)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 50)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18)
                                            .fill(isFocused ? theme.color : (colorScheme == .dark ? Color(white: 0.2) : Color(white: 0.95)))
                                    )
                                    // Rotating Border for Focus
                                    .rotatingBorder(isSelected: isFocused, lineWidth: 4)
                                    .scaleEffect(isFocused ? 1.02 : 1.0)
                                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isFocused)
                                }
                                .buttonStyle(.plain)
                            }
                            .id(index)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 24)
                }
                .frame(height: listHeight)
                .onChange(of: selectedIndex) { _, newIndex in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                    // Haptic on scroll
                    if !isInitialLoad {
                        AudioManager.shared.playMoveSound()
                    }
                }
            }
        }
        .frame(width: cardWidth)
        .background(colorScheme == .dark ? Color(red: 44/255, green: 44/255, blue: 46/255) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.3 : 0.1), radius: 20, x: 0, y: 10)
        .opacity(showContent ? 1 : 0)
        .scaleEffect(showContent ? 1 : 0.95)
        .animation(.easeOut(duration: 0.3), value: showContent)
        
        return ZStack(alignment: .top) {
            if isPortrait {
                VStack(spacing: 24) {
                    Spacer()
                        .frame(height: 120) // HeadView Clearance
                    
                    Text("Choose your theme")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(settings.activeTheme.isDark ? .white : .black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(
                            BubbleBackground(cornerRadius: 20)
                        )
                        .zIndex(1)
                    
                    themeList
                    
                    Spacer()
                }
            } else {
                themeList
                     .position(x: size.width / 2, y: (size.height / 2) + 20)
            }
        }
    }
    
    // iconToggleView removed
    
    // Input Handlers
    
    private func attachInputHandlers(to view: some View) -> some View {
        view
            .onAppear {
                if let index = themes.firstIndex(where: { isThemeActive($0) }) {
                    selectedIndex = index
                }
                gameController.disableHomeNavigation = true
                withAnimation {
                    showContent = true
                }
                
                // Disable initial load flag after view settles
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isInitialLoad = false
                }
            }
            .onDisappear {
                stopScrolling()
                gameController.disableHomeNavigation = false
            }
            .onChange(of: gameController.buttonAPressed) { oldValue, newValue in
                guard isPresented && showContent && !showCustomSettings else { return }
                if newValue {
                    applyTheme(themes[selectedIndex])
                }
            }
            .onChange(of: gameController.buttonBPressed) { oldValue, newValue in
                // If custom settings is open, it handles B. We ignore it here.
                guard isPresented && showContent && !showCustomSettings else { return }
                if newValue {
                    withAnimation(.easeOut(duration: 0.4)) {
                        isPresented = false
                    }
                }
            }
            .onChange(of: gameController.buttonYPressed) { oldValue, newValue in
                guard isPresented && showContent else { return }
                
                if newValue {
                    handleYAction()
                }
            }
            .onChange(of: gameController.dpadDown) { oldValue, newValue in
                guard isPresented && showContent && !showCustomSettings else { 
                    stopScrolling()
                    return 
                }
                if newValue {
                     moveSelection(direction: 1)
                     startScrolling(direction: 1)
                } else {
                     stopScrolling()
                }
            }
            .onChange(of: gameController.dpadUp) { oldValue, newValue in
                guard isPresented && showContent && !showCustomSettings else { 
                    stopScrolling()
                    return 
                }
                if newValue {
                     moveSelection(direction: -1)
                     startScrolling(direction: -1)
                } else {
                     stopScrolling()
                }
            }
    }
    
    //Integration Logic

    private func startScrolling(direction: Int) {
        stopScrolling()
        scrollTask = Task {
            // Initial delay before repeating
            try? await Task.sleep(nanoseconds: 400_000_000) // 0.4s
            
            while !Task.isCancelled {
                await MainActor.run {
                    moveSelection(direction: direction)
                }
                // Scroll speed
                try? await Task.sleep(nanoseconds: 120_000_000) // 0.12s
            }
        }
    }
    
    private func stopScrolling() {
        scrollTask?.cancel()
        scrollTask = nil
    }
    
    private func moveSelection(direction: Int) {
        let current = selectedIndex 
        let newIndex = current + direction
        guard themes.indices.contains(newIndex) else { return }
        
        withAnimation(.spring(response: 0.3, dampingFraction: 1.0)) {
            selectedIndex = newIndex
        }
    }
    
    private func isThemeActive(_ theme: AppTheme) -> Bool {
        return settings.activeThemeID == theme.id
    }
    
    private func applyTheme(_ theme: AppTheme) {
        // Special Handling for Imported Themes
        if theme.id.hasPrefix("imported_") {
            if SettingsManager.shared.loadImportedTheme(id: theme.id) {
                // Success - The imported theme replaces the current "Custom Photo" theme
                // So we set the ID to "custom_photo" (the one SettingsManager uses for custom themes)
                settings.activeThemeID = "custom_photo"
                
                // Force Background Update (Notify Global Observers if any)
                NotificationCenter.default.post(name: NSNotification.Name("ThemeChanged"), object: nil)
                
                AppStatusManager.shared.show("Applied: \(theme.displayName)", icon: "paintbrush.fill")
                AudioManager.shared.playSelectSound()
                AudioManager.shared.playBackgroundMusic()
            } else {
                AppStatusManager.shared.show("Failed to Load Theme", icon: "exclamationmark.triangle")
            }
            return
        }
        
        settings.activeThemeID = theme.id
        AppStatusManager.shared.show("Applied: \(theme.displayName)", icon: "paintbrush.fill")
        AudioManager.shared.playSelectSound()
        // Refresh Music
        AudioManager.shared.playBackgroundMusic()
    }

    private func loadThemes() {
        // Load in background to avoid stutter
        Task {
            let loaded = ThemeRegistry.allThemes.filter { ThemeRegistry.isInstalled($0) }
            await MainActor.run {
                self.cachedThemes = loaded
            }
        }
    }
    
    private func focusedContrastColor(for theme: AppTheme) -> Color {
        let lightThemes = ["grid", "standard"]
        if lightThemes.contains(theme.id) && colorScheme == .light {
            return .black
        }
        return .white
    }
    
    // MARK: - Handlers
    
    private func handleYAction() {
         guard themes.indices.contains(selectedIndex) else { return }
         let theme = themes[selectedIndex]
         
         // Custom Theme: Edit
         if theme.id == "custom_photo" {
             withAnimation { showCustomSettings = true }
             return
         }
         
         // Protection: Cannot delete active theme
         if theme.id == settings.activeThemeID {
            AppStatusManager.shared.show("Active", icon: "checkmark")
             return
         }
         
         // Protection: System Themes
         let protectedThemes = ["grid", "standard", "dark_mode"]
         if protectedThemes.contains(theme.id) {
             AppStatusManager.shared.show("System Theme", icon: "lock.fill")
             return
         }
         
         // Delete Action
         ThemeRegistry.uninstall(theme)
         AppStatusManager.shared.show("Deleted", icon: "trash")
         
         // Adjust Selection if outside bounds after deletion
         if selectedIndex >= themes.count {
             selectedIndex = max(0, themes.count - 1)
         }
    }

}

struct ThemeListItem: View {
    let theme: AppTheme
    let isSelected: Bool
    let isActive: Bool
    @ObservedObject private var settings = SettingsManager.shared
    
    private var contrastColor: Color {
        if theme.id == "custom_photo" {
            return settings.customThemeIsDark ? .white : .black
        }
        let lightThemeIDs = ["standard", "grid", "new_year", "transparent_icons"]
        return lightThemeIDs.contains(theme.id) ? .black : .white
    }
    
    // Explicit solid colors for cards to avoid transparency issues
    private var cardColor: Color {
        switch theme.id {
        case "standard": return .white
        case "grid": return Color(white: 0.92)
        case "transparent_icons": return Color(white: 0.8)
        case "dark_mode": return Color(white: 0.15)
        case "sumee_xmb_black": return Color(white: 0.12)
        default: return theme.color
        }
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(contrastColor.opacity(0.1))
                    .frame(width: 50, height: 50)
                
                Image(systemName: theme.icon)
                    .font(.system(size: 24))
                    .foregroundColor(contrastColor)
            }
            // Icon scale removed to rely on parent scrollTransition
            
            VStack(alignment: .leading, spacing: 4) {
                Text(theme.displayName)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    // Opacity handled by parent scrollTransition
                    .foregroundColor(contrastColor) 
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                
                if isActive {
                     Text("Active")
                        .font(.caption)
                        .foregroundColor(contrastColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(contrastColor.opacity(0.2))
                        .cornerRadius(4)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(cardColor)
               
                .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        )
        
    }
}

struct ThemeControlsView: View {
    let isPortrait: Bool
    @Binding var isPresented: Bool
    @Binding var showContent: Bool
    @Binding var showCustomSettings: Bool
    @ObservedObject var settings: SettingsManager
    
    // Reusable Back Action
    private var backButton: ControlAction {
        ControlAction(icon: "b.circle", label: "Back", action: {
            guard isPresented else { return }
            AudioManager.shared.playBackMusic()
            withAnimation(.easeOut(duration: 0.4)) {
                isPresented = false
            }
        })
    }
    
    var body: some View {
        if isPortrait {
            VStack(spacing: 12) {
                ControlCard(actions: [
                    backButton
                ] + (settings.activeThemeID == "custom_photo" ? [
                    ControlAction(icon: "slider.horizontal.3", label: "Edit Theme", action: {
                        withAnimation { showCustomSettings = true }
                    })
                ] : []), position: .center, isHorizontal: true, scale: 1.25)
                .opacity(showContent ? 1 : 0)
                .offset(y: showContent ? 0 : 50)
            }
            .padding(.bottom, 50) // Adjusted for Safe Area + "little bit more" up
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        } else {
            // Landscape Layout - Full Screen Overlay
            VStack {
                Spacer() 
                
                HStack(alignment: .bottom) {
                     // Left Controls
                     HStack {
                        ControlCard(actions: [
                            ControlAction(icon: "a.circle", label: "Apply"),
                            ControlAction(
                                icon: "y.circle",
                                label: settings.activeThemeID == "custom_photo" ? "Edit" : "Delete",
                                action: {
                                    if settings.activeThemeID == "custom_photo" {
                                        withAnimation { showCustomSettings = true }
                                    }
                                }
                            )
                        ], position: .left, isHorizontal: true, scale: 1.1)
                        .opacity(showContent ? 1 : 0)
                        .offset(x: showContent ? 0 : -50)
                        
                        Spacer()
                    }
                    .padding(.leading, 60)
                    
                     // Right Controls
                     HStack {
                        Spacer()
                        
                        ControlCard(actions: [
                            backButton
                        ], position: .right, isHorizontal: true, scale: 1.1)
                        .opacity(showContent ? 1 : 0)
                        .offset(x: showContent ? 0 : 50)
                    }
                    .padding(.trailing, 60)
                }
                .padding(.bottom, 24) // "Little bit more" up from edge
            }
        }
    }
}
