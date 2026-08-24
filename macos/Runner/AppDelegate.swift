import Cocoa
import FlutterMacOS

final class DockIconView: NSView {
  private let imageView = NSImageView()

  init(icon: NSImage, size: NSSize) {
    super.init(frame: NSRect(origin: .zero, size: size))
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.cornerRadius = min(size.width, size.height) * 0.22
    layer?.masksToBounds = true

    imageView.image = icon
    imageView.imageAlignment = .alignCenter
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.imageFrameStyle = .none
    addSubview(imageView)
    updateImageFrame()
  }

  required init?(coder: NSCoder) {
    nil
  }

  override var isOpaque: Bool {
    false
  }

  override func layout() {
    super.layout()
    layer?.cornerRadius = min(bounds.width, bounds.height) * 0.22
    updateImageFrame()
  }

  private func updateImageFrame() {
    // Match the optical safe area used by neighboring macOS Dock icons. The
    // transparent inset prevents this custom Dock tile from looking larger
    // than the system-rendered icons around it.
    let inset = min(bounds.width, bounds.height) * 0.11
    imageView.frame = bounds.insetBy(dx: inset, dy: inset)
  }
}

enum DockIcon {
  static func apply() {
    guard
      let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
      let icon = NSImage(contentsOf: iconURL)
    else {
      return
    }

    icon.isTemplate = false
    NSApp.applicationIconImage = icon
    let dockTile = NSApp.dockTile
    dockTile.contentView = DockIconView(icon: icon, size: dockTile.size)
    dockTile.display()
  }
}

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
