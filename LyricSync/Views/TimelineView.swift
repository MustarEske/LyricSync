import SwiftUI

/// A custom Canvas-based timeline view showing waveform, playhead, and lyric markers
struct TimelineView: View {
    @ObservedObject var viewModel: LyricSyncViewModel
    @State private var dragLyricId: UUID?
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let width = size.width
                let height = size.height
                let midY = height / 2
                let duration = viewModel.document.duration

                guard duration > 0 else { return }

                // ── Background ──
                context.fill(
                    Path(CGRect(origin: .zero, size: size)),
                    with: .color(Color(NSColor.controlBackgroundColor))
                )

                // ── Waveform ──
                drawWaveform(context: context, width: width, height: height, midY: midY)

                // ── Time grid lines ──
                drawTimeGrid(context: context, width: width, height: height, duration: duration)

                // ── Lyric markers ──
                for lyric in viewModel.document.lyrics {
                    let x = CGFloat(lyric.timestamp / duration) * width
                    let isSelected = lyric.id == viewModel.selectedLyricId

                    // Marker line
                    let lineColor = isSelected ? Color.yellow : Color.red
                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: height))
                        },
                        with: .color(lineColor),
                        lineWidth: isSelected ? 2 : 1
                    )

                    // Marker triangle at top
                    let triSize: CGFloat = 8
                    context.fill(
                        Path { path in
                            path.move(to: CGPoint(x: x - triSize, y: 0))
                            path.addLine(to: CGPoint(x: x + triSize, y: 0))
                            path.addLine(to: CGPoint(x: x, y: triSize * 1.5))
                            path.closeSubpath()
                        },
                        with: .color(lineColor)
                    )

                    // Timestamp label
                    let text = Text(lyric.formattedTimestamp)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(isSelected ? .yellow : .secondary)
                    context.draw(text, at: CGPoint(x: x + 2, y: triSize * 1.8), anchor: .leading)
                }

                // ── Playhead ──
                let playheadX = CGFloat(viewModel.audioEngine.currentTime / duration) * width

                // Playhead glow
                let glowPath = Path { path in
                    path.move(to: CGPoint(x: playheadX, y: 0))
                    path.addLine(to: CGPoint(x: playheadX, y: height))
                }
                context.stroke(glowPath, with: .color(.accentColor.opacity(0.3)), lineWidth: 6)

                // Playhead line
                context.stroke(
                    Path { path in
                        path.move(to: CGPoint(x: playheadX, y: 0))
                        path.addLine(to: CGPoint(x: playheadX, y: height))
                    },
                    with: .color(.accentColor),
                    lineWidth: 2
                )

                // Playhead triangle
                context.fill(
                    Path { path in
                        path.move(to: CGPoint(x: playheadX - 6, y: 0))
                        path.addLine(to: CGPoint(x: playheadX + 6, y: 0))
                        path.addLine(to: CGPoint(x: playheadX, y: 10))
                        path.closeSubpath()
                    },
                    with: .color(.accentColor)
                )
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        handleDragChanged(value: value, geometry: geometry)
                    }
                    .onEnded { value in
                        handleDragEnded(value: value, geometry: geometry)
                    }
            )
            .onTapGesture { location in
                handleTap(at: location, geometry: geometry)
            }
        }
    }

    // MARK: - Drawing

    private func drawWaveform(context: GraphicsContext, width: CGFloat, height: CGFloat, midY: CGFloat) {
        let data = viewModel.document.waveformData
        guard !data.isEmpty else { return }

        let step = width / CGFloat(data.count)
        let waveColor = Color.accentColor.opacity(0.6)

        var path = Path()
        for (i, amplitude) in data.enumerated() {
            let x = CGFloat(i) * step
            let barHeight = CGFloat(amplitude) * (height * 0.8)
            path.addRect(CGRect(
                x: x,
                y: midY - barHeight / 2,
                width: max(step - 0.5, 0.5),
                height: barHeight
            ))
        }
        context.fill(path, with: .color(waveColor))
    }

    private func drawTimeGrid(context: GraphicsContext, width: CGFloat, height: CGFloat, duration: TimeInterval) {
        let interval: TimeInterval = duration > 300 ? 30 : duration > 60 ? 10 : 5
        let textColor = Color.secondary.opacity(0.7)

        var t: TimeInterval = 0
        while t <= duration {
            let x = CGFloat(t / duration) * width

            // Grid line
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: height - 20))
                    path.addLine(to: CGPoint(x: x, y: height))
                },
                with: .color(textColor),
                lineWidth: 0.5
            )

            // Time label
            let minutes = Int(t) / 60
            let seconds = Int(t) % 60
            let label = Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(textColor)
            context.draw(label, at: CGPoint(x: x + 2, y: height - 2), anchor: .topLeading)

            t += interval
        }
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint, geometry: GeometryProxy) {
        let duration = viewModel.document.duration
        guard duration > 0 else { return }

        let time = Double(location.x / geometry.size.width) * duration

        // Check if we tapped near an existing marker
        let threshold: CGFloat = 8
        for lyric in viewModel.document.lyrics {
            let x = CGFloat(lyric.timestamp / duration) * geometry.size.width
            if abs(location.x - x) < threshold {
                viewModel.selectedLyricId = lyric.id
                viewModel.audioEngine.seek(to: lyric.timestamp)
                return
            }
        }

        // Otherwise add a new lyric
        viewModel.addLyric(at: time)
    }

    private func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy) {
        let duration = viewModel.document.duration
        guard duration > 0 else { return }

        if dragLyricId == nil {
            let threshold: CGFloat = 8
            for lyric in viewModel.document.lyrics {
                let x = CGFloat(lyric.timestamp / duration) * geometry.size.width
                if abs(value.startLocation.x - x) < threshold {
                    dragLyricId = lyric.id
                    viewModel.selectedLyricId = lyric.id
                    viewModel.beginDragLyric(id: lyric.id)
                    break
                }
            }
        }

        if let id = dragLyricId {
            let time = Double(value.location.x / geometry.size.width) * duration
            viewModel.moveLyric(id: id, to: max(0, min(time, duration)))
        }
    }

    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        let duration = viewModel.document.duration
        if let id = dragLyricId, duration > 0 {
            let time = Double(value.location.x / geometry.size.width) * duration
            viewModel.endDragLyric(id: id, to: max(0, min(time, duration)))
        }
        dragLyricId = nil
    }
}
