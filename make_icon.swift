import Cocoa

func generateIcon(path: String) {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    
    image.lockFocus()
    
    // Background Rounded Rect (macOS App Icon Shape)
    let inset: CGFloat = 100
    let rect = NSRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
    let cornerRadius: CGFloat = 180
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
    
    // Shadow
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowOffset = NSSize(width: 0, height: -20)
    shadow.shadowBlurRadius = 40
    shadow.set()
    
    // Gradient Background: Sleek Modern Slate & Indigo
    let gradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.18, green: 0.22, blue: 0.32, alpha: 1.0),
            NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.16, alpha: 1.0)
        ]
    )
    gradient?.draw(in: bgPath, angle: -45)
    
    // Reset shadow for content
    NSShadow().set()
    
    // Inner border glow
    bgPath.lineWidth = 4
    NSColor.white.withAlphaComponent(0.15).setStroke()
    bgPath.stroke()
    
    // Draw Keyboard Icon / Monogram 'T'
    let text = "T"
    let font = NSFont.systemFont(ofSize: 420, weight: .bold)
    let textAttributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white
    ]
    let attrString = NSAttributedString(string: text, attributes: textAttributes)
    let textSize = attrString.size()
    let textPoint = NSPoint(
        x: (size.width - textSize.width) / 2,
        y: (size.height - textSize.height) / 2 + 10
    )
    attrString.draw(at: textPoint)
    
    // Draw a small glowing cursor bar under/beside T
    let cursorRect = NSRect(
        x: textPoint.x + textSize.width + 12,
        y: textPoint.y + 70,
        width: 24,
        height: 300
    )
    let cursorPath = NSBezierPath(roundedRect: cursorRect, xRadius: 12, yRadius: 12)
    NSColor(calibratedRed: 0.35, green: 0.65, blue: 1.0, alpha: 0.9).setFill()
    cursorPath.fill()
    
    image.unlockFocus()
    
    // Save to PNG
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
generateIcon(path: outputPath)
