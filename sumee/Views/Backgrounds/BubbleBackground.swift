import SwiftUI

enum BubblePosition {
    case left
    case center
    case right
}

struct BubbleBackground: View {
    var position: BubblePosition = .center
    var cornerRadius: CGFloat = 24
    
    // Explicit dependencies for performance (Pure View)
    var theme: AppTheme
    var reduceTransparency: Bool
    

    // Explicit Overrides
    var overrideColor: Color? = nil
    var overrideStyle: SettingsManager.CustomBubbleStyle? = nil
    var overrideShowDots: Bool? = nil
    var overrideOpacity: Double? = nil
    var overrideBlurBubbles: Bool? = nil
    
    // Convenience init
    init(position: BubblePosition = .center, 
         cornerRadius: CGFloat = 24, 
         theme: AppTheme = SettingsManager.shared.activeTheme, 
         reduceTransparency: Bool = SettingsManager.shared.reduceTransparency,
         overrideColor: Color? = nil,
         overrideStyle: SettingsManager.CustomBubbleStyle? = nil,
         overrideShowDots: Bool? = nil,
         overrideOpacity: Double? = nil,
         overrideBlurBubbles: Bool? = nil) {
        self.position = position
        self.cornerRadius = cornerRadius
        self.theme = theme
        self.reduceTransparency = reduceTransparency
        self.overrideColor = overrideColor
        self.overrideStyle = overrideStyle
        self.overrideShowDots = overrideShowDots
        self.overrideOpacity = overrideOpacity
        self.overrideBlurBubbles = overrideBlurBubbles
    }
    
    private var resolvedBaseColor: Color {
        if theme.id == "custom_photo" {
            return overrideColor ?? SettingsManager.shared.customBubbleColor
        }
        return theme.bubbleTintColor ?? (theme.isDark ? (reduceTransparency ? Color(white: 0.1) : Color.black) : Color.white)
    }

    @ViewBuilder
    private func customBubbleSurface(
        cornerRadius: CGFloat,
        opacity: Double,
        showDots: Bool,
        isBlurEnabled: Bool
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)

        if #available(iOS 26.0, *), SettingsManager.shared.customBubbleUseLiquidGlass {
            customBubbleLayers(
                shape: shape,
                opacity: opacity,
                showDots: showDots,
                includeClassicBlur: false,
                includeBorder: false
            )
            .glassEffect(
                .regular.tint(resolvedBaseColor.opacity(opacity)),
                in: shape
            )
        } else {
            customBubbleLayers(
                shape: shape,
                opacity: opacity,
                showDots: showDots,
                includeClassicBlur: isBlurEnabled,
                includeBorder: true
            )
        }
    }

    @ViewBuilder
    private func customBubbleLayers<S: Shape>(
        shape: S,
        opacity: Double,
        showDots: Bool,
        includeClassicBlur: Bool,
        includeBorder: Bool
    ) -> some View {
        ZStack {
            if includeClassicBlur {
                shape
                    .fill(Material.ultraThin)
                    .environment(\.colorScheme, .dark)
            }

            shape
                .fill(resolvedBaseColor.opacity(opacity))

            if showDots {
                Canvas { context, size in
                    let spacing: CGFloat = 5.0
                    let dotSize: CGFloat = 1.5
                    let dotColor = Color.white.opacity(0.3)

                    for x in stride(from: 0, to: size.width, by: spacing) {
                        for y in stride(from: 0, to: size.height, by: spacing) {
                            let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                            context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                        }
                    }
                }
                .blendMode(.overlay)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            }

            if includeBorder {
                shape
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            }
        }
    }

    var body: some View {
        // Shared logic variables
        let isCustom = theme.id == "custom_photo"
        let showDots = overrideShowDots ?? (isCustom ? SettingsManager.shared.customShowDots : true)
        
        // Resolve Custom Settings
        let opacity = overrideOpacity ?? (isCustom ? SettingsManager.shared.customBubbleOpacity : 0.5)
        let isBlurEnabled = overrideBlurBubbles ?? (isCustom ? SettingsManager.shared.customBubbleBlurBubbles : true)
        
        Group {
            if isCustom {
                //CUSTOM RENDER LOGIC
                GeometryReader { geo in
                    let size = geo.size
                    let endRadius = max(size.width, size.height) * 0.8
                    
                    customBubbleSurface(
                        cornerRadius: cornerRadius,
                        opacity: opacity,
                        showDots: showDots,
                        isBlurEnabled: isBlurEnabled
                    )
                    .shadow(color: Color.black.opacity(0.1), radius: 6, x: 0, y: 4)
                }
            }
            // DEFAULT / STANDARD THEMES (Legacy Logic)
            else {
                if reduceTransparency {
                    // Performance Mode override
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(resolvedBaseColor)
                        .shadow(color: Color.black.opacity(0.15), radius: 6, x: 0, y: 4)
                } else {
                    // Glass Effect
                    GeometryReader { geo in
                        let size = geo.size
                        let endRadius = max(size.width, size.height) * 0.8
                        
                        ZStack {
                            // 1. Blur Base
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(Material.ultraThin)
                                .environment(\.colorScheme, theme.isDark ? .dark : .light)
                            
                            // 2. Gradient
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(
                                    RadialGradient(
                                        gradient: Gradient(stops: theme.isDark ? [
                                            .init(color: resolvedBaseColor.opacity(0.1), location: 0),
                                            .init(color: resolvedBaseColor.opacity(0.3), location: 0.6),
                                            .init(color: resolvedBaseColor.opacity(0.5), location: 0.95),
                                            .init(color: resolvedBaseColor.opacity(0.6), location: 1.0)
                                        ] : [
                                            .init(color: resolvedBaseColor.opacity(0.05), location: 0),
                                            .init(color: resolvedBaseColor.opacity(0.2), location: 0.6),
                                            .init(color: resolvedBaseColor.opacity(0.5), location: 0.95),
                                            .init(color: resolvedBaseColor.opacity(0.6), location: 1.0)
                                        ]),
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: endRadius
                                    )
                                )
                            
                            // 3. Dot Grid (Conditional)
                            if showDots {
                                Canvas { context, size in
                                    let spacing: CGFloat = 5.0
                                    let dotSize: CGFloat = 1.5
                                    let dotColor = theme.isDark ? Color.white.opacity(0.1) : Color.white.opacity(0.35)
                                    
                                    for x in stride(from: 0, to: size.width, by: spacing) {
                                        for y in stride(from: 0, to: size.height, by: spacing) {
                                            let rect = CGRect(x: x, y: y, width: dotSize, height: dotSize)
                                            context.fill(Path(ellipseIn: rect), with: .color(dotColor))
                                        }
                                    }
                                }
                                .blendMode(.overlay)
                                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            }
                            
                            // 4. Uniform Border Glow
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(theme.isDark ? Color.white.opacity(0.15) : Color.white, lineWidth: 3)
                                .blur(radius: 4)
                                .opacity(theme.isDark ? 0.3 : 0.6)
                            
                            // 5. Subtle Definition Rim
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .strokeBorder(Color.white, lineWidth: 1)
                                .opacity(theme.isDark ? 0.2 : 0.5)
                        }
                        .shadow(color: Color.black.opacity(0.15), radius: 10, x: 0, y: 8)
                    }
                }
            }
        }
    }
} 
