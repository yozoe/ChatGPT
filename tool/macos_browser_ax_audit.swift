import AppKit
import ApplicationServices
import Foundation

struct AuditOptions {
  var bundleIdentifier: String?
  var processIdentifier: pid_t?
  var timeout: TimeInterval = 8
  var maxDepth = 12
}

struct AXNodeSnapshot {
  let role: String?
  let title: String?
  let description: String?
  let value: String?
  let depth: Int
  let childCount: Int
}

enum AuditError: Error, CustomStringConvertible {
  case usage(String)
  case accessibilityTrustRequired
  case applicationNotFound(String)
  case noWindows
  case webAreaNotFound

  var description: String {
    switch self {
    case .usage(let message): return message
    case .accessibilityTrustRequired:
      return "Accessibility permission is required. Enable the audit host in System Settings > Privacy & Security > Accessibility."
    case .applicationNotFound(let identifier):
      return "No running application matched \(identifier). Launch the app and keep its browser workspace visible."
    case .noWindows:
      return "The target application has no accessibility windows."
    case .webAreaNotFound:
      return "No AXWebArea descendant was observed before the timeout."
    }
  }
}

func parseOptions(_ arguments: ArraySlice<String>) throws -> AuditOptions {
  var options = AuditOptions()
  var iterator = arguments.makeIterator()
  while let argument = iterator.next() {
    switch argument {
    case "--bundle-id":
      guard let value = iterator.next(), !value.isEmpty else {
        throw AuditError.usage("--bundle-id requires a value")
      }
      options.bundleIdentifier = value
    case "--pid":
      guard let value = iterator.next(), let pid = pid_t(value) else {
        throw AuditError.usage("--pid requires a numeric process identifier")
      }
      options.processIdentifier = pid
    case "--timeout":
      guard let value = iterator.next(), let timeout = TimeInterval(value), timeout > 0 else {
        throw AuditError.usage("--timeout requires a positive number of seconds")
      }
      options.timeout = timeout
    case "--max-depth":
      guard let value = iterator.next(), let depth = Int(value), depth > 0 else {
        throw AuditError.usage("--max-depth requires a positive integer")
      }
      options.maxDepth = depth
    case "--help", "-h":
      printUsageAndExit()
    default:
      throw AuditError.usage("Unknown argument: \(argument)")
    }
  }
  guard options.bundleIdentifier != nil || options.processIdentifier != nil else {
    throw AuditError.usage("Provide --bundle-id or --pid")
  }
  return options
}

func printUsageAndExit() -> Never {
  print(
    """
    Usage: macos_browser_ax_audit --bundle-id <id> [--timeout <seconds>] [--max-depth <depth>]
           macos_browser_ax_audit --pid <pid> [--timeout <seconds>] [--max-depth <depth>]

    The audit host must have macOS Accessibility permission. It waits for the target
    application's AXWebArea descendant and prints the observed role tree.
    """
  )
  exit(EXIT_SUCCESS)
}

func runningApplication(options: AuditOptions) throws -> NSRunningApplication {
  if let pid = options.processIdentifier,
     let application = NSRunningApplication(processIdentifier: pid) {
    return application
  }
  if let identifier = options.bundleIdentifier,
     let application = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
      .first(where: { !$0.isTerminated }) {
    return application
  }
  throw AuditError.applicationNotFound(options.bundleIdentifier.map { "bundle \($0)" } ?? "pid \(options.processIdentifier ?? 0)")
}

func copyAttribute(_ element: AXUIElement, _ attribute: CFString) -> Any? {
  var value: CFTypeRef?
  guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
    return nil
  }
  return value
}

func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
  copyAttribute(element, attribute) as? String
}

func children(of element: AXUIElement) -> [AXUIElement] {
  var result = [AXUIElement]()
  let attributes = [
    kAXChildrenAttribute,
    kAXContentsAttribute,
    kAXVisibleChildrenAttribute,
    kAXRowsAttribute,
    kAXTabsAttribute,
  ] as [CFString]
  for attribute in attributes {
    if let values = copyAttribute(element, attribute) as? [AXUIElement] {
      result.append(contentsOf: values)
    }
  }
  var seen = Set<String>()
  return result.filter { element in
    let key = String(describing: Unmanaged.passUnretained(element).toOpaque())
    return seen.insert(key).inserted
  }
}

func snapshotTree(from element: AXUIElement, depth: Int, maxDepth: Int) -> [AXNodeSnapshot] {
  guard depth <= maxDepth else { return [] }
  let snapshot = AXNodeSnapshot(
    role: stringAttribute(element, kAXRoleAttribute as CFString),
    title: stringAttribute(element, kAXTitleAttribute as CFString),
    description: stringAttribute(element, kAXDescriptionAttribute as CFString),
    value: stringAttribute(element, kAXValueAttribute as CFString),
    depth: depth,
    childCount: children(of: element).count
  )
  return [snapshot] + children(of: element).flatMap {
    snapshotTree(from: $0, depth: depth + 1, maxDepth: maxDepth)
  }
}

func printTree(_ snapshots: [AXNodeSnapshot]) {
  for snapshot in snapshots {
    let label = snapshot.title ?? snapshot.description ?? snapshot.value ?? ""
    let suffix = label.isEmpty ? "" : " \"\(label.prefix(120))\""
    print(
      String(repeating: "  ", count: snapshot.depth)
        + (snapshot.role ?? "<unknown>")
        + " children=\(snapshot.childCount)"
        + suffix
    )
  }
}

func audit(options: AuditOptions) throws {
  guard AXIsProcessTrusted() else {
    throw AuditError.accessibilityTrustRequired
  }
  let application = try runningApplication(options: options)
  let target = AXUIElementCreateApplication(application.processIdentifier)
  let deadline = Date().addingTimeInterval(options.timeout)
  var lastWindowCount = 0
  var observedSnapshots: [AXNodeSnapshot] = []

  repeat {
    let windows = (copyAttribute(target, kAXWindowsAttribute as CFString) as? [AXUIElement]) ?? []
    lastWindowCount = windows.count
    observedSnapshots = windows.flatMap {
      snapshotTree(from: $0, depth: 0, maxDepth: options.maxDepth)
    }
    let roles = Set(observedSnapshots.compactMap(\.role))
    if roles.contains("AXWebArea") || roles.contains("AXLink") || roles.contains("AXHeading") {
      print("Accessibility audit passed for pid \(application.processIdentifier).")
      printTree(observedSnapshots)
      return
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.1))
  } while Date() < deadline

  if lastWindowCount == 0 {
    throw AuditError.noWindows
  }
  printTree(observedSnapshots)
  throw AuditError.webAreaNotFound
}

do {
  let options = try parseOptions(CommandLine.arguments.dropFirst())
  try audit(options: options)
} catch let error as AuditError {
  fputs("Accessibility audit failed: \(error.description)\n", stderr)
  exit(EXIT_FAILURE)
} catch {
  fputs("Accessibility audit failed: \(error)\n", stderr)
  exit(EXIT_FAILURE)
}
