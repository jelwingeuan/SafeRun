import OSLog

enum SafeRunLog {
    static let planner = Logger(subsystem: "com.jelwin.safe-run", category: "planner")
    static let simulation = Logger(subsystem: "com.jelwin.safe-run", category: "simulation")
    static let execution = Logger(subsystem: "com.jelwin.safe-run", category: "execution")
    static let rollback = Logger(subsystem: "com.jelwin.safe-run", category: "rollback")
    static let security = Logger(subsystem: "com.jelwin.safe-run", category: "security")
    static let network = Logger(subsystem: "com.jelwin.safe-run", category: "network")
}
