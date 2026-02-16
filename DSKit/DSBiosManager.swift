import Foundation
import SwiftUI
import Combine

class DSBiosManager: ObservableObject {
    static let shared = DSBiosManager()
    
    @Published var hasBios7: Bool = false
    @Published var hasBios9: Bool = false
    @Published var hasFirmware: Bool = false
    
    private let fileManager = FileManager.default
    
    var systemDirectory: URL? {
        guard let docDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let sysDir = docDir.appendingPathComponent("system")
        try? fileManager.createDirectory(at: sysDir, withIntermediateDirectories: true)
        return sysDir
    }
    
    init() {
        checkBiosStatus()
    }
    
    func checkBiosStatus() {
        guard let sysDir = systemDirectory else { return }
        
        hasBios7 = fileManager.fileExists(atPath: sysDir.appendingPathComponent("bios7.bin").path)
        hasBios9 = fileManager.fileExists(atPath: sysDir.appendingPathComponent("bios9.bin").path)
        
        // Firmware can be named firmware.bin or firmware.nds inside system
        let fwPath1 = sysDir.appendingPathComponent("firmware.bin").path
        let fwPath2 = sysDir.appendingPathComponent("firmware.nds").path
        hasFirmware = fileManager.fileExists(atPath: fwPath1) || fileManager.fileExists(atPath: fwPath2)
    }
    
    var areAllBiosPresent: Bool {
        return hasBios7 && hasBios9 && hasFirmware
    }
    
    func importBios(url: URL, type: BiosType) -> Bool {
        guard let sysDir = systemDirectory else { return false }
        
        // Security: access security scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        
        // If we strictly need access and failed to get it, we might want to log it.
        // However, for some files in open directories, it might return false but still be readable.
        // We proceed, but capture the error if copy fails.

        let destinationFilename: String
        switch type {
        case .bios7: destinationFilename = "bios7.bin"
        case .bios9: destinationFilename = "bios9.bin"
        case .firmware: destinationFilename = "firmware.bin"
        }
        
        let destURL = sysDir.appendingPathComponent(destinationFilename)
        
        do {
            if fileManager.fileExists(atPath: destURL.path) {
                try fileManager.removeItem(at: destURL)
            }
            
            // Use data reading/writing instead of copyItem to avoid permission attribute issues
            // that essentially plague sideloaded apps when copying from security scoped URLs.
            // BIOS files are small enough for this to be safe.
            let data = try Data(contentsOf: url)
            try data.write(to: destURL)
            
            print(" [DSBiosManager] Imported \(destinationFilename)")
            
            // Refresh status on main thread
            DispatchQueue.main.async {
                self.checkBiosStatus()
            }
            return true
        } catch {
            print(" [DSBiosManager] Failed to import bios: \(error)")
            return false
        }
    }
    
    func deleteAllBios() {
        guard let sysDir = systemDirectory else { return }
        let files = ["bios7.bin", "bios9.bin", "firmware.bin", "firmware.nds"]
        
        for file in files {
            let url = sysDir.appendingPathComponent(file)
            try? fileManager.removeItem(at: url)
        }
        
        print("🗑️ [DSBiosManager] Deleted all DS BIOS files.")
        DispatchQueue.main.async {
            self.checkBiosStatus()
        }
    }
    
    enum BiosType {
        case bios7
        case bios9
        case firmware
    }
}
