import Cocoa
import FlutterMacOS
import UserNotifications

enum DockBadge {
  private static var baseIcon: NSImage?
  private static var visible = false
  private static var badgeCount = 0

  static func resetBaseIcon(_ icon: NSImage) {
    baseIcon = icon.copy() as? NSImage
    if visible { render() }
  }

  static func apply(visible: Bool) {
    apply(count: visible ? 1 : 0)
  }

  static func apply(count: Int) {
    badgeCount = max(0, count)
    visible = badgeCount > 0
    render()
  }

  private static func render() {
    guard let baseIcon = baseIcon ?? NSApp.applicationIconImage?.copy() as? NSImage else {
      return
    }
    self.baseIcon = baseIcon

    guard visible else {
      NSApp.applicationIconImage = baseIcon
      NSApp.dockTile.badgeLabel = nil
      NSApp.dockTile.display()
      return
    }

    guard let icon = baseIcon.copy() as? NSImage else { return }
    // Keep the badge legible at the Dock's rendered size.  A 24% badge was
    // only a few pixels wide on a standard Dock and made the count hard to
    // read, especially for users with a smaller Dock scale.
    let diameter = min(icon.size.width, icon.size.height) * 0.34
    let origin = NSPoint(
      x: icon.size.width - diameter * 1.08,
      y: icon.size.height - diameter * 1.08
    )
    icon.lockFocus()
    NSColor.systemRed.setFill()
    NSBezierPath(
      ovalIn: NSRect(
        origin: origin,
        size: NSSize(width: diameter, height: diameter)
      )
    ).fill()
    let label = min(badgeCount, 99)
    let text = "\(label)" as NSString
    let font = NSFont.boldSystemFont(ofSize: diameter * 0.56)
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: NSColor.white,
    ]
    let textSize = text.size(withAttributes: attributes)
    text.draw(
      at: NSPoint(
        x: origin.x + (diameter - textSize.width) / 2,
        y: origin.y + (diameter - textSize.height) / 2
      ),
      withAttributes: attributes
    )
    icon.unlockFocus()
    NSApp.applicationIconImage = icon
    // The rasterized badge is intentionally the only renderer.  Leaving
    // badgeLabel set would add macOS's fixed-size badge on top of this one and
    // make the requested larger size ineffective on supported systems.
    NSApp.dockTile.showsApplicationBadge = false
    NSApp.dockTile.badgeLabel = nil
    NSApp.dockTile.display()
  }

}

enum DockIcon {
  private static let selectedAssetKey = "codexDesk.selectedDockIconAsset"

  @discardableResult
  static func apply(named assetName: String = "DockIcon") -> Bool {
    guard let icon = NSImage(named: NSImage.Name(assetName)) else {
      return false
    }

    guard let dockIcon = icon.copy() as? NSImage else { return false }
    dockIcon.isTemplate = false
    NSApp.applicationIconImage = dockIcon
    DockBadge.resetBaseIcon(dockIcon)
    NSApp.dockTile.display()
    return true
  }

  static func select(named assetName: String) -> Bool {
    guard apply(named: assetName) else { return false }
    UserDefaults.standard.set(assetName, forKey: selectedAssetKey)
    return true
  }

  static func applySelected() {
    let assetName = UserDefaults.standard.string(forKey: selectedAssetKey) ?? "DockIcon"
    if !apply(named: assetName) { _ = apply() }
  }

  static var selectedIdentifier: String {
    UserDefaults.standard.string(forKey: selectedAssetKey) == "CodexDockIcon"
      ? "knot"
      : "commandCloud"
  }
}

@main
class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  override func applicationDidFinishLaunching(_ notification: Notification) {
    UNUserNotificationCenter.current().delegate = self
    super.applicationDidFinishLaunching(notification)
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func notifyTaskCompleted(completion: @escaping (Bool) -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        self.enqueueTaskCompletionNotification(using: center, completion: completion)
      case .notDetermined:
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
          guard granted else {
            completion(false)
            return
          }
          self.enqueueTaskCompletionNotification(using: center, completion: completion)
        }
      default:
        completion(false)
      }
    }
  }

  func setDockBadge(visible: Bool) {
    // NSDockTile is AppKit UI state and must be mutated on the main thread.
    // Flutter method-channel callbacks can arrive off-main in release builds;
    // dispatching here prevents a successful notification from missing its
    // Dock refresh.
    let update = {
      // NSApplication's Dock tile defaults to hiding application badges.  Set
      // this explicitly before updating the label so completion feedback is
      // rendered even when the tile has not displayed a badge before.
      // NSApplication 的 Dock Tile 默认不显示应用徽标；在更新文字前显式开启，
      // 确保首次任务完成时也能绘制徽标。
      DockBadge.apply(visible: visible)
    }
    if Thread.isMainThread {
      update()
    } else {
      DispatchQueue.main.async(execute: update)
    }
  }

  private func enqueueTaskCompletionNotification(
    using center: UNUserNotificationCenter,
    completion: @escaping (Bool) -> Void
  ) {
    let content = UNMutableNotificationContent()
    content.title = "任务已完成"
    content.body = "Codex 已完成一项任务。"
    content.sound = .default
    let request = UNNotificationRequest(
      identifier: "task-completed-\(UUID().uuidString)",
      content: content,
      trigger: nil
    )
    center.add(request) { error in
      completion(error == nil)
    }
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }
}
