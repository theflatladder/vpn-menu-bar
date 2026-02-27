import Foundation

struct VPNService: Equatable {
    enum Status: Equatable {
        case connected
        case disconnected
        case connecting
        case disconnecting
        case unknown

        init(rawValue: String) {
            switch rawValue.lowercased() {
            case "connected":
                self = .connected
            case "disconnected":
                self = .disconnected
            case "connecting":
                self = .connecting
            case "disconnecting":
                self = .disconnecting
            default:
                self = .unknown
            }
        }
    }

    let id: String
    let name: String
    let status: Status

    var isConnected: Bool {
        status == .connected
    }
}
