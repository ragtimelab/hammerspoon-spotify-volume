// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "HammerspoonSpotifyVolume",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "spotify-control", targets: ["SpotifyControl"]),
        .executable(name: "spotify-control-tests", targets: ["SpotifyControlTests"]),
        .executable(name: "spotify-osd", targets: ["SpotifyOSD"]),
        .executable(name: "spotify-volume-keys", targets: ["SpotifyVolumeKeys"]),
        .executable(
            name: "spotify-osd-protocol-tests",
            targets: ["SpotifyOSDProtocolTests"]
        ),
    ],
    targets: [
        .target(name: "BuildIdentity"),
        .target(name: "SpotifyControlCore"),
        .executableTarget(name: "SpotifyControl", dependencies: ["BuildIdentity", "SpotifyControlCore"]),
        .executableTarget(name: "SpotifyControlTests", dependencies: ["SpotifyControlCore"], path: "Tests/SpotifyControlTests"),
        .target(name: "SpotifyOSDCore", dependencies: ["BuildIdentity"]),
        .executableTarget(name: "SpotifyVolumeKeys"),
        .executableTarget(name: "SpotifyOSD", dependencies: ["SpotifyOSDCore"]),
        .executableTarget(
            name: "SpotifyOSDProtocolTests",
            dependencies: ["SpotifyOSDCore"],
            path: "Tests/SpotifyOSDTests"
        ),
    ]
)
