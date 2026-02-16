import SwiftUI

struct ThemeMetadata: Codable {
    // Only decode lightweight properties for the list
    let bubbleColorHex: String
    let hue: Double?
    let saturation: Double?
    let brightness: Double?
    let isDark: Bool?
    let transparentIcons: Bool?
    let musicFileName: String?
}

struct ThemeRegistry {
    static var allThemes: [AppTheme] {
        [
            ThemeRegistry.customTheme,
            ThemeRegistry.standard,
            ThemeRegistry.darkMode,
            ThemeRegistry.grid,
            ThemeRegistry.christmas,
            ThemeRegistry.homebrew,
            ThemeRegistry.newYear,
            ThemeRegistry.sumeeXMB,
            ThemeRegistry.sumeeXMBBlack,
        ] + ThemeRegistry.getImportedThemes()
    }
    
    // Default Definitions
    
    static let standard = AppTheme(
        id: "standard",
        displayName: "Standard White",
        icon: "square.fill",
        color: .white,
        backgroundType: .color(.white),
        iconSet: 1,
        musicTrack: "music_background",
        isDark: false
    )
    
    static let darkMode = AppTheme(
        id: "dark_mode",
        displayName: "Dark Mode",
        icon: "moon.fill",
        color: .black,
        backgroundType: .pattern, // Dark pattern logic handled in view
        iconSet: 2,
        musicTrack: "music_background",
        isDark: true
    )
    
    static let grid = AppTheme(
        id: "grid",
        displayName: "Grid Pattern",
        icon: "grid",
        color: .gray.opacity(0.1),
        backgroundType: .pattern,
        iconSet: 1,
        musicTrack: "music_background",
        isDark: false
    )
    
    static let christmas = AppTheme(
        id: "christmas",
        displayName: "Christmas",
        icon: "snowflake",
        color: .red,
        backgroundType: .custom("Snow"),
        iconSet: 1,
        musicTrack: "We Wish You a Merry Christmas - Twin Musicom",
        isDark: false
    )
    
    static let homebrew = AppTheme(
        id: "homebrew",
        displayName: "Bubbles",
        icon: "soap.fill",
        color: .blue,
        backgroundType: .custom("Homebrew"),
        iconSet: 1,
        musicTrack: "music_background",
        isDark: false // Homebrew usually has white bubbles?
    )
    
    static let newYear = AppTheme(
        id: "new_year",
        displayName: "New Year",
        icon: "fireworks",
        color: .yellow,
        backgroundType: .custom("NewYear"),
        iconSet: 1,
        musicTrack: "Parental Controls",
        isDark: true // Often dark background
    )
    
    static let transparentIcons = AppTheme(
        id: "transparent_icons",
        displayName: "Transparent Icons",
        icon: "square.dashed",
        color: .gray.opacity(0.5),
        backgroundType: .pattern, // Default fallback if used alone
        iconSet: 2,
        musicTrack: "bgm",
        isDark: false
    )
    
    

    static let sumeeXMB = AppTheme(
        id: "sumee_xmb",
        displayName: "SUMEE-XMB",
        icon: "wave.3.right",
        color: .blue, // Matches PS Blue feel
        backgroundType: .custom("SUMEE-XMB"),
        iconSet: 2, // Transparent Icons
        musicTrack: "melonx",
        isDark: true
    )
    
    static let sumeeXMBBlack = AppTheme(
        id: "sumee_xmb_black",
        displayName: "SUMEE-XMB Black",
        icon: "wave.3.left",
        color: .gray, // Onyx/Black
        backgroundType: .custom("SUMEE-XMB-Black"),
        iconSet: 2, // Transparent Icons
        musicTrack: "melonx", // Same iconic track
        isDark: true
    )
    
    static var customTheme: AppTheme {
        // Source of Truth: Documents/Themes/current_theme.json
        var color: Color = .purple
        var music: String? = nil
        var isTransparent: Bool = false
        var isDark: Bool = true // Default to Light Text (Dark Theme)
        
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
             let url = documentsDirectory.appendingPathComponent("Themes/current_theme.json")
             if let data = try? Data(contentsOf: url),
                let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                 
                 // Manual Parse (Robustness)
                 let hue = json["hue"] as? Double ?? 0.0
                 let sat = json["saturation"] as? Double ?? 0.0
                 let bri = json["brightness"] as? Double ?? 1.0
                 color = Color(hue: hue, saturation: sat, brightness: bri)
                 
                 music = json["musicFileName"] as? String
                 isTransparent = json["transparentIcons"] as? Bool ?? false
                 
                 // Fix: Load Text Color Setting
                 if let isDarkVal = json["isDark"] as? Bool {
                     isDark = isDarkVal
                 }
                 
             } else {

         
                 color = .purple // Default Purple
                 music = nil
                 isTransparent = false
                 isDark = true // Default to Light Text
             }
        }

        return AppTheme(
            id: "custom_photo",
            displayName: "Custom Theme",
            icon: "photo.fill",
            color: color, 
            backgroundType: .custom("CustomPhoto"),
            iconSet: isTransparent ? 2 : 1, 
            musicTrack: music,
            isDark: isDark 
        )
    }
    
    // MARK: - Installation Management
    
    static func isInstalled(_ theme: AppTheme) -> Bool {
        if theme.id.hasPrefix("imported_") { return true } // Always show imported themes
        return SettingsManager.shared.installedThemeIDs.contains(theme.id)
    }
    
    static func install(_ theme: AppTheme) {
        if !isInstalled(theme) {
            SettingsManager.shared.installedThemeIDs.append(theme.id)
            print(" Installed theme: \(theme.displayName)")
        }
    }
    
    static func uninstall(_ theme: AppTheme) {
        if theme.id == "grid" { return } // Protect default
        if let index = SettingsManager.shared.installedThemeIDs.firstIndex(of: theme.id) {
            SettingsManager.shared.installedThemeIDs.remove(at: index)
            print("Uninstalled theme: \(theme.displayName)")
        }
    }
    
    
    // MARK: - Imported Themes
    
    private static func getThemesDirectory() -> URL? {
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = documentsDirectory.appendingPathComponent("Themes", isDirectory: true)
        // Ensure directory exists
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }
    
    static func getImportedThemes() -> [AppTheme] {
        guard let dir = getThemesDirectory() else { return [] }
        var themes: [AppTheme] = []
        
        
        do {
            let fileURLs = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
            let jsonFiles = fileURLs.filter { $0.pathExtension == "json" && $0.lastPathComponent != "current_theme.json" }
            
            for url in jsonFiles {
                // Optimization: Decode only metadata, skip heavy Base64 fields
                if let data = try? Data(contentsOf: url),
                   let metadata = try? JSONDecoder().decode(ThemeMetadata.self, from: data) {
                    
                    let filename = url.deletingPathExtension().lastPathComponent
                    let id = "imported_\(filename)"
                    
                    // User Request: Use original filename as display name
                    let displayName = filename
                    
                    // Determine Color
                    // Use HSB if available, otherwise parsing hex is too heavy for list? No, hex is fine.
                    // But we have HSB in metadata now.
                    let color = Color(hue: metadata.hue ?? 0, saturation: metadata.saturation ?? 0, brightness: metadata.brightness ?? 1)
                    
                    let theme = AppTheme(
                        id: id,
                        displayName: displayName,
                        icon: "doc.text.fill", // Or "arrow.down.doc.fill"
                        color: color,
                        backgroundType: .custom("Imported"),
                        iconSet: (metadata.transparentIcons ?? false) ? 2 : 1,
                        musicTrack: metadata.musicFileName,
                        isDark: metadata.isDark ?? true
                    )
                    themes.append(theme)
                }
            }
        } catch {
            print("ThemeRegistry: Error listing themes: \(error)")
        }
        // Sort by newest first (reverse ID/filename usually works for timestamps)
        return themes.sorted { $0.id > $1.id }
    }
}
