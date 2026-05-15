import SwiftUI
import Combine
import AVFoundation
import UIKit
import GameController

struct HeaderView: View {
    var isShowingPhotos: Bool = false
    // var isShowingGameBoy: Bool = false // Deprecated 
    var isShowingGameBoy: Bool = false // Kept for compatibility but unused
    var isShowingMusic: Bool = false
    var isShowingSettings: Bool = false
    var isEditing: Bool = false
    var currentPage: Int = 0
    var mainInterfaceIndex: Int = 0 // NEW: To know if we are in Grid (0) or LiveArea (>0)
    var isControllerConnected: Bool = false
    var controllerName: String = "" // Ya no se muestra, mantenido por compatibilidad
    var activeGameTasks: [ROMItem] = [] // NEW: List of active games
    var onTaskTap: ((Int) -> Void)? = nil // NEW: Callback to switch to task
    var customTitle: String? = nil
    var showContent: Bool = true

    var onControlsTap: (() -> Void)? = nil // New callback for controls
    var onControllerIconTap: (() -> Void)? = nil // Callback for Gamepad Settings
    var useGlassEffect: Bool = false
    @State private var currentDate = Date()
    @State private var isSilentMode = false
    @State private var batteryLevel: Float = 1.0
    @State private var isCharging: Bool = false
    @ObservedObject private var gameController = GameControllerManager.shared
    @ObservedObject private var settings = SettingsManager.shared

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    // Page titles
    private var pageTitle: String {
        if let title = customTitle { return title }
        if isEditing { return "Edit Mode" }
        return "Home Menu"
    }
    
    @ObservedObject private var musicPlayer = MusicPlayerManager.shared
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @State private var animateEntrance = false
    @State private var showMusicPlayer = false // State for music player sheet
    
    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                if geo.size.height > geo.size.width {
                    // Always pill style in vertical orientation
                    verticalLayout
                } else {
                    horizontalLayout
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(.easeOut(duration: 0.3), value: isShowingPhotos)
        .animation(.easeOut(duration: 0.3), value: isShowingGameBoy)
        .onReceive(timer) { input in
            currentDate = input
            // OPTIMIZATION: Update battery with clock timer instead of creating new leaks
            if Int(input.timeIntervalSince1970) % 30 == 0 { // Every 30s
                 updateBatteryLevel()
            }
        }
        .onAppear {
            checkSilentMode()
            updateBatteryLevel()
            // Initialize based on showContent
            if showContent {
                DispatchQueue.main.async {
                    animateEntrance = true
                }
            }
        }
        .onChange(of: showContent) { _, newValue in
            if newValue {
                DispatchQueue.main.async {
                    animateEntrance = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    animateEntrance = false
                }
            }
        }

        .statusBar(hidden: true)
    }
    
    // Helper for cohesive background styling
    private var headerBackgroundStyle: AnyShapeStyle {
        // Custom Theme Logic
        if settings.activeTheme.id == "custom_photo" {
            switch settings.customBubbleStyle {
            case .solid:
                return AnyShapeStyle(settings.customBubbleColor)
            case .transparent:

                return AnyShapeStyle(Color.black.opacity(0.01))
            case .blur:
              
                 return AnyShapeStyle(.ultraThinMaterial)
            }
        }
    
        if settings.reduceTransparency {
            // Performance: Solid Colors
            if let tint = settings.activeTheme.bubbleTintColor {
                return AnyShapeStyle(tint)
            }
            return settings.activeTheme.isDark ? AnyShapeStyle(Color(white: 0.15)) : AnyShapeStyle(Color.white)
        }
        
        // Glass / High Quality
        if useGlassEffect {
            return AnyShapeStyle(.ultraThinMaterial)
        }
        
        // Standard Translucent
        if let tint = settings.activeTheme.bubbleTintColor {
            return AnyShapeStyle(tint)
        }
        
        return settings.activeTheme.isDark ? AnyShapeStyle(Color(white: 0.15)) : AnyShapeStyle(Color.white)
    }

    // Helper for granular custom theme background
    @ViewBuilder
    private func resolvedThemeBackground<S: Shape>(for shape: S) -> some View {
        if settings.activeTheme.id == "custom_photo" {
            if #available(iOS 26.0, *), settings.customBubbleUseLiquidGlass {
                customHeaderLayers(for: shape, includeClassicBlur: false, includeBorder: false)
                    .glassEffect(
                        .regular.tint(settings.customBubbleColor.opacity(settings.customBubbleOpacity)),
                        in: shape
                    )
            } else {
                customHeaderLayers(
                    for: shape,
                    includeClassicBlur: settings.customBubbleBlurBubbles,
                    includeBorder: true
                )
            }
        } else {
            shape.fill(headerBackgroundStyle)
        }
    }

    @ViewBuilder
    private func customHeaderLayers<S: Shape>(
        for shape: S,
        includeClassicBlur: Bool,
        includeBorder: Bool
    ) -> some View {
        ZStack {
            if includeClassicBlur {
                shape.fill(Material.ultraThin)
                    .environment(\.colorScheme, .dark)
            }

            shape.fill(settings.customBubbleColor.opacity(settings.customBubbleOpacity))
            if includeBorder {
                shape.stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        }
    }
    
    //  Layouts
    
    private var horizontalLayout: some View {
        HStack(spacing: 0) {
            Spacer()
            
            // CENTER: Title or Music
            Group {
                if musicPlayer.isSessionActive {
                     musicIndicatorContent
                } else {
                     centerTitleContent
                }
            }
            .padding(.horizontal, 16)
            
            Spacer()
            
            verticalDivider
            
            // RIGHT: Status + Profile
            HStack(spacing: 16) {
                statusDataContent
                
                /* Profile Avatar Hidden
                Button(action: { onProfileTap?() }) {
                    profileAvatarView
                }
                .buttonStyle(.plain)
                */
            }
            .padding(.leading, 16)
            .padding(.trailing, 24)
        }
        .padding(.top, 24)
        .padding(.bottom, 10)
        .frame(maxWidth: 920)
        .background(
            resolvedThemeBackground(for: UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 32, bottomTrailingRadius: 32, topTrailingRadius: 0))
                .ignoresSafeArea(edges: .top)
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 5)
        )
        .padding(.horizontal, 20)
        .padding(.top, -35) // Adjusted to keep it flush but not overly lifted
        .offset(y: animateEntrance ? 0 : -120)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: animateEntrance)
    }
    
    //  Unified Content Components
    
    private var verticalDivider: some View {
        Rectangle()
            .fill(settings.activeTheme.isDark ? Color.white.opacity(0.15) : Color.black.opacity(0.08))
            .frame(width: 1, height: 20)
    }
    

    
    private var centerTitleContent: some View {
        HStack(spacing: 8) {
            // 1. Always show Title (Contextual)
            Text(isShowingPhotos ? "Screenshots" : (
                 isShowingGameBoy ? "Platform Menu" : (
                 isShowingMusic ? "Music" : (
                 isShowingSettings ? "Settings" : pageTitle))))
                .font(.system(size: 15, weight: .bold)) // Fixed size
                .foregroundColor(isEditing ? .white : (settings.activeTheme.isDark ? .white.opacity(0.9) : .black.opacity(0.8)))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                
            // 2. Show Active Tasks (Next to title)
         
            if !activeGameTasks.isEmpty && !isShowingPhotos && !isShowingMusic && !isShowingSettings && !isShowingGameBoy {
                HStack(spacing: 8) {
                    // Divider
                    Rectangle()
                        .fill(settings.activeTheme.isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.2))
                        .frame(width: 1, height: 14)
                    
                    // Home/Grid Icon (Visual Indicator)
                    Button(action: { onTaskTap?(0) }) {
                        ZStack {
                            Circle()
                                .fill(mainInterfaceIndex == 0 ? Color.blue.opacity(0.8) : Color.gray.opacity(0.4))
                            Image(systemName: "house.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.white)
                        }
                        .frame(width: 24, height: 24)
                        .overlay(Circle().stroke(Color.white.opacity(mainInterfaceIndex == 0 ? 1 : 0), lineWidth: 1.5))
                        .opacity(mainInterfaceIndex == 0 ? 1.0 : 0.4) // Dim if not active
                    }
                    .buttonStyle(.plain)
                    
                    // Task Icons
                    ForEach(Array(activeGameTasks.enumerated()), id: \.element.id) { index, rom in
                        let isActive = (mainInterfaceIndex == index + 1)
                        Button(action: { onTaskTap?(index + 1) }) { 
                            if let image = rom.getThumbnail() {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 24, height: 24) // Slightly smaller for header
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(isActive ? 1 : 0), lineWidth: 1.5))
                                    .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                                    .opacity(isActive ? 1.0 : 0.4) // Dim if not active
                            } else {
                                ZStack {
                                    Circle()
                                        .fill(Color.gray.opacity(0.5))
                                    Image(systemName: "gamecontroller.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.white)
                                }
                                .frame(width: 24, height: 24)
                                .overlay(Circle().stroke(Color.white.opacity(isActive ? 1 : 0), lineWidth: 1.5))
                                .opacity(isActive ? 1.0 : 0.4) // Dim if not active
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: 24)
        .id(pageTitle)
        .transition(.push(from: .top).combined(with: .opacity))
    }
    
    private var musicIndicatorContent: some View {
        Button(action: { onControlsTap?() }) {
            HStack(spacing: 8) {
                 Image(systemName: "music.note.list")
                     .font(.system(size: 14))
                     .foregroundColor(settings.activeTheme.isDark ? .white : .black.opacity(0.8))
                 if let song = musicPlayer.currentSong {
                    Text(song.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(settings.activeTheme.isDark ? .white : .black.opacity(0.9))
                        .lineLimit(1)
                 }
            }
        }
        .buttonStyle(.plain)
    }
    
    private var statusDataContent: some View {
        HStack(spacing: 12) {
            // Time & Date
            HStack(spacing: 6) {
                Text(timeString(date: currentDate))
                    .font(.system(size: 13, weight: .bold))
                
                Text("|")
                    .font(.system(size: 13, weight: .regular))
                    .opacity(0.5)
                
                Text(dateString(date: currentDate))
                    .font(.system(size: 13, weight: .bold))
            }
            
            // Battery
            HStack(spacing: 3) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 14))
                    .foregroundColor(batteryColor)
                if settings.showBatteryPercentage {
                    Text("\(Int(batteryLevel * 100))%")
                       .font(.system(size: 11, weight: .medium))
                }
            }
            
            // Controller
            Button(action: { onControllerIconTap?() }) {
                Image(systemName: isControllerConnected ? "gamecontroller.fill" : "gamecontroller")
                     .font(.system(size: 18))
                     .foregroundColor(isControllerConnected ? (settings.activeTheme.isDark ? .white : .black.opacity(0.8)) : .gray.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .foregroundColor(settings.activeTheme.isDark ? .white.opacity(0.9) : .black.opacity(0.7))
    }
    

    
    private var verticalLayout: some View {
        VStack(spacing: 12) {
            // Top Row: Merged Status & Friends
            HStack {
                Spacer()
                portraitStatusBar
                Spacer()
            }
            .zIndex(20)
            
         
        }
        .padding(.horizontal, 16)
        .padding(.top, -15)
        .padding(.bottom, 10)
    }
    
    // Portrait Specific Components
    
    private var portraitStatusBar: some View {
        HStack(spacing: 12) {
            // 0. Active Tasks (NEW)
            if !activeGameTasks.isEmpty && !isShowingPhotos && !isShowingMusic && !isShowingSettings && !isShowingGameBoy {
                HStack(spacing: 8) {
                    // Home/Grid Icon (Portrait)
                     Button(action: { onTaskTap?(0) }) {
                         ZStack {
                             Circle()
                                 .fill(mainInterfaceIndex == 0 ? Color.blue.opacity(0.8) : Color.gray.opacity(0.4))
                             Image(systemName: "house.fill")
                                 .font(.system(size: 10))
                                 .foregroundColor(.white)
                         }
                         .frame(width: 20, height: 20)
                         .overlay(Circle().stroke(Color.white.opacity(mainInterfaceIndex == 0 ? 1 : 0), lineWidth: 1))
                         .opacity(mainInterfaceIndex == 0 ? 1.0 : 0.4)
                     }
                    
                    ForEach(Array(activeGameTasks.enumerated()), id: \.element.id) { index, rom in
                        let isActive = (mainInterfaceIndex == index + 1)
                        Button(action: { onTaskTap?(index + 1) }) {
                            if let image = rom.getThumbnail() {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 20, height: 20)
                                    .clipShape(Circle())
                                    .overlay(Circle().stroke(Color.white.opacity(isActive ? 1 : 0), lineWidth: 1))
                                    .shadow(radius: 1)
                                    .opacity(isActive ? 1.0 : 0.4)
                            } else {
                                Circle()
                                    .fill(Color.gray.opacity(0.5))
                                    .frame(width: 20, height: 20)
                                    .overlay(
                                        Image(systemName: "gamecontroller.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.white)
                                    )
                                    .overlay(Circle().stroke(Color.white.opacity(isActive ? 1 : 0), lineWidth: 1))
                                    .opacity(isActive ? 1.0 : 0.4)
                            }
                        }
                    }
                    
                    // Divider
                    Rectangle()
                        .fill(settings.activeTheme.isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                        .frame(width: 1, height: 12)
                }
            }
            
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundColor(settings.activeTheme.isDark ? .white.opacity(0.8) : .black.opacity(0.6))
                
                Text(timeString(date: currentDate))
                    .font(.system(size: 12, weight: .bold))
                
                Text("|").font(.system(size: 10)).foregroundColor(.gray)
                
                Text(dateString(date: currentDate))
                    .font(.system(size: 12, weight: .bold))
                
                HStack(spacing: 2) {
                    Image(systemName: batteryIcon)
                        .font(.system(size: 14))
                        .foregroundColor(batteryColor)
                    if settings.showBatteryPercentage {
                        Text("\(Int(batteryLevel * 100))%").font(.system(size: 10, weight: .semibold)).foregroundColor(settings.activeTheme.isDark ? .white.opacity(0.8) : .black.opacity(0.6))
                    }
                }
            }
            
            /*
            // Vertical Divider
            Rectangle()
                .fill(settings.activeTheme.isDark ? Color.white.opacity(0.2) : Color.black.opacity(0.1))
                .frame(width: 1, height: 20)
            
            // Profile Button (Integrated)
            Button(action: { onProfileTap?() }) {
                profileAvatarView
                    .frame(width: 32, height: 32) // Slightly smaller for portrait pill
            }
            .buttonStyle(PlainButtonStyle())
            */
            
        }
        .shadow(color: Color.black.opacity(0.4), radius: 1, x: 1, y: 3)
        .padding(.leading, 16)
        .padding(.trailing, 8) 
        .padding(.vertical, 6)
        .foregroundColor(settings.activeTheme.isDark ? .white : .black.opacity(0.7))
        .background(
            resolvedThemeBackground(for: Capsule())
                .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 4)
        )
        .overlay(
            Group {
                // Legacy overlay removed

            }
        )
        .offset(y: animateEntrance ? 0 : -60)
        .opacity(animateEntrance ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: animateEntrance)
    }
    
    // Components
    
    private var centerTitle: some View {
        Group {
            if !pageTitle.isEmpty || isShowingPhotos || isShowingGameBoy || isShowingMusic || isShowingSettings {
                Text(isShowingPhotos ? "Screenshots" : (
                     isShowingGameBoy ? "Platform Menu" : (
                     isShowingMusic ? "Music" : (
                     isShowingSettings ? "Settings" : pageTitle))))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(isEditing ? .white : (settings.activeTheme.isDark ? .white.opacity(0.9) : .black.opacity(0.8)))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        BubbleBackground(position: .center, cornerRadius: 16)
                    )
                    .id(isShowingPhotos ? "photos" : (
                        isShowingGameBoy ? "gameboy" : (
                        isShowingMusic ? "music" : (
                        isShowingSettings ? "settings" : (
                        isEditing ? "edit" : "page")))) ) // Simplified ID
                    .offset(y: animateEntrance ? 0 : -60)
                    .opacity(animateEntrance ? 1 : 0)
                    .scaleEffect(animateEntrance ? 1 : 0.8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: animateEntrance)
            }
        }
    }

    private var rightContent: some View {
        Group {
            if musicPlayer.isSessionActive {
                musicIndicator
            }
        }
    }

    private var statusContent: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.fill")
                .font(.system(size: 12))
                .foregroundColor(settings.activeTheme.isDark ? .white.opacity(0.8) : .black.opacity(0.6))
                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 1, y: 3)
            
            Text(timeString(date: currentDate))
                .font(.system(size: 12, weight: .bold))
                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 1, y: 3)
            
            Text("|")
                .font(.system(size: 10))
                .foregroundColor(.gray)
            
            Text(dateString(date: currentDate))
                .font(.system(size: 12, weight: .bold))
                .shadow(color: Color.black.opacity(0.4), radius: 1, x: 1, y: 3)
            
            // Battery indicator with real level
            HStack(spacing: 2) {
                Image(systemName: batteryIcon)
                    .font(.system(size: 14))
                    .foregroundColor(batteryColor)
                
                if settings.showBatteryPercentage {
                    Text("\(Int(batteryLevel * 100))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(settings.activeTheme.isDark ? .white.opacity(0.8) : .black.opacity(0.6))
                }
            }
            .compositingGroup()
            .shadow(color: Color.black.opacity(0.4), radius: 1, x: 1, y: 3)


            controllerStatusIcon
        }
        .padding(.leading, 12)
        .padding(.trailing, 110)
        .padding(.vertical, 4)
        .padding(.vertical, 4)
        .foregroundColor(settings.activeTheme.isDark ? .white : .black.opacity(0.7))
        .background(
            resolvedThemeBackground(for: UnevenRoundedRectangle(topLeadingRadius: 16, bottomLeadingRadius: 16, bottomTrailingRadius: 0, topTrailingRadius: 0))
                .shadow(color: Color.black.opacity(0.14), radius: 6, x: 0, y: 4)
        )
        .overlay(
            Group {
                // Legacy overlay removed

            }
        )

        .padding(.trailing, UIDevice.current.userInterfaceIdiom == .pad ? 0 : -60)
        .offset(y: animateEntrance ? 0 : -60)
        .opacity(animateEntrance ? 1 : 0)
        .animation(.spring(response: 0.6, dampingFraction: 0.7).delay(0.2), value: animateEntrance)
    }
    

    
    private var musicIndicator: some View {
        Button(action: {
            if let callback = onControlsTap {
                callback()
            } else {
                NotificationCenter.default.post(name: Notification.Name("ShowFullMediaControls"), object: nil)
            }
        }) {
            HStack(spacing: 8) {
                // Album Art
                Group {
                    if let artwork = musicPlayer.currentSong?.artwork {
                        Image(uiImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                    } else {
                        Circle()
                            .fill(settings.reduceTransparency ? (settings.activeTheme.isDark ? Color.gray.opacity(0.5) : Color.gray) : Color.gray.opacity(0.3))
                            .frame(width: 36, height: 36)
                            .overlay(Image(systemName: "music.note").font(.system(size: 14)).foregroundColor(settings.reduceTransparency ? .white : .gray))
                            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
                    }
                }
                
                // Song Title
                if let song = musicPlayer.currentSong {
                    Text(song.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(settings.activeTheme.isDark ? .white.opacity(0.9) : .black.opacity(0.9))
                        .lineLimit(1)
                        .padding(.trailing, 8)
                }
            }
            .padding(4)
            .padding(.trailing, 8) // Extra padding for text
            .background(
                resolvedThemeBackground(for: Capsule())
                    .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 3)
            )
            .overlay(
                Group {
                // Legacy overlay removed

                }
            )
        }
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .padding(.trailing, 16)
        .buttonStyle(.plain)
        .transition(.scale.combined(with: .opacity))
        .padding(.trailing, 16)
    }
    
    // Controller Battery Helpers - Removed
    
    private var batteryIcon: String {
        if isCharging {
            return "battery.100.bolt"
        }
        
        switch batteryLevel {
        case 0.76...1.0:
            return "battery.100"
        case 0.51...0.75:
            return "battery.75"
        case 0.26...0.50:
            return "battery.50"
        case 0.01...0.25:
            return "battery.25"
        default:
            return "battery.0"
        }
    }
    
    private var batteryColor: Color {
        if isCharging {
            return .green
        }
        
        if batteryLevel <= 0.20 {
            return .red
        } else if batteryLevel <= 0.50 {
            return .orange
        }
        return settings.activeTheme.isDark ? .white.opacity(0.8) : .black.opacity(0.6)
    }
    
    private func updateBatteryLevel() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        batteryLevel = UIDevice.current.batteryLevel
        isCharging = UIDevice.current.batteryState == .charging || UIDevice.current.batteryState == .full
    }
    
    func checkSilentMode() {
        // Check if device is in silent mode
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            let outputVolume = AVAudioSession.sharedInstance().outputVolume
            
            // If volume is 0, likely in silent mode (not perfect detection)
            // Better way: check ringer switch but requires private APIs
            isSilentMode = outputVolume == 0
        } catch {
            isSilentMode = false
        }
    }
    
    func timeString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }
    
    func dateString(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: date)
    }
    
    private var controllerStatusIcon: some View {
        ViewThatFits {
            controllerStatusContent(showText: true)
            controllerStatusContent(showText: false)
        }
    }
    
    private func controllerStatusContent(showText: Bool) -> some View {
        // Extract complex color logic to helper variables
        let iconColor: Color = isControllerConnected 
            ? (settings.activeTheme.isDark ? .white.opacity(0.7) : .black.opacity(0.55))
            : (settings.activeTheme.isDark ? .white.opacity(0.3) : .black.opacity(0.2))
            
        let backgroundColor: Color = isControllerConnected
            ? (settings.activeTheme.isDark ? Color.white.opacity(0.2) : Color.white.opacity(0.6))
            : (settings.activeTheme.isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.3))
            
        let borderColor: Color = isControllerConnected
            ? (settings.activeTheme.isDark ? Color.white.opacity(0.3) : Color.black.opacity(0.15))
            : (settings.activeTheme.isDark ? Color.white.opacity(0.1) : Color.black.opacity(0.05))
            
        return HStack(spacing: 6) {
            if showText && !isControllerConnected {
                Text("Controller Required")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.red.opacity(0.8))
                    .lineLimit(1)
            }
            
            // Show Generic Gamepad
            Button(action: { onControllerIconTap?() }) {
                Image(systemName: isControllerConnected ? "gamecontroller.fill" : "gamecontroller")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(iconColor)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: 1)
        )
        .compositingGroup()
        .shadow(color: Color.black.opacity(isControllerConnected ? 0.4 : 0.1), radius: 1, x: 1, y: 3)
        .transition(.scale.combined(with: .opacity))
    }
}

struct HeaderView_Previews: PreviewProvider {
    static var previews: some View {
        HeaderView(isControllerConnected: true, controllerName: "Controller")
            .previewLayout(.sizeThatFits)
            .background(Color.gray.opacity(0.1))
    }
}
