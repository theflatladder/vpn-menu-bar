import AppKit
import Foundation
import Darwin // kill()

enum TrustTunnelManager {

    // MARK: - Stored paths

    private static let executablePathKey = "trustTunnelExecutablePath"
    private static let configPathKey     = "trustTunnelConfigPath"

    static var defaultExecutablePath: String { "/opt/trusttunnel_client/trusttunnel_client" }
    static var defaultConfigPath: String     { "/opt/trusttunnel_client/trusttunnel_client.toml" }

    static var executablePath: String? {
        get { UserDefaults.standard.string(forKey: executablePathKey) }
        set { UserDefaults.standard.set(newValue, forKey: executablePathKey) }
    }

    static var configPath: String? {
        get { UserDefaults.standard.string(forKey: configPathKey) }
        set { UserDefaults.standard.set(newValue, forKey: configPathKey) }
    }

    static var isConfigured: Bool { executablePath != nil && configPath != nil }

    static func save(executablePath: String, configPath: String) {
        self.executablePath = executablePath
        self.configPath     = configPath
    }

    // MARK: - Running state

    private(set) static var runningPID: Int32?
    static var isRunning: Bool { runningPID != nil }

    /// Called on the main thread whenever the CLI starts, stops, or dies on its own.
    static var onStateChanged: (() -> Void)?

    // MARK: - Start

    static func start(completion: @escaping (_ success: Bool) -> Void) {
        guard let execPath = executablePath, let confPath = configPath else {
            completion(false); return
        }

        let execURL = URL(fileURLWithPath: execPath)
        let dir     = execURL.deletingLastPathComponent().path
        let exec    = execURL.lastPathComponent

        // Background the CLI (&). No echo $! — pgrep locates the PID after launch,
        // which is more reliable than relying on do shell script to return $! output.
        let appleScript = """
        do shell script "cd " & quoted form of "\(dir.appleScriptEscaped)" \
        & " && ./" & quoted form of "\(exec.appleScriptEscaped)" \
        & " --config " & quoted form of "\(confPath.appleScriptEscaped)" \
        & " > /dev/null 2>&1 &" with administrator privileges
        """

        DispatchQueue.global(qos: .userInitiated).async {
            // runOsascript returns nil if user cancels the password dialog or command fails.
            guard runOsascript(appleScript) != nil else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            // Give the process a moment to fully start before querying for its PID.
            Thread.sleep(forTimeInterval: 0.5)
            let pid = findPID(for: exec)

            DispatchQueue.main.async {
                if let pid {
                    runningPID = pid
                    startMonitoring(pid: pid)
                    completion(true)
                } else {
                    // CLI exited immediately (wrong path, config error, etc.)
                    completion(false)
                }
            }
        }
    }

    // MARK: - Stop

    static func stop(completion: @escaping () -> Void) {
        guard let pid = runningPID else { completion(); return }

        stopMonitoring()
        runningPID = nil      // clear immediately so the UI reflects the intent
        onStateChanged?()

        let appleScript = "do shell script \"kill \(pid)\" with administrator privileges"
        DispatchQueue.global(qos: .userInitiated).async {
            _ = runOsascript(appleScript)
            DispatchQueue.main.async { completion() }
        }
    }

    // MARK: - PID discovery

    /// Uses pgrep -fn to find the newest process whose command line contains the
    /// executable name. -f matches the full argument list (avoids the 15-char
    /// truncation of the process name field); -n returns only the newest match.
    private static func findPID(for executableName: String) -> Int32? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments     = ["-fn", executableName]
        process.standardError = Pipe() // suppress "no process found" stderr

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data   = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Int32(output)
    }

    // MARK: - Process monitoring

    private static var monitorTimer: Timer?

    /// Polls every 3 seconds using kill(pid, 0).
    /// For a root-owned process: returns EPERM (process alive) or ESRCH (process gone).
    /// Timer is added to .common so it fires even while a menu is open.
    private static func startMonitoring(pid: Int32) {
        stopMonitoring()
        let timer = Timer(timeInterval: 3, repeats: true) { _ in
            guard !isProcessAlive(pid: pid) else { return }
            runningPID = nil
            stopMonitoring()
            onStateChanged?()
        }
        RunLoop.main.add(timer, forMode: .common)
        monitorTimer = timer
    }

    private static func stopMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = nil
    }

    private static func isProcessAlive(pid: Int32) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    // MARK: - osascript runner

    /// Runs an AppleScript source via /usr/bin/osascript as a subprocess.
    /// Returns the trimmed stdout on success, nil if the script errors or the
    /// user cancels the authorization dialog.
    @discardableResult
    private static func runOsascript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments     = ["-e", source]

        let outputPipe = Pipe()
        let errorPipe  = Pipe()
        process.standardOutput = outputPipe
        process.standardError  = errorPipe

        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var appleScriptEscaped: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
