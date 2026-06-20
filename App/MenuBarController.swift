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

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.imageScaling = .scaleNone
        }

        menu.delegate = self
        statusItem.menu = menu

        LaunchAtLoginManager.syncPreferenceAtLaunch()
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

        if services.isEmpty {
            menu.addItem(withTitle: "No VPN services found", action: nil, keyEquivalent: "")
        } else {
            for service in services {
                let item = NSMenuItem(title: service.name, action: #selector(toggleService(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = service.id
                item.state = service.isConnected ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

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
