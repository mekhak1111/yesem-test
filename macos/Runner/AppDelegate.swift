import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Links registered in Info.plist (CFBundleURLTypes, scheme per flavor from
  // YESEM_URL_SCHEME) arrive here, on a cold start as well as while running.
  override func application(_ application: NSApplication, open urls: [URL]) {
    LinkChannel.shared.deliver(urls)
  }
}

/// Hands links to Dart on the `yesem/links` channel. Links that arrive before
/// Dart has asked for them (cold start) are kept until it calls `takePending`.
final class LinkChannel {
  static let shared = LinkChannel()

  private var channel: FlutterMethodChannel?
  private var pending: [String] = []
  private var dartListening = false

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "yesem/links", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "takePending" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.dartListening = true
      result(self.pending)
      self.pending.removeAll()
    }
    self.channel = channel
  }

  func deliver(_ urls: [URL]) {
    let links = urls.map { $0.absoluteString }
    if dartListening, let channel = channel {
      links.forEach { channel.invokeMethod("link", arguments: $0) }
    } else {
      pending.append(contentsOf: links)
    }
  }
}
