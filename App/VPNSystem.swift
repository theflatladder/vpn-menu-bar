import Foundation

enum VPNSystem {
    private static let scutil = URL(fileURLWithPath: "/usr/sbin/scutil")
    private static let uuidRegex = try! NSRegularExpression(pattern: #"[0-9A-Fa-f-]{36}"#)
    private static let quotedRegex = try! NSRegularExpression(pattern: #""([^"]+)""#)

    static func listServices() -> [VPNService] {
        run(["--nc", "list"])
            .split(separator: "\n")
            .compactMap(parseService(from:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func connect(_ service: VPNService) {
        _ = run(["--nc", "start", service.id])
    }

    static func disconnect(_ service: VPNService) {
        _ = run(["--nc", "stop", service.id])
    }

    private static func parseService(from line: Substring) -> VPNService? {
        let text = String(line)
        // Example line: *(Disconnected) UUID ... "Display Name" [VPN:...]
        guard let statusStart = text.firstIndex(of: "("),
              let statusEnd = text[statusStart...].firstIndex(of: ")")
        else {
            return nil
        }

        let statusText = String(text[text.index(after: statusStart)..<statusEnd])
        guard let id = firstMatch(in: text, regex: uuidRegex) else { return nil }
        let quoted = firstMatch(in: text, regex: quotedRegex)
        let name = quoted?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) ?? id
        return VPNService(id: id, name: name, status: .init(rawValue: statusText))
    }

    private static func firstMatch(in text: String, regex: NSRegularExpression) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else {
            return nil
        }
        return String(text[matchRange])
    }

    @discardableResult
    private static func run(_ arguments: [String]) -> String {
        let process = Process()
        process.executableURL = scutil
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
