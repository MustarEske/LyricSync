import SwiftUI
import AVFoundation

// MARK: - Undo Action

private struct UndoAction {
    let undo: () -> Void
    let redo: () -> Void
    let description: String
}

// MARK: - ViewModel

@MainActor
class LyricSyncViewModel: ObservableObject {
    @Published var document = SongDocument()
    @Published var audioEngine = AudioEngine()
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var selectedLyricId: UUID?
    @Published var isEditingLyric = false
    @Published var editingText = ""

    // MARK: - Tap-to-Set Mode
    @Published var tapToSetMode = false
    @Published var tapToSetCount = 0

    /// Index of the lyric line currently active during playback
    @Published var currentLyricIndex: Int? = nil

    // MARK: - Undo / Redo
    private var undoStack: [UndoAction] = []
    private var redoStack: [UndoAction] = []
    private let maxUndoStackSize = 50

    init() {
        setupTimeTracking()
    }

    private func setupTimeTracking() {
        audioEngine.onTimeUpdate = { [weak self] time in
            Task { @MainActor [weak self] in
                self?.updateCurrentLyricIndex(for: time)
            }
        }
    }

    private func updateCurrentLyricIndex(for time: TimeInterval) {
        let lyrics = document.lyrics
        guard !lyrics.isEmpty else {
            currentLyricIndex = nil
            return
        }

        var foundIndex: Int? = nil
        for (index, lyric) in lyrics.enumerated() {
            if lyric.timestamp <= time {
                foundIndex = index
            } else {
                break
            }
        }
        currentLyricIndex = foundIndex
    }

    // MARK: - Undo/Redo Operations

    func canUndo() -> Bool { !undoStack.isEmpty }
    func canRedo() -> Bool { !redoStack.isEmpty }

    func undo() {
        guard let action = undoStack.popLast() else { return }
        action.undo()
        redoStack.append(action)
    }

    func redo() {
        guard let action = redoStack.popLast() else { return }
        action.redo()
        undoStack.append(action)
    }

    private func pushUndo(description: String, undo: @escaping () -> Void, redo: @escaping () -> Void) {
        let action = UndoAction(undo: undo, redo: redo, description: description)
        undoStack.append(action)
        if undoStack.count > maxUndoStackSize {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    // MARK: - File Operations

    /// Open an audio file from disk
    func openAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.mp3, .mpeg4Audio, .aiff, .wav, .appleProtectedMPEG4Audio, .audio]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Choose an Audio File"

        if panel.runModal() == .OK, let url = panel.url {
            loadAudioFile(url: url)
        }
    }

    func loadAudioFile(url: URL) {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let result = try await audioEngine.loadFile(url: url)
                document.fileURL = url
                document.fileName = url.deletingPathExtension().lastPathComponent
                document.duration = result.duration
                document.waveformData = result.waveform
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    // MARK: - Lyric Operations (with undo support)

    /// Add a lyric at the current playback time
    func addLyricAtCurrentTime() {
        let time = audioEngine.currentTime
        addLyric(at: time)
    }

    /// Add a lyric at a specific time (from timeline click)
    func addLyric(at time: TimeInterval) {
        let newLine = LyricLine(timestamp: time, text: "")
        let oldLyrics = document.lyrics

        pushUndo(
            description: "Add lyric",
            undo: { [weak self] in self?.document.lyrics = oldLyrics },
            redo: { [weak self] in self?.document.addLyric(at: time) }
        )

        document.addLyric(at: time)
        selectedLyricId = document.lyrics.last(where: { abs($0.timestamp - time) < 0.1 })?.id
    }

    /// Delete selected lyric
    func deleteSelectedLyric() {
        guard let id = selectedLyricId else { return }
        if let lyric = document.lyrics.first(where: { $0.id == id }) {
            let oldLyrics = document.lyrics
            pushUndo(
                description: "Delete lyric",
                undo: { [weak self] in self?.document.lyrics = oldLyrics },
                redo: { [weak self] in self?.document.removeLyric(id: id) }
            )
        }
        document.removeLyric(id: id)
        selectedLyricId = nil
    }

    /// Begin editing a lyric
    func beginEditing(_ lyric: LyricLine) {
        selectedLyricId = lyric.id
        editingText = lyric.text
        isEditingLyric = true
    }

    /// Commit edited lyric text
    func commitEdit() {
        guard let id = selectedLyricId else { return }
        let oldText = document.lyrics.first(where: { $0.id == id })?.text ?? ""
        let newText = editingText

        pushUndo(
            description: "Edit lyric",
            undo: { [weak self] in self?.document.updateLyric(id: id, text: oldText) },
            redo: { [weak self] in self?.document.updateLyric(id: id, text: newText) }
        )

        document.updateLyric(id: id, text: editingText)
        isEditingLyric = false
        editingText = ""
    }

    /// Move a lyric to a new time
    func moveLyric(id: UUID, to time: TimeInterval) {
        // Note: for drag operations we don't push undo on every frame,
        // only on drag end. See beginDrag/endDrag.
        document.moveLyric(id: id, to: time)
    }

    private var dragStartLyrics: [LyricLine]?

    func beginDragLyric(id: UUID) {
        dragStartLyrics = document.lyrics
    }

    func endDragLyric(id: UUID, to time: TimeInterval) {
        guard let startLyrics = dragStartLyrics else { return }
        let endLyrics = document.lyrics

        pushUndo(
            description: "Move lyric",
            undo: { [weak self] in self?.document.lyrics = startLyrics },
            redo: { [weak self] in self?.document.lyrics = endLyrics }
        )

        dragStartLyrics = nil
    }

    /// Delete all lyrics (for restarting tap-to-set session)
    func clearAllLyrics() {
        let oldLyrics = document.lyrics
        guard !oldLyrics.isEmpty else { return }

        pushUndo(
            description: "Clear all lyrics",
            undo: { [weak self] in self?.document.lyrics = oldLyrics },
            redo: { [weak self] in self?.clearAllLyricsNoUndo() }
        )

        document.lyrics.removeAll()
        tapToSetCount = 0
        selectedLyricId = nil
    }

    private func clearAllLyricsNoUndo() {
        document.lyrics.removeAll()
        tapToSetCount = 0
        selectedLyricId = nil
    }

    // MARK: - Import / Export

    /// Export LRC file
    func exportLRC() {
        let lrcContent = document.exportLRC()
        saveFile(content: lrcContent, extension: "lrc")
    }

    /// Export plain text with timestamps
    func exportPlainText() {
        let textContent = document.exportPlainText()
        saveFile(content: textContent, extension: "txt")
    }

    /// Embed lyrics into the audio file (or write LRC sidecar)
    func embedLyrics() {
        guard let url = document.fileURL else { return }
        guard !document.lyrics.isEmpty else {
            errorMessage = "No lyrics to embed"
            return
        }

        AudioMetadataWriter.embedLyrics(into: url, lyrics: document.lyrics) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let lrcURL):
                    self?.errorMessage = nil
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Import LRC file
    func importLRC() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import LRC File"

        if panel.runModal() == .OK, let url = panel.url {
            let oldLyrics = document.lyrics
            do {
                let content = try String(contentsOf: url)
                document.importLRC(content: content)
                let newLyrics = document.lyrics
                pushUndo(
                    description: "Import LRC",
                    undo: { [weak self] in self?.document.lyrics = oldLyrics },
                    redo: { [weak self] in self?.document.lyrics = newLyrics }
                )
            } catch {
                errorMessage = "Failed to read LRC file: \(error.localizedDescription)"
            }
        }
    }

    private func saveFile(content: String, extension ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(document.fileName).\(ext)"
        panel.allowedContentTypes = [.plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                errorMessage = "Failed to save file: \(error.localizedDescription)"
            }
        }
    }

    /// Seek to a lyric's timestamp
    func seekToLyric(_ lyric: LyricLine) {
        audioEngine.seek(to: lyric.timestamp)
    }

    // MARK: - Tap-to-Set Mode

    func toggleTapToSetMode() {
        tapToSetMode.toggle()
        if tapToSetMode {
            tapToSetCount = 0
        }
    }

    /// Record a tap at the current playback time — creates a new lyric marker
    func tapToSetRecord() {
        guard tapToSetMode else { return }
        let time = audioEngine.currentTime

        let oldLyrics = document.lyrics
        pushUndo(
            description: "Tap marker",
            undo: { [weak self] in self?.document.lyrics = oldLyrics },
            redo: { [weak self] in
                self?.document.addLyric(at: time)
                self?.tapToSetCount += 1
            }
        )

        document.addLyric(at: time)
        tapToSetCount += 1
        selectedLyricId = document.lyrics.last(where: { abs($0.timestamp - time) < 0.05 })?.id
    }

    /// Toggle play/pause
    func togglePlayback() {
        if audioEngine.isPlaying {
            audioEngine.pause()
        } else {
            audioEngine.play()
        }
    }
}
