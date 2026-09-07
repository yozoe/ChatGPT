import Foundation

enum ClipboardTemporaryItemStore {
  static let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexDeskClipboard", isDirectory: true)

  static func deleteItem(atPath path: String) -> Bool {
    let target = URL(fileURLWithPath: path).standardizedFileURL
    let managedDirectory = directory.standardizedFileURL
    guard target.deletingLastPathComponent() == managedDirectory else {
      return false
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(
      atPath: target.path,
      isDirectory: &isDirectory
    ) else {
      return true
    }
    guard !isDirectory.boolValue else { return false }
    do {
      try FileManager.default.removeItem(at: target)
      return true
    } catch {
      return false
    }
  }
}
