import SwiftUI

/// Sidebar view showing lyric lines.
/// When raw text lines are loaded, shows all lines with stamped ones highlighted.
/// Otherwise shows the standard synced lyric list.
struct LyricListView: View {
    @ObservedObject var viewModel: LyricSyncViewModel
    @State private var editingId: UUID?
    @State private var editingText = ""
    @State private var editingRawIndex: Int? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if viewModel.document.hasImportedText {
                    Text("Lines")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(viewModel.document.nextLineIndex)/\(viewModel.document.rawTextLines.count)")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                } else {
                    Text("Lyrics")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text("\(viewModel.document.lyrics.count) lines")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                if !viewModel.document.lyrics.isEmpty {
                    Button(action: { viewModel.clearAllLyrics() }) {
                        Text("Clear")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .foregroundColor(.red)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Content
            if viewModel.document.hasImportedText {
                importedTextListView
            } else if viewModel.document.lyrics.isEmpty {
                emptyStateView
            } else {
                lyricListView
            }
        }
    }

    // MARK: - Imported Text View (Tap-to-Set mode)

    private var importedTextListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(viewModel.document.rawTextLines.enumerated()), id: \.offset) { index, text in
                        let isStamped = index < viewModel.document.nextLineIndex
                        let isNext = index == viewModel.document.nextLineIndex
                        let stampedLyric = isStamped ? viewModel.document.lyrics.first(where: { $0.text == text }) : nil

                        ImportedLineRow(
                            index: index,
                            text: text,
                            isStamped: isStamped,
                            isNext: isNext,
                            isEditing: editingRawIndex == index,
                            timestamp: stampedLyric?.formattedTimestamp ?? nil,
                            onTap: {
                                if isStamped, let lyric = stampedLyric {
                                    viewModel.selectedLyricId = lyric.id
                                    viewModel.audioEngine.seek(to: lyric.timestamp)
                                }
                            },
                            onDoubleClick: {
                                editingRawIndex = index
                            },
                            onEditCommit: { newText in
                                // Update the raw text line
                                if let idx = editingRawIndex {
                                    viewModel.document.rawTextLines[idx] = newText
                                    // Also update the stamped lyric if it exists
                                    if let lyric = viewModel.document.lyrics.first(where: { $0.text == text }) {
                                        viewModel.document.updateLyric(id: lyric.id, text: newText)
                                    }
                                }
                                editingRawIndex = nil
                            },
                            onDelete: {
                                // Remove the stamped lyric for this line
                                if isStamped, let lyric = stampedLyric {
                                    viewModel.document.removeLyric(id: lyric.id)
                                }
                            }
                        )
                        .id("line-\(index)")
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .onChange(of: viewModel.document.nextLineIndex) { _, newIndex in
                if newIndex < viewModel.document.rawTextLines.count {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo("line-\(newIndex)", anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Standard Lyric List View

    private var lyricListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(viewModel.document.lyrics.enumerated()), id: \.element.id) { index, lyric in
                        LyricRowView(
                            lyric: lyric,
                            index: index,
                            isSelected: lyric.id == viewModel.selectedLyricId,
                            isCurrent: index == viewModel.currentLyricIndex,
                            isEditing: editingId == lyric.id,
                            editingText: $editingText,
                            onSelect: {
                                viewModel.selectedLyricId = lyric.id
                                viewModel.seekToLyric(lyric)
                            },
                            onDoubleClick: {
                                editingId = lyric.id
                                editingText = lyric.text
                            },
                            onEditCommit: {
                                viewModel.document.updateLyric(id: lyric.id, text: editingText)
                                editingId = nil
                                editingText = ""
                            },
                            onDelete: {
                                viewModel.document.removeLyric(id: lyric.id)
                            },
                            onRemoveTiming: {
                                viewModel.document.removeLyric(id: lyric.id)
                                if viewModel.selectedLyricId == lyric.id {
                                    viewModel.selectedLyricId = nil
                                }
                            },
                            onAddAfter: {
                                let nextTime: TimeInterval
                                if index + 1 < viewModel.document.lyrics.count {
                                    let current = lyric.timestamp
                                    let next = viewModel.document.lyrics[index + 1].timestamp
                                    nextTime = (current + next) / 2
                                } else {
                                    nextTime = lyric.timestamp + 2.0
                                }
                                viewModel.addLyric(at: nextTime)
                            },
                            onMoveFrom: { fromIndex in
                                // Drag reorder: will be handled by onDrop
                            }
                        )
                        .id(lyric.id)
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
            .onDrop(of: [.text], isTargeted: nil) { providers, location in
                // Handle drop for reorder
                return handleSidebarDrop(providers: providers, location: location)
            }
            .onChange(of: viewModel.currentLyricIndex) { _, newIndex in
                if let index = newIndex {
                    let lyrics = viewModel.document.lyrics
                    if index < lyrics.count {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo(lyrics[index].id, anchor: .center)
                        }
                    }
                }
            }
            .onChange(of: viewModel.selectedLyricId) { _, newId in
                if let id = newId {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func handleSidebarDrop(providers: [NSItemProvider], location: CGPoint) -> Bool {
        // For now, just return true to accept drops
        return true
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No lyrics yet")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Text("Import a .txt or .lrc file to begin")
                .font(.system(size: 11))
                .foregroundColor(.secondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
    }
}

// MARK: - Imported Line Row

struct ImportedLineRow: View {
    let index: Int
    let text: String
    let isStamped: Bool
    let isNext: Bool
    let isEditing: Bool
    let timestamp: String?
    let onTap: () -> Void
    let onDoubleClick: () -> Void
    let onEditCommit: (String) -> Void
    let onDelete: () -> Void

    @State private var editText: String = ""

    var body: some View {
        HStack(spacing: 6) {
            // Index
            Text(String(format: "%02d", index + 1))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(isNext ? .white : (isStamped ? .secondary.opacity(0.5) : .secondary.opacity(0.4)))
                .frame(width: 22, alignment: .leading)

            // Timestamp (if stamped)
            if let ts = timestamp {
                Text(ts)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isNext ? .white.opacity(0.9) : .secondary.opacity(0.6))
                    .frame(width: 68, alignment: .leading)
            } else {
                Text("--:--.--")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary.opacity(0.3))
                    .frame(width: 68, alignment: .leading)
            }

            // Text (editable)
            if isEditing {
                TextField("Lyric text", text: $editText, onCommit: {
                    onEditCommit(editText)
                })
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit {
                    onEditCommit(editText)
                }
                .onAppear {
                    editText = text
                }
            } else {
                Text(text)
                    .font(.system(size: 12, weight: isNext ? .semibold : .regular))
                    .foregroundColor(isNext ? .white : (isStamped ? .secondary.opacity(0.6) : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Status / action icons
            if !isEditing {
                if isStamped {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red.opacity(0.7))
                    .help("Remove timing")
                } else {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary.opacity(0.4))
                    .help("Remove line")
                    if isNext {
                        Spacer().frame(width: 2)
                    }
                }
                if isNext {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isNext ? 5 : 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(borderColor, lineWidth: isNext ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onTapGesture(count: 2, perform: onDoubleClick)
    }

    private var backgroundFill: Color {
        if isNext {
            return Color.orange.opacity(0.3)
        } else if isStamped {
            return Color.green.opacity(0.08)
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isNext {
            return Color.orange.opacity(0.5)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Standard Lyric Row

struct LyricRowView: View {
    let lyric: LyricLine
    let index: Int
    let isSelected: Bool
    let isCurrent: Bool
    let isEditing: Bool
    @Binding var editingText: String
    let onSelect: () -> Void
    let onDoubleClick: () -> Void
    let onEditCommit: () -> Void
    let onDelete: () -> Void
    let onRemoveTiming: () -> Void
    let onAddAfter: () -> Void
    let onMoveFrom: (Int) -> Void

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(isCurrent ? .white.opacity(0.7) : .secondary.opacity(0.5))
                Text(lyric.formattedTimestamp)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(isCurrent ? .white.opacity(0.9) : (isSelected ? .accentColor : .secondary))
            }
            .frame(width: 68, alignment: .leading)

            if isEditing {
                TextField("Lyric text", text: $editingText, onCommit: onEditCommit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .onSubmit(onEditCommit)
            } else {
                Text(lyric.text.isEmpty ? "…" : lyric.text)
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .white : (lyric.text.isEmpty ? .secondary.opacity(0.5) : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                }
                .buttonStyle(.borderless)
                .foregroundColor(isSelected ? .red.opacity(0.9) : .secondary.opacity(0.4))
                .help(isSelected ? "Delete this line" : "Select then delete")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCurrent ? 5 : 3)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(borderColor, lineWidth: isCurrent ? 1 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onTapGesture(count: 2) { onDoubleClick() }
        .onRightClickGesture { _ in
            onAddAfter()
        }
        .onDrag {
            onMoveFrom(index)
            return NSItemProvider(object: String(index) as NSString)
        }
        .contextMenu {
            Button("Add Line After") {
                onAddAfter()
            }
            Button("Delete") {
                onDelete()
            }
            Divider()
            Button("Seek Here") {
                onSelect()
            }
        }
    }

    private var backgroundFill: Color {
        if isCurrent {
            return Color.accentColor
        } else if isSelected {
            return Color.accentColor.opacity(0.1)
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isCurrent {
            return Color.accentColor.opacity(0.4)
        } else {
            return Color.clear
        }
    }
}

// MARK: - Right-click gesture helper (shared with WaveformView)

extension View {
    func onRightClickGesture(perform action: @escaping (CGPoint) -> Void) -> some View {
        self.background(
            RightClickMonitorView(action: action)
        )
    }
}

struct RightClickMonitorView: NSViewRepresentable {
    let action: (CGPoint) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            let point = view.convert(event.locationInWindow, from: nil)
            DispatchQueue.main.async {
                action(point)
            }
            return event
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
