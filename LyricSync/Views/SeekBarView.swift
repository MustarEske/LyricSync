import SwiftUI

/// A horizontal seek bar that shows the playhead position and allows
/// clicking / dragging anywhere to jump to that timestamp.
struct SeekBarView: View {
    @ObservedObject var viewModel: LyricSyncViewModel

    @State private var isDragging = false
    @State private var dragFraction: CGFloat = 0

    private var fraction: CGFloat {
        let duration = viewModel.document.duration
        guard duration > 0 else { return 0 }
        if isDragging { return dragFraction }
        return CGFloat(viewModel.audioEngine.currentTime / duration)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(Color(NSColor.separatorColor).opacity(0.3))

                // Filled portion (played)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: geometry.size.width * fraction)

                // Playhead knob
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                    .offset(x: geometry.size.width * fraction - 5)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        dragFraction = max(0, min(1, value.location.x / geometry.size.width))
                    }
                    .onEnded { value in
                        let frac = max(0, min(1, value.location.x / geometry.size.width))
                        let duration = viewModel.document.duration
                        if duration > 0 {
                            viewModel.audioEngine.seek(to: Double(frac) * duration)
                        }
                        isDragging = false
                    }
            )
            .onTapGesture { location in
                let frac = max(0, min(1, location.x / geometry.size.width))
                let duration = viewModel.document.duration
                if duration > 0 {
                    viewModel.audioEngine.seek(to: Double(frac) * duration)
                }
            }
        }
    }
}
