import AppKit

@main
enum App {
    static func main() {
        let app = NSApplication.shared
        let delegate = MenuBarController()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
