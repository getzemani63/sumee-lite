import Foundation
import SwiftUI
import Combine
import AVFoundation
import GameController
import Darwin
import UniformTypeIdentifiers
import CoreMotion



// MARK: - Libretro Type Definitions & Global Callbacks


// --- Libretro Type Definitions ---


struct retro_variable {
    var key: UnsafePointer<CChar>?
    var value: UnsafePointer<CChar>?
}

struct retro_input_descriptor {
    var port: UInt32
    var device: UInt32
    var index: UInt32
    var id: UInt32
    var description: UnsafePointer<CChar>?
}

// ------------------------------------------------


private let dsRendererInstance = DSRenderer()


private var dsTopRendererRef: DSRenderer? = nil
private var dsBottomRendererRef: DSRenderer? = nil


private var nds_TouchScreen: UnsafeMutableRawPointer? = nil
private var nds_ReleaseScreen: UnsafeMutableRawPointer? = nil
private var dsLastMouseX: Int16 = 0
private var dsLastMouseY: Int16 = 0
private var dsSeenInputPollKeys: Set<String> = []
private var dsLastInputLogAt: TimeInterval = 0


private func callCppVoid(_ funcPtr: UnsafeMutableRawPointer?) {
    guard let ptr = funcPtr else { return }
    let function = unsafeBitCast(ptr, to: (@convention(c) () -> Void).self)
    function()
}


private func callCppUInt16(_ funcPtr: UnsafeMutableRawPointer?, _ x: UInt16, _ y: UInt16) {
    guard let ptr = funcPtr else { return }
    let function = unsafeBitCast(ptr, to: (@convention(c) (UInt16, UInt16) -> Void).self)
    function(x, y)
}


@_cdecl("ds_video_refresh")
func ds_video_refresh(data: UnsafeRawPointer?, width: UInt32, height: UInt32, pitch: Int) {
    guard let data = data else { return }
    dsRendererInstance.updateTexture(width: Int(width), height: Int(height), pitch: pitch, data: data)
    

    dsTopRendererRef?.updateTexture(width: Int(width), height: Int(height), pitch: pitch, data: data)
    dsBottomRendererRef?.updateTexture(width: Int(width), height: Int(height), pitch: pitch, data: data)
}

private var dsTempAudioBuffer: [Int16] = [0, 0]

@_cdecl("ds_audio_sample")
func ds_audio_sample(left: Int16, right: Int16) {
    dsTempAudioBuffer[0] = left
    dsTempAudioBuffer[1] = right
    DSAudio.shared.writeAudio(data: dsTempAudioBuffer, frames: 1)
}

@_cdecl("ds_audio_sample_batch")
func ds_audio_sample_batch(data: UnsafePointer<Int16>?, frames: Int) -> Int {
    guard let data = data else { return 0 }
    DSAudio.shared.writeAudio(data: data, frames: frames)
    return frames
}

@_cdecl("ds_input_poll")
func ds_input_poll() {
    // Polling Input (Fix Latency)
    DSInput.shared.pollInput()
    

    let userIsTouching = DSInput.shared.isTouched
    let touchX = DSInput.shared.touchX
    let touchY = DSInput.shared.touchY
    
    // Check if Direct Touch symbols are available (MelonDS Only)
    if nds_TouchScreen != nil && nds_ReleaseScreen != nil {
        if userIsTouching {
            callCppUInt16(nds_TouchScreen, UInt16(touchX), UInt16(touchY))
        } else {
            callCppVoid(nds_ReleaseScreen)
        }
    } else {
        // Desmume uses Libretro Standard Input for Touch (Device = POINTER)
        // Handled via ds_input_state callback implicitly.
        // No explicit "Release" call needed, just 0 state.
    }
}

@_cdecl("ds_input_state")
func ds_input_state(port: UInt32, device: UInt32, index: UInt32, id: UInt32) -> Int16 {
    if DSInput.debugTouchLogsEnabled {
        let key = "p\(port)-d\(device)-i\(index)-id\(id)"
        if !dsSeenInputPollKeys.contains(key) {
            dsSeenInputPollKeys.insert(key)
            print("🧩 [DSCoreInput] First poll -> \(key)")
        }
    }

    // DeSmuME touchscreen path (some builds query port 0, others port 1).
    if (port == 0 || port == 1) && index == 0 && device == 6 { // RETRO_DEVICE_POINTER
        let touchX = max(0, min(255, Int(DSInput.shared.touchX)))
        let touchY = max(0, min(191, Int(DSInput.shared.touchY)))
        let pointerX = touchX
        let pointerY = max(0, min(383, touchY + 192))

        if DSInput.debugTouchLogsEnabled && id == 2 {
            let now = Date.timeIntervalSinceReferenceDate
            if DSInput.shared.isTouched || now - dsLastInputLogAt > 0.25 {
                print("🧩 [DSCoreInput] POINTER port=\(port) touched=\(DSInput.shared.isTouched) touch=(\(touchX),\(touchY)) ptr=(\(pointerX),\(pointerY))")
                dsLastInputLogAt = now
            }
        }

        // Libretro pointer uses normalized range [-0x7fff, 0x7fff]
        if id == 0 { // X
            let nx = (Double(pointerX) / 255.0) * 2.0 - 1.0
            return Int16(max(-32767, min(32767, Int(nx * 32767.0))))
        }
        if id == 1 { // Y
            let ny = (Double(pointerY) / 383.0) * 2.0 - 1.0
            return Int16(max(-32767, min(32767, Int(ny * 32767.0))))
        }
        if id == 2 || id == 3 { // PRESSED (+ alias used by some cores)
            return DSInput.shared.isTouched ? 1 : 0
        }
        return 0
    }

    // Some DeSmuME builds use analog path for stylus when pointer_device_l is set.
    if (port == 0 || port == 1) && device == 5 { // RETRO_DEVICE_ANALOG
        // Only left stick should drive stylus; keep right stick neutral.
        if index != 0 { return 0 }

        let touchX = max(0, min(255, Int(DSInput.shared.touchX)))
        let touchY = max(0, min(191, Int(DSInput.shared.touchY)))

        if DSInput.debugTouchLogsEnabled && (id == 0 || id == 1) {
            let now = Date.timeIntervalSinceReferenceDate
            if DSInput.shared.isTouched || now - dsLastInputLogAt > 0.25 {
                print("🧩 [DSCoreInput] ANALOG port=\(port) index=\(index) touched=\(DSInput.shared.isTouched) x=\(touchX) y=\(touchY)")
                dsLastInputLogAt = now
            }
        }

        guard DSInput.shared.isTouched else { return 0 }

        // Inverse of DeSmuME pressed-mode transform:
        // touch = clamp( sqrt(2) * (size/2) * (analog/32767) + center )
        if id == 0 { // X
            let width: Double = 256.0
            let centerX = (width - 1.0) / 2.0
            let denomX = sqrt(2.0) * (width / 2.0)
            let analogX = ((Double(touchX) - centerX) / denomX) * 32767.0
            return Int16(max(-32767, min(32767, Int(analogX.rounded()))))
        }
        if id == 1 { // Y
            let height: Double = 192.0
            let centerY = (height - 1.0) / 2.0
            let denomY = sqrt(2.0) * (height / 2.0)
            let analogY = ((Double(touchY) - centerY) / denomY) * 32767.0
            return Int16(max(-32767, min(32767, Int(analogY.rounded()))))
        }

        return 0
    }

    if (port == 0 || port == 1) && index == 0 && device == 2 { // Mouse fallback (legacy cores)
        if DSInput.debugTouchLogsEnabled && id == 2 {
            let now = Date.timeIntervalSinceReferenceDate
            if DSInput.shared.isTouched || now - dsLastInputLogAt > 0.25 {
                print("🧩 [DSCoreInput] MOUSE port=\(port) touched=\(DSInput.shared.isTouched) x=\(DSInput.shared.touchX) y=\(DSInput.shared.touchY)")
                dsLastInputLogAt = now
            }
        }

        // Libretro mouse expects relative deltas for X/Y.
        if id == 0 {
            let delta = Int(DSInput.shared.touchX) - Int(dsLastMouseX)
            dsLastMouseX = DSInput.shared.touchX
            return Int16(max(-32767, min(32767, delta)))
        }
        if id == 1 {
            let delta = Int(DSInput.shared.touchY) - Int(dsLastMouseY)
            dsLastMouseY = DSInput.shared.touchY
            return Int16(max(-32767, min(32767, delta)))
        }
        if id == 2 || id == 3 { return DSInput.shared.isTouched ? 1 : 0 } // LEFT button
        return 0
    }

    // Some DeSmuME builds poll joypad on port 1 instead of port 0.
    if port == 0 || port == 1 {
        if device == 1 || device == 0 { // Joypad or Generic
            
      
            if DSCore.isMicrophoneBlowing {
                if id == 12 || (id >= 16 && id <= 25) {
                    return 1
                }
            }

            if id < 16 {
                // DeSmuME supports stylus tap via Joypad R2 in some input modes.
                if id == 13 { // RETRO_DEVICE_ID_JOYPAD_R2
                    if DSInput.debugTouchLogsEnabled {
                        let now = Date.timeIntervalSinceReferenceDate
                        if DSInput.shared.isTouched || now - dsLastInputLogAt > 0.25 {
                            print("🧩 [DSCoreInput] JOYPAD_R2 touchTap=\(DSInput.shared.isTouched)")
                            dsLastInputLogAt = now
                        }
                    }
                    return DSInput.shared.isTouched ? 1 : 0
                }
                let mask = UInt16(1 << id)
                return (DSInput.shared.buttonMask & mask) != 0 ? 1 : 0
            }
        }
    }
    return 0
}

@_cdecl("ds_environment")
func ds_environment(cmd: UInt32, data: UnsafeMutableRawPointer?) -> Bool {
    print(" [DSCore] Environment Call CMD: \(cmd)")
    switch cmd {
    case 3: // RETRO_ENVIRONMENT_GET_CAN_DUPE
        if let data = data {
            data.bindMemory(to: Bool.self, capacity: 1).pointee = true
        }
        return true
        
    case 9: // RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY
        if let data = data {
            // Define system directory: Documents/system
            if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let sysDir = docDir.appendingPathComponent("system")
                try? FileManager.default.createDirectory(at: sysDir, withIntermediateDirectories: true)
                
                let pathStr = sysDir.path
                // Use a static buffer or ensure lifetime. For bridging, usually temporary string is risky but common in Libretro wrappers if copied immediately.
       
                let cString = strdup(pathStr)
                data.bindMemory(to: UnsafePointer<CChar>?.self, capacity: 1).pointee = UnsafePointer(cString)
                print("📂 [DSCore] System Directory set to: \(pathStr)")
                return true
            }
        }
        return false

    case 31: // RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY
        if let data = data {
            if let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let folderName = DSCore.isDesmumeCoreActive ? "saves/ds_desmume" : "saves/ds"
                let saveDir = docDir.appendingPathComponent(folderName)
                try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
                
                let pathStr = saveDir.path
                let cString = strdup(pathStr)
                data.bindMemory(to: UnsafePointer<CChar>?.self, capacity: 1).pointee = UnsafePointer(cString)
                print(" [DSCore] Save Directory set to: \(pathStr)")
                return true
            }
        }
        return false

    case 10: // RETRO_ENVIRONMENT_SET_PIXEL_FORMAT
        if let data = data {
            let format = data.bindMemory(to: UInt32.self, capacity: 1).pointee
            
            if format == 1 { // RETRO_PIXEL_FORMAT_XRGB8888
                print("[DSCore] Core requested XRGB8888 (32-bit). Allowed. Using .bgra8Unorm.")
                dsRendererInstance.currentPixelFormat = .bgra8Unorm
                dsTopRendererRef?.currentPixelFormat = .bgra8Unorm
                dsBottomRendererRef?.currentPixelFormat = .bgra8Unorm
                return true
            } else if format == 2 { // RETRO_PIXEL_FORMAT_RGB565
                print(" [DSCore] Core requested RGB565 (16-bit). Allowed. Using .b5g6r5Unorm.")
                dsRendererInstance.currentPixelFormat = .b5g6r5Unorm
                dsTopRendererRef?.currentPixelFormat = .b5g6r5Unorm
                dsBottomRendererRef?.currentPixelFormat = .b5g6r5Unorm
                return true
            } else {
                 print("[DSCore] Core requested unsupported format \(format). Denied.")
                 return false 
            }
        }
        return false

    case 11: // RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS
        // Accept descriptors so core can expose stylus-related actions.
        return true

    case 17: // RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE
        if let data = data {
            data.bindMemory(to: Bool.self, capacity: 1).pointee = false
            return true
        }
        return false

    case 35: // RETRO_ENVIRONMENT_SET_CONTROLLER_INFO
        // Accept controller info declarations from core.
        return true
        
    case 15: // RETRO_ENVIRONMENT_GET_VARIABLE
        if let data = data {
            let variable = data.bindMemory(to: retro_variable.self, capacity: 1).pointee
            if let key = variable.key {
                let keyString = String(cString: key)
                print("🔍 [DSCore] Core requested variable: \(keyString)")
                
                // --- DESMUME OPTIONS ---
                if keyString == "desmume_internal_resolution" {
                     let res = DSCore.internalResolution
                     print(" [DSCore] Setting Desmume Resolution -> \(res)x")
                     // Desmume uses "256x192" etc? No, typically scale factor or specific resolution string.
                     // Checking libretro docs: desmume_internal_resolution usually "256x192" (1), "512x384" (2), etc.
                     // Mapping simple Int scaler to Desmume format:
                     let width = 256 * res
                     let height = 192 * res
                     let value = strdup("\(width)x\(height)")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                }
                
                if keyString == "desmume_num_cores" {
                     let value = strdup("2") // Multifilar for better perf
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                }
                
                if keyString == "desmume_jit" {
                     print("⚙️ [DSCore] Disabling Desmume JIT for Stability")
                     let value = strdup("disabled") 
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                }

                 if keyString == "desmume_pointer_mouse" {
                     // Keep pointer stack enabled for compatibility with core input paths.
                     let value = strdup("enabled")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                 if keyString == "desmume_pointer_type" {
                     // Force absolute touchscreen coordinates instead of relative mouse mode.
                     let value = strdup("touch")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                 if keyString == "desmume_pointer_device_l" {
                     // Stable touch path for this build: left analog in pressed mode.
                     let value = strdup("pressed")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                 if keyString == "desmume_pointer_device_r" {
                     // Disable right analog pointer path to avoid conflicts.
                     let value = strdup("none")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                 if keyString == "desmume_pointer_device_deadzone" {
                     // 0 avoids deadzone rejecting valid touches near screen center.
                     let value = strdup("0")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                 if keyString == "desmume_pointer_device_acceleration_mod" {
                     let value = strdup("0")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                 if keyString == "desmume_input_rotation" {
                     let value = strdup("0")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                 }

                // --- MELONDS OPTIONS (Legacy Fallback) ---
                if keyString == "melonds_jit_enable" {
                    // Critical Fix for Pokémon White 2 / Black 2 (IRE*, IRB*)
                    let shouldEnableJIT = DSCore.activeGameID.hasPrefix("IRE") || DSCore.activeGameID.hasPrefix("IRB")
                    
                    if shouldEnableJIT {
                        print("⚙️ [DSCore] Enabling JIT for Pokémon BW2 (Fix Cutscene Freeze)")
                        let value = strdup("enabled")
                        data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                    } else {
                        print("⚙️ [DSCore] Disabling JIT (Default Stability)")
                        let value = strdup("disabled")
                        data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                    }
                    return true
                }
                
                if keyString == "melonds_mic_input" || keyString == "melonds_microphone_input" {
                     let value = strdup("blow")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                }
                
                if keyString == "melonds_internal_resolution" {
                    let res = DSCore.internalResolution
                    print(" [DSCore] Setting Internal Resolution -> \(res)x")
                    let value = strdup("\(res)") 
                    data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                    return true
                }

                
                if keyString == "melonds_console_mode" {
                    print(" [DSCore] Forcing Console Mode -> DS")
                    let value = strdup("DS")
                    data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                    return true
                }
                
                if keyString == "melonds_boot_directly" {
                     print(" [DSCore] Forcing Boot Directly -> enabled")
                     let value = strdup("enabled") 
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                }
                if keyString == "desmume_firmware_language" {
                     let value = strdup("English")
                     data.bindMemory(to: retro_variable.self, capacity: 1).pointee.value = UnsafePointer(value)
                     return true
                }
            }
        }
        return false

    case 16: // RETRO_ENVIRONMENT_SET_VARIABLES
        // Core is providing option definitions; frontend can acknowledge without parsing.
        return true
        
    case 27: // RETRO_ENVIRONMENT_GET_LOG_INTERFACE
        if let data = data {
             // Define the callback closure
             let cb: @convention(c) (UInt32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void = { level, fmt, args in
                 guard let fmt = fmt else { return }
                 // Swift doesn't easily support vprintf from CVaListPointer directly without bridging.
                 // For now, we will print a generic message or try partial string.
                 let msg = String(cString: fmt)
                 print(" [DesmumeLog] \(msg)") 
             }
             
             var logCb = retro_log_callback()
             logCb.log = cb
             
             data.bindMemory(to: retro_log_callback.self, capacity: 1).pointee = logCb
             print(" [DSCore] Log Interface Configured.")
             return true
        }
        return false
        
    case 24:
          return true
        
    case 18:
         return true

    default:
        // print(" [DSCore] Unhandled Environment CMD: \(cmd)")
        return false
    }
}

// Struct for Log Callback
struct retro_log_callback {
    var log: (@convention(c) (UInt32, UnsafePointer<CChar>?, UnsafeMutableRawPointer?) -> Void)?
}


public class DSCore: ObservableObject {
    public static let shared = DSCore()

    @Published public var isRunning = false
    private var coreHandle: UnsafeMutableRawPointer?
    private var displayLink: CADisplayLink?
    
    // Perform memory management for ROM data to prevent use-after-free
    private var romData: Data?
    private var isUsingDesmumeCore: Bool = false
    private var hasShutdown = false

    private var hasPrintedLoop = false
    
    // Global Settings (Static for C-Bridge Access)
    public static var activeGameID: String = "" // Stores current Game Code (e.g. IREO)
    public static var internalResolution: Int = 4 // Default to 4x (Max)
    public static var isDesmumeCoreActive: Bool = false
    
    // Renderers para cada pantalla en modo horizontal
    private let dsTopRenderer: DSRenderer = DSRenderer()
    private let dsBottomRenderer: DSRenderer = DSRenderer()
    
    public var renderer: DSRenderer {
        return dsRendererInstance
    }
    
    public var topRenderer: DSRenderer {
        // Sync Pixel Format from main instance (in case we missed the environment call)
        dsTopRenderer.currentPixelFormat = dsRendererInstance.currentPixelFormat
        // Actualizar referencia global
        dsTopRendererRef = dsTopRenderer
        return dsTopRenderer
    }
    
    public var bottomRenderer: DSRenderer {
        // Sync Pixel Format from main instance
        dsBottomRenderer.currentPixelFormat = dsRendererInstance.currentPixelFormat
        // Actualizar referencia global
        dsBottomRendererRef = dsBottomRenderer
        return dsBottomRenderer
    }
    
    // Punteros Crudos (Raw Pointers)
    private var ptr_retro_init: UnsafeMutableRawPointer?
    private var ptr_retro_deinit: UnsafeMutableRawPointer?
    private var ptr_retro_set_environment: UnsafeMutableRawPointer?
    private var ptr_retro_set_video_refresh: UnsafeMutableRawPointer?
    private var ptr_retro_set_audio_sample: UnsafeMutableRawPointer?
    private var ptr_retro_set_audio_sample_batch: UnsafeMutableRawPointer?
    private var ptr_retro_set_input_poll: UnsafeMutableRawPointer?
    private var ptr_retro_set_input_state: UnsafeMutableRawPointer?
    
    // Controller Port
    private var ptr_retro_set_controller_port_device: UnsafeMutableRawPointer?
    
    private var ptr_retro_load_game: UnsafeMutableRawPointer?
    private var ptr_retro_unload_game: UnsafeMutableRawPointer?
    private var ptr_retro_get_system_av_info: UnsafeMutableRawPointer?
    private var ptr_retro_run: UnsafeMutableRawPointer?
    
    private var ptr_retro_serialize_size: UnsafeMutableRawPointer?
    private var ptr_retro_serialize: UnsafeMutableRawPointer?
    private var ptr_retro_unserialize: UnsafeMutableRawPointer?
    
    // Memory / SRAM (For native saves)
    private var ptr_retro_get_memory_data: UnsafeMutableRawPointer?
    private var ptr_retro_get_memory_size: UnsafeMutableRawPointer?
    
    private var currentROMURL: URL?
    
    // Punteros a funciones internas de NDS
    private var ptr_nds_TouchScreen: UnsafeMutableRawPointer?
    private var ptr_nds_ReleaseScreen: UnsafeMutableRawPointer?

    // Computed Properties (Safe Casting)
    private var retro_init: (@convention(c) () -> Void)? {
        guard let ptr = ptr_retro_init else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) () -> Void).self)
    }
    
    private var retro_deinit: (@convention(c) () -> Void)? {
        guard let ptr = ptr_retro_deinit else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) () -> Void).self)
    }
    
    private var retro_set_environment: (@convention(c) (retro_environment_t) -> Void)? {
        guard let ptr = ptr_retro_set_environment else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (retro_environment_t) -> Void).self)
    }
    
    private var retro_set_video_refresh: (@convention(c) (retro_video_refresh_t) -> Void)? {
        guard let ptr = ptr_retro_set_video_refresh else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (retro_video_refresh_t) -> Void).self)
    }
    
    private var retro_set_audio_sample: (@convention(c) (retro_audio_sample_t) -> Void)? {
        guard let ptr = ptr_retro_set_audio_sample else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (retro_audio_sample_t) -> Void).self)
    }
    
    private var retro_set_audio_sample_batch: (@convention(c) (retro_audio_sample_batch_t) -> Void)? {
        guard let ptr = ptr_retro_set_audio_sample_batch else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (retro_audio_sample_batch_t) -> Void).self)
    }
    
    private var retro_set_input_poll: (@convention(c) (retro_input_poll_t) -> Void)? {
        guard let ptr = ptr_retro_set_input_poll else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (retro_input_poll_t) -> Void).self)
    }
    
    private var retro_set_input_state: (@convention(c) (retro_input_state_t) -> Void)? {
        guard let ptr = ptr_retro_set_input_state else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (retro_input_state_t) -> Void).self)
    }
    
    private var retro_set_controller_port_device: (@convention(c) (UInt32, UInt32) -> Void)? {
         guard let ptr = ptr_retro_set_controller_port_device else { return nil }
         return unsafeBitCast(ptr, to: (@convention(c) (UInt32, UInt32) -> Void).self)
    }
    
    private var retro_load_game: (@convention(c) (UnsafeRawPointer) -> Bool)? {
        guard let ptr = ptr_retro_load_game else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UnsafeRawPointer) -> Bool).self)
    }
    
    private var retro_unload_game: (@convention(c) () -> Void)? {
        guard let ptr = ptr_retro_unload_game else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) () -> Void).self)
    }
    
    private var retro_get_system_av_info: (@convention(c) (UnsafeMutableRawPointer) -> Void)? {
        guard let ptr = ptr_retro_get_system_av_info else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UnsafeMutableRawPointer) -> Void).self)
    }
    
    private var retro_run: (@convention(c) () -> Void)? {
        guard let ptr = ptr_retro_run else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) () -> Void).self)
    }
    
    private var retro_serialize_size: (@convention(c) () -> Int)? {
        guard let ptr = ptr_retro_serialize_size else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) () -> Int).self)
    }
    
    private var retro_serialize: (@convention(c) (UnsafeMutableRawPointer, Int) -> Bool)? {
        guard let ptr = ptr_retro_serialize else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UnsafeMutableRawPointer, Int) -> Bool).self)
    }
    
    private var retro_unserialize: (@convention(c) (UnsafeRawPointer, Int) -> Bool)? {
        guard let ptr = ptr_retro_unserialize else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UnsafeRawPointer, Int) -> Bool).self)
    }
    
    private var retro_get_memory_data: (@convention(c) (UInt32) -> UnsafeMutableRawPointer?)? {
        guard let ptr = ptr_retro_get_memory_data else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UInt32) -> UnsafeMutableRawPointer?).self)
    }
    
    private var retro_get_memory_size: (@convention(c) (UInt32) -> Int)? {
        guard let ptr = ptr_retro_get_memory_size else { return nil }
        return unsafeBitCast(ptr, to: (@convention(c) (UInt32) -> Int).self)
    }
    
    public init() {
        // Lazy initialization: Core will be loaded when loadGame() is called.
    }
    
    public func saveState() -> Data? {
        guard let getSize = retro_serialize_size,
              let serialize = retro_serialize else {
            print("[DSCore] Save State functions not found in core.")
            return nil
        }
        
        let size = getSize()
        print(" [DSCore] State Size Needed: \(size) bytes")
        
        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { ptr in
            return serialize(ptr.baseAddress!, size)
        }
        
        if result {
             print(" [DSCore] State captured successfully.")
             return data
        } else {
             print(" [DSCore] Failed to capture state.")
             return nil
        }
    }
    
    func loadState(data: Data) -> Bool {
        guard let unserialize = retro_unserialize else {
             print(" [DSCore] Load State function not found in core.")
             return false
        }
        
        let result = data.withUnsafeBytes { ptr in
            return unserialize(ptr.baseAddress!, data.count)
        }
        
        if result {
            print(" [DSCore] State loaded successfully.")
            return true
        } else {
            print(" [DSCore] Failed to load state.")
            return false
        }
    }
    
    deinit {
        shutdown()
    }

    public func shutdown() {
        if hasShutdown {
            return
        }
        hasShutdown = true

        stopLoop()

        if isGameLoaded {
            retro_unload_game?()
            isGameLoaded = false
        }

        retro_deinit?()

        if let handle = coreHandle {
            dlclose(handle)
            coreHandle = nil
        }

        romData = nil
        nds_TouchScreen = nil
        nds_ReleaseScreen = nil
        isUsingDesmumeCore = false
        DSCore.isDesmumeCoreActive = false
    }
    
    private func loadCore() {
        hasShutdown = false

        var corePath: String?
        
        // 1. Check Frameworks Directory for Desmume Framework (Priority)
        if let frameworksURL = Bundle.main.privateFrameworksURL {
            let desmumeFrameworkPath = frameworksURL.appendingPathComponent("desmume.framework/desmume").path
            print(" [DSCore] Checking Frameworks Desmume Framework: \(desmumeFrameworkPath)")
            if FileManager.default.fileExists(atPath: desmumeFrameworkPath) {
                print(" [DSCore] Found Desmume Framework in Frameworks!")
                corePath = desmumeFrameworkPath
            }
        }
        
        // 2. Check Bundle Root for Desmume Framework
        if corePath == nil {
             let rootFrameworkExec = Bundle.main.bundleURL.appendingPathComponent("desmume.framework/desmume").path
             if FileManager.default.fileExists(atPath: rootFrameworkExec) {
                 print(" [DSCore] Found Desmume Framework in Root Bundle!")
                 corePath = rootFrameworkExec
             }
        }

        // 3. Fallback: MelonDS Framework Logic
        if corePath == nil {
            if let frameworksURL = Bundle.main.privateFrameworksURL {
                let frameworkPath = frameworksURL.appendingPathComponent("melonds.framework/melonds").path
                if FileManager.default.fileExists(atPath: frameworkPath) {
                    print(" [DSCore] Found MelonDS in Frameworks!")
                    corePath = frameworkPath
                }
            }
        }
        
        // 4. Fallback: MelonDS Dylib
        if corePath == nil, let frameworksURL = Bundle.main.privateFrameworksURL {
             let dylibPath = frameworksURL.appendingPathComponent("melonds_libretro_ios.dylib").path
             if FileManager.default.fileExists(atPath: dylibPath) {
                 print(" [DSCore] Found MelonDS dylib in Frameworks!")
                 corePath = dylibPath
             }
        }

        // 5. Last Resort: Loose dylib in Bundle Resources
        if corePath == nil {
             if let path = Bundle.main.path(forResource: "desmume_libretro_ios", ofType: "dylib") {
                 print(" [DSCore] Found Desmume as Resource!")
                 corePath = path
             } else if let path = Bundle.main.path(forResource: "melonds_libretro_ios", ofType: "dylib") {
                 print(" [DSCore] Found MelonDS as Resource!")
                 corePath = path
             }
        }

        guard let validPath = corePath else {
            print(" [DSCore] FATAL: Could not find melonds binary anywhere.")
            return
        }

        isUsingDesmumeCore = validPath.lowercased().contains("desmume")
        DSCore.isDesmumeCoreActive = isUsingDesmumeCore
        
        print(" [DSCore] Loading Core from: \(validPath)")
        
        coreHandle = dlopen(validPath, RTLD_NOW)
        guard coreHandle != nil else {
            print(" [DSCore] Falló dlopen: \(String(cString: dlerror()))")
            return
        }
        
        // Cargar Símbolos (Directo a RawPointer)
        ptr_retro_init = dlsym(coreHandle, "retro_init")
        ptr_retro_deinit = dlsym(coreHandle, "retro_deinit")
        ptr_retro_set_environment = dlsym(coreHandle, "retro_set_environment")
        ptr_retro_set_video_refresh = dlsym(coreHandle, "retro_set_video_refresh")
        ptr_retro_set_audio_sample = dlsym(coreHandle, "retro_set_audio_sample")
        ptr_retro_set_audio_sample_batch = dlsym(coreHandle, "retro_set_audio_sample_batch")
        ptr_retro_set_input_poll = dlsym(coreHandle, "retro_set_input_poll")
        ptr_retro_set_input_state = dlsym(coreHandle, "retro_set_input_state")
        ptr_retro_set_controller_port_device = dlsym(coreHandle, "retro_set_controller_port_device")
        
        ptr_retro_load_game = dlsym(coreHandle, "retro_load_game")
        ptr_retro_unload_game = dlsym(coreHandle, "retro_unload_game")
        ptr_retro_run = dlsym(coreHandle, "retro_run")
        ptr_retro_get_system_av_info = dlsym(coreHandle, "retro_get_system_av_info")
        
        ptr_retro_serialize_size = dlsym(coreHandle, "retro_serialize_size")
        ptr_retro_serialize = dlsym(coreHandle, "retro_serialize")
        ptr_retro_unserialize = dlsym(coreHandle, "retro_unserialize")
        
        ptr_retro_get_memory_data = dlsym(coreHandle, "retro_get_memory_data")
        ptr_retro_get_memory_size = dlsym(coreHandle, "retro_get_memory_size")
        
        // Cargar funciones internas de NDS para acceso directo al toque (Specific to MelonDS)
        // Check if symbols exist before assigning to avoid issues with other cores (Desmume)
        ptr_nds_TouchScreen = dlsym(coreHandle, "_ZN3NDS11TouchScreenEtt")
        if ptr_nds_TouchScreen == nil {
            print(" [DSCore] Symbol '_ZN3NDS11TouchScreenEtt' not found (Expected for Desmume)")
        } else {
            print(" [DSCore] Found MelonDS Touch Symbol")
        }

        ptr_nds_ReleaseScreen = dlsym(coreHandle, "_ZN3NDS13ReleaseScreenEv")
        
        // Actualizar referencias globales para los callbacks
        nds_TouchScreen = ptr_nds_TouchScreen
        nds_ReleaseScreen = ptr_nds_ReleaseScreen
        
        // Inicializar
        retro_set_environment?(ds_environment)
        retro_set_video_refresh?(ds_video_refresh)
        retro_set_audio_sample?(ds_audio_sample)
        retro_set_audio_sample_batch?(ds_audio_sample_batch)
        retro_set_input_poll?(ds_input_poll)
        retro_set_input_state?(ds_input_state)
        
        retro_init?()
        print(" [DSCore] Core inicializado correctamente.")
    }
    

    
    private var isGameLoaded = false
    
    public func loadGame(url: URL) -> Bool {
        // Ensure Core is initialized
        if coreHandle == nil {
            loadCore()
        }
        
        stopLoop()
        
        // Unload previous game if loaded
        if isGameLoaded {
            print(" [DSCore] Unloading previous game...")
            retro_unload_game?()
            isGameLoaded = false
        }
        
        // Save current ROM URL for save data handling
        currentROMURL = url
        
        // OPTIMIZATION: Use Memory Mapping (.mappedIfSafe)

        
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            self.romData = data // Retain data to prevent deallocation
            print(" [DSCore] Mapped ROM data into memory (Size: \(data.count) bytes)")
            
            let path = url.path.cString(using: .utf8)!
            
            return data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                guard let baseAddress = ptr.baseAddress else { return false }
                
                // Read Game ID (Offset 0x0C, Length 4)
                let gameID: String
                if data.count >= 0x10 {
                    let idData = data.subdata(in: 0x0C..<0x10)
                    gameID = String(data: idData, encoding: .ascii) ?? "UNKN"
                    print(" [DSCore] Detected Game ID: \(gameID)")
                } else {
                    gameID = "UNKN"
                }
                DSCore.activeGameID = gameID
                
                // Keep the path valid
                return path.withUnsafeBufferPointer { pathPtr in
                    
                    // Set Controller Port 0 to Joypad (Device 1)
                    print(" [DSCore] Setting Controller Port Device...")
                    retro_set_controller_port_device?(0, 1)
                    
                    var info = retro_game_info()
                    info.path = pathPtr.baseAddress
                    // Desmume is more stable with fullpath loading (no direct mapped data pointer).
                    if self.isUsingDesmumeCore {
                        info.data = nil
                        info.size = 0
                    } else {
                        info.data = baseAddress
                        info.size = data.count
                    }
                    info.meta = nil
                    
                    print(" [DSCore] Loading Game via Mapped Data: \(url.lastPathComponent)")
                    print(" [DSCore] Calling retro_load_game...")
                    
                    guard withUnsafePointer(to: &info, { infoPtr in
                        let result = retro_load_game?(infoPtr) ?? false
                        print("[DSCore] retro_load_game returned: \(result)")
                        return result
                    }) else {
                        print("❌ [DSCore] retro_load_game falló (returned false).")
                        return false
                    }
                    
                    self.isGameLoaded = true
                    print("[DSCore] Juego cargado exitosamente.")
                    
                    // Load Save RAM manually only for legacy MelonDS path.
                    // Desmume handles its own save files and manual injection can corrupt relaunch flow.
                    if !self.isUsingDesmumeCore {
                        loadSaveRAM()
                    }
                    
                    print(" [DSCore] Requesting AV Info from Core...")
                    var avInfo = retro_system_av_info()
                    withUnsafeMutablePointer(to: &avInfo) { avPtr in
                        retro_get_system_av_info?(avPtr)
                    }
                    
                    let sampleRate = avInfo.timing.sample_rate
                    print(" [DSCore] AV Info Received: Sample Rate: \(sampleRate)Hz, FPS: \(avInfo.timing.fps)")
                    
                    self.currentSampleRate = sampleRate // Store for resume
                    DSAudio.shared.start(rate: sampleRate)
                    
                    self.startLoop(fps: avInfo.timing.fps)
                    return true
                }
            }
        } catch {
            print(" [DSCore] Error mapping ROM: \(error)")
            return false
        }
    }
    
    private func startLoop(fps: Double) {
        isRunning = true
        displayLink = CADisplayLink(target: self, selector: #selector(gameLoop))
        
        // Fix for ProMotion (120Hz) - Cap at 60 FPS
        let targetFPS = Float(fps > 0 ? fps : 60.0)
        if #available(iOS 15.0, *) {
            displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: targetFPS, maximum: targetFPS, preferred: targetFPS)
        } else {
            displayLink?.preferredFramesPerSecond = Int(targetFPS)
        }
        
        displayLink?.add(to: .main, forMode: .common)
        
        // Monitor Micro, dosn't work it might never
        // startMicrophone() // Disabled
        
        // Monitor Motion (Lid)
        startMotion()
    }
    
    // MARK: - Pause/Resume Logic
    private var currentFPS: Double = 60.0
    private var currentSampleRate: Double = 44100.0
    
    public func pause() {
        if isRunning {
            isRunning = false
            displayLink?.isPaused = true
            DSAudio.shared.stop()
            stopMicrophone()
            stopMotion()
            print("sh [DSCore] Paused")
        }
    }
    
    public func resume() {
        if !isRunning && displayLink != nil {
            isRunning = true
            displayLink?.isPaused = false
            DSAudio.shared.start(rate: currentSampleRate) // Use valid rate
            startMotion() // Restart motion
            print("[DSCore] Resumed at \(currentSampleRate)Hz")
        } else if !isRunning {
            startLoop(fps: currentFPS)
            DSAudio.shared.start(rate: currentSampleRate)
        }
    }
    
    public func stopLoop() {
        // Save RAM manually only for legacy MelonDS path.
        // Desmume handles save files internally via libretro save directory.
        if !isUsingDesmumeCore {
            saveSaveRAM()
        }
        
        isRunning = false
        displayLink?.invalidate()
        displayLink = nil
        DSAudio.shared.stop()
        stopMicrophone()
        stopMotion()
    }

    public func unloadGameSession() {
        stopLoop()
        if isGameLoaded {
            retro_unload_game?()
            isGameLoaded = false
        }
        romData = nil
    }
    
    // MARK: - Microphone Support I really don't know why it dosen't wokr
    private var micRecorder: AVAudioRecorder?
    private var micTimer: Timer?
    
    private func setupMicrophone() {
        // Request Permission
        AVAudioSession.sharedInstance().requestRecordPermission { allowed in
            print("[DSCore] Mic Permission: \(allowed)")
        }
        
        // HACK: Reset Audio Session Category to PlayAndRecord to ensure mixing works
        // This is often needed if other apps or system sounds stole focus (i will keep this for now)
        /*
        do {
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetooth])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
             print(" [DSCore] Failed to reset Audio Session: \(error)")
        }
        */
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatAppleLossless),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
        ]
        
        do {
            // NOTE: AudioSession is already configured by DSAudio.start() with .playAndRecord
            // We just need to attach the recorder.
            
            let url = URL(fileURLWithPath: "/dev/null")
            micRecorder = try AVAudioRecorder(url: url, settings: settings)
            micRecorder?.isMeteringEnabled = true
            micRecorder?.prepareToRecord()
            print(" [DSCore] Microphone Setup Complete")
        } catch {
            print(" [DSCore] Mic Setup Failed: \(error)")
        }
    }
    
    private func startMicrophone() {
        if micRecorder == nil { setupMicrophone() }
        micRecorder?.record()
        
        // Monitor levels
        micTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.checkMicLevel()
        }
    }
    
    private func stopMicrophone() {
        micRecorder?.stop()
        micTimer?.invalidate()
        micTimer = nil
    }
    
    private func checkMicLevel() {
         micRecorder?.updateMeters()
         let power = micRecorder?.averagePower(forChannel: 0) ?? -160.0
         
         // Threshold: -20 dB (Adjust based on testing)
         let isBlowing = power > -10.0
         DSCore.isMicrophoneBlowing = isBlowing
         
         if isBlowing && !hasPrintedLoop {
             print(" [DSCore] Microphone BLOW Detected! (Power: \(power))")
             hasPrintedLoop = true // Anti-spam
         } else if !isBlowing {
             hasPrintedLoop = false
         }
    }
    
    // MARK: - Motion Support (Lid Close)
    private let motionManager = CMMotionManager()
    private var motionTimer: Timer?
    
    private func startMotion() {
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.2
            motionManager.startDeviceMotionUpdates()
            
            motionTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.checkOrientation()
            }
            print("📱 [DSCore] Motion Monitoring Started")
        }
    }
    
    private func stopMotion() {
        motionManager.stopDeviceMotionUpdates()
        motionTimer?.invalidate()
        motionTimer = nil
    }
    
    private func checkOrientation() {
        guard let data = motionManager.deviceMotion else { return }
        
      
        let isFaceDown = data.gravity.z > 0.8

        DSInput.shared.setButton(DSInput.ID_LID, pressed: isFaceDown)

    }

    // MARK: - Fast Forward
    public static var fastForward = false
    public static var isMicrophoneBlowing = false
    
    @objc private func gameLoop() {
        if !hasPrintedLoop {
            print(" [DSCore] Game Loop Running...")
            hasPrintedLoop = true
        }
        
        if DSCore.fastForward {
            // Speed up 3x
            retro_run?()
            retro_run?()
            retro_run?()
        } else {
            retro_run?()
        }
    }
    

    
    // MARK: - Save RAM (Memory Card) Manual Handling
    private func getSaveRAMPath() -> URL? {
        guard let romURL = currentROMURL,
              let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        
        let saveDir = docDir.appendingPathComponent("saves/ds")
        try? FileManager.default.createDirectory(at: saveDir, withIntermediateDirectories: true)
        
        let saveName = romURL.deletingPathExtension().lastPathComponent + ".dsv"
        return saveDir.appendingPathComponent(saveName)
    }
    
    func loadSaveRAM() {
        guard let path = getSaveRAMPath(),
              FileManager.default.fileExists(atPath: path.path) else { return }
        
        guard let getData = retro_get_memory_data,
              let getSize = retro_get_memory_size else { return }
        
        let size = getSize(0) // RETRO_MEMORY_SAVE_RAM = 0
        guard size > 0 else { return }
        
        if let ptr = getData(0) {
            if let data = try? Data(contentsOf: path), data.count <= size {
                data.withUnsafeBytes { buffer in
                    ptr.copyMemory(from: buffer.baseAddress!, byteCount: data.count)
                }
                print(" [DSCore] Save RAM loaded: \(path.lastPathComponent)")
            }
        }
    }
    
    func saveSaveRAM() {
        guard let path = getSaveRAMPath() else { return }
        
        guard let getData = retro_get_memory_data,
              let getSize = retro_get_memory_size else { return }
        
        let size = getSize(0) // RETRO_MEMORY_SAVE_RAM = 0
        guard size > 0 else { return }
        
        if let ptr = getData(0) {
            let data = Data(bytes: ptr, count: size)
            do {
                try data.write(to: path)
                print(" [DSCore] Save RAM saved: \(path.lastPathComponent)")
            } catch {
                print(" [DSCore] Failed to write Save RAM: \(error)")
            }
        }
    }
}
