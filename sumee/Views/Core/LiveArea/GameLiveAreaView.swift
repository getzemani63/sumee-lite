import SwiftUI

struct GameLiveAreaView: View {
    let rom: ROMItem
    @ObservedObject var viewModel: HomeViewModel
    
    // Animation State
    @State private var appearAnimation = false
    @State private var showContent = false // Controls the Zoom/Fade In on Launch
    @State private var peelOffset: CGFloat = 50.0 
    @State private var screenshotFrame: CGRect = .zero
    @State private var isZooming = false // Launch Zoom Animation
    private let closeThreshold: CGFloat = 150.0
    
    // ... (inside body)
    

    
    // Computed property for autosave image to ensure consistent checking
    private var autosaveImage: UIImage? {
        if let url = rom.autoSaveScreenshotURL, 
           let data = try? Data(contentsOf: url),
           let image = UIImage(data: data) {
            return image
        }
        return nil
    }
    
    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height
            
            // Dynamic Padding: Increase horizontal padding in landscape for "narrower" look
            let paddingH: CGFloat = isLandscape ? 80 : 44
            
            // Vertical Padding: Asymmetric in Portrait (More top padding for Header, less bottom)
            let paddingTop: CGFloat = isLandscape ? 24 : 85
            let paddingBottom: CGFloat = isLandscape ? 24 : 30
            
            let w = geometry.size.width - (paddingH * 2)
            let h = geometry.size.height - paddingTop - paddingBottom
            
            // Limit peel to avoid breaking visual bounds too much -> REMOVED LIMIT
            // Allowing full peel as per user request to "fully remove the view"
            let limitedPeel = max(0, peelOffset)
            
            ZStack {
                // 1. CONTENT GROUP (Masked)
                ZStack {
                    // Background Layer
                    backgroundContent(w: w, h: h)
                    
                    // Main Layout
                    if isLandscape {
                        landscapeLayout(w: w, h: h)
                    } else {
                        verticalLayout(w: w, h: h)
                    }
                }
                .mask(
                    GamePeelMaskShape(offset: limitedPeel)
                        .animation(.interactiveSpring(), value: limitedPeel)
                )
                .shadow(color: .black.opacity(0.5), radius: 10, x: -5, y: 0) // Shadow on clipped content
                
                // 2. Peel Interaction Layer (Visual + Gesture) - Overlay
                peelLayer(w: w, h: h, offset: limitedPeel)
            }
            // Launch Animation Modifiers
            .opacity(viewModel.isAnimatingLaunch && !showContent ? 0 : 1)
            .scaleEffect(isZooming ? 0.95 : (viewModel.isAnimatingLaunch && !showContent ? 0.8 : 1)) // Shrink on launch
            .blur(radius: isZooming ? 6 : 0) // Blur to hide stutter/create depth
            // Enforce Size and Center within GeometryReader
            .frame(width: w, height: h)
            .position(x: geometry.size.width / 2, y: paddingTop + (h / 2))
        }
        .onAppear {
            if viewModel.isAnimatingLaunch {
                // Wait for the Icon to arrive (0.5s scroll + 0.3s wait = 0.8s total)
                showContent = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeOut(duration: 0.4)) {
                        showContent = true
                    }
                }
            } else {
                showContent = true
            }
            
            withAnimation(.easeOut(duration: 0.5)) {
                appearAnimation = true
            }
        }
        .onReceive(viewModel.liveAreaLaunchSignal) { mode in
            if mode == .resume {
                // Use the tracked screenshot frame and image for visual continuity
                animateAndLaunch(mode: .resume, sourceRect: screenshotFrame, image: autosaveImage)
            } else {
                // Default launch (center/fade)
                animateAndLaunch(mode: mode)
            }
        }
    }
    
    // Launch Logic
    
    private func animateAndLaunch(mode: GameLaunchMode, sourceRect: CGRect? = nil, image: UIImage? = nil) {
        // 1. Trigger Zoom Animation
        withAnimation(.easeIn(duration: 0.2)) {
            isZooming = true
        }
        
        // 2. Delay actual launch to show animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            viewModel.launchGameFromPage(rom, mode: mode, sourceRect: sourceRect, image: image)
            
            // Reset state (though view will likely disappear/be covered)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isZooming = false
            }
        }
    }
    
    //Layouts
    
    @ViewBuilder
    func backgroundContent(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Color.black
            
            // Dynamic theme background based on ROM color if available, else blue
            let baseColor = viewModel.pages.first?.first?.color ?? .blue
            
            RadialGradient(
                gradient: Gradient(colors: [baseColor.opacity(0.3), Color.black]),
                center: .center,
                startRadius: 50,
                endRadius: max(w, h)
            )
            
            // Subtle Pattern
            HexagonPattern()
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
                .frame(width: w * 0.9, height: h * 0.9)
                .rotationEffect(.degrees(appearAnimation ? 10 : 0))
        }
        // Removed .ignoresSafeArea() to respect padding request
    }
    
    @ViewBuilder
    func verticalLayout(w: CGFloat, h: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer()
            
            // Game Visual (Icon or Box Art)
            // If autosave exists, we settle for the icon here, and show screenshot in the action card
            ROMCardView(rom: rom, isSelected: true)
                .scaleEffect(1.2)
                .frame(width: w * 0.4, height: w * 0.4)
                .shadow(color: .white.opacity(0.2), radius: 20)
                .padding(.bottom, 30)
            
            // Title
            Text(rom.displayName)
                .font(.system(size: 24, weight: .bold)) // Reduced from 28
                .lineLimit(2) // Prevent taking too much vertical space
                .minimumScaleFactor(0.8)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
                .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 2)
            
            Spacer().frame(height: 20) // Reduced spacing
            
            // Action Area
            actionButtonsArea(isPortrait: true)
                .frame(width: w * 0.9) // Slightly wider for portrait
            
            Spacer()
            Spacer()
        }
    }
    
    @ViewBuilder
    func landscapeLayout(w: CGFloat, h: CGFloat) -> some View {
        HStack(spacing: 40) {
            // Left: Visuals (Box Art)
            VStack {
                Spacer()
                ROMCardView(rom: rom, isSelected: true)
                    .scaleEffect(1.1)
                    .shadow(color: .black.opacity(0.5), radius: 15, x: 0, y: 10)
                Spacer()
            }
            .frame(width: w * 0.3)
            .padding(.leading, 40)
            
            // Right: Info & Actions
            VStack(alignment: .leading, spacing: 16) {
                Spacer()
                
                Text(rom.displayName)
                    .font(.system(size: 32, weight: .bold))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(.white)
                    // Less aggressive padding, relying on card width to avoid peel
                    .padding(.trailing, 60)
                
                // Action Area - Now handles its own sizing
                actionButtonsArea(isPortrait: false)
                    .frame(maxWidth: 400) // Limit width in landscape for cleaner look
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 40)
        }
    }
    
    func isActionSelected(_ index: Int) -> Bool {
        return viewModel.liveAreaActionIndex == index && viewModel.gameController.isControllerConnected
    }

    @ViewBuilder
    func actionButtonsArea(isPortrait: Bool) -> some View {
        if let screenshot = autosaveImage {
            // --- RESUME STATE ---
            VStack(spacing: 16) {
                // 1. Screenshot Preview
                Image(uiImage: screenshot)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(height: isPortrait ? 180 : 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .background(
                        GeometryReader { geo in
                            Color.clear
                                .onAppear {
                                    self.screenshotFrame = geo.frame(in: .global)
                                }
                                .onChange(of: geo.frame(in: .global)) { newFrame in
                                    self.screenshotFrame = newFrame
                                }
                        }
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.white.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(radius: 5)
                .overlay(
                    // Suspended Badge
                    Text("SUSPENDED")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .padding(8),
                    alignment: .topLeading
                )
                
                // 2. Main Action: "Start" (Pill Button Below Screenshot)
                Button(action: {
                    animateAndLaunch(mode: .resume, sourceRect: screenshotFrame, image: screenshot)
                }) {
                    Text("Start")
                        .font(.system(size: 20, weight: .bold)) // Start Button Style
                        .foregroundColor(.white)
                        .frame(width: 160, height: 44)
                        .background(
                            LinearGradient(
                                colors: [Color.cyan, Color.blue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.5), lineWidth: 1)
                        )
                        .scaleEffect(isActionSelected(0) ? 1.05 : 1.0)
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActionSelected(0))
                }
                .buttonStyle(.plain)
                
                // 3. Restart Option (Separate Button Outside)
                Button(action: {
                    animateAndLaunch(mode: .restart)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Restart from beginning")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(isActionSelected(1) ? .white : .white.opacity(0.6))
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                    .background(isActionSelected(1) ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(Capsule())
                    .scaleEffect(isActionSelected(1) ? 1.05 : 1.0)
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActionSelected(1))
                }
                .buttonStyle(.plain)
            }
            .padding(screenshotPadding(isPortrait))
        } else {
            // --- START FRESH STATE ---
            Button(action: {
                animateAndLaunch(mode: .normal)
            }) {
                HStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 44, height: 44)
                        Image(systemName: "power")
                            .font(.system(size: 20, weight: .bold))
                    }
                    
                    Text("Start Game")
                        .font(.system(size: 20, weight: .bold))
                        .textCase(.uppercase)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .opacity(0.6)
                }
                .foregroundColor(.white)
                .padding(12)
                .background(
                    LinearGradient(colors: [.blue.opacity(0.8), .purple.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .scaleEffect(isActionSelected(0) ? 1.05 : 1.0)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActionSelected(0))
            }
            .frame(maxWidth: isPortrait ? .infinity : 300)
            .scaleEffect(isActionSelected(0) ? 1.02 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isActionSelected(0))
            .padding(.horizontal, isPortrait ? 20 : 0)
        }
    }
    
    func screenshotPadding(_ isPortrait: Bool) -> EdgeInsets {
        return EdgeInsets(top: 0, leading: isPortrait ? 20 : 0, bottom: 0, trailing: isPortrait ? 20 : 0)
    }
    
    // MARK: - Peel Effect Layer
    
    // Haptic Generators
    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    let notificationFeedback = UINotificationFeedbackGenerator()
    @State private var lastHapticValue: CGFloat = 50.0 // Matches initial peelOffset

    @ViewBuilder
    func peelLayer(w: CGFloat, h: CGFloat, offset: CGFloat) -> some View {
        ZStack {
            // The Flap (Top Right)
            GamePeelFlapShape(offset: offset)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(white: 0.95), // Brighter white paper
                            Color(white: 0.85),
                            Color(white: 0.70)
                        ]),
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 8, x: -4, y: 4)
                .animation(.interactiveSpring(), value: offset)

            // Gesture Area
            Color.white.opacity(0.001) // Invisible hit area
                .frame(width: 120, height: 120)
                .position(x: w - 60, y: 60)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            // Logic borrowed from HomeLockScreenView for smooth physics
                            let tx = value.translation.width
                            let ty = value.translation.height
                            let drag = (ty - tx) * 0.7 // Use 0.7 projection like LockScreen
                            let newPeel = max(50, 50 + drag)
                            self.peelOffset = newPeel
                            
                            // Haptic Feedback Logic
                            if abs(newPeel - lastHapticValue) > 10 {
                                impactFeedback.impactOccurred(intensity: 0.6)
                                lastHapticValue = newPeel
                            }
                        }
                        .onEnded { value in
                            if self.peelOffset > closeThreshold {
                                // Close Action - Smooth Exit
                                notificationFeedback.notificationOccurred(.success) // Success Haptic
                                
                                withAnimation(.easeOut(duration: 0.3)) {
                                    self.peelOffset = w * 2.0 // Ensures it clears the screen fully
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    viewModel.closeGamePage(rom)
                                }
                            } else {
                                // Snap Back - Spring Physics
                                withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                    self.peelOffset = 50
                                }
                                lastHapticValue = 50 // Reset tracker
                            }
                        }
                )
        }
    }
}

//Shapes

struct GamePeelMaskShape: Shape {
    var offset: CGFloat
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = offset * 1.5
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - p, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + p))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct GamePeelFlapShape: Shape {
    var offset: CGFloat
    var animatableData: CGFloat {
        get { offset }
        set { offset = newValue }
    }
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p = offset * 1.5
        if p <= 1 { return path }
        path.move(to: CGPoint(x: rect.maxX - p, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + p))
        path.addLine(to: CGPoint(x: rect.maxX - p, y: rect.minY + p))
        path.closeSubpath()
        return path
    }
}

struct HexagonPattern: Shape {
    func path(in rect: CGRect) -> Path {

        var path = Path()
        path.addEllipse(in: rect)
        return path
    }
}
