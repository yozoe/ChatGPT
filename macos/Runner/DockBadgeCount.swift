import Foundation

enum DockBadgeCount {
  /// Validates a Flutter `setDockBadge` payload and returns its requested
  /// count. Older callers that send only `visible` remain supported.
  static func value(from arguments: Any?) -> Int? {
    guard let values = arguments as? [String: Any] else { return nil }
    if let rawCount = values["count"] {
      guard let count = rawCount as? Int else { return nil }
      return max(0, count)
    }
    guard let visible = values["visible"] as? Bool else { return nil }
    return visible ? 1 : 0
  }

  /// Returns the text rendered for a requested completion count.
  static func label(for count: Int) -> String? {
    let normalized = max(0, count)
    guard normalized > 0 else { return nil }
    return "\(min(normalized, 99))"
  }
}
