import SwiftUI

@main
struct LyricSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(appDelegate.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Audio File…") {
                    NotificationCenter.default.post(name: .openAudioFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
            }

            CommandMenu("Lyrics") {
                Button("Add Lyric at Playhead") {
                    NotificationCenter.default.post(name: .addLyricAtPlayhead, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("Delete Selected Lyric") {
                    NotificationCenter.default.post(name: .deleteSelectedLyric, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [])

                Divider()

                Button("Export LRC…") {
                    NotificationCenter.default.post(name: .exportLRC, object: nil)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(after: .undoRedo) {
                Divider()
            }
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let openAudioFile = Notification.Name("openAudioFile")
    static let addLyricAtPlayhead = Notification.Name("addLyricAtPlayhead")
    static let deleteSelectedLyric = Notification.Name("deleteSelectedLyric")
    static let exportLRC = Notification.Name("exportLRC")
    static let toggleAppearance = Notification.Name("toggleAppearance")
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var colorScheme: ColorScheme? = nil

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: .toggleAppearance,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            switch self.colorScheme {
            case nil:
                self.colorScheme = .dark
            case .dark:
                self.colorScheme = .light
            case .light:
                self.colorScheme = nil
            default:
                self.colorScheme = nil
            }
            // Force window refresh
            for window in NSApp.windows {
                window.contentView?.needsDisplay = true
            }
        }
    }
}
