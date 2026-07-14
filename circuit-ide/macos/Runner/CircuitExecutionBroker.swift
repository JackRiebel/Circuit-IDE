import Darwin
import Foundation

/// A deliberately small, separately executable command broker. CircuitCode
/// starts this helper rather than a shell in the app process; the helper then
/// constructs a default-deny macOS sandbox profile from the reviewed request,
/// applies resource limits, and only then launches the requested shell.
///
/// It accepts arguments, never a shell script of its own. The only script text
/// remains the reviewed final argument to the user-selected shell.
@main
struct CircuitExecutionBroker {
  private static let maximumToolRoots = 32
  private static let maximumOpenFiles: rlim_t = 64
  /// Darwin applies RLIMIT_NPROC across the user rather than just this process.
  /// Keep it below the normal system ceiling without starving a developer's
  /// existing app processes before the broker forks the reviewed command.
  private static let maximumUserProcesses: rlim_t = 512
  private static let maximumOutputFileBytes: rlim_t = 512 * 1024 * 1024
  /// Commands may use a predictable system/Homebrew lookup path, but never
  /// inherit a developer's full process PATH. Even though Seatbelt rejects
  /// unapproved roots, preserving such entries would disclose local paths to a
  /// reviewed command and can make its behavior depend on ambient tooling.
  private static let sanitizedPath =
    "/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin"
  /// Tool roots are not a general-purpose filesystem allowlist. The Flutter
  /// host may derive candidates from its inherited PATH, which is useful for
  /// discovery but must never let a value such as `/` broaden the Seatbelt
  /// profile. The broker independently accepts only reviewed system tool
  /// locations, and already grants the necessary system roots below.
  private static let trustedToolRootPrefixes = [
    "/bin",
    "/sbin",
    "/usr/bin",
    "/usr/sbin",
    "/usr/local",
    "/opt/homebrew",
    "/Library/Developer",
  ]

  static func main() {
    do {
      let request = try Request.parse(CommandLine.arguments)
      let workspace = try canonicalDirectory(request.workspace)
      let workspaceAliases = sandboxPathAliases(
        requestedPath: request.workspace,
        canonical: workspace
      )
      let toolRoots = try request.toolRoots
        .prefix(maximumToolRoots)
        .map(canonicalToolRoot)
      let temporaryDirectory = try makeTemporaryDirectory(in: workspace)
      defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
      let networkProxy: CircuitNetworkEgressProxy?
      if request.allowNetwork {
        networkProxy = try CircuitNetworkEgressProxy.start()
      } else {
        networkProxy = nil
      }
      defer { networkProxy?.stop() }

      try setResourceLimits(cpuSeconds: request.cpuLimitSeconds)
      let profile = sandboxProfile(
        workspace: workspace,
        workspaceAliases: workspaceAliases,
        temporaryDirectory: temporaryDirectory,
        toolRoots: toolRoots,
        networkProxyPort: networkProxy?.port
      )
      try run(
        request.command,
        workspace: workspace,
        temporaryDirectory: temporaryDirectory,
        sandboxProfile: profile,
        networkProxyPort: networkProxy?.port
      )
    } catch {
      FileHandle.standardError.write(
        Data(
          "Circuit execution broker denied launch. Check the execution boundary and try again.\n".utf8
        )
      )
      exit(126)
    }
  }

  private static func canonicalDirectory(_ path: String) throws -> URL {
    guard path.hasPrefix("/") else {
      throw BrokerError.invalidArgument("Expected an absolute directory path.")
    }
    let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          isDirectory.boolValue else {
      throw BrokerError.invalidArgument("Directory does not exist: \(path)")
    }
    return url
  }

  /// A caller-controlled tool root must stay within a reviewed system tool
  /// location. In particular, `/`, a user home, and a workspace are never
  /// valid tool roots: allowing one would turn an executable lookup hint into
  /// an unrestricted read/execute filesystem grant.
  private static func canonicalToolRoot(_ path: String) throws -> URL {
    let url = try canonicalDirectory(path)
    let normalized = url.path
    let isTrusted = trustedToolRootPrefixes.contains { prefix in
      normalized == prefix || normalized.hasPrefix(prefix + "/")
    }
    guard isTrusted else {
      throw BrokerError.invalidArgument(
        "Tool root is outside CircuitCode's trusted system tool locations."
      )
    }
    return url
  }

  /// Seatbelt evaluates the physical path used by a child process, while a
  /// user-facing workspace may arrive through macOS compatibility symlinks
  /// such as `/tmp` or `/var`. Foundation normalizes those aliases eagerly,
  /// so preserve the reviewed request spelling as a string too. The only
  /// additional aliases are the known equivalent macOS roots.
  private static func sandboxPathAliases(
    requestedPath: String,
    canonical: URL
  ) -> [String] {
    let requested = "/" + requestedPath
      .split(separator: "/", omittingEmptySubsequences: true)
      .joined(separator: "/")
    let compatibilityAliases = [
      requested,
      canonical.path,
      requested.replacingOccurrences(of: "/tmp/", with: "/private/tmp/"),
      requested.replacingOccurrences(of: "/private/tmp/", with: "/tmp/"),
      requested.replacingOccurrences(of: "/var/", with: "/private/var/"),
      requested.replacingOccurrences(of: "/private/var/", with: "/var/"),
    ]
    var seen = Set<String>()
    return compatibilityAliases.filter { seen.insert($0).inserted }
  }

  private static func makeTemporaryDirectory(in workspace: URL) throws -> URL {
    let manager = FileManager.default
    let requestedRoot = workspace.appendingPathComponent(
      ".circuitcode",
      isDirectory: true
    )
    var isDirectory: ObjCBool = false
    if manager.fileExists(atPath: requestedRoot.path, isDirectory: &isDirectory) {
      // `fileExists` follows links, so inspect the path itself before using it
      // as a parent. Otherwise a repository-owned `.circuitcode` link could
      // redirect the supposedly private child outside the reviewed workspace,
      // and the separately granted temp rule below would become an escape.
      guard isDirectory.boolValue,
            (try? manager.destinationOfSymbolicLink(atPath: requestedRoot.path)) == nil else {
        throw BrokerError.invalidArgument(
          "The workspace temporary directory is not a safe local directory."
        )
      }
    } else {
      try manager.createDirectory(
        at: requestedRoot,
        withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
      )
    }

    let temporaryRoot = requestedRoot.resolvingSymlinksInPath().standardizedFileURL
    guard isStrictDescendant(temporaryRoot, of: workspace) else {
      throw BrokerError.invalidArgument(
        "The workspace temporary directory escapes the reviewed workspace."
      )
    }

    let directory = temporaryRoot.appendingPathComponent(
      "broker-tmp-\(UUID().uuidString)",
      isDirectory: true
    )
    try manager.createDirectory(
      at: directory,
      withIntermediateDirectories: false,
      attributes: [.posixPermissions: 0o700]
    )
    let canonicalDirectory = directory.resolvingSymlinksInPath().standardizedFileURL
    guard isStrictDescendant(canonicalDirectory, of: temporaryRoot) &&
          isStrictDescendant(canonicalDirectory, of: workspace) else {
      throw BrokerError.invalidArgument(
        "The broker temporary directory escapes the reviewed workspace."
      )
    }
    return canonicalDirectory
  }

  private static func isStrictDescendant(_ candidate: URL, of ancestor: URL) -> Bool {
    let canonicalAncestor = ancestor.resolvingSymlinksInPath().standardizedFileURL.path
    let prefix = canonicalAncestor == "/" ? "/" : canonicalAncestor + "/"
    return candidate.path.hasPrefix(prefix) && candidate.path != canonicalAncestor
  }

  private static func setResourceLimits(cpuSeconds: Int) throws {
    let boundedCpu = max(1, min(cpuSeconds, 300))
    var cpu = rlimit(
      rlim_cur: rlim_t(boundedCpu),
      rlim_max: rlim_t(boundedCpu + 1)
    )
    guard setrlimit(RLIMIT_CPU, &cpu) == 0 else {
      throw BrokerError.resourceLimit("Could not apply CPU limit.")
    }

    var fileLimit = rlimit()
    guard getrlimit(RLIMIT_NOFILE, &fileLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not inspect file-descriptor limit.")
    }
    fileLimit.rlim_cur = min(fileLimit.rlim_cur, maximumOpenFiles)
    fileLimit.rlim_max = min(fileLimit.rlim_max, maximumOpenFiles)
    guard setrlimit(RLIMIT_NOFILE, &fileLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not apply file-descriptor limit.")
    }

    var processLimit = rlimit()
    guard getrlimit(RLIMIT_NPROC, &processLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not inspect process limit.")
    }
    processLimit.rlim_cur = min(processLimit.rlim_cur, maximumUserProcesses)
    processLimit.rlim_max = min(processLimit.rlim_max, maximumUserProcesses)
    guard setrlimit(RLIMIT_NPROC, &processLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not apply process limit.")
    }

    var fileSizeLimit = rlimit()
    guard getrlimit(RLIMIT_FSIZE, &fileSizeLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not inspect output-file limit.")
    }
    fileSizeLimit.rlim_cur = min(fileSizeLimit.rlim_cur, maximumOutputFileBytes)
    fileSizeLimit.rlim_max = min(fileSizeLimit.rlim_max, maximumOutputFileBytes)
    guard setrlimit(RLIMIT_FSIZE, &fileSizeLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not apply output-file limit.")
    }

    // Core dumps can contain workspace data and inherited process memory. The
    // broker never needs them because command failures already stream through
    // the redacted Studio command log.
    var coreLimit = rlimit(rlim_cur: 0, rlim_max: 0)
    guard setrlimit(RLIMIT_CORE, &coreLimit) == 0 else {
      throw BrokerError.resourceLimit("Could not disable core dumps.")
    }
  }

  private static func sandboxProfile(
    workspace: URL,
    workspaceAliases: [String],
    temporaryDirectory: URL,
    toolRoots: [URL],
    networkProxyPort: UInt16?
  ) -> String {
    // These are exact OS/runtime locations, never user home or application
    // data. In particular, do not grant `/usr` or `/Library` as a whole:
    // `/usr/local` and most of `/Library` are mutable machine-wide data, not
    // part of the command runtime. Optional Homebrew/local-tool access is
    // instead granted only through the reviewed `toolRoots` request below.
    let systemRoots = [
      "/System",
      "/usr/bin",
      "/usr/sbin",
      "/bin",
      "/sbin",
      "/Library/Developer",
      // `/bin/sh` resolves through this macOS-managed selector on current
      // systems. It is an OS runtime location, not a caller-controlled
      // writable `/private/var` allowance.
      "/private/var/select",
      // `xcrun` reads only this macOS-managed developer-tool selector before
      // resolving an SDK beneath the reviewed `/Library/Developer` root.
      "/var/db/xcode_select_link",
      "/private/var/db/xcode_select_link",
      "/private/var/db/timezone",
      // Apple's curl/OpenSSL compatibility layer consults this system TLS
      // configuration before it can validate a proxied HTTPS peer. Grant only
      // the configuration subtree, never the broader mutable `/private/etc`.
      "/private/etc/ssl",
    ]
    var seenWorkspacePaths = Set<String>()
    let workspacePaths = (workspaceAliases + [workspace.path])
      .filter { seenWorkspacePaths.insert($0).inserted }
    let readableRoots = systemRoots + toolRoots.map(\.path) + workspacePaths
    let executableRoots = systemRoots + toolRoots.map(\.path) + workspacePaths
    let readRules = readableRoots
      .map { "(allow file-read* (subpath \(sandboxLiteral($0))))" }
      .joined(separator: "\n")
    let executeRules = executableRoots
      .map { "(allow process-exec (subpath \(sandboxLiteral($0))))" }
      .joined(separator: "\n")
    // Tool launchers such as Homebrew's Python resolve their own path before
    // execution. They need traversal metadata for `/opt` and other ancestors,
    // but never read access outside the already-approved system/tool root.
    let rootMetadataRules = readableRoots.map { path in
      """
      (allow file-read-metadata file-test-existence
             (path-ancestors \(sandboxLiteral(path))))
      (allow file-read-metadata file-test-existence
             (literal \(sandboxLiteral(path))))
      """
    }.joined(separator: "\n")
    let workspaceRules = workspacePaths.map { path in
      """
      (allow file-read-metadata file-test-existence
             (path-ancestors \(sandboxLiteral(path))))
      (allow file-read-metadata file-test-existence
             (literal \(sandboxLiteral(path))))
      (allow file-write* (subpath \(sandboxLiteral(path))))
      (allow file-write-create file-write-data
             (require-all (vnode-type DIRECTORY)
                          (literal \(sandboxLiteral(path)))))
      """
    }.joined(separator: "\n")
    // The broker never needs to read or write credentials. `system.sb` and
    // the reviewed system roots keep a command runtime functional, but they
    // must not turn into an implicit Keychain grant when macOS services or a
    // system utility resolve their backing stores. The user's Keychain path is
    // deliberately captured before the child HOME is replaced with the
    // workspace-local temporary directory.
    let keychainPaths = [
      FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Keychains", isDirectory: true).path,
      "/Library/Keychains",
      "/System/Library/Keychains",
      "/private/var/db/Keychains",
    ]
    let keychainDenyRules = keychainPaths.map { path in
      """
      (deny file-read* file-read-metadata file-test-existence file-write*
            (subpath \(sandboxLiteral(path))))
      """
    }.joined(separator: "\n")
    // `system.sb` intentionally retains some broad compatibility allowances
    // for ordinary macOS processes. Reassert the command boundary after that
    // import: machine-wide Library data is not part of the runtime. The one
    // explicit exception is Apple's Command Line Tools/SDK root, which is a
    // reviewed executable root and may be required by a command that invokes
    // the system `xcrun` launcher.
    let unreviewedLibraryDenyRule = """
    (deny file-read* file-read-metadata file-test-existence file-write*
          (require-all
            (subpath \(sandboxLiteral("/Library")))
            (require-not (subpath \(sandboxLiteral("/Library/Developer"))))))
    """
    // A reviewed network command never receives generic outbound sockets.
    // Instead, it can reach only the broker-owned loopback proxy. That proxy
    // validates DNS answers and connects directly to the selected public IP,
    // so a command cannot bypass policy through rebinding, a custom resolver,
    // proxy environment changes, or a direct socket call.
    let networkRule = networkProxyPort.map { port in
      // Seatbelt accepts the canonical `localhost` selector here rather than
      // a numeric loopback literal. The proxy itself binds only 127.0.0.1.
      "(allow network-outbound (remote ip \"localhost:\(port)\"))"
    } ?? ""

    return """
    (version 1)
    (deny default)
    ;; Preserve the minimal macOS runtime allowances required for a process
    ;; started by sandbox-exec (dynamic loader, standard descriptors, and
    ;; system service lookups). Workspace, executable, and network access are
    ;; still granted explicitly below.
    (import "/System/Library/Sandbox/Profiles/system.sb")
    (allow process-fork)
    \(readRules)
    \(executeRules)
    \(rootMetadataRules)
    \(workspaceRules)
    \(unreviewedLibraryDenyRule)
    \(keychainDenyRules)
    (allow file-read* (subpath \(sandboxLiteral(temporaryDirectory.path))))
    (allow file-write* (subpath \(sandboxLiteral(temporaryDirectory.path))))
    \(networkRule)
    """
  }

  private static func sandboxLiteral(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
    return "\"\(escaped)\""
  }

  private static func run(
    _ command: [String],
    workspace: URL,
    temporaryDirectory: URL,
    sandboxProfile: String,
    networkProxyPort: UInt16?
  ) throws {
    guard let executable = command.first, executable.hasPrefix("/") else {
      throw BrokerError.invalidArgument("Expected an absolute shell executable.")
    }
    // macOS's public sandbox_init API only supports Apple named profiles;
    // sandbox-exec remains the system-provided interface that can apply our
    // reviewed, per-workspace profile to a child process. Keeping it inside
    // this separate broker means the app never directly assembles or launches
    // unrestricted command processes.
    let sandboxExecutable = "/usr/bin/sandbox-exec"
    guard FileManager.default.isExecutableFile(atPath: sandboxExecutable) else {
      throw BrokerError.sandbox("The macOS sandbox runner is unavailable.")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: sandboxExecutable)
    process.arguments = ["-p", sandboxProfile] + command
    process.currentDirectoryURL = workspace
    let standardOutput = Pipe()
    let standardError = Pipe()
    process.standardOutput = standardOutput
    process.standardError = standardError
    var environment = [
      "HOME": temporaryDirectory.path,
      "TMPDIR": temporaryDirectory.path,
      "TMP": temporaryDirectory.path,
      "TEMP": temporaryDirectory.path,
      "PATH": sanitizedPath,
      "TERM": "dumb",
    ]
    if let networkProxyPort {
      let proxy = "http://127.0.0.1:\(networkProxyPort)"
      // Set both conventional spellings. The child's sandbox profile permits
      // only this loopback peer, so a command that disables these variables or
      // uses a raw socket still fails closed instead of reaching a host.
      environment["http_proxy"] = proxy
      environment["https_proxy"] = proxy
      environment["all_proxy"] = proxy
      environment["HTTP_PROXY"] = proxy
      environment["HTTPS_PROXY"] = proxy
      environment["ALL_PROXY"] = proxy
      environment["no_proxy"] = ""
      environment["NO_PROXY"] = ""
    }
    process.environment = environment
    try process.run()
    let outputGroup = DispatchGroup()
    forward(standardOutput, to: .standardOutput, in: outputGroup)
    forward(standardError, to: .standardError, in: outputGroup)
    process.waitUntilExit()
    outputGroup.wait()
    exit(process.terminationStatus)
  }

  private static func forward(
    _ pipe: Pipe,
    to destination: FileHandle,
    in group: DispatchGroup
  ) {
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
      defer { group.leave() }
      while true {
        let data = pipe.fileHandleForReading.availableData
        guard !data.isEmpty else { return }
        destination.write(data)
      }
    }
  }
}

private struct Request {
  let workspace: String
  let allowNetwork: Bool
  let cpuLimitSeconds: Int
  let toolRoots: [String]
  let command: [String]

  static func parse(_ arguments: [String]) throws -> Request {
    var workspace: String?
    var allowNetwork = false
    var cpuLimitSeconds = 300
    var toolRoots: [String] = []
    var index = 1

    while index < arguments.count {
      let argument = arguments[index]
      if argument == "--" {
        let command = Array(arguments.dropFirst(index + 1))
        guard let workspace, !command.isEmpty else {
          throw BrokerError.invalidArgument("Expected workspace and command arguments.")
        }
        return Request(
          workspace: workspace,
          allowNetwork: allowNetwork,
          cpuLimitSeconds: cpuLimitSeconds,
          toolRoots: toolRoots,
          command: command
        )
      }
      switch argument {
      case "--workspace":
        index += 1
        guard index < arguments.count else { throw BrokerError.invalidArgument("Missing workspace.") }
        workspace = arguments[index]
      case "--network":
        index += 1
        guard index < arguments.count else { throw BrokerError.invalidArgument("Missing network policy.") }
        switch arguments[index] {
        case "allow": allowNetwork = true
        case "deny": allowNetwork = false
        default: throw BrokerError.invalidArgument("Network policy must be allow or deny.")
        }
      case "--cpu-limit":
        index += 1
        guard index < arguments.count, let value = Int(arguments[index]), value > 0 else {
          throw BrokerError.invalidArgument("CPU limit must be a positive integer.")
        }
        cpuLimitSeconds = value
      case "--tool-root":
        index += 1
        guard index < arguments.count else { throw BrokerError.invalidArgument("Missing tool root.") }
        toolRoots.append(arguments[index])
      default:
        throw BrokerError.invalidArgument("Unsupported broker argument: \(argument)")
      }
      index += 1
    }
    throw BrokerError.invalidArgument("Missing -- command delimiter.")
  }
}

private enum BrokerError: LocalizedError {
  case invalidArgument(String)
  case resourceLimit(String)
  case sandbox(String)

  var errorDescription: String? {
    switch self {
    case .invalidArgument(let value), .resourceLimit(let value), .sandbox(let value):
      return value
    }
  }
}
