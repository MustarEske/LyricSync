import Foundation
import AVFoundation

/// Utility for embedding synced lyrics into audio file metadata
enum AudioMetadataWriter {

    /// Embed synced lyrics into the audio file.
    /// For all formats, writes a sidecar .lrc file alongside the audio,
    /// which is the most widely supported approach for synced lyrics.
    static func embedLyrics(
        into audioURL: URL,
        lyrics: [LyricLine],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let ext = audioURL.pathExtension.lowercased()

        switch ext {
        case "mp3":
            embedID3SYLT(into: audioURL, lyrics: lyrics, completion: completion)
        case "m4a", "mp4", "aac":
            writeLRCSidecar(alongside: audioURL, lyrics: lyrics, completion: completion)
        default:
            writeLRCSidecar(alongside: audioURL, lyrics: lyrics, completion: completion)
        }
    }

    // MARK: - MP3 ID3v2 SYLT Embedding

    /// Attempts to embed synced lyrics directly into MP3 ID3v2 SYLT tag.
    /// Falls back to LRC sidecar if direct embedding fails.
    private static func embedID3SYLT(
        into audioURL: URL,
        lyrics: [LyricLine],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        // Read the original file data
        guard let originalData = try? Data(contentsOf: audioURL) else {
            writeLRCSidecar(alongside: audioURL, lyrics: lyrics, completion: completion)
            return
        }

        // Build SYLT frame data
        guard let syltData = buildSYLTFrame(lyrics: lyrics) else {
            writeLRCSidecar(alongside: audioURL, lyrics: lyrics, completion: completion)
            return
        }

        // Parse existing ID3 header
        // Check if file already has ID3v2 tag
        var outputData: Data
        if originalData.prefix(3).elementsEqual([0x49, 0x44, 0x33]) {
            // File has existing ID3 tag — append SYLT frame
            outputData = insertSYLTIntoID3(originalData: originalData, syltFrame: syltData)
        } else {
            // No ID3 tag — create minimal ID3v2.3 header with SYLT
            let id3Tag = buildMinimalID3Tag(syltFrame: syltData)
            outputData = id3Tag + originalData
        }

        // Write to a temporary file first, then replace
        let tempURL = audioURL.appendingPathExtension("tmp")
        do {
            try outputData.write(to: tempURL)
            // Replace original with new file
            let fm = FileManager.default
            let backupURL = audioURL.appendingPathExtension("bak")
            if fm.fileExists(atPath: backupURL.path) {
                try fm.removeItem(at: backupURL)
            }
            try fm.moveItem(at: audioURL, to: backupURL)
            try fm.moveItem(at: tempURL, to: audioURL)
            try? fm.removeItem(at: backupURL)

            // Also write LRC sidecar for maximum compatibility
            let lrcURL = writeLRCContent(alongside: audioURL, lyrics: lyrics)
            completion(.success(lrcURL))
        } catch {
            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)
            // Fall back to sidecar
            writeLRCSidecar(alongside: audioURL, lyrics: lyrics, completion: completion)
        }
    }

    // MARK: - ID3 SYLT Frame Builder

    private static func buildSYLTFrame(lyrics: [LyricLine]) -> Data? {
        var frameData = Data()

        // Frame header for SYLT (ID3v2.3)
        let frameID = "SYLT".data(using: .ascii)!
        frameData.append(frameID)

        // Frame body
        var body = Data()

        // Encoding: 0 = ISO-8859-1, 1 = UTF-16, 2 = UTF-16BE, 3 = UTF-8
        body.append(3) // UTF-8

        // Language: "eng"
        body.append("eng".data(using: .ascii)!)

        // Time stamp format: 1 = MPEG frames, 2 = milliseconds
        body.append(2) // milliseconds

        // Content type: 0 = other, 1 = lyrics, 2 = text transcription, 3 = movement/part name, 4 = events, 5 = chord, 6 = trivia/'pop up' information
        body.append(1) // lyrics

        // Content descriptor (empty null-terminated)
        body.append(0) // null terminator for empty descriptor

        // Sync entries
        for lyric in lyrics {
            // Text (null-terminated UTF-8)
            let textData = lyric.text.data(using: .utf8) ?? Data()
            body.append(textData)
            body.append(0) // null terminator

            // Timestamp in milliseconds
            let ms = UInt32(lyric.timestamp * 1000)
            body.append(contentsOf: [
                UInt8((ms >> 24) & 0xFF),
                UInt8((ms >> 16) & 0xFF),
                UInt8((ms >> 8) & 0xFF),
                UInt8(ms & 0xFF)
            ])
        }

        // Frame size (4 bytes, big-endian, not syncsafe for v2.3)
        let size = UInt32(body.count)
        frameData.append(contentsOf: [
            UInt8((size >> 24) & 0xFF),
            UInt8((size >> 16) & 0xFF),
            UInt8((size >> 8) & 0xFF),
            UInt8(size & 0xFF)
        ])

        // Flags (2 bytes, 0x0000 = no flags)
        frameData.append(contentsOf: [0x00, 0x00])

        frameData.append(body)

        return frameData
    }

    private static func buildMinimalID3Tag(syltFrame: Data) -> Data {
        var tag = Data()

        // ID3v2 header
        tag.append("ID3".data(using: .ascii)!) // Identifier
        tag.append(contentsOf: [0x03, 0x00])   // Version 2.3
        tag.append(0x00)                        // Flags

        // Tag size (syncsafe integer)
        let frameSize = syltFrame.count
        let totalSize = frameSize // No padding for simplicity
        tag.append(contentsOf: [
            UInt8((totalSize >> 21) & 0x7F),
            UInt8((totalSize >> 14) & 0x7F),
            UInt8((totalSize >> 7) & 0x7F),
            UInt8(totalSize & 0x7F)
        ])

        tag.append(syltFrame)

        return tag
    }

    private static func insertSYLTIntoID3(originalData: Data, syltFrame: Data) -> Data {
        // Parse existing ID3 header (version at [3], flags at [5])

        // Read tag size (syncsafe integer)
        let sizeBytes = [originalData[6], originalData[7], originalData[8], originalData[9]]
        let tagSize = (Int(sizeBytes[0]) << 21) | (Int(sizeBytes[1]) << 14) | (Int(sizeBytes[2]) << 7) | Int(sizeBytes[3])

        var output = Data()

        // ID3 header (10 bytes)
        let newTagSize = tagSize + syltFrame.count
        var header = Data(originalData.prefix(10))

        // Update size in header
        header[6] = UInt8((newTagSize >> 21) & 0x7F)
        header[7] = UInt8((newTagSize >> 14) & 0x7F)
        header[8] = UInt8((newTagSize >> 7) & 0x7F)
        header[9] = UInt8(newTagSize & 0x7F)

        output.append(header)

        // Copy existing frames
        output.append(originalData.subdata(in: 10..<(10 + tagSize)))

        // Append SYLT frame
        output.append(syltFrame)

        // Copy audio data (after ID3 tag)
        let audioStart = 10 + tagSize
        if audioStart < originalData.count {
            output.append(originalData.subdata(in: audioStart..<originalData.count))
        }

        return output
    }

    // MARK: - LRC Sidecar

    private static func writeLRCSidecar(
        alongside audioURL: URL,
        lyrics: [LyricLine],
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        let lrcContent = buildLRCContent(lyrics)

        do {
            try lrcContent.write(to: lrcURL, atomically: true, encoding: .utf8)
            completion(.success(lrcURL))
        } catch {
            completion(.failure(error))
        }
    }

    @discardableResult
    private static func writeLRCContent(alongside audioURL: URL, lyrics: [LyricLine]) -> URL {
        let lrcURL = audioURL.deletingPathExtension().appendingPathExtension("lrc")
        let lrcContent = buildLRCContent(lyrics)
        try? lrcContent.write(to: lrcURL, atomically: true, encoding: .utf8)
        return lrcURL
    }

    // MARK: - Helpers

    private static func buildLRCContent(_ lyrics: [LyricLine]) -> String {
        var lines: [String] = []
        lines.append("[lr:LyricSync]")
        lines.append("")
        for lyric in lyrics {
            lines.append(lyric.lrcLine)
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Errors

enum EmbedError: LocalizedError {
    case unsupportedFormat(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported audio format: .\(ext). LRC sidecar file created instead."
        case .writeFailed(let reason):
            return "Failed to embed lyrics: \(reason)"
        }
    }
}
