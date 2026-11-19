import Foundation
import Darwin

/// Foundation's read(upToCount:) can wait to fill its requested length on a
/// persistent pipe. POSIX read returns the currently available short frame.
public func readPipeChunk(_ descriptor: Int32) throws -> Data {
    var bytes = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress!, $0.count) }
        if count < 0 && errno == EINTR { continue }
        guard count >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        return Data(bytes.prefix(count))
    }
}
