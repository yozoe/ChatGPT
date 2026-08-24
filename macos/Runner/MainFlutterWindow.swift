import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
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
      DockIcon.apply()
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

    super.awakeFromNib()
  }
}
