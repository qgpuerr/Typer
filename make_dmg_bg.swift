import Cocoa

func generateDmgBackground(path: String) {
    let width: CGFloat = 560
    let height: CGFloat = 360
    let size = NSSize(width: width, height: height)
    let image = NSImage(size: size)
    
    image.lockFocus()
    
    // Background Clean Gradient
    let bgRect = NSRect(x: 0, y: 0, width: width, height: height)
    let bgGradient = NSGradient(
        colors: [
            NSColor(calibratedRed: 0.96, green: 0.97, blue: 0.99, alpha: 1.0),
            NSColor(calibratedRed: 0.91, green: 0.93, blue: 0.96, alpha: 1.0)
        ]
    )
    bgGradient?.draw(in: bgRect, angle: -90)
    
    // Draw subtle border
    let border = NSBezierPath(rect: bgRect)
    border.lineWidth = 1
    NSColor(calibratedWhite: 0.82, alpha: 1.0).setStroke()
    border.stroke()
    
    // Draw Title: "拖拽 Typer 到右侧 Applications 即可完成安装"
    let title = "拖拽 Typer 到右侧完成安装"
    let font = NSFont.systemFont(ofSize: 15, weight: .medium)
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1.0)
    ]
    let titleString = NSAttributedString(string: title, attributes: titleAttrs)
    let titleSize = titleString.size()
    titleString.draw(at: NSPoint(x: (width - titleSize.width) / 2, y: height - 55))
    
    // Draw Arrow in the middle
    let arrow = "➔"
    let arrowFont = NSFont.systemFont(ofSize: 34, weight: .bold)
    let arrowAttrs: [NSAttributedString.Key: Any] = [
        .font: arrowFont,
        .foregroundColor: NSColor(calibratedRed: 0.25, green: 0.55, blue: 0.95, alpha: 0.6)
    ]
    let arrowString = NSAttributedString(string: arrow, attributes: arrowAttrs)
    let arrowSize = arrowString.size()
    arrowString.draw(at: NSPoint(x: (width - arrowSize.width) / 2, y: (height - arrowSize.height) / 2 - 10))
    
    image.unlockFocus()
    
    if let tiff = image.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg_bg.png"
generateDmgBackground(path: outputPath)
