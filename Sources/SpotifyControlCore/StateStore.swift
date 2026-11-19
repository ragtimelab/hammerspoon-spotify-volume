import Foundation
import Darwin

/// Atomic owner-only state replacement. Existing state survives every failure
/// before rename, including an attacker-created temporary symlink.
public func persistSegment(_ segment: Int, path: String) throws {
    func error(_ operation: String) -> NSError {
        NSError(domain: "SpotifyControl.State", code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: operation])
    }
    guard (0...16).contains(segment) else {
        throw NSError(domain: "SpotifyControl.State", code: 64,
                      userInfo: [NSLocalizedDescriptionKey: "invalid-segment"])
    }
    let temporary = path + ".tmp." + String(getpid())
    let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
    guard fd >= 0 else { throw error("state-open") }
    var closed = false
    defer { if !closed { close(fd) }; unlink(temporary) }
    let bytes = Array(String(segment).utf8)
    var offset = 0
    while offset < bytes.count {
        let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!.advanced(by: offset), bytes.count - offset) }
        if n < 0 && errno == EINTR { continue }
        guard n > 0 else { throw error("state-write") }
        offset += n
    }
    guard fchmod(fd, 0o600) == 0, fsync(fd) == 0 else { throw error("state-flush") }
    let result = close(fd)
    closed = true
    guard result == 0 else { throw error("state-close") }
    guard rename(temporary, path) == 0 else { throw error("state-rename") }
}
