import Foundation
import Combine
import UIKit
import SwiftUI
import AVFoundation

struct ThemeExport: Codable {
    let bubbleColorHex: String
    let opacity: Double
    let blurBubbles: Bool
    let showDots: Bool
    let transparentIcons: Bool
    let darkenBackground: Bool
    let blurBackground: Bool
    let musicFileName: String?
    let base64Image: String? // Optional: High quality JPEG base64
    // New: Explicit HSB for robust file persistence
    var hue: Double?
    var saturation: Double?
    var brightness: Double?
    
    // Music Data
    var musicBase64: String?
    var musicExtension: String?
    
    // 5. Console Icons (Map: Console RawValue -> Base64 String for export / Empty for local ref check)
    var consoleIcons: [String: String]?
    
    // 6. Text Color (isDark: true = Light Text, false = Dark Text)
    var isDark: Bool?
    
    // 7. System App Icons (Map: iconName -> Base64 String)
    var systemIcons: [String: String]?
    
    // 8. Video Background
    var base64Video: String?
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    static let liteModeKey = "settings.liteMode_v2" // Migrated key to fix persistence

    @Published var enableBackgroundMusic: Bool {
        didSet { UserDefaults.standard.set(enableBackgroundMusic, forKey: "settings.enableBackgroundMusic") }
    }
    @Published var enableUISounds: Bool {
        didSet { UserDefaults.standard.set(enableUISounds, forKey: "settings.enableUISounds") }
    }
    
    @Published var idleTimerDuration: Double { // Seconds. 0 = Disabled.
        didSet { UserDefaults.standard.set(idleTimerDuration, forKey: "settings.idleTimerDuration") }
    }

    @Published var backgroundVolume: Float {
        didSet { UserDefaults.standard.set(backgroundVolume, forKey: "settings.backgroundVolume") }
    }
    @Published var sfxVolume: Float {
        didSet { UserDefaults.standard.set(sfxVolume, forKey: "settings.sfxVolume") }
    }


    @Published var showBatteryPercentage: Bool {
        didSet { UserDefaults.standard.set(showBatteryPercentage, forKey: "settings.showBatteryPercentage") }
    }
    
    @Published var showFloatingCartridges: Bool {
        didSet { UserDefaults.standard.set(showFloatingCartridges, forKey: "settings.showFloatingCartridges") }
    }
    
    @Published var floatingCartridgesBlur: Bool {
        didSet { UserDefaults.standard.set(floatingCartridgesBlur, forKey: "settings.floatingCartridgesBlur") }
    }

    @Published var reduceTransparency: Bool {
        didSet { UserDefaults.standard.set(reduceTransparency, forKey: "settings.reduceTransparency") }
    }

    @Published var performanceMode: Bool {
        didSet { 
            UserDefaults.standard.set(performanceMode, forKey: "settings.performanceMode")
            if performanceMode {
                // Performance Mode automatically enables useful optimizations
                reduceTransparency = true
                floatingCartridgesBlur = false
                showFloatingCartridges = false
                showFloatingChat = false
            } else {
                // Restore standard visual fidelity
                reduceTransparency = false
                floatingCartridgesBlur = true
     
            }
        }
    }
    
    @Published var showFloatingChat: Bool {
        didSet { UserDefaults.standard.set(showFloatingChat, forKey: "settings.showFloatingChat") }
    }
    @Published var liteMode: Bool {
        didSet {
            // Guard to prevent redundant updates from resetting user preferences during app launch or binding updates
            if liteMode == oldValue { return }
            
            print("SettingsManager: [TRACE] liteMode changed to \(liteMode)")
            saveLiteModeToFile(liteMode)
            
            if liteMode {
                // Automatically disable start animation for better performance/lite experience
                UserDefaults.standard.set(true, forKey: "disableStartAnimation")
                
                // Disable visuals for Lite Mode
                showFloatingCartridges = false
                showFloatingChat = false
            } else {
                // If Lite Mode is disabled, restore the Start Animation (Enable it = disableStartAnimation: false)
                UserDefaults.standard.set(false, forKey: "disableStartAnimation")
                
                // Restore visuals automatically when exiting Lite Mode
                showFloatingCartridges = true
                // showFloatingChat = true // Disabled by default
            }
        }
    }
    
    // Auto-Save Toggle
    @Published var enableAutoSave: Bool {
        didSet { UserDefaults.standard.set(enableAutoSave, forKey: "settings.enableAutoSave") }
    }
    
    @Published var customSystemIcons: [String: String] = [:] // IconName -> FileName
    
    // Explicit setter with verification
    func setLiteMode(_ enabled: Bool) {
        if liteMode != enabled {
             print(" SettingsManager: Toggling Lite Mode to \(enabled) (Was: \(liteMode))")
             liteMode = enabled
             // Explicit save handled by didSet
        } else {
             print(" SettingsManager: Lite Mode update skipped (Already \(enabled))")
        }
    }

    private func saveCustomIconMap() {
        if let data = try? JSONEncoder().encode(customSystemIcons) {
            UserDefaults.standard.set(data, forKey: "settings.customSystemIcons")
        }
    }
    
    private func getCustomIconDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let url = documentsDirectory.appendingPathComponent("CustomSystemIcons", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
    
    func saveCustomSystemIcon(data: Data, for iconName: String) {
        guard let dir = getCustomIconDirectory() else { return }
        
        // Generate Unique Filename
        let fileName = "\(iconName)_\(UUID().uuidString).png"
        let fileURL = dir.appendingPathComponent(fileName)
        
        do {
            try data.write(to: fileURL)
            
            // Remove old file if exists
            if let oldFile = customSystemIcons[iconName] {
                 let oldURL = dir.appendingPathComponent(oldFile)
                 try? FileManager.default.removeItem(at: oldURL)
            }
            
            customSystemIcons[iconName] = fileName
            saveCustomIconMap()
            
            // Notify
            NotificationCenter.default.post(name: Notification.Name("RefreshAppIcons"), object: nil)
            print("SettingsManager: Saved custom icon for \(iconName)")
        } catch {
            print("SettingsManager: Failed to save custom icon: \(error)")
        }
    }
    
    func getCustomIconPath(for iconName: String) -> URL? {
        guard let fileName = customSystemIcons[iconName],
              let dir = getCustomIconDirectory() else { return nil }
        return dir.appendingPathComponent(fileName)
    }
    
    func getCustomSystemIcon(named iconName: String, ignoreActiveTheme: Bool = false) -> UIImage? {
        // Only show custom icons if the active theme is the Custom Theme
        if !ignoreActiveTheme && activeThemeID != "custom_photo" {
            return nil
        }

        guard let url = getCustomIconPath(for: iconName),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    
    func resetCustomSystemIcon(for iconName: String) {
        if let fileName = customSystemIcons[iconName],
           let dir = getCustomIconDirectory() {
            let url = dir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        customSystemIcons.removeValue(forKey: iconName)
        saveCustomIconMap()
        NotificationCenter.default.post(name: Notification.Name("RefreshAppIcons"), object: nil)
    }
    
    func deleteAllCustomSystemIcons() {
        guard let dir = getCustomIconDirectory() else { return }
        
        // 1. Delete all tracked files
        for fileName in customSystemIcons.values {
            let url = dir.appendingPathComponent(fileName)
            try? FileManager.default.removeItem(at: url)
        }
        
        // 2. Clear map
        customSystemIcons.removeAll()
        saveCustomIconMap()
        
        // 3. Notify
        NotificationCenter.default.post(name: Notification.Name("RefreshAppIcons"), object: nil)
    }

    //  File Persistence for Reliable Lite Mode
    private func getLiteModeFileURL() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsDirectory.appendingPathComponent("lite_mode_config.json")
    }

    private func saveLiteModeToFile(_ enabled: Bool) {
        guard let url = getLiteModeFileURL() else { return }
        do {
            let data = try JSONEncoder().encode(["liteMode": enabled])
            try data.write(to: url)
            print(" SettingsManager: Saved Lite Mode (\(enabled)) to file: \(url.path)")
        } catch {
            print(" SettingsManager: Failed to save Lite Mode to file: \(error)")
        }
    }

    public func loadLiteModeFromFile() -> Bool {
        guard let url = getLiteModeFileURL(),
              let data = try? Data(contentsOf: url),
              let json = try? JSONDecoder().decode([String: Bool].self, from: data),
              let value = json["liteMode"] else {
            return false // Default to false if missing
        }
        print("📂 SettingsManager: Loaded Lite Mode (\(value)) from file")
        return value
    }

    @Published var activeThemeID: String {
        didSet {
            UserDefaults.standard.set(activeThemeID, forKey: "settings.activeThemeID")
            // Sync activeTheme immediately
            let newTheme = ThemeRegistry.allThemes.first(where: { $0.id == activeThemeID }) ?? ThemeRegistry.standard
            activeTheme = newTheme
            
            // Enforce Icon Style from Theme
     
            if newTheme.iconSet == 2 {
                if !useTransparentIcons { useTransparentIcons = true }
            } else {
                if useTransparentIcons { useTransparentIcons = false }
            }
        }
    }
    @Published var useTransparentIcons: Bool {
        didSet { 
            UserDefaults.standard.set(useTransparentIcons, forKey: "settings.useTransparentIcons")
            // Sync to ProfileManager immediately for reactivity
            ProfileManager.shared.iconSet = useTransparentIcons ? 2 : 1
            // Trigger UI update if needed via notification?
            NotificationCenter.default.post(name: Notification.Name("RefreshAppIcons"), object: nil)
        }
    }
    
    @Published var installedThemeIDs: [String] {
        didSet {
            UserDefaults.standard.set(installedThemeIDs, forKey: "settings.installedThemeIDs")
        }
    }
    
    // Cached property for O(1) access
    @Published var activeTheme: AppTheme
    
    // Legacy flags support (Computed for backward compatibility if needed, else removed)

    private init() {
        // Load defaults
        let d = UserDefaults.standard
        enableBackgroundMusic = d.object(forKey: "settings.enableBackgroundMusic") != nil ? d.bool(forKey: "settings.enableBackgroundMusic") : true
        enableUISounds = d.object(forKey: "settings.enableUISounds") != nil ? d.bool(forKey: "settings.enableUISounds") : true
        
        idleTimerDuration = d.object(forKey: "settings.idleTimerDuration") as? Double ?? 30.0

        backgroundVolume = d.object(forKey: "settings.backgroundVolume") as? Float ?? 0.3
        sfxVolume = d.object(forKey: "settings.sfxVolume") as? Float ?? 0.6


        showBatteryPercentage = d.bool(forKey: "settings.showBatteryPercentage")
        
        showFloatingCartridges = d.object(forKey: "settings.showFloatingCartridges") != nil ? d.bool(forKey: "settings.showFloatingCartridges") : true
        // Floating Chat disabled by default
        showFloatingChat = d.object(forKey: "settings.showFloatingChat") != nil ? d.bool(forKey: "settings.showFloatingChat") : false
        
        floatingCartridgesBlur = d.object(forKey: "settings.floatingCartridgesBlur") != nil ? d.bool(forKey: "settings.floatingCartridgesBlur") : true

        reduceTransparency = d.bool(forKey: "settings.reduceTransparency")
        
        let finalPerformanceMode: Bool
        if d.object(forKey: "settings.performanceMode") != nil {
            finalPerformanceMode = d.bool(forKey: "settings.performanceMode")
        } else {
            // Auto-enable for older devices (iPhone 15 and below)
            let shouldEnable = SettingsManager.isOlderDevice()
            finalPerformanceMode = shouldEnable
            if shouldEnable {
                print(" SettingsManager: Detected older device (iPhone 15 or older). Performance Mode ENABLED by default.")
            }
        }
        performanceMode = finalPerformanceMode

        // Force Apply Side Effects (didSet doesn't fire in init)
        if finalPerformanceMode {
            reduceTransparency = true
            floatingCartridgesBlur = false
            showFloatingCartridges = false
            showFloatingChat = false
            print(" SettingsManager: Performance Mode Active -> Applied optimizations (Blur: OFF, Transparency: REDUCED)")
        }

        // Force sync before reading critical launch flags
        d.synchronize()
        // Initialize Lite Mode from FILE (Nuclear Persistence)
        liteMode = false 
        // Load real value from file
        let loadedLiteMode = d.bool(forKey: SettingsManager.liteModeKey)
        
        liteMode = false // Temporary
        enableAutoSave = d.object(forKey: "settings.enableAutoSave") != nil ? d.bool(forKey: "settings.enableAutoSave") : true
  

        
        let loadedID = d.string(forKey: "settings.activeThemeID") ?? "standard"
        activeThemeID = loadedID
        // Initialize cached theme using local variable to avoid capturing 'self'
        let finalActiveTheme = ThemeRegistry.allThemes.first(where: { $0.id == loadedID }) ?? ThemeRegistry.standard
        activeTheme = finalActiveTheme
        
        useTransparentIcons = d.object(forKey: "settings.useTransparentIcons") as? Bool ?? false
        
        // Sync Icon Style on Launch (Crucial for Custom Theme persistence)
        if finalActiveTheme.iconSet == 2 {
            // Theme enforces Transparent
            useTransparentIcons = true
        } else if finalActiveTheme.iconSet == 1 {
            // Theme enforces Solid
            useTransparentIcons = false
        }
        
        let savedInstalledIDs = d.stringArray(forKey: "settings.installedThemeIDs") ?? []
        if savedInstalledIDs.isEmpty {
             // Defaults: All themes installed EXCEPT "new_year" (and transparent_icons if not in array)
             installedThemeIDs = [
                 "standard", 
                 "dark_mode", 
                 "grid", 
                 "christmas", 
                 "homebrew", 
                 "sumee_xmb", 
                 "sumee_xmb_black",
                 "custom_photo"
             ]
        } else {
             var loadedIDs = savedInstalledIDs
             if !loadedIDs.contains("custom_photo") {
                 loadedIDs.append("custom_photo")
             }
             installedThemeIDs = loadedIDs
        }
        
        // Migration: Load legacy Hex if Hue/Sat not yet saved
        let legacyHex = d.string(forKey: "settings.customBubbleColorHex")
        
        customShowDots = d.object(forKey: "settings.customShowDots") as? Bool ?? true
        customBlurBackground = d.object(forKey: "settings.customBlurBackground") as? Bool ?? false
        customDarkenBackground = d.object(forKey: "settings.customDarkenBackground") as? Bool ?? false
        customThemeMusic = d.string(forKey: "settings.customThemeMusic")
        
        let styleRaw = d.object(forKey: "settings.customBubbleStyle") as? Int ?? 0 // Default Blur
        customBubbleStyle = CustomBubbleStyle(rawValue: styleRaw) ?? .blur
        
        customBackgroundIsVideo = d.object(forKey: "settings.customBackgroundIsVideo") as? Bool ?? false
        
        customBubbleOpacity = d.object(forKey: "settings.customBubbleOpacity") as? Double ?? 0.5
        customBubbleBlurBubbles = d.object(forKey: "settings.customBubbleBlurBubbles") as? Bool ?? true
        let loadedHue = d.object(forKey: "settings.customBubbleHue") as? Double
        let loadedSat = d.object(forKey: "settings.customBubbleSaturation") as? Double
        
        // Load Custom Icons
        if let data = d.data(forKey: "settings.customSystemIcons"),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            customSystemIcons = decoded
        }
        
        if let h = loadedHue, let s = loadedSat {
            customBubbleHue = h
            customBubbleSaturation = s
        } else if let hex = legacyHex {
            // Migration: Convert hex to HSB
           
            
            var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
            var rgb: UInt64 = 0
            if Scanner(string: hexSanitized).scanHexInt64(&rgb) {
                let length = hexSanitized.count
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
                if length == 6 {
                    r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
                    g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
                    b = CGFloat(rgb & 0x0000FF) / 255.0
                } else if length == 8 {
                    r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
                    g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
                    b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
                }
                
                let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1.0)
                var h: CGFloat = 0
                var s: CGFloat = 0
                var br: CGFloat = 0
                var al: CGFloat = 0
                uiColor.getHue(&h, saturation: &s, brightness: &br, alpha: &al)
                customBubbleHue = Double(h)
                customBubbleSaturation = Double(s)
            } else {
                customBubbleHue = 0
                customBubbleSaturation = 0
            }
        } else {
            customBubbleHue = 0.0
            customBubbleSaturation = 0.0
        }
        
        
        customBubbleBrightness = d.object(forKey: "settings.customBubbleBrightness") as? Double ?? 1.0
        customThemeIsDark = true // Default to Dark Theme (White Text)
        
        // HYDRATE FROM FILE (Overrides UserDefaults if present)
        ensureThemeFileExists() // Creates defaults if missing
        loadThemeFromFile()
        
        // Load persistency for Lite Mode
        liteMode = loadLiteModeFromFile()
        
        // Ensure hex string is consistent on load if needed, but we rely on Hue/Sat now
        
        print(" SettingsManager: Init complete. Lite Mode = \(liteMode) (Key: \(SettingsManager.liteModeKey))")
    }

    func resetToDefaults() {
        print("SettingsManager: [TRACE] resetToDefaults() CALLED! Resetting Lite Mode to FALSE")
        enableBackgroundMusic = true
        enableUISounds = true
        idleTimerDuration = 30.0

        backgroundVolume = 0.3
        sfxVolume = 0.6


        showBatteryPercentage = false
        floatingCartridgesBlur = true

        reduceTransparency = false
        performanceMode = false
        liteMode = false
        enableAutoSave = true
        activeThemeID = "grid"
        activeTheme = ThemeRegistry.grid
        useTransparentIcons = false
        installedThemeIDs = [
            "standard", 
            "dark_mode", 
            "grid", 
            "christmas", 
            "homebrew", 
            "sumee_xmb", 
            "sumee_xmb_black",
            "custom_photo"
        ]
    }
    
    // Custom Theme Logic
    
  
    
    private var cachedCustomImage: UIImage?
    private var cachedCustomBlurImage: UIImage?
    
    func getCustomBackgroundImageURL() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsDirectory.appendingPathComponent("custom_bg.jpg")
    }

    func getCustomBlurredBackgroundImageURL() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsDirectory.appendingPathComponent("custom_bg_blur.jpg")
    }

    func getCustomBackgroundGIFURL() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsDirectory.appendingPathComponent("custom_bg.gif")
    }
    
    func getCustomBackgroundVideoURL() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        return documentsDirectory.appendingPathComponent("custom_bg.mp4")
    }
    
    var hasCustomGIF: Bool {
        guard let url = getCustomBackgroundGIFURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    var hasCustomVideo: Bool {
        guard let url = getCustomBackgroundVideoURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    
    func loadCustomBackgroundGIFData() -> Data? {
        guard let url = getCustomBackgroundGIFURL() else { return nil }
        return try? Data(contentsOf: url)
    }
    
    func getMemoryCachedCustomImage(blurred: Bool) -> UIImage? {
        return blurred ? cachedCustomBlurImage : cachedCustomImage
    }

    func loadCustomBackgroundImage(blurred: Bool = false) -> UIImage? {
        // Return memory cached image if available
        if let cached = getMemoryCachedCustomImage(blurred: blurred) {
             return cached
        }
        
        guard let url = blurred ? getCustomBlurredBackgroundImageURL() : getCustomBackgroundImageURL(),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        
        // Cache for future use
        if blurred {
            self.cachedCustomBlurImage = image
        } else {
            self.cachedCustomImage = image
        }
        return image
    }
    
    func saveCustomBackgroundImage(_ image: UIImage) {
        // If saving an image, ensure we delete any existing GIF so it takes precedence
        if let gifUrl = getCustomBackgroundGIFURL() {
            try? FileManager.default.removeItem(at: gifUrl)
        }
        
        guard let url = getCustomBackgroundImageURL() else { return }
        
        // 1. Resize Image (Max 1920x1080 to save memory/performance)
        let resizedImage = resizeImage(image, targetSize: CGSize(width: 1920, height: 1080))
        
        // 2. Wrap in Task to perform disk I/O off the main thread if called from UI, 
      
        // Update Cache immediately
        self.cachedCustomImage = resizedImage
        
        // 3. Save to Disk (Normal)
        if let data = resizedImage.jpegData(compressionQuality: 0.8) { 
            try? data.write(to: url)
        }

        // 4. Generate and Save Blurred Version
        if let blurUrl = getCustomBlurredBackgroundImageURL() {
            let blurredImage = applyBlur(to: resizedImage, radius: 20)
            self.cachedCustomBlurImage = blurredImage
            if let blurData = blurredImage.jpegData(compressionQuality: 0.8) {
                try? blurData.write(to: blurUrl)
            }
        }
        
        // Notify UI to refresh
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("RefreshCustomThemeImage"), object: nil)
        }
    }
    
    func saveCustomBackgroundImage(data: Data) {
        // Check for Video Header (ftyp) - Often at bytes 4-8
        let header = data.prefix(12)
        let headerString = String(data: header, encoding: .ascii) ?? ""
        
        // Basic check for MP4/MOV signatures
        if headerString.contains("ftyp") {
            if let videoUrl = getCustomBackgroundVideoURL() {
                try? data.write(to: videoUrl)
                print("Saved Custom Wallpaper as Video")
                
                self.customBackgroundIsVideo = true
                
                // Clear GIF to avoid confusion
                if let gifUrl = getCustomBackgroundGIFURL() {
                    try? FileManager.default.removeItem(at: gifUrl)
                }
                
                // Generate Thumbnail & Blur
                generateThumbnailRaw(from: videoUrl) { thumbnail in
                    guard let thumbnail = thumbnail else { return }
                    
                    // Save as main background image (fallback/preview)
                    if let jpgUrl = self.getCustomBackgroundImageURL(),
                       let jpgData = thumbnail.jpegData(compressionQuality: 0.8) {
                        try? jpgData.write(to: jpgUrl)
                    }
                    
                    // Cache
                    self.cachedCustomImage = thumbnail
                    
                    // Blur
                    if let blurUrl = self.getCustomBlurredBackgroundImageURL() {
                        let blurred = self.applyBlur(to: thumbnail, radius: 20)
                        self.cachedCustomBlurImage = blurred
                        if let blurData = blurred.jpegData(compressionQuality: 0.7) {
                            try? blurData.write(to: blurUrl)
                        }
                    }
                    
                    // Notify UI
                    DispatchQueue.main.async {
                        NotificationCenter.default.post(name: Notification.Name("RefreshCustomThemeImage"), object: nil)
                    }
                }
                return
            }
        }
        
        self.customBackgroundIsVideo = false
        
        // Remove video if replacing with image/gif
        if let videoUrl = getCustomBackgroundVideoURL() {
            try? FileManager.default.removeItem(at: videoUrl)
        }

        // Check signature for GIF (GIF87a or GIF89a)
        if String(data: header.prefix(3), encoding: .ascii) == "GIF" {
            // It is a GIF!
            if let gifUrl = getCustomBackgroundGIFURL() {
                try? data.write(to: gifUrl)
                print(" Saved Custom Wallpaper as GIF")
                
                // Clear JPG to ensure GIF is prioritized
                if let jpgUrl = getCustomBackgroundImageURL() {
                    try? FileManager.default.removeItem(at: jpgUrl)
                }
                
                // Generate a static preview for caching (First frame)
                if let source = CGImageSourceCreateWithData(data as CFData, nil),
                   let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                    let image = UIImage(cgImage: cgImage)
                    self.cachedCustomImage = image
                    
                    // Generate blur from first frame
                    if let blurUrl = getCustomBlurredBackgroundImageURL() {
                        let blurredImage = applyBlur(to: image, radius: 20)
                        self.cachedCustomBlurImage = blurredImage
                        if let blurData = blurredImage.jpegData(compressionQuality: 0.7) {
                            try? blurData.write(to: blurUrl)
                        }
                    }
                }
            }
        } else {
            // Fallback to Image
            if let image = UIImage(data: data) {
                saveCustomBackgroundImage(image)
            }
        }
        
        // Notify UI to refresh
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("RefreshCustomThemeImage"), object: nil)
        }
    }
    
    private func generateThumbnailRaw(from url: URL, completion: @escaping (UIImage?) -> Void) {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        
        let time = CMTime(seconds: 0.0, preferredTimescale: 600)
        
        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, image, _, _, _ in
            DispatchQueue.main.async {
                if let image = image {
                    completion(UIImage(cgImage: image))
                } else {
                    completion(nil)
                }
            }
        }
    }
    
    private func resizeImage(_ image: UIImage, targetSize: CGSize) -> UIImage {
        let size = image.size
        
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Figure out what our orientation is, and use that to form the rectangle
        var newSize: CGSize
        if(widthRatio > heightRatio) {
            newSize = CGSize(width: size.width * heightRatio, height: size.height * heightRatio)
        } else {
            newSize = CGSize(width: size.width * widthRatio,  height: size.height * widthRatio)
        }
        
        // This is the rect that we've calculated out and this is what is actually used below
        let rect = CGRect(x: 0, y: 0, width: newSize.width, height: newSize.height)
        
        // Actually do the resizing to the rect using the ImageContext stuff
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: rect)
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return newImage ?? image
    }

    private func applyBlur(to image: UIImage, radius: CGFloat) -> UIImage {
        guard let ciImage = CIImage(image: image) ?? CIImage(image: image, options: nil),
              let filter = CIFilter(name: "CIGaussianBlur") else { return image }
        
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(radius, forKey: kCIInputRadiusKey)
        
        guard let output = filter.outputImage else { return image }
        
        let context = CIContext()
        // Crop input to extent to avoid black edges (though simple crop works too)
        guard let cgImage = context.createCGImage(output, from: ciImage.extent) else { return image }
        return UIImage(cgImage: cgImage)
    }
    
    // Custom Bubble Style
    enum CustomBubbleStyle: Int, Codable {
        case blur = 0
        case solid = 1
        case transparent = 2
    }
    
    @Published var customShowDots: Bool {
        didSet { /* UserDefaults.standard.set(customShowDots, forKey: "settings.customShowDots") */ }
    }
    
    @Published var customBubbleStyle: CustomBubbleStyle {
        didSet { UserDefaults.standard.set(customBubbleStyle.rawValue, forKey: "settings.customBubbleStyle") }
    }
    
    @Published var customBackgroundIsVideo: Bool {
        didSet { UserDefaults.standard.set(customBackgroundIsVideo, forKey: "settings.customBackgroundIsVideo") }
    }
    
    @Published var customBubbleOpacity: Double {
        didSet { /* UserDefaults.standard.set(customBubbleOpacity, forKey: "settings.customBubbleOpacity") */ }
    }
    
    @Published var customBubbleBlurBubbles: Bool {
        didSet { /* UserDefaults.standard.set(customBubbleBlurBubbles, forKey: "settings.customBubbleBlurBubbles") */ }
    }
    
    // Custom Bubble Color Persistence (Now via Hue/Sat for reliability)
    
    @Published var customBubbleHue: Double {
        didSet { /* UserDefaults.standard.set(customBubbleHue, forKey: "settings.customBubbleHue") */ }
    }
    
    @Published var customBubbleBrightness: Double {
        didSet { /* UserDefaults.standard.set(customBubbleBrightness, forKey: "settings.customBubbleBrightness") */ }
    }
    
    @Published var customBubbleSaturation: Double {
        didSet { /* UserDefaults.standard.set(customBubbleSaturation, forKey: "settings.customBubbleSaturation") */ }
    }
    
    // Kept for legacy/export, computed from Hue/Sat
    var customBubbleColorHex: String {
        let color = Color(hue: customBubbleHue, saturation: customBubbleSaturation, brightness: customBubbleBrightness)
        return hexString(from: color)
    }
    
    @Published var customDarkenBackground: Bool {
        didSet { /* UserDefaults.standard.set(customDarkenBackground, forKey: "settings.customDarkenBackground") */ }
    }

    @Published var customBlurBackground: Bool {
        didSet { /* UserDefaults.standard.set(customBlurBackground, forKey: "settings.customBlurBackground") */ }
    }
    
    @Published var customThemeMusic: String? {
        didSet { UserDefaults.standard.set(customThemeMusic, forKey: "settings.customThemeMusic") }
    }
    
    @Published var customThemeIsDark: Bool {
        didSet { /* UserDefaults.standard.set(customThemeIsDark, forKey: "settings.customThemeIsDark") */ }
    }
    
    //  Private Color Helpers
    
    private func hexString(from color: Color) -> String {
        guard let components = UIColor(color).cgColor.components, components.count >= 3 else {
            return "#FFFFFF"
        }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        var a = Float(1.0)
        
        if components.count >= 4 {
            a = Float(components[3])
        }

        if a != 1.0 {
            return String(format: "#%02lX%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255), lroundf(a * 255))
        } else {
            return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
        }
    }
    
    private func color(fromHex hex: String) -> Color {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        var r: CGFloat = 0.0
        var g: CGFloat = 0.0
        var b: CGFloat = 0.0
        var a: CGFloat = 1.0

        let length = hexSanitized.count

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return .white }

        if length == 6 {
            r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
            g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
            b = CGFloat(rgb & 0x0000FF) / 255.0

        } else if length == 8 {
            r = CGFloat((rgb & 0xFF000000) >> 24) / 255.0
            g = CGFloat((rgb & 0x00FF0000) >> 16) / 255.0
            b = CGFloat((rgb & 0x0000FF00) >> 8) / 255.0
            a = CGFloat(rgb & 0x000000FF) / 255.0
        }

        return Color(red: r, green: g, blue: b, opacity: a)
    }

    var customBubbleColor: Color {
        return Color(hue: customBubbleHue, saturation: customBubbleSaturation, brightness: customBubbleBrightness)
    }
    
    func setCustomBubbleColor(hue: Double, saturation: Double, brightness: Double = 1.0) {
        self.customBubbleHue = hue
        self.customBubbleSaturation = saturation
        self.customBubbleBrightness = brightness
    }

    // Explicit Commit for Restart Logic
    func commitCustomTheme(hue: Double, saturation: Double, opacity: Double, showDots: Bool, blurBubbles: Bool, darkenBG: Bool, blurBG: Bool, brightness: Double, transparentIcons: Bool, isDark: Bool) {
        print(" SettingsManager: Committing Custom Theme to File...")
        
        // 1. Update In-Memory State (for immediate UI reflection on current run)
        self.customBubbleHue = hue
        self.customBubbleSaturation = saturation
        self.customBubbleOpacity = opacity
        self.customShowDots = showDots
        self.customBubbleBlurBubbles = blurBubbles
        self.customDarkenBackground = darkenBG
        self.customBlurBackground = blurBG
        self.customBubbleBrightness = brightness
        self.customThemeIsDark = isDark

        // 2. Prepare Data for File Persistence
        let exportData = ThemeExport(
            bubbleColorHex: hexString(from: Color(hue: hue, saturation: saturation, brightness: brightness)),
            opacity: opacity,
            blurBubbles: blurBubbles,
            showDots: showDots,
            transparentIcons: transparentIcons,
            darkenBackground: darkenBG,
            blurBackground: blurBG,
            musicFileName: customThemeMusic,
            base64Image: nil, // We don't save image inside JSON for local persistence, keep generic
            hue: hue,
            saturation: saturation,
            brightness: brightness,
            musicBase64: nil,
            musicExtension: nil,
            consoleIcons: nil,
            isDark: isDark
        )
        
        // 3. Save to "Documents/Themes/current_theme.json"
        saveThemeToFile(exportData)
        
        // 4. Force Update 'activeTheme' if we are currently using the custom theme
      
        if activeThemeID == "custom_photo" {
            DispatchQueue.main.async {
                self.activeTheme = ThemeRegistry.customTheme
            }
        }
        
        print("SettingsManager: Custom Theme Committed to File.")
    }
    
    // File Persistence Helpers
    
    private func getThemeFileURL() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let themesDir = documentsDirectory.appendingPathComponent("Themes")
        
        if !FileManager.default.fileExists(atPath: themesDir.path) {
            try? FileManager.default.createDirectory(at: themesDir, withIntermediateDirectories: true)
        }
        
        return themesDir.appendingPathComponent("current_theme.json")
    }
    
    private func saveThemeToFile(_ theme: ThemeExport) {
        guard let url = getThemeFileURL() else { return }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(theme) {
            try? data.write(to: url)
            print("📁 Saved theme JSON to: \(url.path)")
        }
    }
    
    func ensureThemeFileExists() {
        guard let url = getThemeFileURL() else { return }
        
        if !FileManager.default.fileExists(atPath: url.path) {
            print("SettingsManager: Theme file missing. Creating defaults from bundle...")
            
            // Try to load from bundle "theme_default.json"
            if let bundleUrl = Bundle.main.url(forResource: "theme_default", withExtension: "json") {
                do {
                    // Read data
                    let data = try Data(contentsOf: bundleUrl)
                    if let jsonString = String(data: data, encoding: .utf8) {
                        // Use importTheme logic to handle Image/Music extraction + Persistence
        
                        let success = importTheme(jsonString: jsonString)
                        
                        if success {
                            print("SettingsManager: Successfully imported default theme from bundle.")
                        } else {
                            print(" SettingsManager: Import failed for bundled theme. Fallback to hardcoded.")
                            createHardcodedDefaultTheme(at: url)
                        }
                    } else {
                         print(" SettingsManager: Could not decode bundled theme string.")
                         createHardcodedDefaultTheme(at: url)
                    }
                } catch {
                    print(" SettingsManager: Failed to read bundled theme: \(error)")
                    // Fallback to hardcoded if copy fails
                    createHardcodedDefaultTheme(at: url)
                }
            } else {
                print(" SettingsManager: Bundled theme_default.json not found. Using hardcoded defaults.")
                createHardcodedDefaultTheme(at: url)
            }
        }
    }
    
    private func createHardcodedDefaultTheme(at url: URL) {
        // Create Default Theme (Fallback)
        let defaultTheme = ThemeExport(
            bubbleColorHex: "#AF52DE", // Purple
            opacity: 0.5,
            blurBubbles: true,
            showDots: true,
            transparentIcons: false,
            darkenBackground: false,
            blurBackground: false,
            musicFileName: nil,
            base64Image: nil,
            hue: 0.77, // Purple Hue approx
            saturation: 0.63,
            brightness: 1.0,
            musicBase64: nil,
            musicExtension: nil,
            consoleIcons: nil,
            isDark: true // Default to Light Text (Dark Theme)
        )
        saveThemeToFile(defaultTheme)
    }
    
    func loadThemeFromFile() {
        guard let url = getThemeFileURL(),
              let data = try? Data(contentsOf: url) else {
            print(" No custom theme file found at path.")
            return
        }
        
        let decoder = JSONDecoder()
        if let theme = try? decoder.decode(ThemeExport.self, from: data) {
            print(" Loaded custom theme from file.")
            
            // Apply to Memory
            self.customBubbleHue = theme.hue ?? 0.0 // Fallback if old export format
            self.customBubbleSaturation = theme.saturation ?? 0.0
            self.customBubbleBrightness = theme.brightness ?? 1.0
            
            // If legacy export without HSB explicit fields used hex
            if theme.hue == nil {
               // Fallback hex logic if needed, but for our file we add HSB fields
               let color = self.color(fromHex: theme.bubbleColorHex)
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                UIColor(color).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                self.customBubbleHue = h
                self.customBubbleSaturation = s
                self.customBubbleBrightness = b
            }

            self.customBubbleOpacity = theme.opacity
            self.customShowDots = theme.showDots
            self.customBubbleBlurBubbles = theme.blurBubbles
            self.customDarkenBackground = theme.darkenBackground
            self.customBlurBackground = theme.blurBackground
            self.customThemeMusic = theme.musicFileName
            self.useTransparentIcons = theme.transparentIcons // Load Transparent Icons Setting
            
            // 6. Load Text Color Preference
            self.customThemeIsDark = theme.isDark ?? true

            // Image is handled separately via caching/file path standard logic
        }
    }

    
    // Theme Export / Import
    
    func exportTheme() -> String? {
        // 1. Get current background (Video, GIF, or Image)
        var base64String: String? = nil
        var base64VideoString: String? = nil
        
        // Priority 1: Video
        if customBackgroundIsVideo, 
           let videoURL = getCustomBackgroundVideoURL(),
           let videoData = try? Data(contentsOf: videoURL) {
            
            base64VideoString = videoData.base64EncodedString()
            print(" Exporting Video Wallpaper (\(videoData.count / 1024 / 1024) MB)")
            
            // Also export the thumbnail/image as fallback 'base64Image'
            if let image = loadCustomBackgroundImage(blurred: false) {
                 let resized = resizeImage(image, targetSize: CGSize(width: 1080, height: 1920))
                 if let data = resized.jpegData(compressionQuality: 0.8) {
                     base64String = data.base64EncodedString()
                 }
            }
        }
        // Priority 2: GIF
        else if hasCustomGIF, let gifData = loadCustomBackgroundGIFData() {
            // Export raw GIF data
            base64String = gifData.base64EncodedString()
            print(" Exporting GIF Wallpaper (\(gifData.count / 1024) KB)")
        } 
        // Priority 3: Static Image
        else if let image = loadCustomBackgroundImage(blurred: false) {
            // Resize and Compress
            let resized = resizeImage(image, targetSize: CGSize(width: 1080, height: 1920))
            if let data = resized.jpegData(compressionQuality: 0.8) {
                base64String = data.base64EncodedString()
            }
        }
        
        // Prepare Console Icons Base64
        var iconsBase64: [String: String] = [:]

        for console in ROMItem.Console.allCases {
            if let icon = getCustomConsoleIcon(for: console) {
                if let data = icon.pngData() {
                    iconsBase64[console.rawValue] = data.base64EncodedString()
                }
            }
        }
        
        // Prepare System App Icons Base64
        var systemIconsBase64: [String: String] = [:]
        for (iconName, _) in customSystemIcons {
            if let url = getCustomIconPath(for: iconName),
               let data = try? Data(contentsOf: url) {
               systemIconsBase64[iconName] = data.base64EncodedString()
            }
        }
        
        // 2. Create struct
        let theme = ThemeExport(
            bubbleColorHex: customBubbleColorHex,
            opacity: customBubbleOpacity,
            blurBubbles: customBubbleBlurBubbles,
            showDots: customShowDots,
            transparentIcons: useTransparentIcons,
            darkenBackground: customDarkenBackground,
            blurBackground: customBlurBackground,
            musicFileName: customThemeMusic,
            base64Image: base64String,
            hue: customBubbleHue,
            saturation: customBubbleSaturation,
            brightness: customBubbleBrightness,
            musicBase64: nil, 
            musicExtension: nil,
            consoleIcons: iconsBase64.isEmpty ? nil : iconsBase64,
            isDark: customThemeIsDark,
            systemIcons: systemIconsBase64.isEmpty ? nil : systemIconsBase64,
            base64Video: base64VideoString
        )
        
        // 2a. Handle Music Export
        var finalTheme = theme
        if let musicName = customThemeMusic {
            // Check Documents/Music first (User content)
            let fileManager = FileManager.default
            if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                let musicDir = documentsPath.appendingPathComponent("Music")
                let extensions = ["mp3", "m4a", "wav", "aac"]
                
                for ext in extensions {
                    let fileURL = musicDir.appendingPathComponent("\(musicName).\(ext)")
                    if fileManager.fileExists(atPath: fileURL.path) {
                        // Found user file! Encode it.
                        if let musicData = try? Data(contentsOf: fileURL) {
                            // Size check: Warn or limit if > 15MB? For now, we assume reasonable MP3s.
                            finalTheme.musicBase64 = musicData.base64EncodedString()
                            finalTheme.musicExtension = ext
                            print(" Exporting Music: \(musicName).\(ext) (\(musicData.count / 1024) KB)")
                        }
                        break
                    }
                }
            }
        }
        
        // 3. Encode to JSON
        let encoder = JSONEncoder()
        if let jsonData = try? encoder.encode(finalTheme) {
            return String(data: jsonData, encoding: .utf8)
        }
        return nil
    }
    
    // Persistent Library Logic
    
    private func getThemesDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = documentsDirectory.appendingPathComponent("Themes", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // Old getImportedThemes removed (Moved to ThemeRegistry)
    
    func loadImportedTheme(id: String) -> Bool {
        guard id.hasPrefix("imported_") else { return false }
        let filename = String(id.dropFirst("imported_".count))
        
        guard let dir = getThemesDirectory() else { return false }
        let url = dir.appendingPathComponent("\(filename).json")
        
        guard let data = try? Data(contentsOf: url),
              let jsonString = String(data: data, encoding: .utf8) else {
            return false
        }
        
        // Apply using existing logic, but do NOT save as a duplicate file
        return importTheme(jsonString: jsonString, saveToFile: false)
    }

    func importTheme(jsonString: String, filename: String? = nil, saveToFile: Bool = true) -> Bool {
        guard let data = jsonString.data(using: .utf8) else { return false }
        
        let decoder = JSONDecoder()
        do {
            let theme = try decoder.decode(ThemeExport.self, from: data)
            
            // 0. Save to File (Library Persistence)
            if saveToFile {
                if let dir = getThemesDirectory() {
                    // Use provided filename or generate unique timestamp
                    let finalFilename: String
                    if let name = filename {
                        finalFilename = name
                    } else {
                        let formatter = DateFormatter()
                        formatter.dateFormat = "yyyyMMdd_HHmmss"
                        let timestamp = formatter.string(from: Date())
                        finalFilename = "Theme_\(timestamp).json"
                    }
                    
                    let url = dir.appendingPathComponent(finalFilename)
                    
                    try? jsonString.write(to: url, atomically: true, encoding: .utf8)
                    print(" Saved Imported Theme to Library: \(filename)")
                }
            }
            
            // 1. Handle Background (Video Priority)
            if let videoBase64 = theme.base64Video,
               let videoData = Data(base64Encoded: videoBase64) {
                // Save Video logic (auto-detects 'ftyp' and sets customBackgroundIsVideo = true)
                saveCustomBackgroundImage(data: videoData)
                print(" Imported Custom Video Background")
            } 
            else if let base64 = theme.base64Image,
               let imageData = Data(base64Encoded: base64) {
                // Pass raw data (GIF or Image)
                saveCustomBackgroundImage(data: imageData)
                print(" Imported Custom Image/GIF Background")
            }
            
            // 2. Handle Music Import
            if let musicBase64 = theme.musicBase64,
               let ext = theme.musicExtension,
               let musicName = theme.musicFileName,
               let musicData = Data(base64Encoded: musicBase64) {
               
                let fileManager = FileManager.default
                if let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first {
                    let musicDir = documentsPath.appendingPathComponent("Music")
                    try? fileManager.createDirectory(at: musicDir, withIntermediateDirectories: true)
                    
                    let finalURL = musicDir.appendingPathComponent("\(musicName).\(ext)")
                    do {
                        try musicData.write(to: finalURL)
                        print(" Imported Music: \(finalURL.path)")
                        
                        // Trigger Library Refresh
                        Task {
                            await MusicPlayerManager.shared.loadLibrary()
                        }
                    } catch {
                        print(" Failed to save imported music: \(error)")
                    }
                }
            }
            
            // 2.5 Handle Console Icons Import
            if let icons = theme.consoleIcons, !icons.isEmpty {
                // First clear existing to ensure clean state matching the theme exactly
                deleteAllCustomConsoleIcons()
                
                for (consoleRaw, base64) in icons {
                    if let console = ROMItem.Console(rawValue: consoleRaw),
                       let data = Data(base64Encoded: base64),
                       let image = UIImage(data: data) {
                         saveCustomConsoleIcon(image: image, for: console)
                         print("Imported Icon for: \(console.systemName)")
                    }
                }
                // Refresh Cache after bulk import
                refreshIconCache()
            } else {
                // If imported theme has no icons, clear current ones so they reset to default.
                deleteAllCustomConsoleIcons()
            }
            
            // 2.6 Handle System Icons Import
            if let sysIcons = theme.systemIcons, !sysIcons.isEmpty {
                // Clear existing
                deleteAllCustomSystemIcons()
                
                for (iconName, base64) in sysIcons {
                    if let data = Data(base64Encoded: base64) {
                        saveCustomSystemIcon(data: data, for: iconName)
                        print(" Imported System Icon for: \(iconName)")
                    }
                }
            } else {
                 deleteAllCustomSystemIcons()
            }
            
            // 3. Overwrite current_theme.json
     
            let localPersistenceTheme = ThemeExport(
                bubbleColorHex: theme.bubbleColorHex,
                opacity: theme.opacity,
                blurBubbles: theme.blurBubbles,
                showDots: theme.showDots,
                transparentIcons: theme.transparentIcons,
                darkenBackground: theme.darkenBackground,
                blurBackground: theme.blurBackground,
                musicFileName: theme.musicFileName,
                base64Image: nil, // Do not save base64 to local json
                hue: theme.hue,
                saturation: theme.saturation,
                brightness: theme.brightness,
                musicBase64: nil, // Do not save massive music data to local settings JSON
                musicExtension: nil,
                consoleIcons: nil, // Do not save base64 icons to local JSON
                isDark: theme.isDark ?? true, // Default to Light Text (Dark Theme) if missing
                systemIcons: nil // Do not save base64 icons to local JSON
            )
            
            saveThemeToFile(localPersistenceTheme)
            
            // 3. Refresh In-Memory State
            loadThemeFromFile()
            
            print(" SettingsManager: Theme Imported & Saved to File.")
            return true
            
        } catch {
            print(" SettingsManager: Failed to import theme: \(error)")
            return false
        }
    }

    // Console Custom Icons
    
    // Performance: Cache for checking existence and loaded images
    private var customIconExistenceCache: Set<String>? = nil
    private let iconImageCache = NSCache<NSString, UIImage>()

    private func getConsoleIconDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = documentsDirectory.appendingPathComponent("Themes/ConsoleIcons", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    // Refresh the existence cache (Call after any modification)
    private func refreshIconCache() {
        guard let dir = getConsoleIconDirectory() else { return }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            let files = urls.map { $0.lastPathComponent }
            customIconExistenceCache = Set(files)
        } catch {
            customIconExistenceCache = []
        }
        // Also clear memory image cache
        iconImageCache.removeAllObjects()
    }
    
    func saveCustomConsoleIcon(image: UIImage, for console: ROMItem.Console) {
        guard let dir = getConsoleIconDirectory() else { return }
        let fileURL = dir.appendingPathComponent("\(console.rawValue).png")
        
        // Resize constraint? Let's limit to 300x300
        let resized = resizeImage(image, targetSize: CGSize(width: 300, height: 300))
        
        if let data = resized.pngData() {
            try? data.write(to: fileURL)
            
            // Update Caches
            refreshIconCache()
            iconImageCache.setObject(resized, forKey: fileURL.path as NSString)
            
            // Post notification for UI refresh
             DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("RefreshConsoleIcons"), object: nil)
            }
        }
    }
    
    func getCustomConsoleIcon(for console: ROMItem.Console, ignoreActiveTheme: Bool = false) -> UIImage? {
        guard let path = getCustomConsoleIconPath(for: console, ignoreActiveTheme: ignoreActiveTheme) else { return nil }
        
        // Check Memory Cache
        if let cached = iconImageCache.object(forKey: path as NSString) {
            return cached
        }
        
        // Load from Disk
        if let image = UIImage(contentsOfFile: path) {
            iconImageCache.setObject(image, forKey: path as NSString)
            return image
        }
        return nil
    }
    
    func getCustomConsoleIconPath(for console: ROMItem.Console, ignoreActiveTheme: Bool = false) -> String? {
        // Only show custom icons if the active theme is the Custom Theme
        if !ignoreActiveTheme && activeThemeID != "custom_photo" {
            return nil
        }
        
        // Initialize cache if needed
        if customIconExistenceCache == nil { refreshIconCache() }
        
        guard let cache = customIconExistenceCache else { return nil }
        let filename = "\(console.rawValue).png"
        
        if cache.contains(filename) {
             guard let dir = getConsoleIconDirectory() else { return nil }
             return dir.appendingPathComponent(filename).path
        }
        return nil
    }
    
    func deleteCustomConsoleIcon(for console: ROMItem.Console) {
        guard let dir = getConsoleIconDirectory() else { return }
        let fileURL = dir.appendingPathComponent("\(console.rawValue).png")
        try? FileManager.default.removeItem(at: fileURL)
        refreshIconCache()
         DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("RefreshConsoleIcons"), object: nil)
        }
    }
    
    private func deleteAllCustomConsoleIcons() {
        guard let dir = getConsoleIconDirectory() else { return }
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            for fileURL in fileURLs {
                try FileManager.default.removeItem(at: fileURL)
            }
            print("SettingsManager: Cleared all custom console icons.")
            refreshIconCache()
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Notification.Name("RefreshConsoleIcons"), object: nil)
            }
        } catch {
            print("SettingsManager: Error clearing console icons: \(error)")
        }
    }

    // Log Export
    func exportLogs(completion: @escaping (URL?) -> Void) {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            completion(nil)
            return
        }
        
        let logsDir = documentsDirectory.appendingPathComponent("system/logs")
        
        // Use NSFileCoordinator to create a zip archive
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(readingItemAt: logsDir, options: [.forUploading], error: &error) { zipURL in
            // zipURL is a temporary file. We need to move it to a location we control to share it.
            let tempDir = FileManager.default.temporaryDirectory
            let dstURL = tempDir.appendingPathComponent("sumee_logs_archive.zip")
            
            do {
                if FileManager.default.fileExists(atPath: dstURL.path) {
                    try FileManager.default.removeItem(at: dstURL)
                }
                try FileManager.default.copyItem(at: zipURL, to: dstURL)
                print(" Zipped logs to: \(dstURL.path)")
                completion(dstURL)
            } catch {
                print(" Failed to move zip: \(error)")
                completion(nil)
            }
        }
        
        if let error = error {
            print("Coordinator error: \(error)")
            completion(nil)
        }
    }

    //  Device Compat Helper
    
    static func isOlderDevice() -> Bool {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        
        // Check for iPhone
        if identifier.hasPrefix("iPhone") {
            let versionString = identifier.dropFirst("iPhone".count)
            if let commaIndex = versionString.firstIndex(of: ",") {
                let majorString = versionString[..<commaIndex]
                if let major = Int(majorString) {
                    // iPhone 16 is "iPhone17,x"
                    // iPhone 15 is "iPhone16,x"
                    // We want to enable for iPhone 15 and older.
                    // So return true if major < 17
                    return major < 17
                }
            }
        }
        
        // Check for iPad
        if identifier.hasPrefix("iPad") {
             let versionString = identifier.dropFirst("iPad".count)
             if let commaIndex = versionString.firstIndex(of: ",") {
                 let majorString = versionString[..<commaIndex]
                 let minorString = versionString[versionString.index(after: commaIndex)...]
                 
                 if let major = Int(majorString), let minor = Int(minorString) {
                     // M1 iPads started at iPad13,4
                     // M-Series (Performance Mode OFF = return false)
                     // A-Series (Performance Mode ON = return true)
                     
                     if major < 13 {
                         return true // Older than A14 (e.g. iPad 9 is iPad12,x)
                     }
                     
                     if major == 13 {
                         // iPad13,1 & 13,2 = iPad Air 4 (A14) -> True
                         // iPad13,4...13,11 = iPad Pro M1 -> False
                         // iPad13,16 & 13,17 = iPad Air 5 (M1) -> False
                         // iPad13,18 & 13,19 = iPad 10 (A14) -> True
                         
                         let m1Models = [4, 5, 6, 7, 8, 9, 10, 11, 16, 17]
                         if m1Models.contains(minor) {
                             return false // It is M1
                         }
                         return true // It is A14 (Air 4, iPad 10)
                     }
                     
                     if major == 14 {
                         // iPad14,1 & 14,2 = iPad mini 6 (A15) -> True
                         // iPad14,3...14,6 = iPad Pro M2 -> False
                         
                         if minor <= 2 {
                             return true // Mini 6
                         }
                         return false // M2 Pro
                     }
                     
                     if major > 14 {
                         // M4 / Future -> False
                         return false
                     }
                 }
             }
        }
        
        return false
    }
}

// Helper Extensions for Color <-> Hex



