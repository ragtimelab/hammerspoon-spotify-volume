import Foundation
import SpotifyOSDCore

let arguments = CommandLine.arguments

guard arguments.count == 2 else {
    writeLine("Usage: spotify-osd <0-16> | --server | --version", to: .standardError)
    exit(64)
}

switch arguments[1] {
case "--version":
    writeLine("spotify-osd \(spotifyOSDVersion) protocol=\(spotifyOSDProtocolVersion) build=\(spotifyOSDBuildID)")
    exit(EXIT_SUCCESS)
case "--server":
    guard let server = HUDServer() else {
        writeLine("BUSY")
        exit(75)
    }
    server.run()
default:
    guard let segment = parseSegment(arguments[1]) else {
        writeLine("Usage: spotify-osd <0-16> | --server | --version", to: .standardError)
        exit(64)
    }
    runOneShot(segment: segment)
}
