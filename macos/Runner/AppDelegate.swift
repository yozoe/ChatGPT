import Cocoa
import FlutterMacOS
import UserNotifications

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
    NSApp.dockTile.badgeLabel = visible ? "•" : nil
    NSApp.dockTile.display()
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
