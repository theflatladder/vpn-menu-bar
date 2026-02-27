import Foundation
import SystemConfiguration

final class VPNStatusMonitor {
    private let onChange: () -> Void
    private let debounceQueue = DispatchQueue(label: "com.vpnmenubar.status-monitor", qos: .utility)
    private let debounceInterval: TimeInterval = 0.2
    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var pendingNotificationWorkItem: DispatchWorkItem?

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
    }

    @discardableResult
    func start() -> Bool {
        guard store == nil else { return true }

        var context = SCDynamicStoreContext(
            version: 0,
            info: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: SCDynamicStoreCallBack = { _, _, info in
            guard let info else { return }
            let monitor = Unmanaged<VPNStatusMonitor>.fromOpaque(info).takeUnretainedValue()
            monitor.notifyChange()
        }

        guard let store = SCDynamicStoreCreate(nil, "VPNMenuBarStatusMonitor" as CFString, callback, &context) else {
            return false
        }

        let keys: [CFString] = [
            "State:/Network/Global/IPv4" as CFString,
            "State:/Network/Global/IPv6" as CFString
        ]
        let patterns: [CFString] = [
            "State:/Network/Service/.*/PPP" as CFString,
            "State:/Network/Service/.*/IPSec" as CFString,
            "State:/Network/Service/.*/VPN" as CFString,
            "State:/Network/Service/.*/IPv4" as CFString,
            "State:/Network/Service/.*/IPv6" as CFString
        ]

        guard SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray),
              let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        else {
            return false
        }

        self.store = store
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        return true
    }

    func stop() {
        debounceQueue.sync {
            pendingNotificationWorkItem?.cancel()
            pendingNotificationWorkItem = nil
        }
        guard let source = runLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
        runLoopSource = nil
        store = nil
    }

    private func notifyChange() {
        debounceQueue.async { [weak self] in
            guard let self else { return }
            self.pendingNotificationWorkItem?.cancel()
            let workItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                DispatchQueue.main.async { [weak self] in
                    self?.onChange()
                }
            }
            pendingNotificationWorkItem = workItem
            debounceQueue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
        }
    }

    deinit {
        stop()
    }
}
