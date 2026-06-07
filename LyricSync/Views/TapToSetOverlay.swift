import SwiftUI

/// Tap-to-Set key handler — uses a local NSEvent monitor to capture Space
/// regardless of which view is first responder.
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
    private var eventMonitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        setupEventMonitor()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        removeEventMonitor()
    }

    deinit {
        removeEventMonitor()
    }

    private func setupEventMonitor() {
        removeEventMonitor()
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.viewModel?.tapToSetMode == true && event.keyCode == 49 {
                self.viewModel?.tapToSetRecord()
                return nil
            }
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        if viewModel?.tapToSetMode == true {
            viewModel?.tapToSetRecord()
        } else {
            super.mouseDown(with: event)
        }
    }
}

/// HUD overlay shown when tap-to-set mode is active.
/// Shows the next line to stamp, progress, and current time.
struct TapToSetHUD: View {
    @ObservedObject var viewModel: LyricSyncViewModel

    var body: some View {
        HStack(spacing: 16) {
            // ── Status + next line ──
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "hand.tap.fill")
                        .foregroundColor(.orange)
                        .font(.title3)
                    Text("Tap-to-Set Mode")
                        .font(.headline)
                }

                if viewModel.document.hasImportedText {
                    let nextIdx = viewModel.document.nextLineIndex
                    let total = viewModel.document.rawTextLines.count
                    if nextIdx < total {
                        Text("Line \(nextIdx + 1) of \(total)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(viewModel.document.rawTextLines[nextIdx])
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .frame(maxWidth: 280, alignment: .leading)
                    } else {
                        Text("All \(total) lines stamped!")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.green)
                    }
                } else {
                    Text("Press Space to drop a marker")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(minWidth: 160, alignment: .leading)

            Divider().frame(height: 50)

            // ── Live time ──
            VStack(alignment: .center, spacing: 2) {
                Text("Time")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(formatTime(viewModel.audioEngine.currentTime))
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundColor(.orange)
            }
            .frame(width: 90)

            Divider().frame(height: 50)

            // ── Progress ──
            VStack(alignment: .center, spacing: 2) {
                Text("Stamped")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                if viewModel.document.hasImportedText {
                    Text("\(viewModel.document.nextLineIndex) / \(viewModel.document.rawTextLines.count)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                    // Progress bar
                    ProgressView(value: Double(viewModel.document.nextLineIndex), total: Double(max(1, viewModel.document.rawTextLines.count)))
                        .progressViewStyle(.linear)
                        .frame(width: 60)
                } else {
                    Text("\(viewModel.tapToSetCount)")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.primary)
                }
            }
            .frame(width: 80)

            Divider().frame(height: 50)

            // ── Actions ──
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
