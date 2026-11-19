import AppKit
import CoreGraphics
import Foundation
import SpotifyOSDCore

@objc protocol OSDUIHelperProtocol {
    func showImage(
        _ image: Int64,
        onDisplayID: UInt32,
        priority: UInt32,
        msecUntilFade: UInt32,
        filledChiclets: UInt32,
        totalChiclets: UInt32,
        locked: Bool
    )
}

private let standardOutput = FileHandle.standardOutput
private let standardError = FileHandle.standardError
private let serverPortName =
    "io.github.ragtimelab.hammerspoon-spotify-volume.osd" as CFString

private let serverPortCallback: CFMessagePortCallBack = { _, _, _, _ in nil }

func writeLine(_ line: String, to handle: FileHandle = standardOutput) {
    guard let data = "\(line)\n".data(using: .utf8) else { return }
    handle.write(data)
}

final class VolumeHUD {
    private let connection: NSXPCConnection
    private let sound: NSSound?

    init() {
        connection = NSXPCConnection(
            machServiceName: "com.apple.OSDUIHelper",
            options: []
        )
        connection.remoteObjectInterface = NSXPCInterface(with: OSDUIHelperProtocol.self)
        connection.interruptionHandler = {
            writeLine("ERR xpc-interrupted OSD connection interrupted", to: standardError)
        }
        connection.invalidationHandler = {
            writeLine("ERR xpc-invalidated OSD connection invalidated", to: standardError)
        }
        connection.resume()

        sound = NSSound(
            contentsOfFile: "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff",
            byReference: true
        )
    }

    func show(segment: Int) {
        let proxy = connection.remoteObjectProxyWithErrorHandler { error in
            writeLine(
                "ERR xpc-proxy \(error.localizedDescription)",
                to: standardError
            )
        } as? OSDUIHelperProtocol

        proxy?.showImage(
            3,
            onDisplayID: CGMainDisplayID(),
            priority: 0x1F4,
            msecUntilFade: 1500,
            filledChiclets: UInt32(segment),
            totalChiclets: 16,
            locked: false
        )

        if segment > 0 {
            sound?.stop()
            sound?.play()
        }
    }

    func invalidate() {
        sound?.stop()
        connection.interruptionHandler = nil
        connection.invalidationHandler = nil
        connection.invalidate()
    }
}

final class HUDServer {
    private let hud: VolumeHUD
    private let singletonPort: CFMessagePort
    private let singletonSource: CFRunLoopSource
    private var framer = LineFramer()
    private var isStopping = false

    init?() {
        var context = CFMessagePortContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        guard let port = CFMessagePortCreateLocal(
            kCFAllocatorDefault,
            serverPortName,
            serverPortCallback,
            &context,
            nil
        ), let source = CFMessagePortCreateRunLoopSource(
            kCFAllocatorDefault,
            port,
            0
        ) else {
            return nil
        }

        singletonPort = port
        singletonSource = source
        hud = VolumeHUD()
        CFRunLoopAddSource(CFRunLoopGetMain(), singletonSource, .defaultMode)
    }

    func run() -> Never {
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            DispatchQueue.main.async {
                guard let self else { return }
                if data.isEmpty {
                    self.stop()
                } else {
                    self.consume(data)
                }
            }
        }

        writeLine("READY \(spotifyOSDProtocolVersion) \(spotifyOSDBuildID)")
        RunLoop.main.run()
        exit(EXIT_SUCCESS)
    }

    private func consume(_ data: Data) {
        for framedLine in framer.append(data) {
            switch framedLine {
            case .invalidUTF8:
                writeLine("ERR invalid-utf8 invalid UTF-8")
            case .line(let line):
                handle(line)
            }
        }
    }

    private func handle(_ line: String) {
        do {
            switch try parseServerCommand(line) {
            case .show(let segment):
                hud.show(segment: segment)
                writeLine("OK \(segment)")
            }
        } catch {
            writeLine("ERR invalid-command expected SHOW <0-16>")
        }
    }

    private func stop() {
        guard !isStopping else { return }
        isStopping = true
        FileHandle.standardInput.readabilityHandler = nil
        hud.invalidate()
        CFRunLoopRemoveSource(CFRunLoopGetMain(), singletonSource, .defaultMode)
        CFMessagePortInvalidate(singletonPort)
        exit(EXIT_SUCCESS)
    }
}

func runOneShot(segment: Int) -> Never {
    let hud = VolumeHUD()
    hud.show(segment: segment)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.5))
    hud.invalidate()
    exit(EXIT_SUCCESS)
}
