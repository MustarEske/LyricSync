import SwiftUI

/// Sidebar view showing all lyric lines in a list
struct LyricListView: View {
    @ObservedObject var viewModel: LyricSyncViewModel
    @State private var editingId: UUID?
    @State private var editingText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Lyrics")
                    .font(.headline)
                Spacer()
                Text("\(viewModel.document.lyrics.count) lines")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Lyric list
            if viewModel.document.lyrics.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "music.note.list")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No lyrics yet")
                        .foregroundColor(.secondary)
                    Text("Click the timeline or press ⌘N to add")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
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
                                    }
                                )
                                .id(lyric.id)
                            }
                        }
                        .padding(4)
                    }
                    // Auto-scroll to current lyric during playback
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
                    // Also scroll when user manually selects a lyric
                    .onChange(of: viewModel.selectedLyricId) { _, newId in
                        if let id = newId {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                proxy.scrollTo(id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// A single row in the lyric list
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

    var body: some View {
        HStack(spacing: 6) {
            // Timestamp button
            Text(lyric.formattedTimestamp)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(isCurrent ? .white : (isSelected ? .accentColor : .secondary))
                .frame(width: 70, alignment: .leading)

            // Lyric text (editable)
            if isEditing {
                TextField("Lyric text", text: $editingText, onCommit: onEditCommit)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .onSubmit(onEditCommit)
            } else {
                Text(lyric.text.isEmpty ? "..." : lyric.text)
                    .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .white : (lyric.text.isEmpty ? .secondary : .primary))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Delete button (visible on selection)
            if isSelected && !isEditing {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, isCurrent ? 6 : 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: isCurrent ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onTapGesture(count: 2) {
            onDoubleClick()
        }
    }

    private var backgroundFill: Color {
        if isCurrent {
            return Color.accentColor
        } else if isSelected {
            return Color.accentColor.opacity(0.15)
        } else {
            return Color.clear
        }
    }

    private var borderColor: Color {
        if isCurrent {
            return Color.accentColor.opacity(0.5)
        } else {
            return Color.clear
        }
    }
}
