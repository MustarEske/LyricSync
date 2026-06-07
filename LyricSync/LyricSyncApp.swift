import SwiftUI

@main
struct LyricSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Audio File…") {
                    // Handled via notification or responder chain
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Lyrics") {
                Button("Add Lyric at Playhead") {
                    // Notification
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Delete Selected Lyric") {
                    // Notification
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Export LRC…") {
                    // Notification
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(after: .undoRedo) {
                Divider()
            }
        }
    }
}
