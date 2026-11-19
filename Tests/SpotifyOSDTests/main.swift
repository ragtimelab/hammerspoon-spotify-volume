import Foundation
import SpotifyOSDCore

private var passed = 0
private var failed = 0

private func check(_ condition: @autoclosure () throws -> Bool, _ name: String) {
    do {
        if try condition() {
            passed += 1
            print("PASS \(name)")
        } else {
            failed += 1
            print("FAIL \(name)")
        }
    } catch {
        failed += 1
        print("FAIL \(name): \(error)")
    }
}

for segment in 0...16 {
    check(
        try parseServerCommand("SHOW \(segment)") == .show(segment),
        "parse SHOW \(segment)"
    )
    check(parseSegment(String(segment)) == segment, "parse segment \(segment)")
}

for command in ["SHOW -1", "SHOW 17", "SHOW", "HIDE 1", "SHOW x"] {
    var rejected = false
    do {
        _ = try parseServerCommand(command)
    } catch {
        rejected = true
    }
    check(rejected, "reject \(command)")
}

var framer = LineFramer()
check(framer.append(Data("SH".utf8)).isEmpty, "buffer partial frame")
check(
    framer.append(Data("OW 1\nSHOW 2\r\npartial".utf8))
        == [.line("SHOW 1"), .line("SHOW 2")],
    "frame multiple lines"
)
check(
    framer.append(Data(" line\n".utf8)) == [.line("partial line")],
    "complete buffered frame"
)

var invalidFramer = LineFramer()
check(
    invalidFramer.append(Data([0xFF, 0x0A])) == [.invalidUTF8],
    "report invalid UTF-8"
)
check(!spotifyOSDVersion.isEmpty, "program version")
check(spotifyOSDProtocolVersion == 1, "protocol version")

print("RESULT passed=\(passed) failed=\(failed)")
if failed > 0 {
    exit(EXIT_FAILURE)
}
