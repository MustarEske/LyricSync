import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Speech

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
        var lastUpdateTime: TimeInterval = 0
        audioEngine.onTimeUpdate = { [weak self] time in
            // Throttle callbacks to ~15fps for UI updates (audio engine still tracks at 30fps)
            guard time - lastUpdateTime > 0.066 else { return }
            lastUpdateTime = time
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

    func addLyricAtCurrentTime() {
        let time = audioEngine.currentTime
        addLyric(at: time)
    }

    func addLyric(at time: TimeInterval) {
        let oldLyrics = document.lyrics

        pushUndo(
            description: "Add lyric",
            undo: { [weak self] in self?.document.replaceLyrics(oldLyrics) },
            redo: { [weak self] in self?.document.addLyric(at: time) }
        )

        document.addLyric(at: time)
        selectedLyricId = document.lyrics.last(where: { abs($0.timestamp - time) < 0.1 })?.id
    }

    func deleteSelectedLyric() {
        guard let id = selectedLyricId else { return }
        if document.lyrics.first(where: { $0.id == id }) != nil {
            let oldLyrics = document.lyrics
            pushUndo(
                description: "Delete lyric",
                undo: { [weak self] in self?.document.replaceLyrics(oldLyrics) },
                redo: { [weak self] in self?.document.removeLyric(id: id) }
            )
        }
        document.removeLyric(id: id)
        selectedLyricId = nil
    }

    func beginEditing(_ lyric: LyricLine) {
        selectedLyricId = lyric.id
        editingText = lyric.text
        isEditingLyric = true
    }

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

    func moveLyric(id: UUID, to time: TimeInterval) {
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
            undo: { [weak self] in self?.document.replaceLyrics(startLyrics) },
            redo: { [weak self] in self?.document.replaceLyrics(endLyrics) }
        )

        dragStartLyrics = nil
    }

    func clearAllLyrics() {
        let oldLyrics = document.lyrics
        guard !oldLyrics.isEmpty else { return }

        pushUndo(
            description: "Clear all lyrics",
            undo: { [weak self] in self?.document.replaceLyrics(oldLyrics) },
            redo: { [weak self] in self?.clearAllLyricsNoUndo() }
        )

        document.clearLyrics()
        document.rawTextLines.removeAll()
        document.nextLineIndex = 0
        tapToSetCount = 0
        selectedLyricId = nil
    }

    private func clearAllLyricsNoUndo() {
        document.clearLyrics()
        document.rawTextLines.removeAll()
        document.nextLineIndex = 0
        tapToSetCount = 0
        selectedLyricId = nil
    }

    // MARK: - Import / Export

    func exportLRC() {
        let lrcContent = document.exportLRC()
        saveFile(content: lrcContent, extension: "lrc")
    }

    func exportPlainText() {
        let textContent = document.exportPlainText()
        saveFile(content: textContent, extension: "txt")
    }

    func embedLyrics() {
        guard let url = document.fileURL else { return }
        guard !document.lyrics.isEmpty else {
            errorMessage = "No lyrics to embed"
            return
        }

        AudioMetadataWriter.embedLyrics(into: url, lyrics: document.lyrics) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(_):
                    self?.errorMessage = nil
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Import an LRC or TXT file. Called from file picker or drag-and-drop.
    func importTextFile(url: URL) {
        let ext = url.pathExtension.lowercased()
        guard ext == "lrc" || ext == "txt" else {
            errorMessage = "Unsupported file type: .\(ext)"
            return
        }

        let oldLyrics = document.lyrics
        let oldRawLines = document.rawTextLines

        do {
            let content = try String(contentsOf: url)
            document.importText(content: content, fileExtension: ext)
            tapToSetCount = 0

            let newLyrics = document.lyrics
            let newRawLines = document.rawTextLines

            pushUndo(
                description: "Import \(ext.uppercased())",
                undo: { [weak self] in
                    self?.document.replaceLyrics(oldLyrics)
                    self?.document.rawTextLines = oldRawLines
                    self?.document.nextLineIndex = 0
                },
                redo: { [weak self] in
                    self?.document.replaceLyrics(newLyrics)
                    self?.document.rawTextLines = newRawLines
                }
            )
        } catch {
            errorMessage = "Failed to read file: \(error.localizedDescription)"
        }
    }

    /// Import LRC file (menu action — opens file picker)
    func importLRC() {
        let panel = NSOpenPanel()
        // Use broad types so .lrc files aren't greyed out
        panel.allowedContentTypes = [.data, .item]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Import LRC or TXT File"

        if panel.runModal() == .OK, let url = panel.url {
            let ext = url.pathExtension.lowercased()
            guard ext == "lrc" || ext == "txt" else {
                errorMessage = "Please select a .lrc or .txt file"
                return
            }
            importTextFile(url: url)
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

    func seekToLyric(_ lyric: LyricLine) {
        audioEngine.seek(to: lyric.timestamp)
    }

    // MARK: - Tap-to-Set Mode

    func toggleTapToSetMode() {
        tapToSetMode.toggle()
        if tapToSetMode {
            tapToSetCount = document.lyrics.count
            // If we have raw text lines but no lyrics yet, start from 0
            if document.lyrics.isEmpty {
                document.nextLineIndex = 0
            }
        }
    }

    /// Record a tap at the current playback time.
    /// If raw text lines are loaded, stamps the next line with its text.
    /// Otherwise creates an empty marker.
    func tapToSetRecord() {
        guard tapToSetMode else { return }
        let time = audioEngine.currentTime

        let oldLyrics = document.lyrics
        let oldNextIndex = document.nextLineIndex

        pushUndo(
            description: "Tap marker",
            undo: { [weak self] in
                self?.document.replaceLyrics(oldLyrics)
                self?.document.nextLineIndex = oldNextIndex
                self?.tapToSetCount = oldLyrics.count
            },
            redo: { [weak self] in
                guard let self = self else { return }
                if self.document.hasImportedText && self.document.nextLineIndex < self.document.rawTextLines.count {
                    _ = self.document.stampNextLine(at: time)
                } else {
                    self.document.addLyric(at: time)
                }
                self.tapToSetCount = self.document.lyrics.count
            }
        )

        if document.hasImportedText && document.nextLineIndex < document.rawTextLines.count {
            // Stamp the next text line with the current time
            if let stampedIdx = document.stampNextLine(at: time) {
                tapToSetCount += 1
                // Select the newly stamped lyric
                if let newLyric = document.lyrics.first(where: { abs($0.timestamp - time) < 0.05 && $0.text == document.rawTextLines[stampedIdx] }) {
                    selectedLyricId = newLyric.id
                }
            }
        } else {
            // No text loaded — create empty marker (old behavior)
            document.addLyric(at: time)
            tapToSetCount += 1
            selectedLyricId = document.lyrics.last(where: { abs($0.timestamp - time) < 0.05 })?.id
        }
    }

    /// Toggle play/pause
    func togglePlayback() {
        if audioEngine.isPlaying {
            audioEngine.pause()
        } else {
            audioEngine.play()
        }
    }

    // MARK: - Auto Transcribe

    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0
    @Published var transcriptionStatus: String = ""

    var canAutoTranscribe: Bool {
        document.hasFile && !isTranscribing
    }

    func autoTranscribe() {
        guard let url = document.fileURL else { return }

        isTranscribing = true
        transcriptionProgress = 0
        transcriptionStatus = "Requesting permission…"

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self?.isTranscribing = false
                    self?.errorMessage = "Speech recognition not authorized. Enable in System Settings > Privacy & Security > Speech Recognition."
                    return
                }

                self?.performTranscription(url: url)
            }
        }
    }

    private func performTranscription(url: URL) {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            isTranscribing = false
            errorMessage = "Speech recognizer not available."
            return
        }

        transcriptionStatus = "Transcribing audio…"

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        var lastProcessedTime: TimeInterval = 0

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                if let error = error {
                    self?.isTranscribing = false
                    self?.errorMessage = "Transcription failed: \(error.localizedDescription)"
                    return
                }

                guard let result = result else { return }

                var segments: [(text: String, timestamp: TimeInterval)] = []
                for segment in result.bestTranscription.segments {
                    let text = segment.substring.trimmingCharacters(in: .whitespaces)
                    guard !text.isEmpty else { continue }
                    let ts = Double(segment.timestamp)
                    if ts > lastProcessedTime + 0.1 {
                        segments.append((text: text, timestamp: ts))
                        lastProcessedTime = ts
                    }
                }

                self?.transcriptionProgress = result.isFinal ? 1.0 : 0.3
                self?.transcriptionStatus = result.isFinal
                    ? "Finalizing…"
                    : "Transcribing…"

                if result.isFinal {
                    self?.isTranscribing = false
                    let lyrics = self?.groupSegments(segments) ?? []
                    self?.document.replaceLyrics(lyrics)
                    self?.document.rawTextLines = lyrics.map { $0.text }
                    self?.document.nextLineIndex = lyrics.count
                    self?.transcriptionStatus = "✅ Found \(lyrics.count) lyric lines"
                }
            }
        }

        // Timeout after 5 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            if !task.isFinishing { task.finish() }
        }
    }

    private func groupSegments(_ segments: [(text: String, timestamp: TimeInterval)]) -> [LyricLine] {
        guard !segments.isEmpty else { return [] }

        var lines: [LyricLine] = []
        var currentWords: [String] = []
        var lineStart: TimeInterval = segments[0].timestamp
        var lastTs: TimeInterval = segments[0].timestamp

        for seg in segments {
            if seg.timestamp - lastTs > 1.5 && !currentWords.isEmpty {
                let text = currentWords.joined(separator: " ")
                if !text.isEmpty { lines.append(LyricLine(timestamp: lineStart, text: text)) }
                currentWords = []
                lineStart = seg.timestamp
            }
            currentWords.append(seg.text)
            lastTs = seg.timestamp
        }

        if !currentWords.isEmpty {
            let text = currentWords.joined(separator: " ")
            if !text.isEmpty { lines.append(LyricLine(timestamp: lineStart, text: text)) }
        }

        return lines
    }

    /// Cycle appearance: system → dark → light → system
    func showAppearancePicker() {
        NotificationCenter.default.post(name: .toggleAppearance, object: nil)
    }
}
