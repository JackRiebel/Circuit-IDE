import Cocoa
import FlutterMacOS
import Security
import Sparkle
import Vision
import WebKit

@main
class AppDelegate: FlutterAppDelegate, SPUUpdaterDelegate {
  private enum CircuitUpdateChannel: String {
    case stable
    case beta
  }

  private static let updateChannelPreference = "CircuitUpdateChannel"
  private var updaterController: SPUStandardUpdaterController?
  private var updateConfigurationError: String?
  private var updateMutationActive = false
  private var deferredInstallHandler: (() -> Void)?
  private var fileOpenChannel: FlutterMethodChannel?
  private var workspaceAccessChannel: FlutterMethodChannel?
  private var secureCredentialsChannel: FlutterMethodChannel?
  private var packagedSmokeChannel: FlutterMethodChannel?
  private weak var packagedSmokeController: FlutterViewController?
  private var pendingFileOpenRequests: [[String: Any]] = []
  private var fileOpenDeliveryReady = false
  private var activeWorkspaceScopes: [String: URL] = [:]
  private let packagedSmokeLaunchArgument = "--circuitcode-packaged-smoke"
  private let packagedPrivacyCrashAuditLaunchArgument = "--circuitcode-packaged-privacy-crash"
  private let packagedReleasePerformanceProbeLaunchArgument = "--circuitcode-packaged-performance-probe"

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    if !flag {
      for window in sender.windows {
        window.makeKeyAndOrderFront(self)
      }
    }
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func application(_ application: NSApplication, open urls: [URL]) {
    deliverFileOpenURLs(urls)
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    // ── Disable ALL text checking and IME composition marks ──

    // 1. UserDefaults — covers system-level checks
    let defaults = UserDefaults.standard
    let keys = [
      "ContinuousSpellCheckingEnabled",
      "GrammarCheckingEnabled",
      "AutomaticSpellingCorrectionEnabled",
      "NSAutomaticSpellingCorrectionEnabled",
      "NSAutomaticTextCompletionEnabled",
      "WebContinuousSpellCheckingEnabled",
      "NSAutomaticQuoteSubstitutionEnabled",
      "NSAutomaticDashSubstitutionEnabled",
      "NSAutomaticTextReplacementEnabled",
      "NSAutomaticCapitalizationEnabled",
      "NSAutomaticPeriodSubstitutionEnabled",
      "NSAutomaticInlinePredictionEnabled",
    ]
    for key in keys {
      defaults.set(false, forKey: key)
    }

    // 2. Disable the global spell checker
    NSSpellChecker.shared.automaticallyIdentifiesLanguages = false

    // 3. Swizzle NSTextView (base class) — spell check + IME marks
    swizzleSpellCheckingOnClass(NSTextView.self)
    swizzleIMEMarkedText(NSTextView.self)

    // 4. Swizzle FlutterTextInputPlugin — the ACTUAL class Flutter uses.
    //    It's a subclass of NSTextView and may override these properties.
    if let flutterClass = NSClassFromString("FlutterTextInputPlugin") as? NSTextView.Type {
      swizzleSpellCheckingOnClass(flutterClass)
      swizzleIMEMarkedText(flutterClass)
    }
    // Also try alternate class name
    if let flutterClass2 = NSClassFromString("FlutterTextInputSemanticsObject") as? NSView.Type {
      disableSpellCheckOnAnyClass(flutterClass2)
    }

    // 5. Observe new windows and disable on all text views
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowDidBecomeKey(_:)),
      name: NSWindow.didBecomeKeyNotification,
      object: nil
    )

    // Flutter starts the Dart entrypoint from its superclass launch path.
    // Register every app-owned channel first so an early startup request cannot
    // race a missing native handler (notably the packaged lifecycle smoke and
    // the queued Finder-open boundary).
    configureLocalOcrChannel()
    configureBrowserSnapshotChannel()
    configureFileRevealChannel()
    configureFileOpenChannel()
    configureWorkspaceAccessChannel()
    configureSecureCredentialsChannel()
    configurePackagedSmokeChannel()
    configureUpdateChannel()
    super.applicationDidFinishLaunching(notification)
    // Release startup can finish creating the Flutter binary messenger after
    // the first registration pass. Retain the first channel when available,
    // but make one post-super pass so standard Finder/Open delivery is never
    // missing from a valid packaged host.
    configureFileOpenChannel()
    configureWorkspaceAccessChannel()
    configureSecureCredentialsChannel()
    // The same host initialization edge applies to the two private packaged
    // smoke signals. Retrying registration here guarantees that Dart can
    // distinguish the lifecycle and crash audits from a normal app launch.
    configurePackagedSmokeChannel()
  }

  // MARK: - Secure Circuit credentials

  /// Stores Circuit credential values in the user's login Keychain. This
  /// deliberately uses the standard macOS Keychain instead of the Data
  /// Protection Keychain so ad-hoc development builds work before a signing
  /// team and its entitlements are configured. No credential is written to
  /// the filesystem, logged, or returned except to this local Flutter process.
  private static let credentialKeychainService = "com.circuitide.app.credentials"
  private static let maximumCredentialKeyLength = 128
  private static let maximumCredentialValueLength = 32 * 1024

  private func configureSecureCredentialsChannel() {
    if secureCredentialsChannel != nil {
      return
    }
    guard let controller = packagedSmokeController ??
        (mainFlutterWindow?.contentViewController as? FlutterViewController) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/secure_credentials",
      binaryMessenger: controller.engine.binaryMessenger
    )
    secureCredentialsChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Secure credential storage is unavailable.", details: nil))
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let key = self.validCredentialKey(arguments["key"]) else {
        result(FlutterError(code: "invalid_credential", message: "Invalid credential request.", details: nil))
        return
      }
      switch call.method {
      case "read":
        self.readCredential(key: key, result: result)
      case "write":
        guard let value = arguments["value"] as? String,
              value.utf8.count <= Self.maximumCredentialValueLength else {
          result(FlutterError(code: "invalid_credential", message: "Invalid credential request.", details: nil))
          return
        }
        self.writeCredential(key: key, value: value, result: result)
      case "delete":
        self.deleteCredential(key: key, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func validCredentialKey(_ rawKey: Any?) -> String? {
    guard let key = rawKey as? String,
          !key.isEmpty,
          key.utf8.count <= Self.maximumCredentialKeyLength,
          key.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil else {
      return nil
    }
    return key
  }

  private func credentialQuery(key: String) -> [CFString: Any] {
    return [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: Self.credentialKeychainService,
      kSecAttrAccount: key,
    ]
  }

  private func readCredential(key: String, result: @escaping FlutterResult) {
    var query = credentialQuery(key: key)
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    switch status {
    case errSecSuccess:
      guard let data = item as? Data,
            let value = String(data: data, encoding: .utf8) else {
        keychainFailure(result)
        return
      }
      result(value)
    case errSecItemNotFound:
      result(nil)
    default:
      keychainFailure(result)
    }
  }

  private func writeCredential(key: String, value: String, result: @escaping FlutterResult) {
    let query = credentialQuery(key: key)
    let valueData = Data(value.utf8)
    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData: valueData] as CFDictionary
    )
    if updateStatus == errSecSuccess {
      result(nil)
      return
    }
    guard updateStatus == errSecItemNotFound else {
      keychainFailure(result)
      return
    }
    var addQuery = query
    addQuery[kSecValueData] = valueData
    addQuery[kSecAttrLabel] = "CircuitCode credential"
    if SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess {
      result(nil)
    } else {
      keychainFailure(result)
    }
  }

  private func deleteCredential(key: String, result: @escaping FlutterResult) {
    let status = SecItemDelete(credentialQuery(key: key) as CFDictionary)
    if status == errSecSuccess || status == errSecItemNotFound {
      result(nil)
    } else {
      keychainFailure(result)
    }
  }

  private func keychainFailure(_ result: @escaping FlutterResult) {
    // Never expose OSStatus values: they can reveal local Keychain state to
    // the Dart layer and are not actionable for an end user.
    result(FlutterError(code: "keychain_unavailable", message: "Secure credential storage is unavailable.", details: nil))
  }

  // MARK: - Packaged lifecycle smoke

  /// The release smoke harness starts the application through LaunchServices,
  /// just like a user opening the app. Flutter does not retain `open --args`
  /// values in `Platform.executableArguments`, so this local host channel is
  /// the bounded, read-only bridge for the two smoke-only launch signals.
  private func configurePackagedSmokeChannel() {
    if packagedSmokeChannel != nil {
      return
    }
    guard let controller = packagedSmokeController ??
        (mainFlutterWindow?.contentViewController as? FlutterViewController) else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/packaged_smoke",
      binaryMessenger: controller.engine.binaryMessenger
    )
    packagedSmokeChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Packaged smoke bridge is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "isRequested":
        result(self.isPackagedSmokeRequested)
      case "isPrivacyCrashRequested":
        result(self.isPackagedPrivacyCrashAuditRequested)
      case "isPerformanceProbeRequested":
        result(self.isPackagedReleasePerformanceProbeRequested)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// MainFlutterWindow creates the production Flutter engine before AppKit's
  /// launch callback can be relied on. Binding this one private smoke bridge
  /// there keeps `open --args` test routing deterministic without exposing a
  /// user, agent, or tool surface.
  func attachPackagedSmokeController(_ controller: FlutterViewController) {
    packagedSmokeController = controller
    // MainFlutterWindow creates the Flutter controller before AppKit's launch
    // callback is guaranteed to expose mainFlutterWindow. Bind the credential
    // store here as well, so Settings cannot race a missing native handler on
    // a fresh packaged launch.
    configureSecureCredentialsChannel()
    configurePackagedSmokeChannel()
  }

  private var isPackagedSmokeRequested: Bool {
    CommandLine.arguments.contains(packagedSmokeLaunchArgument)
  }

  private var isPackagedPrivacyCrashAuditRequested: Bool {
    CommandLine.arguments.contains(packagedPrivacyCrashAuditLaunchArgument)
  }

  private var isPackagedReleasePerformanceProbeRequested: Bool {
    CommandLine.arguments.contains(packagedReleasePerformanceProbeLaunchArgument)
  }

  // MARK: - Standard macOS file open behavior

  /// Handles File > Open and Finder/Dock document-open events. Only existing
  /// local files and folders are delivered. The channel is local UI plumbing,
  /// never an agent, browser, or MCP tool surface.
  @IBAction func openDocument(_ sender: Any?) {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.resolvesAliases = true
    panel.prompt = "Open"
    if let window = mainFlutterWindow {
      panel.beginSheetModal(for: window) { [weak self] response in
        guard response == .OK, let url = panel.url else { return }
        self?.deliverFileOpenURLs([url])
      }
    } else if panel.runModal() == .OK, let url = panel.url {
      deliverFileOpenURLs([url])
    }
  }

  private func configureFileOpenChannel() {
    if fileOpenChannel != nil {
      return
    }
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/file_open",
      binaryMessenger: controller.engine.binaryMessenger
    )
    fileOpenChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "File open service is unavailable.", details: nil))
        return
      }
      guard call.method == "drainOpenRequests" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.fileOpenDeliveryReady = true
      let queued = self.pendingFileOpenRequests
      self.pendingFileOpenRequests.removeAll()
      result(queued)
    }
  }

  private func deliverFileOpenURLs(_ urls: [URL]) {
    let requests = urls.compactMap(fileOpenRequest)
    guard !requests.isEmpty else { return }
    NSApp.activate(ignoringOtherApps: true)
    mainFlutterWindow?.makeKeyAndOrderFront(nil)
    guard fileOpenDeliveryReady, let channel = fileOpenChannel else {
      pendingFileOpenRequests.append(contentsOf: requests)
      return
    }
    for request in requests {
      channel.invokeMethod("open", arguments: request)
    }
  }

  /// Shared by the standard Open command, Finder/Dock events, and the
  /// MainFlutterWindow drag destination. Keeping all three routes here means
  /// they receive identical existing-local-path validation and launch queue
  /// behavior before Dart binds a workspace.
  func openUserSelectedURLs(_ urls: [URL]) {
    deliverFileOpenURLs(urls)
  }

  private func fileOpenRequest(for url: URL) -> [String: Any]? {
    guard url.isFileURL else { return nil }
    let resolved = url.resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else {
      return nil
    }
    return [
      "path": resolved.path,
      "isDirectory": isDirectory.boolValue,
    ]
  }

  // MARK: - Security-scoped workspace access

  /// A workspace bookmark is an opaque macOS capability retained in Keychain
  /// by Dart. This narrow channel may only be reached from the user-controlled
  /// workspace binding flow; it is never an agent, browser, MCP, or command
  /// tool surface. In the current non-sandboxed development/release profile
  /// it reports `sandboxed: false` without manufacturing a bookmark. That
  /// keeps the scope migration backward compatible while a future isolated
  /// no-network helper is designed and reviewed.
  private func configureWorkspaceAccessChannel() {
    if workspaceAccessChannel != nil {
      return
    }
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/workspace_access",
      binaryMessenger: controller.engine.binaryMessenger
    )
    workspaceAccessChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Workspace access bridge is unavailable.", details: nil))
        return
      }
      guard let arguments = call.arguments as? [String: Any],
            let path = arguments["path"] as? String else {
        result(FlutterError(code: "invalid_workspace", message: "Workspace access requires a local directory.", details: nil))
        return
      }
      switch call.method {
      case "createAndStartWorkspaceAccess":
        self.createAndStartWorkspaceAccess(path: path, result: result)
      case "resumeWorkspaceAccess":
        self.resumeWorkspaceAccess(
          path: path,
          bookmark: arguments["bookmark"] as? String,
          result: result
        )
      case "stopWorkspaceAccess":
        self.stopWorkspaceAccess(path: path)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private var appSandboxEnabled: Bool {
    guard let task = SecTaskCreateFromSelf(kCFAllocatorDefault),
          let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.app-sandbox" as CFString,
            nil
          ) else {
      return false
    }
    if let bool = value as? Bool {
      return bool
    }
    return (value as? NSNumber)?.boolValue ?? false
  }

  private func createAndStartWorkspaceAccess(
    path: String,
    result: @escaping FlutterResult
  ) {
    guard let url = workspaceDirectoryURL(path) else {
      result(FlutterError(code: "invalid_workspace", message: "Select an existing local project folder.", details: nil))
      return
    }
    do {
      result(try beginWorkspaceScope(url))
    } catch {
      result(FlutterError(code: "workspace_access_denied", message: "Workspace access was not granted.", details: nil))
    }
  }

  private func resumeWorkspaceAccess(
    path: String,
    bookmark: String?,
    result: @escaping FlutterResult
  ) {
    if !appSandboxEnabled {
      guard let url = workspaceDirectoryURL(path) else {
        result(FlutterError(code: "invalid_workspace", message: "Select an existing local project folder.", details: nil))
        return
      }
      result(["sandboxed": false, "path": url.path])
      return
    }
    guard let bookmark,
          bookmark.count <= 262_144,
          let bookmarkData = Data(base64Encoded: bookmark) else {
      result(FlutterError(code: "missing_workspace_bookmark", message: "Workspace access must be granted again.", details: nil))
      return
    }
    do {
      var stale = false
      let resolved = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope, .withoutUI],
        relativeTo: nil,
        bookmarkDataIsStale: &stale
      )
      guard let workspace = workspaceDirectoryURL(resolved.path) else {
        throw CocoaError(.fileNoSuchFile)
      }
      var payload = try beginWorkspaceScope(workspace)
      if stale {
        // `beginWorkspaceScope` always returns a freshly generated bookmark,
        // so Dart can atomically replace the Keychain value after a move.
        payload["bookmarkWasStale"] = true
      }
      result(payload)
    } catch {
      result(FlutterError(code: "workspace_access_denied", message: "Workspace access must be granted again.", details: nil))
    }
  }

  private func beginWorkspaceScope(_ url: URL) throws -> [String: Any] {
    if !appSandboxEnabled {
      return ["sandboxed": false, "path": url.path]
    }
    if activeWorkspaceScopes[url.path] == nil {
      guard url.startAccessingSecurityScopedResource() else {
        throw CocoaError(.fileReadNoPermission)
      }
      activeWorkspaceScopes[url.path] = url
    }
    let bookmark = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return [
      "sandboxed": true,
      "path": url.path,
      "bookmark": bookmark.base64EncodedString(),
    ]
  }

  private func stopWorkspaceAccess(path: String) {
    guard let url = workspaceDirectoryURL(path),
          let active = activeWorkspaceScopes.removeValue(forKey: url.path) else {
      return
    }
    active.stopAccessingSecurityScopedResource()
  }

  private func workspaceDirectoryURL(_ path: String) -> URL? {
    guard path.hasPrefix("/") else { return nil }
    let url = URL(fileURLWithPath: path)
      .resolvingSymlinksInPath()
      .standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      return nil
    }
    return url
  }

  // MARK: - Signed macOS updates

  /// Sparkle owns package signature validation, download, installation, and
  /// rollback-safe replacement. The app deliberately refuses to initialize an
  /// updater without a canonical public HTTPS appcast and a 32-byte EdDSA
  /// public key embedded in the signed bundle. Appcast user info, query
  /// parameters, and fragments are refused so a release cannot accidentally
  /// bake credentials or per-request tokens into its signed metadata.
  /// Local/debug builds therefore have no update route.
  private func configureUpdateChannel() {
    guard let feedUrl = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
          let feed = URLComponents(string: feedUrl),
          feed.scheme?.lowercased() == "https", feed.host != nil,
          feed.user == nil, feed.password == nil,
          feed.query == nil, feed.fragment == nil,
          let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
          let keyData = Data(base64Encoded: publicKey), keyData.count == 32,
          !keyData.allSatisfy({ $0 == 0 }) else {
      updateConfigurationError = "This build does not include a signed update feed."
      configureUpdateMethodChannel()
      return
    }

    updaterController = SPUStandardUpdaterController(
      updaterDelegate: self,
      userDriverDelegate: nil
    )
    updateConfigurationError = nil
    configureUpdateMethodChannel()
  }

  private func configureUpdateMethodChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/updates",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Update service is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "status":
        result(self.updateStatus())
      case "setChannel":
        guard let args = call.arguments as? [String: Any],
              let value = args["channel"] as? String,
              let updateChannel = CircuitUpdateChannel(rawValue: value) else {
          result(FlutterError(code: "invalid_channel", message: "Choose the stable or beta update channel.", details: nil))
          return
        }
        UserDefaults.standard.set(updateChannel.rawValue, forKey: Self.updateChannelPreference)
        self.updaterController?.updater.resetUpdateCycle()
        result(self.updateStatus())
      case "setAutomaticChecks":
        guard let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool,
              let updater = self.updaterController?.updater else {
          result(FlutterError(code: "not_configured", message: self.updateConfigurationError ?? "Updates are not configured for this build.", details: nil))
          return
        }
        updater.automaticallyChecksForUpdates = enabled
        // The visible Flutter toggle already conveys this dependency, but the
        // native Sparkle boundary enforces it as well. A future Dart/UI change
        // cannot leave background downloads enabled after checks are revoked.
        if !enabled {
          updater.automaticallyDownloadsUpdates = false
        }
        result(self.updateStatus())
      case "setAutomaticDownloads":
        guard let args = call.arguments as? [String: Any], let enabled = args["enabled"] as? Bool,
              let updater = self.updaterController?.updater else {
          result(FlutterError(code: "not_configured", message: self.updateConfigurationError ?? "Updates are not configured for this build.", details: nil))
          return
        }
        guard !enabled || updater.automaticallyChecksForUpdates else {
          result(FlutterError(
            code: "automatic_checks_required",
            message: "Automatic downloads require automatic update checks.",
            details: self.updateStatus()
          ))
          return
        }
        updater.automaticallyDownloadsUpdates = enabled
        result(self.updateStatus())
      case "setMutationActive":
        guard let args = call.arguments as? [String: Any], let active = args["active"] as? Bool else {
          result(FlutterError(code: "invalid_mutation_state", message: "A mutation state is required.", details: nil))
          return
        }
        self.updateMutationActive = active
        if !active, let install = self.deferredInstallHandler {
          self.deferredInstallHandler = nil
          DispatchQueue.main.async(execute: install)
        }
        result(self.updateStatus())
      case "checkForUpdates":
        guard let controller = self.updaterController else {
          result(FlutterError(code: "not_configured", message: self.updateConfigurationError ?? "Updates are not configured for this build.", details: nil))
          return
        }
        guard !self.updateMutationActive else {
          result(FlutterError(code: "active_mutation", message: "Finish or cancel the active Studio task before checking for an update.", details: self.updateStatus()))
          return
        }
        guard controller.updater.canCheckForUpdates else {
          result(FlutterError(code: "check_unavailable", message: "An update check is already in progress.", details: self.updateStatus()))
          return
        }
        controller.checkForUpdates(nil)
        result(self.updateStatus())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func updateStatus() -> [String: Any] {
    let updater = updaterController?.updater
    return [
      "configured": updater != nil,
      "channel": currentUpdateChannel().rawValue,
      "automaticChecks": updater?.automaticallyChecksForUpdates ?? false,
      "automaticDownloads": updater?.automaticallyDownloadsUpdates ?? false,
      "allowsAutomaticDownloads": updater?.allowsAutomaticUpdates ?? false,
      "canCheck": updater?.canCheckForUpdates ?? false,
      "checkInProgress": updater?.sessionInProgress ?? false,
      "lastCheckEpochMillis": updater?.lastUpdateCheckDate.map { Int64($0.timeIntervalSince1970 * 1000) } as Any,
      "mutationActive": updateMutationActive,
      "installDeferred": deferredInstallHandler != nil,
      "message": updateConfigurationError as Any,
    ]
  }

  private func currentUpdateChannel() -> CircuitUpdateChannel {
    CircuitUpdateChannel(rawValue: UserDefaults.standard.string(forKey: Self.updateChannelPreference) ?? "") ?? .stable
  }

  func allowedChannels(for updater: SPUUpdater) -> Set<String> {
    currentUpdateChannel() == .beta ? [CircuitUpdateChannel.beta.rawValue] : []
  }

  func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
    if updateMutationActive {
      throw NSError(
        domain: "CircuitCode.Updates",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "CircuitCode is preserving an active Studio task before checking for updates."]
      )
    }
  }

  func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
    if updateMutationActive {
      throw NSError(
        domain: "CircuitCode.Updates",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "CircuitCode will offer this update after the active Studio task is finished."]
      )
    }
    if let minimumSchema = try minimumDataSchema(for: updateItem),
       currentDataCompatibilitySchema < minimumSchema {
      throw NSError(
        domain: "CircuitCode.Updates",
        code: 3,
        userInfo: [
          NSLocalizedDescriptionKey:
            "This update requires data schema \(minimumSchema), but this CircuitCode installation has schema \(currentDataCompatibilitySchema). Restore or migrate your project data before updating."
        ]
      )
    }
  }

  func updater(
    _ updater: SPUUpdater,
    shouldPostponeRelaunchForUpdate item: SUAppcastItem,
    untilInvokingBlock installHandler: @escaping () -> Void
  ) -> Bool {
    guard updateMutationActive else { return false }
    deferredInstallHandler = installHandler
    return true
  }

  /// Releases can place `circuit:minimumDataSchema` (or the normalized
  /// `minimumDataSchema` property) on a signed appcast item. Sparkle exposes
  /// the original item dictionary after signature validation; unknown or
  /// malformed values fail closed only when a release explicitly declares a
  /// requirement.
  private func minimumDataSchema(for item: SUAppcastItem) throws -> Int? {
    let keys = [
      "circuit:minimumDataSchema",
      "minimumDataSchema",
      "circuit.minimumDataSchema",
    ]
    for key in keys {
      if let number = item.propertiesDictionary[key] as? NSNumber {
        guard number.intValue > 0 else {
          throw invalidDataSchemaRequirement(for: key)
        }
        return number.intValue
      }
      if let value = item.propertiesDictionary[key] as? String {
        guard let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
              number > 0 else {
          throw invalidDataSchemaRequirement(for: key)
        }
        return number
      }
      if item.propertiesDictionary[key] != nil {
        throw invalidDataSchemaRequirement(for: key)
      }
    }
    return nil
  }

  private func invalidDataSchemaRequirement(for key: String) -> NSError {
    NSError(
      domain: "CircuitCode.Updates",
      code: 4,
      userInfo: [
        NSLocalizedDescriptionKey:
          "The signed update declares an invalid \(key) compatibility requirement. The update was not downloaded."
      ]
    )
  }

  private var currentDataCompatibilitySchema: Int {
    let value = Bundle.main.object(forInfoDictionaryKey: "CircuitDataSchemaVersion")
    if let number = value as? NSNumber, number.intValue > 0 {
      return number.intValue
    }
    if let string = value as? String, let number = Int(string), number > 0 {
      return number
    }
    return 1
  }

  // MARK: - Finder reveal

  /// This channel is only reached by an explicit local UI action. It selects
  /// an existing file in Finder; it neither reads the file nor exposes a
  /// desktop-control capability to agent, browser, or MCP tools.
  private func configureFileRevealChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/file_reveal",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "reveal" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "An existing local file path is required for Finder reveal.",
          details: nil
        ))
        return
      }
      let url = URL(fileURLWithPath: path).standardizedFileURL
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
        result(FlutterError(
          code: "file_unavailable",
          message: "The requested local file is no longer available.",
          details: nil
        ))
        return
      }
      DispatchQueue.main.async {
        NSWorkspace.shared.activateFileViewerSelecting([url])
        result(true)
      }
    }
  }

  // MARK: - Local browser snapshot

  /// Captures only the visible WebKit page into Dart session memory. It never
  /// writes an image to disk and is not connected to an agent-facing channel.
  private func configureBrowserSnapshotChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/browser_snapshot",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "captureVisibleSnapshot" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let expectedUrlValue = arguments["url"] as? String,
        let expectedUrl = URL(string: expectedUrlValue),
        expectedUrl.scheme == "http" || expectedUrl.scheme == "https"
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "A visible http or https page URL is required for capture.",
          details: nil
        ))
        return
      }
      DispatchQueue.main.async {
        self?.captureVisibleBrowserSnapshot(expectedUrl: expectedUrl, result: result)
      }
    }
  }

  private func captureVisibleBrowserSnapshot(
    expectedUrl: URL,
    result: @escaping FlutterResult
  ) {
    guard let webView = visibleWebView() else {
      result(FlutterError(
        code: "webview_unavailable",
        message: "No visible browser preview is available to capture.",
        details: nil
      ))
      return
    }
    guard let currentUrl = webView.url, sameBrowserPage(currentUrl, expectedUrl) else {
      result(FlutterError(
        code: "navigation_changed",
        message: "The visible browser page changed before the snapshot was captured.",
        details: nil
      ))
      return
    }
    webView.takeSnapshot(with: nil) { image, error in
      guard error == nil, let image = image else {
        result(FlutterError(
          code: "snapshot_failed",
          message: "The visible browser preview could not be captured.",
          details: error?.localizedDescription
        ))
        return
      }
      guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
      else {
        result(FlutterError(
          code: "snapshot_encoding_failed",
          message: "The browser snapshot could not be encoded as PNG.",
          details: nil
        ))
        return
      }
      guard png.count <= 4 * 1024 * 1024 else {
        result(FlutterError(
          code: "snapshot_too_large",
          message: "The browser snapshot exceeded the 4 MiB session-memory limit.",
          details: nil
        ))
        return
      }
      result(FlutterStandardTypedData(bytes: png))
    }
  }

  private func visibleWebView() -> WKWebView? {
    guard let root = mainFlutterWindow?.contentView else { return nil }
    return visibleWebView(in: root)
  }

  private func visibleWebView(in view: NSView) -> WKWebView? {
    if let webView = view as? WKWebView, !webView.isHidden {
      return webView
    }
    for subview in view.subviews.reversed() {
      if let webView = visibleWebView(in: subview) {
        return webView
      }
    }
    return nil
  }

  private func sameBrowserPage(_ current: URL, _ expected: URL) -> Bool {
    let currentPort = current.port ?? (current.scheme == "https" ? 443 : 80)
    let expectedPort = expected.port ?? (expected.scheme == "https" ? 443 : 80)
    return current.scheme?.lowercased() == expected.scheme?.lowercased() &&
      current.host?.lowercased() == expected.host?.lowercased() &&
      currentPort == expectedPort &&
      (current.path.isEmpty ? "/" : current.path) ==
        (expected.path.isEmpty ? "/" : expected.path) &&
      current.query == expected.query
  }

  // MARK: - Local OCR

  /// OCR remains entirely on-device. Dart receives only recognized text,
  /// confidence, and normalized regions; the source image never leaves the
  /// selected request unless its model separately advertises vision support.
  private func configureLocalOcrChannel() {
    guard let controller = mainFlutterWindow?.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "circuitcode/local_ocr",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "recognizeText" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        !path.isEmpty
      else {
        result(FlutterError(
          code: "invalid_arguments",
          message: "A readable image path is required for local OCR.",
          details: nil
        ))
        return
      }
      self?.recognizeText(at: path, result: result)
    }
  }

  private func recognizeText(at path: String, result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      guard
        let image = NSImage(contentsOfFile: path),
        let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
      else {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "unreadable_image",
            message: "The selected image could not be opened for local OCR.",
            details: nil
          ))
        }
        return
      }

      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
      do {
        try handler.perform([request])
        let blocks: [[String: Any]] = (request.results ?? []).compactMap { observation in
          guard let candidate = observation.topCandidates(1).first else { return nil }
          let box = observation.boundingBox
          // Vision uses a bottom-left origin. Flutter's comparison/annotation
          // regions use a top-left origin, so convert before crossing the boundary.
          return [
            "text": candidate.string,
            "confidence": Double(candidate.confidence),
            "x": Double(box.origin.x),
            "y": Double(1 - box.origin.y - box.size.height),
            "width": Double(box.size.width),
            "height": Double(box.size.height),
          ]
        }
        DispatchQueue.main.async {
          result([
            "engine": "macos_vision",
            "blocks": blocks,
          ])
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(
            code: "ocr_failed",
            message: "Local OCR could not process the selected image.",
            details: error.localizedDescription
          ))
        }
      }
    }
  }

  @objc private func windowDidBecomeKey(_ notification: Notification) {
    guard let window = notification.object as? NSWindow else { return }
    disableSpellCheckRecursive(window.contentView)
  }

  private func disableSpellCheckRecursive(_ view: NSView?) {
    guard let view = view else { return }
    if let textView = view as? NSTextView {
      textView.isContinuousSpellCheckingEnabled = false
      textView.isGrammarCheckingEnabled = false
      textView.isAutomaticSpellingCorrectionEnabled = false
      textView.isAutomaticQuoteSubstitutionEnabled = false
      textView.isAutomaticDashSubstitutionEnabled = false
      textView.isAutomaticTextReplacementEnabled = false
      textView.isAutomaticTextCompletionEnabled = false
      textView.isAutomaticLinkDetectionEnabled = false
      textView.isAutomaticDataDetectionEnabled = false
    }
    for subview in view.subviews {
      disableSpellCheckRecursive(subview)
    }
  }

  // MARK: - IME Marked Text Swizzling (fixes yellow underlines)

  /// Swizzle IME composition marking methods to strip underline attributes.
  /// The yellow underlines come from macOS IME `setMarkedText:selectedRange:replacementRange:`
  /// adding NSUnderlineStyle attributes, NOT from spell-check.
  private func swizzleIMEMarkedText(_ cls: AnyClass) {
    // 1. Override markedTextAttributes getter to return empty dict
    //    This removes the yellow underline styling entirely
    let markedAttrSel = NSSelectorFromString("markedTextAttributes")
    let emptyDict: @convention(block) (AnyObject) -> [NSAttributedString.Key: Any]? = { _ in
      return [:]
    }
    let emptyDictImp = imp_implementationWithBlock(emptyDict)
    if let method = class_getInstanceMethod(cls, markedAttrSel) {
      method_setImplementation(method, emptyDictImp)
    } else {
      class_addMethod(cls, markedAttrSel, emptyDictImp, "@16@0:8")
    }

    // 2. Override markedTextAttributes setter to no-op
    let setMarkedAttrSel = NSSelectorFromString("setMarkedTextAttributes:")
    let noopSetDict: @convention(block) (AnyObject, Any?) -> Void = { _, _ in }
    let noopSetDictImp = imp_implementationWithBlock(noopSetDict)
    if let method = class_getInstanceMethod(cls, setMarkedAttrSel) {
      method_setImplementation(method, noopSetDictImp)
    } else {
      class_addMethod(cls, setMarkedAttrSel, noopSetDictImp, "v24@0:8@16")
    }

    // 3. Override validAttributesForMarkedText to return empty array
    //    This tells the system no attributes are valid for marked text
    let validAttrSel = NSSelectorFromString("validAttributesForMarkedText")
    let emptyArray: @convention(block) (AnyObject) -> [Any] = { _ in [] }
    let emptyArrayImp = imp_implementationWithBlock(emptyArray)
    if let method = class_getInstanceMethod(cls, validAttrSel) {
      method_setImplementation(method, emptyArrayImp)
    } else {
      class_addMethod(cls, validAttrSel, emptyArrayImp, "@16@0:8")
    }
  }

  // MARK: - Spell Check Swizzling

  /// Swizzle all spell-check getter/setter methods on an NSTextView-compatible class.
  private func swizzleSpellCheckingOnClass(_ cls: AnyClass) {
    // Getter selectors — all return Bool
    let getterSelectors: [Selector] = [
      #selector(getter: NSTextView.isContinuousSpellCheckingEnabled),
      #selector(getter: NSTextView.isGrammarCheckingEnabled),
      #selector(getter: NSTextView.isAutomaticSpellingCorrectionEnabled),
      #selector(getter: NSTextView.isAutomaticQuoteSubstitutionEnabled),
      #selector(getter: NSTextView.isAutomaticDashSubstitutionEnabled),
      #selector(getter: NSTextView.isAutomaticTextReplacementEnabled),
      #selector(getter: NSTextView.isAutomaticTextCompletionEnabled),
    ]

    let alwaysFalse: @convention(block) (AnyObject) -> Bool = { _ in false }
    let falseImp = imp_implementationWithBlock(alwaysFalse)

    for sel in getterSelectors {
      if let method = class_getInstanceMethod(cls, sel) {
        method_setImplementation(method, falseImp)
      } else {
        let typeEncoding = "B@:" // BOOL, self, _cmd
        class_addMethod(cls, sel, falseImp, typeEncoding)
      }
    }

    // Setter selectors — no-op so nothing can re-enable
    let setterSelectors: [Selector] = [
      #selector(setter: NSTextView.isContinuousSpellCheckingEnabled),
      #selector(setter: NSTextView.isGrammarCheckingEnabled),
      #selector(setter: NSTextView.isAutomaticSpellingCorrectionEnabled),
      #selector(setter: NSTextView.isAutomaticQuoteSubstitutionEnabled),
      #selector(setter: NSTextView.isAutomaticDashSubstitutionEnabled),
      #selector(setter: NSTextView.isAutomaticTextReplacementEnabled),
      #selector(setter: NSTextView.isAutomaticTextCompletionEnabled),
    ]

    let noopSetter: @convention(block) (AnyObject, Bool) -> Void = { _, _ in }
    let noopImp = imp_implementationWithBlock(noopSetter)

    for sel in setterSelectors {
      if let method = class_getInstanceMethod(cls, sel) {
        method_setImplementation(method, noopImp)
      } else {
        let typeEncoding = "v@:B" // void, self, _cmd, BOOL
        class_addMethod(cls, sel, noopImp, typeEncoding)
      }
    }

    // Also swizzle the important check methods
    let checkSel = NSSelectorFromString("checkTextInRange:types:options:")
    let noopCheck: @convention(block) (AnyObject, NSRange, UInt64, [String: Any]) -> Void = { _, _, _, _ in }
    let noopCheckImp = imp_implementationWithBlock(noopCheck)
    if let method = class_getInstanceMethod(cls, checkSel) {
      method_setImplementation(method, noopCheckImp)
    }

    let handleSel = NSSelectorFromString("handleTextCheckingResults:forRange:types:options:orthography:wordCount:")
    let noopHandle: @convention(block) (AnyObject, [Any], NSRange, UInt64, [String: Any], Any?, Int) -> Void = { _, _, _, _, _, _, _ in }
    let noopHandleImp = imp_implementationWithBlock(noopHandle)
    if let method = class_getInstanceMethod(cls, handleSel) {
      method_setImplementation(method, noopHandleImp)
    }
  }

  /// For non-NSTextView classes, try disabling via known selectors
  private func disableSpellCheckOnAnyClass(_ cls: AnyClass) {
    let checkSel = NSSelectorFromString("checkTextInRange:types:options:")
    let noopCheck: @convention(block) (AnyObject, NSRange, UInt64, [String: Any]) -> Void = { _, _, _, _ in }
    let noopCheckImp = imp_implementationWithBlock(noopCheck)
    if let method = class_getInstanceMethod(cls, checkSel) {
      method_setImplementation(method, noopCheckImp)
    }
  }
}
