import AppKit

enum StatusIconFactory {
    static let disconnected = makeLayeredStatusIcon(
        backgroundSymbol: "shield",
        backgroundColor: .white
    )

    static let connected = makeLayeredStatusIcon(
        backgroundSymbol: "shield",
        backgroundColor: .white,
        foregroundSymbol: "lock.fill",
        foregroundColor: .systemGreen,
        foregroundScale: 0.62
    )

    private static func makeLayeredStatusIcon(
        backgroundSymbol: String,
        backgroundColor: NSColor,
        foregroundSymbol: String? = nil,
        foregroundColor: NSColor = .white,
        foregroundScale: CGFloat = 1
    ) -> NSImage? {
        guard let backgroundBase = NSImage(systemSymbolName: backgroundSymbol, accessibilityDescription: "VPN") else {
            return nil
        }

        let pointSize = NSStatusBar.system.thickness - 4
        let backgroundConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular, scale: .large)
            .applying(NSImage.SymbolConfiguration(hierarchicalColor: backgroundColor))
        let backgroundIcon = backgroundBase.withSymbolConfiguration(backgroundConfig) ?? backgroundBase

        let canvasSide = NSStatusBar.system.thickness - 1
        let canvasSize = NSSize(width: canvasSide, height: canvasSide)
        let canvas = NSImage(size: canvasSize)
        canvas.lockFocus()

        let inset: CGFloat = 0.25
        let backgroundRect = NSRect(
            x: inset,
            y: inset,
            width: canvasSize.width - (inset * 2),
            height: canvasSize.height - (inset * 2)
        )
        backgroundIcon.draw(in: backgroundRect)

        if let foregroundSymbol {
            let foregroundBase = NSImage(systemSymbolName: foregroundSymbol, accessibilityDescription: "VPN")
            let foregroundPointSize = pointSize * foregroundScale
            let foregroundConfig = NSImage.SymbolConfiguration(pointSize: foregroundPointSize, weight: .bold, scale: .medium)
                .applying(NSImage.SymbolConfiguration(hierarchicalColor: foregroundColor))
            let foregroundIcon = (foregroundBase?.withSymbolConfiguration(foregroundConfig)) ?? foregroundBase

            if let foregroundIcon {
                let lockHeight = canvasSize.width * 0.52
                let lockWidth = lockHeight * 0.9
                let lockRect = NSRect(
                    x: (canvasSize.width - lockWidth) / 2 - 0.1,
                    y: (canvasSize.height - lockHeight) / 2 + 0.6,
                    width: lockWidth,
                    height: lockHeight
                )
                foregroundIcon.draw(in: lockRect)
            }
        }

        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }
}
