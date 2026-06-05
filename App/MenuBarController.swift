import AppKit
import Foundation

final class MenuBarController: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let refreshQueue = DispatchQueue(label: "com.vpnmenubar.refresh", qos: .utility)
    private let actionQueue = DispatchQueue(label: "com.vpnmenubar.actions", qos: .userInitiated)
    private let menu = NSMenu()

    private lazy var statusMonitor = VPNStatusMonitor { [weak self] in
        self?.requestRefresh()
    }

    private var services: [VPNService] = []
    private var isRefreshInFlight = false
    private var refreshRequestedWhileInFlight = false
    private var lastConnectedState: Bool?
    private var fallbackTimer: Timer?
    private weak var startAtLoginItem: NSMenuItem?
    private var isTrustTunnelBusy = false

    // Held during the setup dialog so Browse button actions can update the fields.
    private var setupExecField: NSTextField?
    private var setupConfigField: NSTextField?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.imageScaling = .scaleNone
        }

        menu.delegate = self
        statusItem.menu = menu

        LaunchAtLoginManager.syncPreferenceAtLaunch()

        // Rebuild menu whenever the CLI process starts, stops, or dies on its own.
        TrustTunnelManager.onStateChanged = { [weak self] in
            self?.rebuildMenu()
        }

        rebuildMenu()
        updateIcon(connected: false)

        if !statusMonitor.start() {
            // Rare fallback in case the system monitor cannot be created.
            let timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
                self?.requestRefresh()
            }
            timer.tolerance = 1
            fallbackTimer = timer
        }

        requestRefresh()
    }

    func applicationWillTerminate(_ notification: Notification) {
        fallbackTimer?.invalidate()
        statusMonitor.stop()
    }

    func menuWillOpen(_ menu: NSMenu) {
        startAtLoginItem?.state = LaunchAtLoginManager.isEnabled ? .on : .off
        requestRefresh()
    }

    @objc private func toggleService(_ sender: NSMenuItem) {
        guard let tappedID = sender.representedObject as? String else { return }
        guard let tapped = services.first(where: { $0.id == tappedID }) else { return }
        let currentConnected = services.first(where: \.isConnected)

        actionQueue.async { [weak self] in
            if tapped.isConnected {
                VPNSystem.disconnect(tapped)
            } else {
                // "Switch VPN" behavior: always stop current first, then start selected.
                if let currentConnected, currentConnected.id != tapped.id {
                    VPNSystem.disconnect(currentConnected)
                }
                VPNSystem.connect(tapped)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self?.requestRefresh()
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func toggleTrustTunnel() {
        guard !isTrustTunnelBusy else { return }
        isTrustTunnelBusy = true
        rebuildMenu()

        if TrustTunnelManager.isRunning {
            TrustTunnelManager.stop {
                self.isTrustTunnelBusy = false
                self.rebuildMenu()
            }
        } else {
            TrustTunnelManager.start { _ in
                self.isTrustTunnelBusy = false
                self.rebuildMenu()
            }
        }
    }

    @objc private func showTrustTunnelSetup() {
        let alert = NSAlert()
        alert.messageText = "TrustTunnel CLI Setup"
        alert.informativeText = "Enter the paths to the TrustTunnel executable and config file."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        // Layout constants
        let containerWidth: CGFloat = 460
        let labelWidth: CGFloat     = 90
        let fieldX: CGFloat         = 98
        let browseWidth: CGFloat    = 80
        let fieldWidth              = containerWidth - fieldX - 6 - browseWidth
        let browseX                 = fieldX + fieldWidth + 6
        let container = NSView(frame: NSRect(x: 0, y: 0, width: containerWidth, height: 68))

        // --- Executable row ---
        let execLabel = NSTextField(labelWithString: "Executable:")
        execLabel.frame = NSRect(x: 0, y: 46, width: labelWidth, height: 20)
        execLabel.alignment = .right

        let execField = NSTextField(frame: NSRect(x: fieldX, y: 44, width: fieldWidth, height: 22))
        execField.stringValue       = TrustTunnelManager.executablePath ?? TrustTunnelManager.defaultExecutablePath
        execField.placeholderString = TrustTunnelManager.defaultExecutablePath

        let execBrowse = NSButton(title: "Browse…", target: self, action: #selector(browseExecutable))
        execBrowse.frame      = NSRect(x: browseX, y: 44, width: browseWidth, height: 22)
        execBrowse.bezelStyle = .rounded

        // --- Config file row ---
        let configLabel = NSTextField(labelWithString: "Config file:")
        configLabel.frame = NSRect(x: 0, y: 16, width: labelWidth, height: 20)
        configLabel.alignment = .right

        let configField = NSTextField(frame: NSRect(x: fieldX, y: 14, width: fieldWidth, height: 22))
        configField.stringValue       = TrustTunnelManager.configPath ?? TrustTunnelManager.defaultConfigPath
        configField.placeholderString = TrustTunnelManager.defaultConfigPath

        let configBrowse = NSButton(title: "Browse…", target: self, action: #selector(browseConfig))
        configBrowse.frame      = NSRect(x: browseX, y: 14, width: browseWidth, height: 22)
        configBrowse.bezelStyle = .rounded

        container.addSubview(execLabel)
        container.addSubview(execField)
        container.addSubview(execBrowse)
        container.addSubview(configLabel)
        container.addSubview(configField)
        container.addSubview(configBrowse)
        alert.accessoryView = container

        // Store fields so browse actions can update them while the dialog is open.
        setupExecField   = execField
        setupConfigField = configField
        defer {
            setupExecField   = nil
            setupConfigField = nil
        }

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let exec = execField.stringValue.trimmingCharacters(in: .whitespaces)
        let conf = configField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !exec.isEmpty, !conf.isEmpty else { return }

        TrustTunnelManager.save(executablePath: exec, configPath: conf)
        rebuildMenu()
    }

    @objc private func browseExecutable() {
        let panel = NSOpenPanel()
        panel.title                = "Select TrustTunnel Executable"
        panel.canChooseFiles       = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let current = setupExecField?.stringValue, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setupExecField?.stringValue = url.path
    }

    @objc private func browseConfig() {
        let panel = NSOpenPanel()
        panel.title                = "Select TrustTunnel Config File"
        panel.canChooseFiles       = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let current = setupConfigField?.stringValue, !current.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setupConfigField?.stringValue = url.path
    }

    @objc private func toggleStartAtLogin() {
        let newValue = !LaunchAtLoginManager.isEnabled
        if LaunchAtLoginManager.setEnabled(newValue) {
            startAtLoginItem?.state = newValue ? .on : .off
        }
    }

    private func requestRefresh() {
        if isRefreshInFlight {
            refreshRequestedWhileInFlight = true
            return
        }

        isRefreshInFlight = true
        refreshQueue.async { [weak self] in
            let latestServices = VPNSystem.listServices()
            DispatchQueue.main.async {
                guard let self else { return }
                self.apply(latestServices)
            }
        }
    }

    private func apply(_ latestServices: [VPNService]) {
        let previousServices = services
        let wasConnected = lastConnectedState ?? previousServices.contains(where: \.isConnected)
        let isConnected = latestServices.contains(where: \.isConnected)

        services = latestServices

        if wasConnected != isConnected || lastConnectedState == nil {
            updateIcon(connected: isConnected)
            lastConnectedState = isConnected
        }

        if !hasSameServiceIdentity(previousServices, latestServices) {
            rebuildMenu()
        } else if previousServices != latestServices {
            updateServiceStates(latestServices)
        }

        isRefreshInFlight = false
        if refreshRequestedWhileInFlight {
            refreshRequestedWhileInFlight = false
            requestRefresh()
        }
    }

    private func updateIcon(connected: Bool) {
        guard let button = statusItem.button else { return }
        button.image = connected ? StatusIconFactory.connected : StatusIconFactory.disconnected
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let cliRunning = TrustTunnelManager.isRunning

        if services.isEmpty {
            menu.addItem(withTitle: "No VPN services found", action: nil, keyEquivalent: "")
        } else {
            for service in services {
                // Gray out VPN items while the CLI is active — using both at once
                // risks conflicting network configurations.
                let item = NSMenuItem(
                    title: service.name,
                    action: cliRunning ? nil : #selector(toggleService(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = service.id
                item.state = service.isConnected ? .on : .off
                menu.addItem(item)
            }
        }

        if TrustTunnelManager.isConfigured {
            let title: String
            if isTrustTunnelBusy {
                title = TrustTunnelManager.isRunning ? "Stopping TrustTunnel CLI…" : "Starting TrustTunnel CLI…"
            } else {
                title = TrustTunnelManager.isRunning ? "Stop TrustTunnel CLI" : "Run TrustTunnel CLI"
            }
            let tunnelItem = NSMenuItem(
                title: title,
                action: isTrustTunnelBusy ? nil : #selector(toggleTrustTunnel),
                keyEquivalent: ""
            )
            tunnelItem.target = self
            menu.addItem(tunnelItem)
        }

        menu.addItem(.separator())

        if !TrustTunnelManager.isConfigured {
            let addItem = NSMenuItem(title: "Add TrustTunnel CLI", action: #selector(showTrustTunnelSetup), keyEquivalent: "")
            addItem.target = self
            menu.addItem(addItem)
        } else {
            let configureItem = NSMenuItem(title: "Configure TrustTunnel CLI", action: #selector(showTrustTunnelSetup), keyEquivalent: "")
            configureItem.target = self
            menu.addItem(configureItem)
        }

        let startAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleStartAtLogin), keyEquivalent: "")
        startAtLoginItem.target = self
        startAtLoginItem.state = LaunchAtLoginManager.isEnabled ? .on : .off
        menu.addItem(startAtLoginItem)
        self.startAtLoginItem = startAtLoginItem

        let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    private func hasSameServiceIdentity(_ lhs: [VPNService], _ rhs: [VPNService]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.id == right.id && left.name == right.name
        }
    }

    private func updateServiceStates(_ latestServices: [VPNService]) {
        var serviceIndex = 0
        for item in menu.items {
            guard item.action == #selector(toggleService(_:)) else { continue }
            guard serviceIndex < latestServices.count else { break }
            item.state = latestServices[serviceIndex].isConnected ? .on : .off
            serviceIndex += 1
        }
    }
}
