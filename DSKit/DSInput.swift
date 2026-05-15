import Foundation
import Combine
import GameController

class DSInput: ObservableObject {
    static let shared = DSInput()
    static var debugTouchLogsEnabled = true
    
    @Published var isControllerConnected = false
    var buttonMask: UInt16 = 0
    private var physicalButtonMask: UInt16 = 0
    private var virtualButtonMask: UInt16 = 0
    
    // Touch State
    var touchX: Int16 = 0
    var touchY: Int16 = 0
    var isTouched: Bool = false
    private var lastTouchLogAt: TimeInterval = 0
    private var lastTouchLogSignature: String = ""
    
    func setTouch(x: Int16, y: Int16, pressed: Bool, source: String = "unknown") {
        touchX = x
        touchY = y
        isTouched = pressed

        guard Self.debugTouchLogsEnabled else { return }

        let signature = "\(pressed)-\(x)-\(y)-\(source)"
        let now = Date.timeIntervalSinceReferenceDate
        let shouldLog = (signature != lastTouchLogSignature) && (pressed || now - lastTouchLogAt > 0.06)

        if shouldLog {
            print("👆 [DSTouchInput] src=\(source) pressed=\(pressed) x=\(x) y=\(y)")
            lastTouchLogAt = now
            lastTouchLogSignature = signature
        }
    }
    
    private var currentController: GCController?
    
    static let ID_B: Int = 0
    static let ID_Y: Int = 1
    static let ID_SELECT: Int = 2
    static let ID_START: Int = 3
    static let ID_UP: Int = 4
    static let ID_DOWN: Int = 5
    static let ID_LEFT: Int = 6
    static let ID_RIGHT: Int = 7
    static let ID_A: Int = 8
    static let ID_X: Int = 9
    static let ID_L: Int = 10
    static let ID_R: Int = 11
    static let ID_MIC: Int = 12 // Map Microphone to L2 (Retrying L2 with Core Option 'blow' enabled)
    static let ID_LID: Int = 14 // Map Lid Close to L3 (Standard Libretro)
    
    private init() {
        setupControllerObserver()
    }
    
    // Virtual Controller Input
    func updateActionButtons(_ pressedIDs: Set<Int>) {
        // 1. Clear Action Buttons (A, B, X, Y)
        virtualButtonMask &= ~((1 << Self.ID_A) | (1 << Self.ID_B) | (1 << Self.ID_X) | (1 << Self.ID_Y))
        
        // 2. Set Active Buttons
        for id in pressedIDs {
            virtualButtonMask |= (1 << id)
        }

        // Keep effective mask updated even before next poll callback.
        buttonMask = physicalButtonMask | virtualButtonMask
    }
    
    func setButton(_ id: Int, pressed: Bool) {
        if pressed {
            virtualButtonMask |= (1 << id)
        } else {
            virtualButtonMask &= ~(1 << id)
        }

        // Keep effective mask updated even before next poll callback.
        buttonMask = physicalButtonMask | virtualButtonMask
    }
    
    func pollInput() {
        var mask: UInt16 = 0
        
        // Physical Controller
        if let controller = currentController, let gamepad = controller.extendedGamepad {
            
            if ControllerMappingManager.shared.isPressed(DSAction.a, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_A) }
            if ControllerMappingManager.shared.isPressed(DSAction.b, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_B) }
            if ControllerMappingManager.shared.isPressed(DSAction.x, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_X) } // Note: Check ID mapping (X usually maps to bit X)
            if ControllerMappingManager.shared.isPressed(DSAction.y, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_Y) }
            
            if ControllerMappingManager.shared.isPressed(DSAction.l, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_L) }
            if ControllerMappingManager.shared.isPressed(DSAction.r, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_R) }
            
            // Standard Triggers can double as L/R or be remapped. 
            // For now, let's keep extra triggers as Duplicate L/R if not mapped, or rely on Manager? 
            // Manager handles "Default" which usually includes Triggers. 
            // But here we need to map Action -> Bit.
            // Since Manager .l / .r map to shoulder/trigger, we rely on the Manager 'isPressed' to check all assigned inputs.
            
            if ControllerMappingManager.shared.isPressed(DSAction.start, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_START) }
            if ControllerMappingManager.shared.isPressed(DSAction.select, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_SELECT) }
            
            if ControllerMappingManager.shared.isPressed(DSAction.up, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_UP) }
            if ControllerMappingManager.shared.isPressed(DSAction.down, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_DOWN) }
            if ControllerMappingManager.shared.isPressed(DSAction.left, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_LEFT) }
            if ControllerMappingManager.shared.isPressed(DSAction.right, gamepad: gamepad, console: "Nintendo DS") { mask |= (1 << Self.ID_RIGHT) }
        }
        
        self.physicalButtonMask = mask
        self.buttonMask = mask | virtualButtonMask
    }
    
    private func setupControllerObserver() {
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidConnect), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerDidDisconnect), name: .GCControllerDidDisconnect, object: nil)
        
        if let controller = GCController.controllers().first {
            setupController(controller)
        }
    }
    
    @objc private func controllerDidConnect(_ notification: Notification) {
        if let controller = notification.object as? GCController {
            setupController(controller)
        }
    }
    
    @objc private func controllerDidDisconnect(_ notification: Notification) {
        isControllerConnected = false
        currentController = nil
        print("🎮 [DSInput] Mando desconectado")
    }
    
    private func setupController(_ controller: GCController) {
        print("🎮 [DSInput] Mando conectado: \(controller.vendorName ?? "Genérico")")
        currentController = controller
        isControllerConnected = true
        // Event handlers removed for polling
    }
}
