import Foundation

/// Represents a single synced lyric line with timestamp
struct LyricLine: Identifiable, Codable, Equatable {
    var id: UUID
    var timestamp: TimeInterval  // in seconds
    var text: String

    init(id: UUID = UUID(), timestamp: TimeInterval, text: String) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
    }

    /// Formatted timestamp as [mm:ss.xx]
    var formattedTimestamp: String {
        let totalMs = Int(timestamp * 100)
        let minutes = totalMs / 6000
        let seconds = (totalMs % 6000) / 100
        let centiseconds = totalMs % 100
        return String(format: "[%02d:%02d.%02d]", minutes, seconds, centiseconds)
    }

    /// LRC-formatted line
    var lrcLine: String {
        return "\(formattedTimestamp)\(text)"
    }
}

/// Represents a song/audio file with its lyrics
class SongDocument: ObservableObject {
    @Published var fileURL: URL?
    @Published var fileName: String = "No file loaded"
    @Published var duration: TimeInterval = 0
    @Published var lyrics: [LyricLine] = []
    @Published var waveformData: [Float] = []

    var hasFile: Bool {
        fileURL != nil
    }

    func addLyric(at timestamp: TimeInterval) {
        let newLine = LyricLine(timestamp: timestamp, text: "")
        lyrics.append(newLine)
        lyrics.sort { $0.timestamp < $1.timestamp }
    }

    func removeLyric(id: UUID) {
        lyrics.removeAll { $0.id == id }
    }

    func updateLyric(id: UUID, text: String) {
        if let index = lyrics.firstIndex(where: { $0.id == id }) {
            lyrics[index].text = text
        }
    }

    func moveLyric(id: UUID, to timestamp: TimeInterval) {
        if let index = lyrics.firstIndex(where: { $0.id == id }) {
            lyrics[index].timestamp = max(0, min(timestamp, duration))
            lyrics.sort { $0.timestamp < $1.timestamp }
        }
    }

    /// Export as LRC format with full metadata
    func exportLRC() -> String {
        var lines: [String] = []
        lines.append("[ti:\(fileName)]")
        lines.append("[la:en]")
        lines.append("[lr:LyricSync]")
        lines.append(String(format: "[length:%02d:%02d]", Int(duration) / 60, Int(duration) % 60))
        lines.append("")
        for lyric in lyrics {
            lines.append(lyric.lrcLine)
        }
        return lines.joined(separator: "\n")
    }

    /// Export as plain text with timestamps
    func exportPlainText() -> String {
        var lines: [String] = []
        for lyric in lyrics {
            lines.append("\(lyric.formattedTimestamp) \(lyric.text)")
        }
        return lines.joined(separator: "\n")
    }

    /// Import from LRC format
    func importLRC(content: String) {
        let pattern = #"\[(\d{2}):(\d{2})\.(\d{2})\](.*)"#
        let regex = try! NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(content.startIndex..., in: content)

        var newLyrics: [LyricLine] = []
        regex.enumerateMatches(in: content, range: nsRange) { match, _, _ in
            guard let match = match else { return }
            let minuteRange = Range(match.range(at: 1), in: content)!
            let secondRange = Range(match.range(at: 2), in: content)!
            let centiRange = Range(match.range(at: 3), in: content)!
            let textRange = Range(match.range(at: 4), in: content)!

            let minutes = Int(content[minuteRange]) ?? 0
            let seconds = Int(content[secondRange]) ?? 0
            let centiseconds = Int(content[centiRange]) ?? 0
            let timestamp = TimeInterval(minutes * 60 + seconds) + TimeInterval(centiseconds) / 100.0
            let text = String(content[textRange])

            newLyrics.append(LyricLine(timestamp: timestamp, text: text))
        }

        lyrics = newLyrics.sorted { $0.timestamp < $1.timestamp }
    }
}
