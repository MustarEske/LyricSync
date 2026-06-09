import SwiftUI

/// Waveform canvas — optimized for performance.
struct WaveformView: View {
    @ObservedObject var viewModel: LyricSyncViewModel

    @State private var dragLyricId: UUID?
    @State private var dragOffsetX: CGFloat = 0
    @State private var isDraggingPlayhead = false
    @State private var dragPlayheadX: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Canvas uses drawingGroup() for GPU-accelerated rendering
                // The waveform path is cached; only overlays change during drag
                Canvas { context, size in
                    let width = size.width
                    let height = size.height
                    let duration = viewModel.document.duration

                    guard duration > 0 else {
                        let emptyText = Text("Open an audio file to begin")
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                        context.draw(emptyText, at: CGPoint(x: width / 2, y: height / 2), anchor: .center)
                        return
                    }

                    // ── Background ──
                    context.fill(
                        Path(CGRect(origin: .zero, size: size)),
                        with: .color(Color(NSColor.controlBackgroundColor))
                    )

                    // ── Waveform (single path) ──
                    drawWaveform(context: context, width: width, height: height)

                    // ── Time grid ──
                    drawTimeGrid(context: context, width: width, height: height, duration: duration)

                    // ── Lyric markers ──
                    let lyrics = viewModel.document.lyrics
                    for lyric in lyrics {
                        var x = CGFloat(lyric.timestamp / duration) * width
                        if lyric.id == dragLyricId {
                            x += dragOffsetX
                        }

                        let isSelected = lyric.id == viewModel.selectedLyricId
                        let lineColor = isSelected ? Color.yellow : Color.red.opacity(0.8)

                        context.stroke(
                            Path { path in
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: height))
                            },
                            with: .color(lineColor),
                            lineWidth: isSelected ? 2 : 1
                        )

                        let triSize: CGFloat = 7
                        context.fill(
                            Path { path in
                                path.move(to: CGPoint(x: x - triSize, y: 0))
                                path.addLine(to: CGPoint(x: x + triSize, y: 0))
                                path.addLine(to: CGPoint(x: x, y: triSize * 1.5))
                                path.closeSubpath()
                            },
                            with: .color(lineColor)
                        )

                        let text = Text(lyric.formattedTimestamp)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(isSelected ? .yellow : .secondary)
                        context.draw(text, at: CGPoint(x: x + 2, y: triSize * 1.8), anchor: .leading)
                    }

                    // ── Playhead ──
                    var playheadX = CGFloat(viewModel.audioEngine.currentTime / duration) * width
                    if isDraggingPlayhead {
                        playheadX = dragPlayheadX
                    }

                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: playheadX, y: 0))
                            path.addLine(to: CGPoint(x: playheadX, y: height))
                        },
                        with: .color(.accentColor.opacity(0.2)),
                        lineWidth: isDraggingPlayhead ? 12 : 8
                    )

                    context.stroke(
                        Path { path in
                            path.move(to: CGPoint(x: playheadX, y: 0))
                            path.addLine(to: CGPoint(x: playheadX, y: height))
                        },
                        with: .color(.accentColor),
                        lineWidth: isDraggingPlayhead ? 3 : 2
                    )

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
                .drawingGroup()  // GPU-accelerated rendering for the Canvas

                // Transparent overlay for gesture handling — Canvas swallows gestures
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                handleDragChanged(value: value, geometry: geometry)
                            }
                            .onEnded { value in
                                handleDragEnded(value: value, geometry: geometry)
                            }
                    )
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded { _ in }
                    )
                    .onTapGesture { location in
                        handleTap(at: location, geometry: geometry)
                    }
                    .contextMenu {
                        Button("Remove Timing") {
                            if let id = viewModel.selectedLyricId {
                                viewModel.document.removeLyric(id: id)
                                viewModel.selectedLyricId = nil
                            }
                        }
                        Button("Seek Here") {
                            if let id = viewModel.selectedLyricId,
                               let lyric = viewModel.document.lyrics.first(where: { $0.id == id }) {
                                viewModel.audioEngine.seek(to: lyric.timestamp)
                            }
                        }
                    }
            }
            .clipped()
        }
    }

    // MARK: - Drawing (optimized)

    private func drawWaveform(context: GraphicsContext, width: CGFloat, height: CGFloat) {
        let data = viewModel.document.waveformData
        guard !data.isEmpty else { return }

        let midY = height / 2
        let step = width / CGFloat(data.count)
        let waveColor = Color.accentColor.opacity(0.5)

        // Draw as a smooth filled area path (mirrored around center)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: midY))

        // Top edge (positive amplitudes)
        for (i, amplitude) in data.enumerated() {
            let x = CGFloat(i) * step
            let barHeight = CGFloat(amplitude) * (height * 0.75)
            path.addLine(to: CGPoint(x: x, y: midY - barHeight / 2))
        }

        // Right edge down to center
        path.addLine(to: CGPoint(x: width, y: midY))

        // Bottom edge (negative amplitudes, mirrored)
        for i in stride(from: data.count - 1, through: 0, by: -1) {
            let x = CGFloat(i) * step
            let barHeight = CGFloat(data[i]) * (height * 0.75)
            path.addLine(to: CGPoint(x: x, y: midY + barHeight / 2))
        }

        path.closeSubpath()
        context.fill(path, with: .color(waveColor))
    }

    private func drawTimeGrid(context: GraphicsContext, width: CGFloat, height: CGFloat, duration: TimeInterval) {
        let interval: TimeInterval = duration > 300 ? 30 : duration > 60 ? 10 : 5
        let textColor = Color.secondary.opacity(0.6)

        var t: TimeInterval = 0
        while t <= duration {
            let x = CGFloat(t / duration) * width

            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: height - 18))
                    path.addLine(to: CGPoint(x: x, y: height))
                },
                with: .color(textColor),
                lineWidth: 0.5
            )

            let minutes = Int(t) / 60
            let seconds = Int(t) % 60
            let label = Text(String(format: "%d:%02d", minutes, seconds))
                .font(.system(size: 8, design: .monospaced))
                .foregroundColor(textColor)
            context.draw(label, at: CGPoint(x: x + 2, y: height - 2), anchor: .topLeading)

            t += interval
        }
    }

    // MARK: - Interaction

    private func handleTap(at location: CGPoint, geometry: GeometryProxy) {
        let duration = viewModel.document.duration
        guard duration > 0 else { return }

        let playheadX = CGFloat(viewModel.audioEngine.currentTime / duration) * geometry.size.width

        // If tapped near the playhead, seek to tap position
        if abs(location.x - playheadX) < 15 {
            let time = Double(location.x / geometry.size.width) * duration
            viewModel.audioEngine.seek(to: max(0, min(time, duration)))
            return
        }

        let time = Double(location.x / geometry.size.width) * duration

        // Check if tapped near existing lyric marker
        for lyric in viewModel.document.lyrics {
            let x = CGFloat(lyric.timestamp / duration) * geometry.size.width
            if abs(location.x - x) < 20 {
                viewModel.selectedLyricId = lyric.id
                viewModel.audioEngine.seek(to: lyric.timestamp)
                return
            }
        }

        viewModel.addLyric(at: time)
    }

    private func handleDragChanged(value: DragGesture.Value, geometry: GeometryProxy) {
        let duration = viewModel.document.duration
        guard duration > 0 else { return }

        // First check if we're dragging a lyric marker (takes priority over playhead)
        if dragLyricId == nil {
            let lyricThreshold: CGFloat = 20  // wider hit area
            for lyric in viewModel.document.lyrics {
                let x = CGFloat(lyric.timestamp / duration) * geometry.size.width
                if abs(value.startLocation.x - x) < lyricThreshold {
                    dragLyricId = lyric.id
                    viewModel.selectedLyricId = lyric.id
                    viewModel.beginDragLyric(id: lyric.id)
                    break
                }
            }
        }

        if dragLyricId != nil {
            dragOffsetX = value.location.x - value.startLocation.x
            return
        }

        // Then check if we're dragging the playhead
        let playheadX = CGFloat(viewModel.audioEngine.currentTime / duration) * geometry.size.width
        if !isDraggingPlayhead && abs(value.startLocation.x - playheadX) < 15 {
            isDraggingPlayhead = true
            dragPlayheadX = playheadX
        }

        if isDraggingPlayhead {
            dragPlayheadX = max(0, min(value.location.x, geometry.size.width))
            let time = Double(dragPlayheadX / geometry.size.width) * duration
            viewModel.audioEngine.seek(to: max(0, min(time, duration)))
        }
    }

    private func handleDragEnded(value: DragGesture.Value, geometry: GeometryProxy) {
        let duration = viewModel.document.duration

        if isDraggingPlayhead {
            if duration > 0 {
                let time = Double(dragPlayheadX / geometry.size.width) * duration
                viewModel.audioEngine.seek(to: max(0, min(time, duration)))
            }
            isDraggingPlayhead = false
            return
        }

        if let id = dragLyricId, duration > 0 {
            let totalOffset = value.location.x - value.startLocation.x
            if let lyric = viewModel.document.lyrics.first(where: { $0.id == id }) {
                let originalX = CGFloat(lyric.timestamp / duration) * geometry.size.width
                let finalX = originalX + totalOffset
                let time = Double(finalX / geometry.size.width) * duration
                viewModel.endDragLyric(id: id, to: max(0, min(time, duration)))
            }
        }
        dragLyricId = nil
        dragOffsetX = 0
    }
}
