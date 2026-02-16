import SwiftUI

struct CustomThemeView: View {
    @ObservedObject var settings = SettingsManager.shared
    @State private var backgroundImage: UIImage? = SettingsManager.shared.getMemoryCachedCustomImage(blurred: SettingsManager.shared.customBlurBackground)
    @State private var gifData: Data?
    @State private var videoURL: URL?
    @State private var currentBlurState: Bool? = SettingsManager.shared.customBlurBackground // Sync state
    
    var body: some View {
        GeometryReader { geo in
            Group {
                if let videoUrl = videoURL, !settings.customBlurBackground {
                    LoopingVideoPlayer(videoURL: videoUrl)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false)
                        .overlay(Color.black.opacity(settings.customDarkenBackground ? 0.3 : 0.0))
                } else if let data = gifData, !settings.customBlurBackground {
                    // Render GIF
                    DataGIFView(gifData: data)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                        .allowsHitTesting(false) // CRITICAL: Ensure touches pass through to HomeView gesture
                        .overlay(Color.black.opacity(settings.customDarkenBackground ? 0.3 : 0.0))
                } else if let image = backgroundImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Slight zoom to fix blur edge artifacts if present
                        .scaleEffect(settings.customBlurBackground ? 1.05 : 1.0)
                        .clipped()
                        .overlay(Color.black.opacity(settings.customDarkenBackground ? 0.3 : 0.0))
                } else {
                    // Fallback placeholder
                    ZStack {
                        Color(UIColor.secondarySystemBackground)
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("No Image Selected")
                                .font(.headline)
                                .foregroundColor(.gray)
                            Text("Go to Themes to select a photo")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            // Load on background thread to prevent UI hitch
            DispatchQueue.global(qos: .userInitiated).async {
                loadCustomImage()
            }
        }
        .onChange(of: settings.customBlurBackground) { newValue in
            if currentBlurState != newValue {
                DispatchQueue.global(qos: .userInitiated).async {
                    loadCustomImage()
                }
            }
        }
        .onChange(of: settings.customBackgroundIsVideo) { _ in
             DispatchQueue.global(qos: .userInitiated).async {
                 loadCustomImage()
             }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RefreshCustomThemeImage"))) { _ in
            DispatchQueue.global(qos: .userInitiated).async {
                loadCustomImage()
            }
        }
    }
    
    private func loadCustomImage() {
        let isBlurred = settings.customBlurBackground
        
        // Logical Fork:
        // 1. If Blurred -> Show Static Blurred Image (Performance)
        // 2. If Not Blurred + Video -> Show Video
        // 3. If Not Blurred + GIF -> Show Animated GIF
        // 4. Else -> Show Static Image
        
        if !isBlurred && settings.customBackgroundIsVideo {
             if let url = settings.getCustomBackgroundVideoURL(),
                FileManager.default.fileExists(atPath: url.path) {
                 DispatchQueue.main.async {
                     self.videoURL = url
                     self.backgroundImage = nil
                     self.gifData = nil // Clear GIF
                     self.currentBlurState = isBlurred
                 }
                 return
             }
        }
        
        if !isBlurred && SettingsManager.shared.hasCustomGIF {
            // Load GIF Data
            if let data = SettingsManager.shared.loadCustomBackgroundGIFData() {
                DispatchQueue.main.async {
                    self.gifData = data
                    self.backgroundImage = nil // Clear static
                    self.videoURL = nil // Ensure Video is cleared
                    self.currentBlurState = isBlurred
                }
                return
            }
        }
        
        // Optimistic check: if we already have the right image loaded (and state matches), skip
        // Only if we aren't switching away from GIF or Video
        if currentBlurState == isBlurred && backgroundImage != nil && gifData == nil && videoURL == nil { return }
        
        // Fallback / Static
        if let image = SettingsManager.shared.loadCustomBackgroundImage(blurred: isBlurred) {
            DispatchQueue.main.async {
                self.backgroundImage = image
                self.gifData = nil // Clear GIF
                self.videoURL = nil // Ensure Video is cleared
                self.currentBlurState = isBlurred
            }
        }
    }
}
