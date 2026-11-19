import Foundation
import BuildIdentity

public let spotifyOSDVersion = buildVersion
public let spotifyOSDBuildID = buildIdentity
public let spotifyOSDProtocolVersion = 1

public enum ServerCommand: Equatable {
    case show(Int)
}

public enum ServerCommandError: Error, Equatable {
    case invalidCommand
}

public enum FramedLine: Equatable {
    case line(String)
    case invalidUTF8
}

public struct LineFramer {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [FramedLine] {
        buffer.append(data)
        var lines: [FramedLine] = []

        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)

            guard var line = String(data: lineData, encoding: .utf8) else {
                lines.append(.invalidUTF8)
                continue
            }
            if line.last == "\r" {
                line.removeLast()
            }
            lines.append(.line(line))
        }

        return lines
    }
}

public func parseSegment(_ value: String) -> Int? {
    guard let segment = Int(value), (0...16).contains(segment) else {
        return nil
    }
    return segment
}

public func parseServerCommand(_ line: String) throws -> ServerCommand {
    let fields = line.split(separator: " ", omittingEmptySubsequences: true)
    guard fields.count == 2,
          fields[0] == "SHOW",
          let segment = parseSegment(String(fields[1])) else {
        throw ServerCommandError.invalidCommand
    }
    return .show(segment)
}
