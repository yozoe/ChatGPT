import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var taskCompletionChannel: FlutterMethodChannel?
  private var appActivationObserver: NSObjectProtocol?
  private static let frameAutosaveName = "CodexDeskMainWindow"
  private static let clipboardTemporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexDeskClipboard", isDirectory: true)

  private static func readClipboardItems() throws -> [[String: Any]] {
    let pasteboard = NSPasteboard.general
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true
    ]
    let urls = pasteboard.readObjects(
      forClasses: [NSURL.self],
      options: options
    ) as? [URL] ?? []
    if !urls.isEmpty {
      return urls.map { url -> [String: Any] in
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return [
          "path": url.path,
          "isDirectory": values?.isDirectory ?? url.hasDirectoryPath,
          "isTemporary": false
        ]
      }
    }

    guard
      let image = NSImage(pasteboard: pasteboard),
      let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
    else {
      return []
    }

    try FileManager.default.createDirectory(
      at: clipboardTemporaryDirectory,
      withIntermediateDirectories: true
    )
    let imageUrl = clipboardTemporaryDirectory.appendingPathComponent(
      "clipboard-image-\(pasteboard.changeCount).png"
    )
    if !FileManager.default.fileExists(atPath: imageUrl.path) {
      try pngData.write(to: imageUrl, options: .atomic)
    }
    return [[
      "path": imageUrl.path,
      "isDirectory": false,
      "isTemporary": true
    ]]
  }

  private static func deleteClipboardTemporaryItem(atPath path: String) -> Bool {
    let target = URL(fileURLWithPath: path).standardizedFileURL
    let directory = clipboardTemporaryDirectory.standardizedFileURL
    guard target.deletingLastPathComponent() == directory else { return false }
    guard FileManager.default.fileExists(atPath: target.path) else { return true }
    do {
      try FileManager.default.removeItem(at: target)
      return true
    } catch {
      return false
    }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.setFrameAutosaveName(Self.frameAutosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)
    DispatchQueue.main.async {
      DockIcon.applySelected()
    }
    try? FileManager.default.removeItem(at: Self.clipboardTemporaryDirectory)

    let clipboardChannel = FlutterMethodChannel(
      name: "codex_desk/clipboard",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    clipboardChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "readFileItems":
        do {
          result(try Self.readClipboardItems())
        } catch {
          result(FlutterError(
            code: "clipboard_image_failed",
            message: "Unable to prepare the clipboard image.",
            details: error.localizedDescription
          ))
        }
      case "deleteTemporaryItem":
        guard let path = call.arguments as? String else {
          result(FlutterError(
            code: "invalid_temporary_path",
            message: "A temporary clipboard path is required.",
            details: nil
          ))
          return
        }
        result(Self.deleteClipboardTemporaryItem(atPath: path))
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let taskCompletionChannel = FlutterMethodChannel(
      name: "codex_desk/task_completion",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    self.taskCompletionChannel = taskCompletionChannel
    taskCompletionChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "notifyTaskCompleted":
        guard let appDelegate = NSApp.delegate as? AppDelegate else {
          result(FlutterError(
            code: "app_delegate_unavailable",
            message: "The application delegate is unavailable.",
            details: nil
          ))
          return
        }
        appDelegate.notifyTaskCompleted { delivered in
          result(delivered)
        }
      case "setDockBadge":
        let arguments = call.arguments as? [String: Any]
        let visible = arguments?["visible"] as? Bool ?? false
        let count = arguments?["count"] as? Int ?? (visible ? 1 : 0)
        // Update the application Dock tile directly instead of requiring an
        // AppDelegate cast. This keeps the diagnostic button usable even when
        // the host delegate is supplied by another Flutter embedding.
        let update = {
          DockBadge.apply(count: count)
        }
        if Thread.isMainThread {
          update()
        } else {
          DispatchQueue.main.async(execute: update)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    appActivationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in
      self?.taskCompletionChannel?.invokeMethod("dockActivated", arguments: nil)
    }

    let dockIconChannel = FlutterMethodChannel(
      name: "codex_desk/dock_icon",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    dockIconChannel.setMethodCallHandler { call, result in
      if call.method == "getDockIcon" {
        result(DockIcon.selectedIdentifier)
        return
      }
      guard call.method == "setDockIcon", let arguments = call.arguments as? [String: Any], let icon = arguments["icon"] as? String else {
        result(FlutterMethodNotImplemented)
        return
      }
      switch icon {
      case "knot":
        result(DockIcon.select(named: "CodexDockIcon"))
      case "commandCloud":
        result(DockIcon.select(named: "DockIcon"))
      default:
        result(FlutterError(
          code: "unknown_dock_icon",
          message: "The requested Dock icon is not available.",
          details: nil
        ))
      }
    }

    super.awakeFromNib()
  }

  deinit {
    if let observer = appActivationObserver {
      NotificationCenter.default.removeObserver(observer)
    }
  }
}
