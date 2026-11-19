import AppKit
import Foundation
import Darwin
import SpotifyControlCore

// A separate process owns synchronous Apple events. Never run these on the
// Hammerspoon Lua thread. No application launch API is used here.
struct Request: Decodable {
    let id: Int
    let generation: Int
    let pid: Int32
    let operation: String
    let value: Int?
}

func code(_ string: String) -> UInt32 {
    string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
}

func fail(_ message: String, _ number: Int = 1) -> NSError {
    NSError(domain: "SpotifyControl", code: number,
            userInfo: [NSLocalizedDescriptionKey: message])
}

func output(_ object: [String: Any]) {
    do {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try FileHandle.standardOutput.write(contentsOf: data + Data([10]))
    } catch { exit(74) }
}

func volumeEvent(_ pid: Int32, value: Int?) throws -> Int {
    guard let app = NSRunningApplication(processIdentifier: pid),
          app.bundleIdentifier == "com.spotify.client", !app.isTerminated else {
        throw fail("spotify-not-running")
    }
    let property = NSAppleEventDescriptor.record()
    property.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
    property.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
    property.setDescriptor(NSAppleEventDescriptor(typeCode: code("pVol")), forKeyword: code("seld"))
    property.setDescriptor(NSAppleEventDescriptor.null(), forKeyword: code("from"))
    guard let specifier = property.coerce(toDescriptorType: code("obj ")) else { throw fail("property-specifier") }
    let event = NSAppleEventDescriptor(eventClass: code("core"),
        eventID: code(value == nil ? "getd" : "setd"),
        targetDescriptor: NSAppleEventDescriptor(processIdentifier: pid),
        returnID: -1, transactionID: 0)
    event.setParam(specifier, forKeyword: code("----"))
    if let value {
        guard (0...100).contains(value) else { throw fail("invalid-volume") }
        event.setParam(NSAppleEventDescriptor(int32: Int32(value)), forKeyword: code("data"))
    }
    let reply = try event.sendEvent(options: [.waitForReply, .neverInteract], timeout: 120)
    if let error = reply.paramDescriptor(forKeyword: code("errn")), error.int32Value != 0 {
        throw fail(reply.paramDescriptor(forKeyword: code("errs"))?.stringValue ?? "apple-event-error", Int(error.int32Value))
    }
    if let value { return value }
    guard let result = reply.paramDescriptor(forKeyword: code("----")),
          let integer = result.coerce(toDescriptorType: code("long")) else { throw fail("invalid-volume-reply") }
    let volume = Int(integer.int32Value)
    guard (0...100).contains(volume) else { throw fail("invalid-volume-reply") }
    return volume
}

let args = CommandLine.arguments
if args.count == 2 && args[1] == "--version" {
    output(["buildID": compiledBuildID, "protocolVersion": 1]); exit(0)
}
guard args.count == 5, args[1] == "--server", let targetPID = Int32(args[2]),
      let target = NSRunningApplication(processIdentifier: targetPID),
      target.bundleIdentifier == "com.spotify.client" else { exit(64) }
let launchDate = target.launchDate
let statePath = args[3]
guard args[4] == compiledBuildID else { exit(65) }
let buildID = compiledBuildID
var singletonContext = CFMessagePortContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
let singletonCallback: CFMessagePortCallBack = { _, _, _, _ in nil }
guard let singletonPort = CFMessagePortCreateLocal(kCFAllocatorDefault,
    "io.github.ragtimelab.hammerspoon-spotify-volume.control" as CFString,
    singletonCallback, &singletonContext, nil) else {
    output(["busy": true]); exit(75)
}
let stateQueue = DispatchQueue(label: "spotify-control.state")
var pendingSave: DispatchWorkItem?
var dirtySegment: Int?
func flushState() throws {
    pendingSave?.cancel()
    pendingSave = nil
    if let segment = dirtySegment {
        try persistSegment(segment, path: statePath)
        dirtySegment = nil
    }
}
signal(SIGTERM, SIG_IGN)
let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: stateQueue)
termination.setEventHandler {
    do { try flushState(); exit(0) }
    catch { exit(74) }
}
termination.resume()
signal(SIGPIPE, SIG_IGN)
output(["ready": 1, "buildID": buildID, "pid": Int(getpid())])
var buffer = Data()
var lastID = 0
var expectedGeneration: Int?
do {
    while true {
        let chunk = try readPipeChunk(STDIN_FILENO)
        if chunk.isEmpty {
            // Parent reload/exit closes stdin. Persist successful writes even
            // when Lua was torn down before it could send the release barrier.
            try stateQueue.sync { try flushState() }
            break
        }
        buffer.append(chunk)
        guard buffer.count <= 65536 else { throw fail("frame-too-large") }
        while let end = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<end])
            buffer.removeSubrange(...end)
            let request = try JSONDecoder().decode(Request.self, from: line)
            guard request.id > lastID, request.pid == targetPID else { throw fail("invalid-request-identity") }
            if let expectedGeneration {
                guard expectedGeneration == request.generation else { throw fail("invalid-generation") }
            } else { expectedGeneration = request.generation }
            lastID = request.id
            var response: [String: Any] = ["id": request.id, "generation": request.generation]
            do {
                if request.operation == "write" {
                    guard let segment = request.value else { throw fail("missing-segment") }
                    try stateQueue.sync {
                        dirtySegment = segment
                        try flushState()
                    }
                } else {
                    guard let current = NSRunningApplication(processIdentifier: targetPID),
                          current.launchDate == launchDate else { throw fail("spotify-generation-changed") }
                    switch request.operation {
                    case "get": response["value"] = try volumeEvent(targetPID, value: nil)
                    case "set":
                        guard let value = request.value else { throw fail("missing-volume") }
                        response["value"] = try volumeEvent(targetPID, value: value)
                        let segment = (value * 16 + 50) / 100
                        stateQueue.sync {
                            dirtySegment = segment
                            pendingSave?.cancel()
                            let work = DispatchWorkItem {
                                do { try flushState() }
                                catch {
                                    let message = "state-save-failed: \(error)\n"
                                    try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
                                }
                            }
                            pendingSave = work
                            stateQueue.asyncAfter(deadline: .now() + 0.25, execute: work)
                        }
                    default: throw fail("invalid-operation")
                    }
                }
                response["ok"] = true
            } catch {
                response["ok"] = false
                response["error"] = (error as NSError).localizedDescription
                response["code"] = (error as NSError).code
            }
            output(response)
        }
    }
} catch {
    try? stateQueue.sync { try flushState() }
    output(["fatal": (error as NSError).localizedDescription]); exit(65)
}
