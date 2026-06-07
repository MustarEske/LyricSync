import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = LyricSyncViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // ── Toolbar area ──
            toolbar

            Divider()

            // ── Main area ──
            HStack(spacing: 0) {
                // Timeline + Transport
                VStack(spacing: 0) {
                    // Timeline
                    TimelineView(viewModel: viewModel)
                        .frame(height: 180)
                        .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    // Transport bar
                    TransportBar(viewModel: viewModel)
                }

                Divider()

                // Lyric list sidebar
                LyricListView(viewModel: viewModel)
                    .frame(width: 320)
            }

            // ── Status bar ──
            statusBar
        }
        .frame(minWidth: 900, minHeight: 500)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Ensure window can receive key events
        }
        .background(
            // Invisible key capture for tap-to-set
            TapToSetKeyHandler(viewModel: viewModel)
        )
        .overlay(alignment: .top) {
            if viewModel.tapToSetMode {
                TapToSetHUD(viewModel: viewModel)
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Label("LyricSync", systemImage: "music.note")
                .font(.headline)

            Spacer()

            Button(action: viewModel.openAudioFile) {
                Label("Open Audio", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)

            if viewModel.document.hasFile {
                Button(action: viewModel.importLRC) {
                    Label("Import LRC", systemImage: "doc.text")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading audio…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if viewModel.document.hasFile {
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
                Text(viewModel.document.fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                Text("\(viewModel.document.lyrics.count) lyrics")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("Open an audio file to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

