import Darwin
import Foundation

/// A broker-owned loopback HTTP proxy for reviewed command-network access.
///
/// The command process is sandboxed to this one loopback port. It cannot
/// bypass the proxy with a direct socket, a custom DNS resolver, or an
/// environment override. The broker resolves each requested host once,
/// rejects every non-public answer, then opens its upstream socket to that
/// pinned numeric address rather than asking the child process to resolve it.
/// This gives ordinary HTTP(S)-proxy-aware tooling (including package clients)
/// bounded network access without granting unrestricted `network-outbound`.
final class CircuitNetworkEgressProxy {
  private static let headerLimit = 32 * 1024
  private static let maxClients = 8
  private static let socketTimeoutSeconds: Int = 30

  let port: UInt16

  private let listener: Int32
  private let clientSlots = DispatchSemaphore(value: maxClients)
  private let stateLock = NSLock()
  private var stopped = false
  private let acceptQueue = DispatchQueue(
    label: "com.circuitcode.execution-proxy.accept",
    qos: .userInitiated
  )
  private let clientQueue = DispatchQueue(
    label: "com.circuitcode.execution-proxy.client",
    qos: .userInitiated,
    attributes: .concurrent
  )

  private init(listener: Int32, port: UInt16) {
    self.listener = listener
    self.port = port
  }

  static func start() throws -> CircuitNetworkEgressProxy {
    let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else {
      throw CircuitNetworkEgressProxyError.startup
    }

    var reuseAddress: Int32 = 1
    guard setsockopt(
      descriptor,
      SOL_SOCKET,
      SO_REUSEADDR,
      &reuseAddress,
      socklen_t(MemoryLayout<Int32>.size)
    ) == 0 else {
      Darwin.close(descriptor)
      throw CircuitNetworkEgressProxyError.startup
    }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = in_port_t(0).bigEndian
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0, Darwin.listen(descriptor, 16) == 0 else {
      Darwin.close(descriptor)
      throw CircuitNetworkEgressProxyError.startup
    }

    var boundAddress = sockaddr_in()
    var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let receivedAddress = withUnsafeMutablePointer(to: &boundAddress) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.getsockname(descriptor, $0, &boundLength)
      }
    }
    guard receivedAddress == 0, boundAddress.sin_port != 0 else {
      Darwin.close(descriptor)
      throw CircuitNetworkEgressProxyError.startup
    }

    let proxy = CircuitNetworkEgressProxy(
      listener: descriptor,
      port: UInt16(bigEndian: boundAddress.sin_port)
    )
    proxy.startAccepting()
    return proxy
  }

  func stop() {
    stateLock.lock()
    let wasStopped = stopped
    stopped = true
    stateLock.unlock()
    guard !wasStopped else { return }
    _ = Darwin.shutdown(listener, SHUT_RDWR)
    _ = Darwin.close(listener)
  }

  deinit {
    stop()
  }

  private func startAccepting() {
    acceptQueue.async { [weak self] in
      self?.acceptLoop()
    }
  }

  private func acceptLoop() {
    while !isStopped {
      var address = sockaddr_storage()
      var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
      let client = withUnsafeMutablePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
          Darwin.accept(listener, $0, &length)
        }
      }
      if client < 0 {
        if isStopped { return }
        if errno == EINTR { continue }
        continue
      }
      guard clientSlots.wait(timeout: .now()) == .success else {
        writeFailure(to: client, status: "503 Service Unavailable")
        _ = Darwin.close(client)
        continue
      }
      clientQueue.async { [weak self] in
        defer { self?.clientSlots.signal() }
        self?.handle(client: client)
      }
    }
  }

  private var isStopped: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return stopped
  }

  private func handle(client: Int32) {
    defer { _ = Darwin.close(client) }
    configureTimeout(on: client)
    var responseStarted = false
    do {
      let requestData = try readRequestHeader(from: client)
      let request = try CircuitProxyRequest.parse(
        header: requestData.header,
        trailingBytes: requestData.trailing
      )
      let addresses = try CircuitNetworkAddressPolicy.resolvePublic(
        host: request.host
      )
      let upstream = try openPinnedSocket(
        address: addresses[0],
        port: request.port
      )
      configureTimeout(on: upstream)
      defer { _ = Darwin.close(upstream) }

      switch request.kind {
      case .connect:
        try writeAll(
          Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8),
          to: client
        )
        responseStarted = true
      case .http(let forwardedHeader):
        try writeAll(forwardedHeader, to: upstream)
      }
      if !request.trailingBytes.isEmpty {
        try writeAll(request.trailingBytes, to: upstream)
      }
      relay(client: client, upstream: upstream)
    } catch {
      if !responseStarted {
        writeFailure(to: client, status: "502 Bad Gateway")
      }
    }
  }

  private func readRequestHeader(from descriptor: Int32) throws
    -> (header: Data, trailing: Data) {
    let terminator = Data("\r\n\r\n".utf8)
    var request = Data()
    while request.count <= Self.headerLimit {
      if let range = request.range(of: terminator) {
        let end = range.upperBound
        return (Data(request[..<end]), Data(request[end...]))
      }
      let chunk = try receiveChunk(from: descriptor)
      guard !chunk.isEmpty else { throw CircuitNetworkEgressProxyError.request }
      request.append(chunk)
    }
    throw CircuitNetworkEgressProxyError.request
  }

  private func relay(client: Int32, upstream: Int32) {
    let group = DispatchGroup()
    group.enter()
    clientQueue.async {
      defer { group.leave() }
      self.copy(from: client, to: upstream)
    }
    group.enter()
    clientQueue.async {
      defer { group.leave() }
      self.copy(from: upstream, to: client)
    }
    group.wait()
  }

  private func copy(from source: Int32, to destination: Int32) {
    while true {
      guard let chunk = try? receiveChunk(from: source), !chunk.isEmpty else {
        _ = Darwin.shutdown(destination, SHUT_WR)
        return
      }
      guard (try? writeAll(chunk, to: destination)) != nil else {
        _ = Darwin.shutdown(destination, SHUT_WR)
        return
      }
    }
  }

  private func receiveChunk(from descriptor: Int32) throws -> Data {
    var buffer = [UInt8](repeating: 0, count: 16 * 1024)
    let count = buffer.withUnsafeMutableBytes { rawBuffer in
      Darwin.recv(descriptor, rawBuffer.baseAddress, rawBuffer.count, 0)
    }
    if count < 0 {
      if errno == EINTR { return try receiveChunk(from: descriptor) }
      throw CircuitNetworkEgressProxyError.socket
    }
    return Data(buffer.prefix(Int(count)))
  }

  private func openPinnedSocket(address: String, port: UInt16) throws -> Int32 {
    var hints = addrinfo(
      ai_flags: AI_NUMERICHOST,
      ai_family: AF_UNSPEC,
      ai_socktype: SOCK_STREAM,
      ai_protocol: IPPROTO_TCP,
      ai_addrlen: 0,
      ai_canonname: nil,
      ai_addr: nil,
      ai_next: nil
    )
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(address, String(port), &hints, &result) == 0,
          let result else {
      throw CircuitNetworkEgressProxyError.socket
    }
    defer { freeaddrinfo(result) }

    var cursor: UnsafeMutablePointer<addrinfo>? = result
    while let candidate = cursor {
      let info = candidate.pointee
      let descriptor = Darwin.socket(
        info.ai_family,
        info.ai_socktype,
        info.ai_protocol
      )
      if descriptor >= 0 {
        configureTimeout(on: descriptor)
        if Darwin.connect(descriptor, info.ai_addr, info.ai_addrlen) == 0 {
          return descriptor
        }
        _ = Darwin.close(descriptor)
      }
      cursor = info.ai_next
    }
    throw CircuitNetworkEgressProxyError.socket
  }

  private func configureTimeout(on descriptor: Int32) {
    var timeout = timeval(tv_sec: Self.socketTimeoutSeconds, tv_usec: 0)
    let length = socklen_t(MemoryLayout<timeval>.size)
    _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &timeout, length)
    _ = setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, &timeout, length)
  }

  private func writeFailure(to descriptor: Int32, status: String) {
    let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    try? writeAll(Data(response.utf8), to: descriptor)
  }

  private func writeAll(_ data: Data, to descriptor: Int32) throws {
    var offset = 0
    while offset < data.count {
      let sent = data.withUnsafeBytes { rawBuffer -> Int in
        guard let base = rawBuffer.baseAddress else { return -1 }
        return Darwin.send(
          descriptor,
          base.advanced(by: offset),
          data.count - offset,
          0
        )
      }
      if sent < 0 {
        if errno == EINTR { continue }
        throw CircuitNetworkEgressProxyError.socket
      }
      guard sent > 0 else { throw CircuitNetworkEgressProxyError.socket }
      offset += sent
    }
  }
}

private struct CircuitProxyRequest {
  enum Kind {
    case connect
    case http(Data)
  }

  let kind: Kind
  let host: String
  let port: UInt16
  let trailingBytes: Data

  static func parse(header: Data, trailingBytes: Data) throws -> CircuitProxyRequest {
    guard let text = String(data: header, encoding: .utf8),
          !text.contains("\u{0000}") else {
      throw CircuitNetworkEgressProxyError.request
    }
    let lines = text.components(separatedBy: "\r\n")
    guard let requestLine = lines.first else {
      throw CircuitNetworkEgressProxyError.request
    }
    let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count == 3,
          parts[2].hasPrefix("HTTP/") else {
      throw CircuitNetworkEgressProxyError.request
    }
    let method = String(parts[0]).uppercased()
    let target = String(parts[1])
    let version = String(parts[2])

    if method == "CONNECT" {
      let authority = try parseAuthority(target)
      return CircuitProxyRequest(
        kind: .connect,
        host: authority.host,
        port: authority.port,
        trailingBytes: trailingBytes
      )
    }

    guard let components = URLComponents(string: target),
          components.scheme?.lowercased() == "http",
          components.user == nil,
          components.password == nil,
          let host = components.host else {
      throw CircuitNetworkEgressProxyError.request
    }
    let port = UInt16(components.port ?? 80)
    guard port > 0 else { throw CircuitNetworkEgressProxyError.request }
    var path = components.percentEncodedPath
    if path.isEmpty { path = "/" }
    if let query = components.percentEncodedQuery, !query.isEmpty {
      path += "?\(query)"
    }

    var forwarded = ["\(method) \(path) \(version)"]
    var hasHostHeader = false
    for line in lines.dropFirst() where !line.isEmpty {
      let lower = line.lowercased()
      if lower.hasPrefix("proxy-connection:") ||
          lower.hasPrefix("proxy-authorization:") {
        continue
      }
      if lower.hasPrefix("host:") { hasHostHeader = true }
      forwarded.append(line)
    }
    if !hasHostHeader {
      forwarded.append("Host: \(host)")
    }
    let forwardedHeader = Data((forwarded.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    return CircuitProxyRequest(
      kind: .http(forwardedHeader),
      host: host,
      port: port,
      trailingBytes: trailingBytes
    )
  }

  private static func parseAuthority(_ raw: String) throws -> (host: String, port: UInt16) {
    if raw.hasPrefix("[") {
      guard let closing = raw.firstIndex(of: "]"),
            raw.index(after: closing) < raw.endIndex,
            raw[raw.index(after: closing)] == ":" else {
        throw CircuitNetworkEgressProxyError.request
      }
      let host = String(raw[raw.index(after: raw.startIndex)..<closing])
      let portText = String(raw[raw.index(after: raw.index(after: closing))...])
      return (host, try parsePort(portText))
    }
    guard let separator = raw.lastIndex(of: ":") else {
      throw CircuitNetworkEgressProxyError.request
    }
    let host = String(raw[..<separator])
    guard !host.isEmpty, !host.contains(":") else {
      throw CircuitNetworkEgressProxyError.request
    }
    return (host, try parsePort(String(raw[raw.index(after: separator)...])))
  }

  private static func parsePort(_ raw: String) throws -> UInt16 {
    guard let value = UInt16(raw), value > 0 else {
      throw CircuitNetworkEgressProxyError.request
    }
    return value
  }
}

private enum CircuitNetworkAddressPolicy {
  static func resolvePublic(host rawHost: String) throws -> [String] {
    let host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isAllowedHostName(host) else {
      throw CircuitNetworkEgressProxyError.address
    }

    var hints = addrinfo(
      ai_flags: AI_ADDRCONFIG,
      ai_family: AF_UNSPEC,
      ai_socktype: SOCK_STREAM,
      ai_protocol: IPPROTO_TCP,
      ai_addrlen: 0,
      ai_canonname: nil,
      ai_addr: nil,
      ai_next: nil
    )
    var result: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &result) == 0,
          let result else {
      throw CircuitNetworkEgressProxyError.address
    }
    defer { freeaddrinfo(result) }

    var addresses = [String]()
    var seen = Set<String>()
    var cursor: UnsafeMutablePointer<addrinfo>? = result
    while let candidate = cursor {
      let info = candidate.pointee
      var numericHost = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      let nameResult = getnameinfo(
        info.ai_addr,
        info.ai_addrlen,
        &numericHost,
        socklen_t(numericHost.count),
        nil,
        0,
        NI_NUMERICHOST
      )
      guard nameResult == 0 else { throw CircuitNetworkEgressProxyError.address }
      let address = String(cString: numericHost)
      guard publicAddressBlockReason(address) == nil else {
        throw CircuitNetworkEgressProxyError.address
      }
      if seen.insert(address).inserted { addresses.append(address) }
      cursor = info.ai_next
    }
    guard !addresses.isEmpty else { throw CircuitNetworkEgressProxyError.address }
    return addresses
  }

  private static func isAllowedHostName(_ host: String) -> Bool {
    guard !host.isEmpty,
          host.count <= 253,
          !host.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value == 0x7f }) else {
      return false
    }
    guard host != "localhost",
          host != "localhost.localdomain",
          !host.hasSuffix(".localhost"),
          !host.hasSuffix(".local"),
          !host.hasSuffix(".internal"),
          !host.hasSuffix(".lan") else {
      return false
    }
    if !host.contains(".") && !host.contains(":") { return false }
    let labels = host.split(separator: ".", omittingEmptySubsequences: false)
    if labels.allSatisfy({ label in
      let value = String(label)
      return value.allSatisfy(\.isNumber) ||
        value.lowercased().hasPrefix("0x")
    }) {
      if labels.count != 4 { return false }
      if labels.contains(where: {
        $0.count > 1 && ($0.first == "0" || $0.lowercased().hasPrefix("0x"))
      }) {
        return false
      }
    }
    return true
  }

  private static func publicAddressBlockReason(_ address: String) -> String? {
    if let bytes = ipv4Bytes(address) {
      return ipv4BlockReason(bytes)
    }
    if let bytes = ipv6Bytes(address) {
      if bytes.allSatisfy({ $0 == 0 }) { return "unspecified" }
      if bytes.dropLast().allSatisfy({ $0 == 0 }) && bytes.last == 1 {
        return "loopback"
      }
      if bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80 { return "link-local" }
      if (bytes[0] & 0xfe) == 0xfc { return "unique-local" }
      if bytes[0] == 0xff { return "multicast" }
      if bytes.prefix(10).allSatisfy({ $0 == 0 }) && bytes[10] == 0xff && bytes[11] == 0xff {
        return ipv4BlockReason(Array(bytes.suffix(4)))
      }
      if bytes.prefix(12).allSatisfy({ $0 == 0 }) {
        return ipv4BlockReason(Array(bytes.suffix(4))) ?? "IPv4-compatible"
      }
      if (bytes[0] == 0x20 && bytes[1] == 0x02) ||
          (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x00 && bytes[3] == 0x00) ||
          (bytes[0] == 0x00 && bytes[1] == 0x64 && bytes[2] == 0xff && bytes[3] == 0x9b) ||
          (bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8) {
        return "special-purpose IPv6"
      }
      return nil
    }
    return "invalid address"
  }

  private static func ipv4Bytes(_ address: String) -> [UInt8]? {
    var parsed = in_addr()
    guard address.withCString({ inet_pton(AF_INET, $0, &parsed) }) == 1 else {
      return nil
    }
    return withUnsafeBytes(of: &parsed.s_addr) { Array($0) }
  }

  private static func ipv6Bytes(_ address: String) -> [UInt8]? {
    var parsed = in6_addr()
    guard address.withCString({ inet_pton(AF_INET6, $0, &parsed) }) == 1 else {
      return nil
    }
    return withUnsafeBytes(of: &parsed) { Array($0) }
  }

  private static func ipv4BlockReason(_ octets: [UInt8]) -> String? {
    guard octets.count == 4 else { return "invalid IPv4" }
    let first = octets[0]
    let second = octets[1]
    let third = octets[2]
    if first == 0 || first == 127 { return "loopback or unspecified IPv4" }
    if first == 10 ||
        (first == 172 && (16...31).contains(second)) ||
        (first == 192 && second == 168) ||
        (first == 100 && (64...127).contains(second)) ||
        (first == 169 && second == 254) {
      return "private IPv4"
    }
    if (first == 192 && second == 0 && (third == 0 || third == 2)) ||
        (first == 198 && (second == 18 || second == 19)) ||
        (first == 198 && second == 51 && third == 100) ||
        (first == 203 && second == 0 && third == 113) ||
        first >= 224 {
      return "reserved IPv4"
    }
    return nil
  }
}

private enum CircuitNetworkEgressProxyError: Error {
  case startup
  case request
  case address
  case socket
}
