import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private static let frameAutosaveName = "CodexDeskMainWindow"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.setFrameAutosaveName(Self.frameAutosaveName)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
