import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow, NSDraggingDestination {
  private static let frameAutosaveName = "CircuitCodeMainWindowFrame"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // AppKit owns persistence of the user's size and screen placement. Keep a
    // stable, product-specific name so a restored frame cannot collide with a
    // future auxiliary window, and fall back to a centered first launch.
    let restoredFrame = self.setFrameUsingName(Self.frameAutosaveName)
    self.setFrameAutosaveName(Self.frameAutosaveName)
    if !restoredFrame {
      self.center()
    }

    // App-owned launch and credential channels must be available before Dart
    // starts its first method-channel request. Plugin registration can take
    // longer than that first request on a cold packaged launch.
    (NSApp.delegate as? AppDelegate)?.attachPackagedSmokeController(
      flutterViewController
    )
    RegisterGeneratedPlugins(registry: flutterViewController)
    registerForDraggedTypes([.fileURL])

    super.awakeFromNib()
  }

  func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
    fileURLs(from: sender).isEmpty ? [] : .copy
  }

  func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
    !fileURLs(from: sender).isEmpty
  }

  func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
    let urls = fileURLs(from: sender)
    guard !urls.isEmpty else { return false }
    (NSApp.delegate as? AppDelegate)?.openUserSelectedURLs(urls)
    return true
  }

  private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [
      .urlReadingFileURLsOnly: true,
    ]
    return sender.draggingPasteboard
      .readObjects(forClasses: [NSURL.self], options: options)?
      .compactMap { $0 as? URL } ?? []
  }
}
