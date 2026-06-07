import SwiftUI

/// Compact transport bar with a single play/pause toggle button.
struct TransportBar: View {
    @ObservedObject var viewModel: LyricSyncViewModel

    var body: some View {
        HStack(spacing: 10) {
            // ── File info ──
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.document.fileName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if viewModel.document.duration > 0 {
                    Text(formatDuration(viewModel.document.duration))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: 160, alignment: .leading)

            Spacer()

            // ── Single play/pause button ──
            Button(action: { viewModel.togglePlayback() }) {
                Image(systemName: viewModel.audioEngine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)
            }
            .buttonStyle(.borderless)
            .disabled(!viewModel.document.hasFile)
            .keyboardShortcut(" ", modifiers: [])

            // ── Time display ──
            Text(formatTime(viewModel.audioEngine.currentTime))
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 70)

            Spacer()

            // ── Action buttons ──
            Button(action: { viewModel.addLyricAtCurrentTime() }) {
                HStack(spacing: 3) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!viewModel.document.hasFile)
            .keyboardShortcut("n", modifiers: .command)

            Button(action: { viewModel.toggleTapToSetMode() }) {
                HStack(spacing: 3) {
                    Image(systemName: viewModel.tapToSetMode ? "hand.tap.fill" : "hand.tap")
                    Text(viewModel.tapToSetMode ? "ON" : "Tap")
                }
                .font(.system(size: 11))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(viewModel.tapToSetMode ? .orange : .secondary)
            .disabled(!viewModel.document.hasFile)

            Menu {
                Button("Import LRC…", action: viewModel.importLRC)
                Divider()
                Button("Export LRC…", action: viewModel.exportLRC)
                Button("Export Text…", action: viewModel.exportPlainText)
                Divider()
                Button("Embed in File…", action: viewModel.embedLyrics)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 30)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
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
