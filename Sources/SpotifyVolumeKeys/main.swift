import AppKit

struct Binding: Codable {
    let modifiers: [String]
    let keyCode: UInt16
    let label: String
}

struct Selection: Codable {
    let down: Binding
    let up: Binding
}

struct Retry: Decodable {
    let selection: Selection
    let direction: String
}

let functionKeys: [UInt16: String] = [
    122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
    98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
    80: "F19", 90: "F20",
]

@MainActor
func capture(_ action: String, distinctFrom: Binding?) -> Binding? {
    let alert = NSAlert()
    alert.messageText = "Set the Spotify volume \(action) shortcut"
    alert.informativeText = "Press a function key or a combination with Command, Option, Control, or Shift."
    let useButton = alert.addButton(withTitle: "Use Shortcut")
    useButton.keyEquivalent = ""
    useButton.isEnabled = false
    alert.addButton(withTitle: "Cancel")
    var candidate: Binding?
    let token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
        guard event.window === alert.window, event.keyCode != 53 else { return event }
        let names: [(NSEvent.ModifierFlags, String)] = [
            (.control, "ctrl"), (.option, "alt"), (.shift, "shift"), (.command, "cmd"),
        ]
        let modifiers = names.compactMap { event.modifierFlags.contains($0.0) ? $0.1 : nil }
        let functionKey = functionKeys[event.keyCode]
        if modifiers.isEmpty && functionKey == nil {
            candidate = nil
            useButton.isEnabled = false
            alert.informativeText = "Choose a function key or add a modifier."
            return nil
        }
        if let distinctFrom, distinctFrom.keyCode == event.keyCode && distinctFrom.modifiers == modifiers {
            candidate = nil
            useButton.isEnabled = false
            alert.informativeText = "That shortcut is already selected for the other direction. Choose a different shortcut."
            return nil
        }
        let characters = event.charactersIgnoringModifiers ?? ""
        let key = functionKey ?? (characters.count == 1 && characters.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || CharacterSet.punctuationCharacters.contains($0)
        } ? characters.uppercased() : "Key code \(event.keyCode)")
        let label = (modifiers + [key]).joined(separator: " + ")
        candidate = Binding(modifiers: modifiers, keyCode: event.keyCode, label: label)
        alert.informativeText = label
        useButton.isEnabled = true
        return nil
    }
    defer { if let token { NSEvent.removeMonitor(token) } }
    return alert.runModal() == .alertFirstButtonReturn ? candidate : nil
}

try MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    if #available(macOS 14.0, *) { app.activate() }
    else { app.activate(ignoringOtherApps: true) }
    let retry = try CommandLine.arguments.dropFirst().first.map { argument in
        try JSONDecoder().decode(Retry.self, from: Data(argument.utf8))
    }
    let selection: Selection
    if let retry, retry.direction == "down" {
        guard let down = capture("down", distinctFrom: retry.selection.up) else { exit(2) }
        selection = Selection(down: down, up: retry.selection.up)
    } else if let retry, retry.direction == "up" {
        guard let up = capture("up", distinctFrom: retry.selection.down) else { exit(2) }
        selection = Selection(down: retry.selection.down, up: up)
    } else {
        guard let down = capture("down", distinctFrom: nil),
              let up = capture("up", distinctFrom: down) else { exit(2) }
        selection = Selection(down: down, up: up)
    }
    let data = try JSONEncoder().encode(selection)
    try FileHandle.standardOutput.write(contentsOf: data)
}
