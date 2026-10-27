import ServiceManagement

/// Launch-at-login via `SMAppService.mainApp`. The single place that talks to ServiceManagement.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Registers or unregisters the app. Throws when the system refuses (e.g. an unsigned build).
    static func set(enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }
}
