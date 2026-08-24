import Cocoa
import FlutterMacOS

enum DockIcon {
  static func apply() {
    guard let icon = NSImage(named: "DockIcon") else {
      return
    }

    icon.isTemplate = false
    NSApp.applicationIconImage = icon
    NSApp.dockTile.display()
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
