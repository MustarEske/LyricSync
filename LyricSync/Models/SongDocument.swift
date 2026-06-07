import Foundation

/// Represents a single synced lyric line with timestamp
struct LyricLine: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: TimeInterval
    var text: String

    init(id: UUID = UUID(), timestamp: TimeInterval, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }

    var formattedTimestamp: String {
        let totalMs = Int(timestamp * 100)
        let minutes = totalMs / 6000
        let seconds = (totalMs % 6000) / 100
        let centiseconds = totalMs % 100
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }

    var lrcLine: String {
        return "\(formattedTimestamp)\(text)"
    }
}

/// Represents a song/audio file with its lyrics.
/// Mutations are batched — the @Published `lyrics` array is only updated
/// when explicitly flushed, reducing SwiftUI redraw churn.
class SongDocument: ObservableObject {
    @Published var fileURL: URL?
    @Published var fileName: String = "No file loaded"
    @Published var duration: TimeInterval = 0
    @Published var waveformData: [Float] = []

    /// Raw text lines imported from a .txt or .lrc file
    @Published var rawTextLines: [String] = []

    /// Index of the next line to be stamped in tap-to-set mode
    @Published var nextLineIndex: Int = 0

    // Private backing store — mutations happen here without triggering @Published
    private var _lyrics: [LyricLine] = []

    /// Public read-only access to lyrics
    var lyrics: [LyricLine] { _lyrics }

    /// Remove all lyrics
    func clearLyrics() {
        _lyrics = []
    }

    /// Replace all lyrics (used by undo/redo)
    func replaceLyrics(_ newLyrics: [LyricLine]) {
        _lyrics = newLyrics
    }

    var hasFile: Bool { fileURL != nil }
    var hasImportedText: Bool { !rawTextLines.isEmpty }

    /// Begin a batch of mutations. Call `endBatch()` when done.
    func beginBatch() {
        objectWillChange.send()
    }

    /// End batch — single notification for all mutations since beginBatch()
    func endBatch() {
        // objectWillChange was already sent in beginBatch, SwiftUI will redraw once
    }

    /// Add a lyric using binary insertion (O(log n) search + O(n) insert vs O(n log n) sort)
    func addLyric(at timestamp: TimeInterval, text: String = "") {
        let newLine = LyricLine(timestamp: timestamp, text: text)
        let insertIndex = _lyrics.binarySearch { $0.timestamp < timestamp }
        _lyrics.insert(newLine, at: insertIndex)
    }

    /// Stamp the next text line with a timestamp
    @discardableResult
    func stampNextLine(at timestamp: TimeInterval) -> Int? {
        guard nextLineIndex < rawTextLines.count else { return nil }
        let text = rawTextLines[nextLineIndex]
        addLyric(at: timestamp, text: text)
        let stampedIndex = nextLineIndex
        nextLineIndex += 1
        return stampedIndex
    }

    func removeLyric(id: UUID) {
        _lyrics.removeAll { $0.id == id }
    }

    func updateLyric(id: UUID, text: String) {
        if let index = _lyrics.firstIndex(where: { $0.id == id }) {
            _lyrics[index].text = text
        }
    }

    func moveLyric(id: UUID, to timestamp: TimeInterval) {
        guard let index = _lyrics.firstIndex(where: { $0.id == id }) else { return }
        var lyric = _lyrics.remove(at: index)
        lyric.timestamp = max(0, min(timestamp, duration))
        let insertIndex = _lyrics.binarySearch { $0.timestamp < timestamp }
        _lyrics.insert(lyric, at: insertIndex)
    }

    func exportLRC() -> String {
        var lines: [String] = []
        lines.append("[ti:\(fileName)]")
        lines.append("[la:en]")
        lines.append("[lr:LyricSync]")
        lines.append(String(format: "[length:%02d:%02d]", Int(duration) / 60, Int(duration) % 60))
        lines.append("")
        for lyric in _lyrics {
            lines.append(lyric.lrcLine)
        }
        return lines.joined(separator: "\n")
    }

    func exportPlainText() -> String {
        var lines: [String] = []
        for lyric in _lyrics {
            lines.append("\(lyric.formattedTimestamp) \(lyric.text)")
        }
        return lines.joined(separator: "\n")
    }

    func importText(content: String, fileExtension: String) {
        let ext = fileExtension.lowercased()

        if ext == "lrc" {
            _lyrics = parseLRC(content: content)
            rawTextLines = _lyrics.map { $0.text }
        } else {
            rawTextLines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            _lyrics = []
        }
        nextLineIndex = 0
    }

    private func parseLRC(content: String) -> [LyricLine] {
        var result: [LyricLine] = []

        for line in content.components(separatedBy: .newlines) {
            var searchStart = line.startIndex

            while searchStart < line.endIndex {
                guard let bracketOpen = line[searchStart...].firstIndex(of: "[") else { break }
                guard let bracketEnd = line[bracketOpen...].firstIndex(of: "]") else { break }

                let inside = String(line[line.index(after: bracketOpen)..<bracketEnd])
                let text = String(line[line.index(after: bracketEnd)...])

                let parts = inside.split(separator: ":")
                guard parts.count == 2 else { break }

                let minParts = String(parts[1]).split(separator: ".")
                guard minParts.count == 2 else { break }

                guard let minutes = Int(parts[0]),
                      let seconds = Int(minParts[0]),
                      let frac = Int(minParts[1]) else { break }

                let fracDigits = minParts[1].count
                let centiseconds: Int
                if fracDigits <= 2 {
                    centiseconds = frac * (fracDigits <= 1 ? 10 : 1)
                } else if fracDigits == 3 {
                    centiseconds = (frac + 5) / 10
                } else {
                    centiseconds = frac
                }

                let timestamp = TimeInterval(minutes * 60 + seconds) + TimeInterval(centiseconds) / 100.0
                result.append(LyricLine(timestamp: timestamp, text: text))

                searchStart = line.index(after: bracketEnd)
            }
        }

        return result.sorted { $0.timestamp < $1.timestamp }
    }
}

// MARK: - Binary insertion helper

extension Array {
    /// Returns the index where `element` should be inserted to maintain sorted order
    /// according to the given predicate (which must return true for "should come before").
    func binarySearch(predicate: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if predicate(self[mid]) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}
