import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The Pin Code Manager flavor is a small helper dialog, not a workspace.
    if Bundle.main.bundleIdentifier?.hasSuffix(".pincode") == true {
      self.setContentSize(NSSize(width: 520, height: 640))
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
