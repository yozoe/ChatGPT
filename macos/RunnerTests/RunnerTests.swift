import Cocoa
import FlutterMacOS
import XCTest

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

}
