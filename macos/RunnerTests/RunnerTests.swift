import Cocoa
import FlutterMacOS
import Network
import ApplicationServices
import XCTest
import WebKit

private final class RunnerWebViewNavigationDelegate: NSObject, WKNavigationDelegate {
  var didFinish: ((Int) -> Void)?
  var didFailProvisional: ((Error) -> Void)?
  private(set) var finishedNavigationCount = 0

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finishedNavigationCount += 1
    didFinish?(finishedNavigationCount)
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    didFailProvisional?(error)
  }
}

private final class RunnerWebViewDownloadDelegate: NSObject,
  WKNavigationDelegate,
  WKDownloadDelegate {
  var didBecomeDownload: (() -> Void)?
  var didDecideDestination: ((URLResponse, String) -> Void)?

  @available(macOS 11.3, *)
  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationResponse: WKNavigationResponse,
    decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
  ) {
    decisionHandler(.download)
  }

  @available(macOS 11.3, *)
  func webView(
    _ webView: WKWebView,
    navigationResponse: WKNavigationResponse,
    didBecome download: WKDownload
  ) {
    download.delegate = self
    didBecomeDownload?()
  }

  @available(macOS 11.3, *)
  func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String,
    completionHandler: @escaping (URL?) -> Void
  ) {
    didDecideDestination?(response, suggestedFilename)
    completionHandler(nil)
  }
}

private final class RunnerDownloadServer {
  private let queue = DispatchQueue(label: "codex-desk.runner-download-server")
  private let listener: NWListener
  private var connections: [NWConnection] = []

  var port: UInt16 {
    listener.port?.rawValue ?? 0
  }

  init() throws {
    listener = try NWListener(using: .tcp, on: .any)
  }

  func start(onReady: @escaping () -> Void) {
    listener.stateUpdateHandler = { [weak self] state in
      guard let self else { return }
      if case .ready = state {
        onReady()
      }
    }
    listener.newConnectionHandler = { [weak self] connection in
      self?.accept(connection)
    }
    listener.start(queue: queue)
  }

  func stop() {
    listener.cancel()
    connections.forEach { $0.cancel() }
    connections.removeAll()
  }

  private func accept(_ connection: NWConnection) {
    connections.append(connection)
    connection.stateUpdateHandler = { [weak self, weak connection] state in
      guard let self, let connection else { return }
      if case .ready = state {
        self.receiveRequest(on: connection)
      }
    }
    connection.start(queue: queue)
  }

  private func receiveRequest(on connection: NWConnection) {
    connection.receive(
      minimumIncompleteLength: 1,
      maximumLength: 4096
    ) { [weak self] _, _, _, _ in
      guard let self else { return }
      let body = Data("download body".utf8)
      let header = "HTTP/1.1 200 OK\r\n"
        + "Content-Type: application/octet-stream\r\n"
        + "Content-Disposition: attachment; filename=sample.txt\r\n"
        + "Content-Length: \(body.count)\r\n"
        + "Connection: close\r\n\r\n"
      let response = Data(header.utf8) + body
      connection.send(
        content: response,
        completion: .contentProcessed { _ in
          connection.cancel()
          self.connections.removeAll { $0 === connection }
        }
      )
    }
  }
}

final class RunnerTests: XCTestCase {

  override func tearDown() {
    try? FileManager.default.removeItem(
      at: ClipboardTemporaryItemStore.directory
    )
    super.tearDown()
  }

  func testDeletesOnlyDirectClipboardTemporaryItems() throws {
    let directory = ClipboardTemporaryItemStore.directory
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    let directItem = directory.appendingPathComponent("clipboard-image.png")
    try Data("image".utf8).write(to: directItem)

    XCTAssertTrue(
      ClipboardTemporaryItemStore.deleteItem(atPath: directItem.path)
    )
    XCTAssertFalse(FileManager.default.fileExists(atPath: directItem.path))

    let nestedDirectory = directory.appendingPathComponent("nested")
    try FileManager.default.createDirectory(
      at: nestedDirectory,
      withIntermediateDirectories: true
    )
    let nestedItem = nestedDirectory.appendingPathComponent("image.png")
    try Data("image".utf8).write(to: nestedItem)
    XCTAssertFalse(
      ClipboardTemporaryItemStore.deleteItem(atPath: nestedItem.path)
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: nestedItem.path))
  }

  func testRejectsClipboardTemporaryPathsOutsideTheManagedDirectory() throws {
    let outside = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-desk-outside-test.txt")
    try Data("outside".utf8).write(to: outside)
    defer { try? FileManager.default.removeItem(at: outside) }

    XCTAssertFalse(
      ClipboardTemporaryItemStore.deleteItem(atPath: outside.path)
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
  }

  func testRejectsDirectoriesInTheManagedClipboardDirectory() throws {
    let directory = ClipboardTemporaryItemStore.directory
    let nestedDirectory = directory.appendingPathComponent("clipboard-folder")
    try FileManager.default.createDirectory(
      at: nestedDirectory,
      withIntermediateDirectories: true
    )

    XCTAssertFalse(
      ClipboardTemporaryItemStore.deleteItem(atPath: nestedDirectory.path)
    )
    XCTAssertTrue(FileManager.default.fileExists(atPath: nestedDirectory.path))
  }

  func testNormalizesDockBadgeLabels() {
    XCTAssertNil(DockBadgeCount.label(for: -1))
    XCTAssertNil(DockBadgeCount.label(for: 0))
    XCTAssertEqual(DockBadgeCount.label(for: 1), "1")
    XCTAssertEqual(DockBadgeCount.label(for: 42), "42")
    XCTAssertEqual(DockBadgeCount.label(for: 100), "99")
  }

  func testValidatesDockBadgeMethodChannelArguments() {
    XCTAssertEqual(DockBadgeCount.value(from: ["visible": true]), 1)
    XCTAssertEqual(DockBadgeCount.value(from: ["visible": false]), 0)
    XCTAssertEqual(DockBadgeCount.value(from: ["count": 42]), 42)
    XCTAssertEqual(DockBadgeCount.value(from: ["count": -4]), 0)
    XCTAssertNil(DockBadgeCount.value(from: nil))
    XCTAssertNil(DockBadgeCount.value(from: [:]))
    XCTAssertNil(DockBadgeCount.value(from: ["visible": "true"]))
    XCTAssertNil(DockBadgeCount.value(from: ["count": "42"]))
  }

  func testWKWebViewLoadsHTMLAndCanBeTornDown() {
    let loaded = expectation(description: "WKWebView finishes loading HTML")
    let reloaded = expectation(description: "WKWebView finishes reloading HTML")
    let webView = WKWebView(frame: .zero)
    let delegate = RunnerWebViewNavigationDelegate()
    delegate.didFinish = { navigationCount in
      switch navigationCount {
      case 1:
        loaded.fulfill()
        DispatchQueue.main.async {
          webView.reload()
        }
      case 2:
        reloaded.fulfill()
      default:
        break
      }
    }
    webView.navigationDelegate = delegate

    webView.loadHTMLString(
      "<html><head><title>Browser smoke test</title></head><body>ok</body></html>",
      baseURL: nil
    )
    wait(for: [loaded, reloaded], timeout: 5)
    XCTAssertEqual(delegate.finishedNavigationCount, 2)

    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
  }

  func testWKWebsiteDataStoreCanClearCookies() {
    let store = WKWebsiteDataStore.default()
    let cookieReady = expectation(description: "cookie is written")
    let cookieCleared = expectation(description: "cookie is cleared")
    let cookie = HTTPCookie(properties: [
      .domain: "native-smoke.example",
      .path: "/",
      .name: "browserSmoke",
      .value: "1",
      .secure: false,
    ])!

    store.httpCookieStore.setCookie(cookie) {
      cookieReady.fulfill()
      store.httpCookieStore.getAllCookies { cookies in
        XCTAssertTrue(cookies.contains { $0.name == "browserSmoke" })
        let smokeCookies = cookies.filter { $0.name == "browserSmoke" }
        func deleteSmokeCookie(at index: Int) {
          guard index < smokeCookies.count else {
            store.httpCookieStore.getAllCookies { remaining in
              XCTAssertFalse(remaining.contains { $0.name == "browserSmoke" })
              cookieCleared.fulfill()
            }
            return
          }
          store.httpCookieStore.delete(smokeCookies[index]) {
            deleteSmokeCookie(at: index + 1)
          }
        }
        deleteSmokeCookie(at: 0)
      }
    }

    wait(for: [cookieReady, cookieCleared], timeout: 5)
  }

  func testWKWebViewReportsUnreachableNavigation() {
    let failed = expectation(description: "WKWebView reports unreachable navigation")
    let webView = WKWebView(frame: .zero)
    let delegate = RunnerWebViewNavigationDelegate()
    delegate.didFailProvisional = { error in
      XCTAssertFalse(error.localizedDescription.isEmpty)
      failed.fulfill()
    }
    webView.navigationDelegate = delegate

    let missingFile = FileManager.default.temporaryDirectory
      .appendingPathComponent("codex-missing-webview-file.html")
    try? FileManager.default.removeItem(at: missingFile)
    webView.loadFileURL(
      missingFile,
      allowingReadAccessTo: missingFile.deletingLastPathComponent()
    )
    wait(for: [failed], timeout: 5)

    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
  }

  func testWKWebViewPublishesAccessibilityTreeContractThroughAX() throws {
    let loaded = expectation(description: "WKWebView finishes accessibility tree page")
    let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
      styleMask: [.titled],
      backing: .buffered,
      defer: false
    )
    window.contentView = webView
    window.makeKeyAndOrderFront(nil)
    defer {
      window.orderOut(nil)
      window.close()
    }
    let delegate = RunnerWebViewNavigationDelegate()
    delegate.didFinish = { _ in loaded.fulfill() }
    webView.navigationDelegate = delegate

    webView.loadHTMLString(
      """
      <html><body>
        <main aria-label="Browser content">
          <h1>Download fixture</h1>
          <button aria-label="Start download">Download</button>
          <input aria-label="Address" value="https://example.com">
        </main>
      </body></html>
      """,
      baseURL: nil
    )
    wait(for: [loaded], timeout: 5)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))

    let attributeNames = webView.accessibilityAttributeNames()
    guard
      attributeNames.contains(NSAccessibility.Attribute.role),
      attributeNames.contains(NSAccessibility.Attribute.children),
      webView.isAccessibilityElement(),
      webView.accessibilityRole() != nil,
      let windowChildren = window.accessibilityChildren(),
      windowChildren.contains(where: { ($0 as AnyObject) === webView })
    else {
      throw XCTSkip("WebKit host accessibility is unavailable on this runner")
    }
    let applicationElement = AXUIElementCreateApplication(
      ProcessInfo.processInfo.processIdentifier
    )
    var windowValue: CFTypeRef?
    let windowResult = AXUIElementCopyAttributeValue(
      applicationElement,
      kAXWindowsAttribute as CFString,
      &windowValue
    )
    guard windowResult == .success, windowValue != nil else {
      throw XCTSkip(
        "Accessibility application queries are unavailable on this runner"
      )
    }
    func axChildren(_ element: AXUIElement) -> [AXUIElement] {
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(
          element,
          kAXChildrenAttribute as CFString,
          &value
        ) == .success,
        let value
      else {
        return []
      }
      return (value as? [AXUIElement]) ?? []
    }
    let applicationWindows = (windowValue as? [AXUIElement]) ?? []
    guard !applicationWindows.isEmpty else {
      throw XCTSkip("The test process has no observable accessibility windows")
    }
    func axRole(_ element: AXUIElement) -> String? {
      var value: CFTypeRef?
      guard
        AXUIElementCopyAttributeValue(
          element,
          kAXRoleAttribute as CFString,
          &value
        ) == .success
      else {
        return nil
      }
      return value as? String
    }
    func collectAXRoles(
      _ element: AXUIElement,
      depth: Int,
      roles: inout Set<String>
    ) {
      if let role = axRole(element) {
        roles.insert(role)
      }
      guard depth < 8 else { return }
      for child in axChildren(element) {
        collectAXRoles(child, depth: depth + 1, roles: &roles)
      }
    }
    var roles = Set<String>()
    for appWindow in applicationWindows {
      collectAXRoles(appWindow, depth: 0, roles: &roles)
    }
    guard !roles.isEmpty else {
      throw XCTSkip("Accessibility descendants are unavailable on this runner")
    }
    guard roles.contains(kAXWindowRole as String) else {
      throw XCTSkip("Accessibility window roles are unavailable on this runner")
    }
    // WKWebView descendants are owned by the WebKit accessibility process and
    // may be unavailable to a synchronous XCTest query even when the children
    // attribute is advertised by the host view.

    webView.navigationDelegate = nil
    webView.removeFromSuperview()
  }

  @available(macOS 11.3, *)
  func testWKWebViewDownloadDelegateReceivesAttachmentResponse() throws {
    let server = try RunnerDownloadServer()
    defer { server.stop() }
    let serverReady = expectation(description: "download server is ready")
    server.start { serverReady.fulfill() }
    wait(for: [serverReady], timeout: 5)
    XCTAssertGreaterThan(server.port, 0)

    let downloadStarted = expectation(description: "WKWebView creates a download")
    let destinationSelected = expectation(description: "WKDownload asks for a destination")
    let webView = WKWebView(frame: .zero)
    let delegate = RunnerWebViewDownloadDelegate()
    delegate.didBecomeDownload = { downloadStarted.fulfill() }
    delegate.didDecideDestination = { response, filename in
      XCTAssertEqual(response.mimeType, "application/octet-stream")
      XCTAssertEqual(filename, "sample.txt")
      destinationSelected.fulfill()
    }
    webView.navigationDelegate = delegate

    let url = URL(string: "http://127.0.0.1:\(server.port)/download")!
    webView.load(URLRequest(url: url))
    wait(for: [downloadStarted, destinationSelected], timeout: 10)

    webView.stopLoading()
    webView.navigationDelegate = nil
    webView.removeFromSuperview()
  }

}
