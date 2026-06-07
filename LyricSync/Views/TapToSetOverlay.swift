import SwiftUI

/// An NSViewRepresentable that captures Space bar presses for tap-to-set mode
struct TapToSetKeyHandler: NSViewRepresentable {
    @ObservedObject var viewModel: LyricSyncViewModel

    func makeNSView(context: Context) -> TapToSetNSView {
        let view = TapToSetNSView()
        view.viewModel = viewModel
        return view
    }

    func updateNSView(_ nsView: TapToSetNSView, context: Context) {
        nsView.viewModel = viewModel
    }
}

class TapToSetNSView: NSView {
    weak var viewModel: LyricSyncViewModel?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Space bar
            viewModel?.tapToSetRecord()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        // Only handle clicks when in tap-to-set mode
        if viewModel?.tapToSetMode == true {
            viewModel?.tapToSetRecord()
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// HUD overlay shown when tap-to-set mode is active
struct TapToSetHUD: View {
    @ObservedObject var viewModel: LyricSyncViewModel

    var body: some View {
        HStack(spacing: 20) {
            // Status indicator
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill")
                    .foregroundColor(.orange)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Tap-to-Set Mode")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Press Space or click anywhere to drop a marker at the playhead")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()
                .frame(height: 40)

            // Live time display
            VStack(alignment: .center, spacing: 2) {
                Text("Current Time")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatTime(viewModel.audioEngine.currentTime))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .frame(width: 100)

            Divider()
                .frame(height: 40)

            // Marker count
            VStack(alignment: .center, spacing: 2) {
                Text("Markers")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("\(viewModel.tapToSetCount)")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
            }
            .frame(width: 60)

            Divider()
                .frame(height: 40)

            // Actions
            VStack(spacing: 4) {
                Button("Done") {
                    viewModel.toggleTapToSetMode()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button("Clear All") {
                    viewModel.clearAllLyrics()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        )
        .padding(.top, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
}
