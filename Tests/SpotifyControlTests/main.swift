import Foundation
import Darwin
import SpotifyControlCore

var descriptors: [Int32] = [0, 0]
guard pipe(&descriptors) == 0 else { exit(1) }
let frame = Array("{}\n".utf8)
_ = frame.withUnsafeBytes { Darwin.write(descriptors[1], $0.baseAddress!, $0.count) }
// Keep the writing end OPEN. A fill-to-length reader would hang until alarm.
alarm(2)
let shortFrame = try readPipeChunk(descriptors[0])
alarm(0)
guard shortFrame == Data(frame) else { exit(1) }
close(descriptors[1])
guard try readPipeChunk(descriptors[0]).isEmpty else { exit(1) }
close(descriptors[0])

let root = FileManager.default.temporaryDirectory.appendingPathComponent("spotify-state-tests-" + UUID().uuidString)
try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
defer { try? FileManager.default.removeItem(at: root) }
let path = root.appendingPathComponent("segment").path
var checks = 2
func check(_ condition: Bool, _ message: String) {
    guard condition else { print("FAIL \(message)"); exit(1) }
    checks += 1
}
for segment in 0...16 {
    try persistSegment(segment, path: path)
    check(try String(contentsOfFile: path, encoding: .utf8) == String(segment), "roundtrip \(segment)")
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    check((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "permissions")
}
do { try persistSegment(17, path: path); check(false, "invalid segment accepted") }
catch { check(try String(contentsOfFile: path, encoding: .utf8) == "16", "invalid preserves state") }
let temporary = path + ".tmp." + String(getpid())
try FileManager.default.createSymbolicLink(atPath: temporary, withDestinationPath: path)
do { try persistSegment(3, path: path); check(false, "temporary symlink accepted") }
catch { check(try String(contentsOfFile: path, encoding: .utf8) == "16", "symlink preserves state") }
try FileManager.default.removeItem(atPath: temporary)
let directory = root.appendingPathComponent("directory").path
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: false)
do { try persistSegment(3, path: directory); check(false, "rename failure ignored") }
catch { check(!FileManager.default.fileExists(atPath: directory + ".tmp." + String(getpid())), "failed rename cleans temporary") }
print("RESULT state-store passed=\(checks) failed=0")
