import SwiftUI
import Combine

// Models

struct StoreItem: Identifiable, Equatable {
    let id: String
    let title: String
    let price: String
    let iconName: String
    let color: Color
    let description: String
    var systemApp: SystemApp? = nil
    
    static func == (lhs: StoreItem, rhs: StoreItem) -> Bool {
        return lhs.id == rhs.id
    }
}

struct SidebarMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
}

struct CreditItem: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let role: String
    let discordLink: String?
    let systemApp: SystemApp?
    
    static func == (lhs: CreditItem, rhs: CreditItem) -> Bool {
        return lhs.id == rhs.id
    }
}

// ViewModel
class StoreViewModel: ObservableObject {
    // Dependencies
    var homeViewModel: HomeViewModel?
    
    // State
    @Published var selectedTab: StoreTab = .store
    @Published var selectedSidebarIndex: Int = 0
    @Published var selectedContentIndex: Int = 0
    @Published var isSidebarFocused: Bool = true
    @Published var selectedCreditIndex: Int = 0
    @Published var isCarouselFocused: Bool = false
    
    // Detail View State
    @Published var isShowingDetail: Bool = false
    @Published var selectedDetailItem: StoreItem?
    
    // Detail View State
    enum DetailFocus {
        case action
        case close
    }
    @Published var detailFocus: DetailFocus = .action

    // Tabs
    enum StoreTab: String, CaseIterable {
        case store = "Add ons"
        case community = "Community"
        case credits = "Credits"
    }
    
    // Sidebar Data
    let sidebarMenuItems: [SidebarMenuItem] = [
        SidebarMenuItem(title: "Home", icon: "house.fill"),
        SidebarMenuItem(title: "Apps", icon: "square.grid.2x2.fill"),
        SidebarMenuItem(title: "Games", icon: "gamecontroller.fill"),
        SidebarMenuItem(title: "Themes", icon: "paintpalette.fill")
    ]
    
    // Computed Helpers
    var currentCategoryTitle: String {
        guard selectedSidebarIndex < sidebarMenuItems.count else { return "" }
        return sidebarMenuItems[selectedSidebarIndex].title
    }
    
    var currentItems: [StoreItem] {
        switch currentCategoryTitle {
        case "Home": return featuredItems
        case "Apps": return appItems
        case "Games": return gameItems
        case "Themes": return themeItems
        default: return []
        }
    }
    
    // Stable items for the carousel to prevent reshuffling on every view update
    @Published var carouselItems: [StoreItem] = []
    
    private func updateCarouselItems() {
        if carouselItems.isEmpty {
            carouselItems = featuredItems.shuffled()
        }
    }
    
    init() {
         updateCarouselItems()
    }
    
    // Data Sources
    
    private lazy var featuredItems: [StoreItem] = {
            SystemApp.allCases
                // TEMP: Hide Slither.io + MeloNX from Store for now.
                .filter { !$0.isPreinstalled && $0 != .slither && $0 != .meloNX }
                .map { app in
            StoreItem(
                id: app.id,
                title: app.defaultName,
                price: "Available",
                iconName: app.iconName,
                color: app.defaultColor,
                description: app.description,
                systemApp: app
            )
        }
    }()
    
    private lazy var appItems: [StoreItem] = {
            SystemApp.allCases
                // TEMP: Hide Slither.io + MeloNX from Store for now.
                .filter { !$0.isPreinstalled && $0.category == .app && $0 != .slither && $0 != .meloNX }
                .map { app in
            StoreItem(
                id: app.id,
                title: app.defaultName,
                price: "Available",
                iconName: app.iconName,
                color: app.defaultColor,
                description: app.description,
                systemApp: app
            )
        }
    }()
    
    private lazy var gameItems: [StoreItem] = {
            SystemApp.allCases
                // TEMP: Hide Slither.io + MeloNX from Store for now.
                .filter { !$0.isPreinstalled && $0.category == .game && $0 != .slither && $0 != .meloNX }
                .map { app in
            StoreItem(
                id: app.id,
                title: app.defaultName,
                price: "Available",
                iconName: app.iconName,
                color: app.defaultColor,
                description: app.description,
                systemApp: app
            )
        }
    }()
    
    private var themeItems: [StoreItem] {
        ThemeRegistry.allThemes.map { theme in
            let isOwned = ThemeRegistry.isInstalled(theme)
            return StoreItem(
                id: theme.id,
                title: theme.displayName,
                price: isOwned ? "Installed" : "Available",
                iconName: theme.icon,
                color: theme.color,
                description: "Customize your home screen with the \(theme.displayName) theme. Features unique colors and icons.",
                systemApp: nil
            )
        }
    }
    
    let credits: [CreditItem] = [
        CreditItem(name: "Classic Games", role: "TETR.IO", discordLink: "https://discord.com/invite/tetrio", systemApp: .tetris)
    ]
    
    // Download State
    enum DownloadState {
        case idle
        case downloading
        case installed
    }
    
    @Published var downloadState: DownloadState = .idle
    @Published var downloadProgress: CGFloat = 0.0
    private var downloadTimer: Timer?
    
    
    // Logic
    
    func isItemInstalled(_ item: StoreItem) -> Bool {
        if let sysApp = item.systemApp {
            guard let homeVM = homeViewModel else { return false }
            return homeVM.pages.flatMap { $0 }.contains(where: { $0.systemApp == sysApp })
        } else if let theme = ThemeRegistry.allThemes.first(where: { $0.id == item.id }) {
            return ThemeRegistry.isInstalled(theme)
        }
        return true
    }
    
    func switchTab(to tab: StoreTab) {
        withAnimation {
            selectedTab = tab
            // Reset focus when switching tabs
            isSidebarFocused = true
            selectedSidebarIndex = 0
            selectedContentIndex = 0
        }
    }
    
    func nextTab() {
        let all = StoreTab.allCases
        if let idx = all.firstIndex(of: selectedTab) {
            let nextIdx = (idx + 1) % all.count
            switchTab(to: all[nextIdx])
        }
    }
    
    func prevTab() {
        let all = StoreTab.allCases
        if let idx = all.firstIndex(of: selectedTab) {
            let prevIdx = (idx - 1 + all.count) % all.count
            switchTab(to: all[prevIdx])
        }
    }


    @Published var gridColumns: Int = 3

    func handleNavigation(_ direction: GameControllerManager.Direction) {
        // Detail View Navigation
        if isShowingDetail {
            switch direction {
            case .left:
                if detailFocus == .close { 
                    detailFocus = .action 
                    AudioManager.shared.playNavigationSound()
                }
            case .right:
                if detailFocus == .action { 
                    detailFocus = .close 
                    AudioManager.shared.playNavigationSound()
                }
            default: break
            }
            return 
        }
        
        // Normal Navigation
        
        if selectedTab == .community {
            // Community Placeholder Navigation
            return 
        }
        
        if selectedTab == .credits {
            let columns = gridColumns // Reuse grid columns logic (usually 2 or 3)
            switch direction {
            case .up:
                if selectedCreditIndex >= columns { 
                    selectedCreditIndex -= columns 
                    AudioManager.shared.playNavigationSound()
                }
            case .down:
                if selectedCreditIndex + columns < credits.count { 
                    selectedCreditIndex += columns 
                    AudioManager.shared.playNavigationSound()
                }
            case .left:
                if selectedCreditIndex > 0 { 
                    selectedCreditIndex -= 1 
                    AudioManager.shared.playNavigationSound()
                }
            case .right:
                if selectedCreditIndex < credits.count - 1 { 
                    selectedCreditIndex += 1 
                    AudioManager.shared.playNavigationSound()
                }
            }
            return
        }
        
        if isSidebarFocused {
            switch direction {
            case .up:
                if selectedSidebarIndex > 0 { 
                    selectedSidebarIndex -= 1 
                    AudioManager.shared.playNavigationSound()
                }
            case .down:
                if selectedSidebarIndex < sidebarMenuItems.count - 1 { 
                    selectedSidebarIndex += 1 
                    AudioManager.shared.playNavigationSound()
                }
            case .right:
                if currentCategoryTitle == "Home" {
                    isSidebarFocused = false
                    isCarouselFocused = true
                    AudioManager.shared.playNavigationSound()
                } else if !currentItems.isEmpty {
                    isSidebarFocused = false
                    selectedContentIndex = 0
                    AudioManager.shared.playNavigationSound()
                }
            default: break
            }
        } else if isCarouselFocused {
            switch direction {
            case .left:
                isCarouselFocused = false
                isSidebarFocused = true
                AudioManager.shared.playNavigationSound()
            case .down:
                isCarouselFocused = false
                selectedContentIndex = 0 // Move to first grid item
                AudioManager.shared.playNavigationSound()
            case .right:
                // Potentially cycle carousel items here future
                break
            default: break
            }
        } else {
            let columns = gridColumns
            switch direction {
            case .up:
                if selectedContentIndex < columns {
                    if currentCategoryTitle == "Home" {
                        isCarouselFocused = true // Move specificially to carousel from top row
                        AudioManager.shared.playNavigationSound()
                    }
                } else {
                    selectedContentIndex -= columns
                    AudioManager.shared.playNavigationSound()
                }
            case .down:
                if selectedContentIndex + columns < currentItems.count { 
                    selectedContentIndex += columns 
                    AudioManager.shared.playNavigationSound()
                }
            case .left:
                if selectedContentIndex % columns == 0 {
                    isSidebarFocused = true
                    AudioManager.shared.playNavigationSound()
                } else {
                    selectedContentIndex -= 1
                    AudioManager.shared.playNavigationSound()
                }
            case .right:
                if selectedContentIndex % columns != columns - 1 && selectedContentIndex < currentItems.count - 1 {
                    selectedContentIndex += 1
                    AudioManager.shared.playNavigationSound()
                }
            }
        }
    }
    
    func handleSelect() {
        print(" StoreViewModel: handleSelect called. Tab: \(selectedTab)")
        
        if isShowingDetail {
            // "A" button in Detail View
            if detailFocus == .action {
                // Trigger Action (Install if idle)
                if downloadState == .idle {
                     startDownloadProcess()
                }
            } else {
                // Trigger Close
                closeDetail()
            }
            return
        }
        
        if selectedTab == .credits {
             guard selectedCreditIndex < credits.count else { return }
             let item = credits[selectedCreditIndex]
             if let link = item.discordLink, let url = URL(string: link) {
                 print(" Opening Discord: \(link)")
                 UIApplication.shared.open(url)
             }
             return
        }
        if isSidebarFocused {
            // Focus feedback if needed
        } else if isCarouselFocused {
             // Carousel Selection -> Open Detail
             if !carouselItems.isEmpty {
                 selectedDetailItem = carouselItems.first 
                 withAnimation { isShowingDetail = true }
                 downloadState = (selectedDetailItem.map { isItemInstalled($0) } ?? false) ? .installed : .idle
                 AudioManager.shared.playSelectSound()
             }
        } else {
            guard selectedContentIndex < currentItems.count else { return }
            let item = currentItems[selectedContentIndex]
            
            // OPEN DETAIL VIEW Instead of immediate install
            selectedDetailItem = item
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                isShowingDetail = true
                downloadState = isItemInstalled(item) ? .installed : .idle
            }
            AudioManager.shared.playSelectSound()
        }
    }
    
    private var lastCloseTime: Date?
    
    // Returns TRUE if the app should dismiss/exit
    func handleBack() -> Bool {
        // 1. Debounce check: If we just closed the detail view, ignore back presses for a moment
        if let lastClose = lastCloseTime, Date().timeIntervalSince(lastClose) < 0.5 {
            return false
        }
        
        // 2. If Detail is showing, close it and DO NOT dismiss app
        if isShowingDetail {
            closeDetail()
            return false
        }
        
        // 3. If standard navigation, dismiss app
        return true
    }
    
    func closeDetail() {
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingDetail = false
            selectedDetailItem = nil
            downloadState = .idle
            downloadProgress = 0.0
        }
        lastCloseTime = Date() // Mark time
        downloadTimer?.invalidate()
        downloadTimer = nil
        AudioManager.shared.playSelectSound()
    }
    
    func startDownloadProcess() {
        guard let item = selectedDetailItem, !isItemInstalled(item) else { return }
        
        withAnimation(.easeOut(duration: 0.3)) {
            downloadState = .downloading
            downloadProgress = 0.0
        }
        
        // Simulating 6 second download
        let totalTime: TimeInterval = 6.0
        let interval: TimeInterval = 0.1
        let steps = totalTime / interval
        let increment = 1.0 / steps
        
        downloadTimer?.invalidate()
        downloadTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            
            withAnimation(.linear(duration: interval)) {
                self.downloadProgress += CGFloat(increment)
            }
            
            if self.downloadProgress >= 1.0 {
                timer.invalidate()
                self.downloadTimer = nil
                
                // Finish
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.installCurrentItem() // Actually install
                    AudioManager.shared.playSelectSound() 
                    withAnimation(.spring()) {
                        self.downloadState = .installed 
                    }
                }
            }
        }
    }
    
    func installCurrentItem() {
        guard let item = selectedDetailItem else { return }
        
        print(" Installing/Opening: \(item.title)")
        
        if let systemApp = item.systemApp {
            if !isItemInstalled(item) {
                 print(" Installing \(systemApp.defaultName)... HomeVM: \(homeViewModel != nil)")
                 if homeViewModel == nil {
                     print(" ERROR: homeViewModel is nil in StoreViewModel. Cannot install.")
                 }
                 withAnimation {
                     homeViewModel?.installApp(systemApp)
                 }
                 AppStatusManager.shared.show("Installed \(systemApp.defaultName)", icon: "checkmark.circle.fill")
                 AudioManager.shared.playSuccessSound() // If available, or generic select
            } else {
                   print(" Already installed: \(systemApp.defaultName)")
                   AppStatusManager.shared.show("Opening...", icon: "arrow.up.right.circle.fill")
            }
        } else {
            // Theme Logic
            if let theme = ThemeRegistry.allThemes.first(where: { $0.id == item.id }) {
                if ThemeRegistry.isInstalled(theme) {
                      AppStatusManager.shared.show("Owned", icon: "checkmark")
                } else {
                    print("Installing Theme: \(theme.displayName)")
                    ThemeRegistry.install(theme)
                    AppStatusManager.shared.show("Theme Installed", icon: "checkmark.circle.fill")
                    AudioManager.shared.playSelectSound()
                }
            }
        }
    }
}
