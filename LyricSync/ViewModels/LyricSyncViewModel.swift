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

        transcriptionStatus = "Transcribing…"

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = true
        // .dictation is better for continuous speech / singing — it keeps
        // listening and produces far more segments than .search which is
        // designed for short spoken commands.
        request.taskHint = .dictation
        // Allow cloud recognition — more accurate than on-device
        if #available(macOS 10.15, *) {
            request.requiresOnDeviceRecognition = false
        }

        var allSegments: [(text: String, timestamp: TimeInterval)] = []
        // Use 10ms dedup buckets — very fine granularity to catch
        // closely-spaced words that SFSpeech sometimes splits or repeats
        var seenTimestamps = Set<Int>()
        let lock = NSLock()

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.isTranscribing = false
                    let nsError = error as NSError
                    // Don't report cancellation as error
                    if nsError.code != 216 && nsError.domain != "kAFAssistantErrorDomain" {
                        self?.errorMessage = "Transcription error: \(error.localizedDescription)"
                    }
                }
                return
            }

            guard let result = result else { return }

            lock.lock()
            defer { lock.unlock() }

            // Collect ALL segments — use 10ms buckets for very fine dedup
            for segment in result.bestTranscription.segments {
                let text = segment.substring.trimmingCharacters(in: .whitespaces)
                guard !text.isEmpty else { continue }
                // 10ms buckets (100 per second) — minimal dedup
                let tsKey = Int(segment.timestamp * 100)
                if !seenTimestamps.contains(tsKey) {
                    seenTimestamps.insert(tsKey)
                    allSegments.append((text: segment.substring, timestamp: Double(segment.timestamp)))
                }
            }

            DispatchQueue.main.async {
                self?.transcriptionProgress = result.isFinal ? 1.0 : min(Double(allSegments.count) * 0.01, 0.95)
                self?.transcriptionStatus = result.isFinal
                    ? "Finalizing \(allSegments.count) words…"
                    : "Heard \(allSegments.count) words…"

                if result.isFinal {
                    self?.isTranscribing = false
                    let lyrics = self?.groupSegments(allSegments) ?? []
                    if !lyrics.isEmpty {
                        self?.document.replaceLyrics(lyrics)
                        self?.document.rawTextLines = lyrics.map { $0.text }
                        self?.document.nextLineIndex = lyrics.count
                        self?.transcriptionStatus = "✅ Found \(lyrics.count) lines from \(allSegments.count) words"
                    } else {
                        self?.errorMessage = "No speech detected. Try a file with clearer vocals."
                        self?.transcriptionStatus = ""
                    }
                }
            }
        }

        // Timeout after 10 minutes
        DispatchQueue.main.asyncAfter(deadline: .now() + 600) {
            if !task.isFinishing { task.finish() }
        }
    }

    private func groupSegments(_ segments: [(text: String, timestamp: TimeInterval)]) -> [LyricLine] {
        guard !segments.isEmpty else { return [] }

        // Group words into lines based on natural pauses.
        // For transcribed lyrics we combine short words until we hit
        // a gap or reach ~8 words per line (typical lyric line length).
        var lines: [LyricLine] = []
        var currentWords: [String] = []
        var lineStart: TimeInterval = segments[0].timestamp
        var lastTs: TimeInterval = segments[0].timestamp

        for seg in segments {
            let gap = seg.timestamp - lastTs
            // Start a new line on a long pause (>2s) or at ~8 words
            if (gap > 2.0 || currentWords.count >= 8) && !currentWords.isEmpty {
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

    // MARK: - Genius Search

    @Published var isShowingGeniusSearch = false
    @Published var geniusSearchQuery = ""
    @Published var geniusSearchResults: [GeniusSong] = []
    @Published var isSearchingGenius = false
    @Published var geniusSearchError: String?
    @Published var isImportingGenius = false

    struct GeniusSong: Identifiable {
        let id = UUID()
        let title: String
        let artist: String
        let url: String
    }

    func showGeniusSearch() {
        geniusSearchQuery = document.fileName
            .replacingOccurrences(of: ".mp3", with: "")
            .replacingOccurrences(of: ".m4a", with: "")
            .replacingOccurrences(of: ".wav", with: "")
            .replacingOccurrences(of: ".aac", with: "")
        isShowingGeniusSearch = true
        geniusSearchResults = []
        geniusSearchError = nil
    }

    func searchGenius() {
        guard !geniusSearchQuery.isEmpty else { return }
        isSearchingGenius = true
        geniusSearchError = nil

        let query = geniusSearchQuery
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://genius.com/api/search/song?q=\(encoded)&per_page=5"

        guard let url = URL(string: urlString) else {
            isSearchingGenius = false
            geniusSearchError = "Invalid search URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.isSearchingGenius = false
                if let error = error {
                    self?.geniusSearchError = "Network error: \(error.localizedDescription)"
                    return
                }
                guard let data = data else {
                    self?.geniusSearchError = "No data received"
                    return
                }
                do {
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let response = json["response"] as? [String: Any],
                          let sections = response["sections"] as? [[String: Any]] else {
                        self?.geniusSearchError = "Could not parse response"
                        return
                    }
                    var songs: [GeniusSong] = []
                    for section in sections {
                        guard let hits = section["hits"] as? [[String: Any]] else { continue }
                        for hit in hits {
                            guard let result = hit["result"] as? [String: Any],
                                  let title = result["title"] as? String,
                                  let songURL = result["url"] as? String else { continue }
                            let artistDict = result["primary_artist"] as? [String: Any]
                            let artistName = artistDict?["name"] as? String ?? "Unknown"
                            songs.append(GeniusSong(title: title, artist: artistName, url: songURL))
                        }
                    }
                    if songs.isEmpty {
                        self?.geniusSearchError = "No results found"
                    } else {
                        self?.geniusSearchResults = songs
                    }
                } catch {
                    self?.geniusSearchError = "Parse error"
                }
            }
        }.resume()
    }

    func importGeniusLyrics(_ song: GeniusSong) {
        isImportingGenius = true
        geniusSearchError = nil

        guard let url = URL(string: song.url) else {
            isImportingGenius = false
            geniusSearchError = "Invalid URL"
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: request) { [weak self] data, _, error in
            DispatchQueue.main.async {
                self?.isImportingGenius = false
                if let error = error {
                    self?.geniusSearchError = "Network error: \(error.localizedDescription)"
                    return
                }
                guard let data = data, let html = String(data: data, encoding: .utf8) else {
                    self?.geniusSearchError = "No data received"
                    return
                }
                let lyrics = Self.extractLyricsFromHTML(html)
                if lyrics.isEmpty {
                    self?.geniusSearchError = "Could not extract lyrics from page"
                } else {
                    // Check if it looks like an LRC file or plain text
                    let hasTimestamps = lyrics.contains("[00:") || lyrics.contains("[01:")
                    let ext = hasTimestamps ? "lrc" : "txt"
                    self?.document.importText(content: lyrics, fileExtension: ext)
                    self?.isShowingGeniusSearch = false
                }
            }
        }.resume()
    }

    private static func extractLyricsFromHTML(_ html: String) -> String {
        var resultChunks: [String] = []

        // Genius pages have multiple data-lyrics-container divs, plus lots of
        // surrounding meta, contributor, translation divs.  We only want the
        // actual lyric lines.

        let containerTag = "data-lyrics-container=\"true\""
        var searchStart = html.startIndex

        while searchStart < html.endIndex {
            guard let openRange = html.range(of: containerTag, range: searchStart..<html.endIndex) else {
                break
            }
            guard let divStart = html[..<openRange.lowerBound].lastIndex(of: "<") else {
                searchStart = openRange.upperBound
                continue
            }
            guard let divOpenEnd = html[divStart...].firstIndex(of: ">") else {
                searchStart = openRange.upperBound
                continue
            }
            let contentStart = html.index(after: divOpenEnd)

            // Find matching </div> by tracking depth
            var depth = 1
            var pos = contentStart
            while pos < html.endIndex && depth > 0 {
                if html[pos] == "<" {
                    if html[pos...].hasPrefix("</div>") {
                        depth -= 1
                        if depth == 0 { break }
                        pos = html.index(pos, offsetBy: 6)
                        continue
                    } else if html[pos...].hasPrefix("<div") {
                        depth += 1
                        if let closeGT = html[pos...].firstIndex(of: ">") {
                            pos = html.index(after: closeGT)
                            continue
                        }
                    }
                }
                pos = html.index(after: pos)
            }

            guard depth == 0 else {
                searchStart = openRange.upperBound
                continue
            }

            // Extract and clean the container's inner HTML
            var text = String(html[contentStart..<pos])

            // Convert <br> tags to newlines BEFORE stripping other tags
            for tag in ["<br>", "<br/>", "<br />", "<Br>", "<BR>"] {
                text = text.replacingOccurrences(of: tag, with: "\n")
            }

            // Strip all remaining HTML tags
            if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>", options: []) {
                text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
            }

            // Decode HTML entities
            text = text.replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#x27;", with: "'")
                .replacingOccurrences(of: "&#39;", with: "'")
                .replacingOccurrences(of: "&nbsp;", with: " ")
                .replacingOccurrences(of: "&#8230;", with: "…")

            // Split, clean, and filter
            for line in text.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }

                // Skip Genesis meta headers: "N Contributors", "Translations",
                // long description text, "Read More", section tags like [Verse 1]
                // Only add the very first lyric line found, skip all preamble.
                if isMetaHeader(trimmed) {
                    // If we already have lyrics, this means we're past the lyric
                    // section (e.g. footer annotations) — stop.
                    if !resultChunks.isEmpty { break }
                    continue
                }

                resultChunks.append(trimmed)
            }

            searchStart = html.index(after: pos)
            if searchStart < html.endIndex {
                searchStart = html.index(searchStart, offsetBy: 5)
            }
        }

        return resultChunks.joined(separator: "\n")
    }

    /// Returns true if a line is page metadata rather than an actual lyric.
    private static func isMetaHeader(_ line: String) -> Bool {
        // Section tags: [Verse], [Chorus], [Bridge], [Intro], [Outro], etc.
        if line.hasPrefix("[") && line.hasSuffix("]") {
            // But allow LRC-style timestamps like [00:12.34]
            let inner = String(line.dropFirst().dropLast())
            if inner.contains(":") {
                // Could be a timestamp — check if it's actually a time
                let parts = inner.split(separator: ":")
                if parts.count >= 2, Int(parts[0]) != nil, Double(parts[1]) != nil {
                    return false
                }
            }
            return true
        }

        // "Read More" or "… Read More"
        if line.lowercased().contains("read more") { return true }

        // Footer: "Embed" / "Share" actions
        if line == "Embed" || line == "Share" { return true }

        // Prefix pattern: "N Contributors…" or "ContributorsTranslations…"
        let lower = line.lowercased()
        if lower.hasPrefix("contributor") || lower.hasPrefix("translation") {
            return true
        }

        // Lines that are very long (> 200 chars) are likely meta descriptions,
        // unless they have an LRC timestamp prefix.
        if line.count > 200 && !line.hasPrefix("[") {
            return true
        }

        // Standalone artist/song title info: line is just the song title or
        // "ArtistName Lyrics" with no spaces (camelCase pattern from Genius)
        // If the line starts with a number followed by contributor-style text

        return false
    }
}
