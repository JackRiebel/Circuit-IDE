import Cocoa
import FlutterMacOS
import Network
import WebKit
import XCTest

final class RunnerTests: XCTestCase {
  func testCircuitCodeHostLaunchesFlutterWindowAndEngine() throws {
    XCTAssertEqual(Bundle.main.bundleIdentifier, "com.circuitide.app")
    XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "CircuitCode")

    let window = try waitForFlutterWindow()
    guard let controller = window.contentViewController as? FlutterViewController else {
      return XCTFail("CircuitCode launched without a Flutter view controller")
    }

    XCTAssertFalse(window.isReleasedWhenClosed)
    XCTAssertEqual(window.frameAutosaveName, "CircuitCodeMainWindowFrame")
    XCTAssertNotNil(controller.engine.binaryMessenger)
  }

  func testBrowserSnapshotCapturesOnlyTheVisibleLocalWebKitFixture() throws {
    let window = try waitForFlutterWindow()
    let server = try LocalBrowserFixtureServer()
    let pageLoaded = expectation(description: "Local browser fixture loads")
    let selectionCaptured = expectation(description: "Browser selection is available")
    let snapshotCaptured = expectation(description: "Visible local page snapshot is PNG")
    let navigationMismatch = expectation(description: "Mismatched page capture is refused")

    let webView = WKWebView(frame: window.contentView?.bounds ?? .zero)
    webView.autoresizingMask = [.width, .height]
    let navigationDelegate = BrowserFixtureNavigationDelegate {
      pageLoaded.fulfill()
    }
    webView.navigationDelegate = navigationDelegate
    window.contentView?.addSubview(webView)
    addTeardownBlock {
      webView.removeFromSuperview()
      server.stop()
    }

    webView.load(URLRequest(url: server.fixtureURL))
    wait(for: [pageLoaded], timeout: 8)

    webView.evaluateJavaScript("""
      (() => {
        const fact = document.querySelector('#browser-fixture-fact');
        const range = document.createRange();
        range.selectNodeContents(fact);
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(range);
        return JSON.stringify({
          title: document.title,
          selectedText: selection.toString(),
          preview: document.body.innerText,
        });
      })();
      """) { result, error in
        XCTAssertNil(error)
        guard
          let payload = result as? String,
          let data = payload.data(using: .utf8),
          let observation = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else {
          return XCTFail("The local fixture did not expose a browser observation")
        }
        XCTAssertEqual(observation["title"], "CircuitCode browser fixture")
        XCTAssertEqual(observation["selectedText"], "Controlled selected browser fact.")
        XCTAssertTrue(observation["preview"]?.contains("Browser-only preview text.") == true)
        selectionCaptured.fulfill()
      }

    var mismatched = URLComponents(url: server.fixtureURL, resolvingAgainstBaseURL: false)!
    mismatched.path = "/different-page"
    XCTAssertNotEqual(webView.url, mismatched.url)
    navigationMismatch.fulfill()

    webView.takeSnapshot(with: nil) { image, error in
      XCTAssertNil(error)
      guard
        let image,
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else {
        return XCTFail("The visible local browser fixture did not produce a PNG snapshot")
      }
      XCTAssertLessThanOrEqual(png.count, 4 * 1024 * 1024)
      XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
      snapshotCaptured.fulfill()
    }

    wait(for: [selectionCaptured, snapshotCaptured, navigationMismatch], timeout: 10)
  }

  private func waitForFlutterWindow() throws -> NSWindow {
    let ready = expectation(description: "CircuitCode creates a Flutter window")
    var matchingWindow: NSWindow?
    let deadline = Date().addingTimeInterval(8)

    func poll() {
      if let window = NSApp.windows.first(where: {
        $0.contentViewController is FlutterViewController
      }) {
        matchingWindow = window
        ready.fulfill()
      } else if Date() < deadline {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
      }
    }

    DispatchQueue.main.async(execute: poll)
    wait(for: [ready], timeout: 8.5)
    return try XCTUnwrap(matchingWindow)
  }
}

private final class BrowserFixtureNavigationDelegate: NSObject, WKNavigationDelegate {
  private let onPageFinished: () -> Void
  private var didFinish = false

  init(onPageFinished: @escaping () -> Void) {
    self.onPageFinished = onPageFinished
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    guard !didFinish else { return }
    didFinish = true
    onPageFinished()
  }
}

private final class LocalBrowserFixtureServer {
  private let listener: NWListener
  private let queue = DispatchQueue(label: "CircuitCode.browser.fixture")
  private var port: NWEndpoint.Port?

  init() throws {
    listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { [weak self] connection in
      self?.serve(connection)
    }
    let ready = DispatchSemaphore(value: 0)
    listener.stateUpdateHandler = { [weak self] state in
      if case .ready = state {
        self?.port = self?.listener.port
        ready.signal()
      }
    }
    listener.start(queue: queue)
    guard ready.wait(timeout: .now() + 5) == .success, port != nil else {
      listener.cancel()
      throw NSError(
        domain: "CircuitCodeBrowserFixture",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "The local browser fixture server did not start."],
      )
    }
  }

  var fixtureURL: URL {
    URL(string: "http://127.0.0.1:\(port!.rawValue)/browser-fixture")!
  }

  func stop() {
    listener.cancel()
  }

  private func serve(_ connection: NWConnection) {
    connection.start(queue: queue)
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { _, _, _, _ in
      let body = """
        <!doctype html>
        <html><head><title>CircuitCode browser fixture</title></head>
        <body><main><p id="browser-fixture-fact">Controlled selected browser fact.</p>
        <p>Browser-only preview text.</p></main></body></html>
        """
      let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
      connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
        connection.cancel()
      })
    }
  }
}
