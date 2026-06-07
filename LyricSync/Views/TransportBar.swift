import SwiftUI

/// Transport bar with playback controls and time display
struct TransportBar: View {
    @ObservedObject var viewModel: LyricSyncViewModel

    var body: some View {
        HStack(spacing: 16) {
            // File info
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.document.fileName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if viewModel.document.duration > 0 {
                    Text(formatDuration(viewModel.document.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 200, alignment: .leading)

            Spacer()

            // Playback controls
            HStack(spacing: 12) {
                // Skip back
                Button(action: { viewModel.audioEngine.seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.document.hasFile)

                // Play/Pause
                Button(action: { viewModel.togglePlayback() }) {
                    Image(systemName: viewModel.audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.document.hasFile)

                // Stop
                Button(action: { viewModel.audioEngine.stop() }) {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .disabled(!viewModel.document.hasFile)
            }

            // Current time display
            Text(formatTime(viewModel.audioEngine.currentTime))
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .frame(width: 80)

            Spacer()

            // Add lyric button
            Button(action: { viewModel.addLyricAtCurrentTime() }) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Lyric")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!viewModel.document.hasFile)
            .keyboardShortcut("n", modifiers: .command)

            // Tap-to-Set mode toggle
            Button(action: { viewModel.toggleTapToSetMode() }) {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.tapToSetMode ? "hand.tap.fill" : "hand.tap")
                    Text(viewModel.tapToSetMode ? "Tap-Set ON" : "Tap to Set")
                }
            }
            .buttonStyle(.bordered)
            .tint(viewModel.tapToSetMode ? .orange : .secondary)
            .disabled(!viewModel.document.hasFile)

            // Import/Export
            Menu {
                Button("Import LRC…", action: viewModel.importLRC)
                Divider()
                Button("Export LRC…", action: viewModel.exportLRC)
                Button("Export Plain Text…", action: viewModel.exportPlainText)
                Divider()
                Button("Embed Lyrics in File…", action: viewModel.embedLyrics)
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
