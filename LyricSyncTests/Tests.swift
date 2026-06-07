import Foundation

// ── Include SongDocument source directly ──
// (We compile this alongside SongDocument.swift)

var passed = 0
var failed = 0

func check(_ condition: Bool, _ message: String) {
    if condition { passed += 1; print("  ✅ \(message)") }
    else { failed += 1; print("  ❌ \(message)") }
}

func checkEqual<T: Equatable>(_ a: T, _ b: T, _ message: String) {
    check(a == b, "\(message): got \(a), expected \(b)")
}

func checkClose(_ a: TimeInterval, _ b: TimeInterval, _ message: String) {
    check(abs(a - b) <= 0.01, "\(message): got \(a), expected ~\(b)")
}

func checkNil<T>(_ value: T?, _ message: String) { check(value == nil, "\(message) is nil") }

@main
struct TestRunner {
    static func main() {
        print("🧪 Running LyricSync Tests\n")

        // ── LRC Import ──
        print("── LRC Import ──")
        do {
            let doc = SongDocument()
            doc.importText(content: "[00:01.50]Hello\n[00:05.20]World\n[00:10.00]Third", fileExtension: "lrc")
            checkEqual(doc.lyrics.count, 3, "basic: 3 lyrics")
            checkEqual(doc.lyrics[0].text, "Hello", "basic: first text")
            checkClose(doc.lyrics[0].timestamp, 1.5, "basic: first timestamp")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "[00:01.500]Hello", fileExtension: "lrc")
            checkEqual(doc.lyrics.count, 1, "milliseconds: 1 lyric")
            checkClose(doc.lyrics[0].timestamp, 1.5, "milliseconds: timestamp")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "[00:01.00][00:05.00]Repeated", fileExtension: "lrc")
            checkEqual(doc.lyrics.count, 2, "multi-timestamp: 2 lyrics")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "[ti:Test]\n[ar:Artist]\n[00:01.00]Line", fileExtension: "lrc")
            checkEqual(doc.lyrics.count, 1, "metadata: skips tags")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "[00:01.00]Hello\n[00:02.00]World", fileExtension: "lrc")
            checkEqual(doc.rawTextLines.count, 2, "rawText: 2 lines")
        }

        // ── Plain Text ──
        print("\n── Plain Text Import ──")
        do {
            let doc = SongDocument()
            doc.importText(content: "A\nB\nC", fileExtension: "txt")
            checkEqual(doc.rawTextLines.count, 3, "txt: 3 lines")
            checkEqual(doc.lyrics.count, 0, "txt: no lyrics")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "A\n\n  \nB", fileExtension: "txt")
            checkEqual(doc.rawTextLines.count, 2, "txt: skips empty")
        }

        // ── Lyric Operations ──
        print("\n── Lyric Operations ──")
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 5.0, text: "Test")
            checkEqual(doc.lyrics.count, 1, "add: 1 lyric")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 10.0, text: "C")
            doc.addLyric(at: 5.0, text: "A")
            doc.addLyric(at: 7.0, text: "B")
            checkEqual(doc.lyrics[0].text, "A", "order: A first")
            checkEqual(doc.lyrics[1].text, "B", "order: B second")
            checkEqual(doc.lyrics[2].text, "C", "order: C third")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 5.0, text: "Test")
            let id = doc.lyrics[0].id
            doc.removeLyric(id: id)
            checkEqual(doc.lyrics.count, 0, "remove: 0 lyrics")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 5.0, text: "Old")
            doc.updateLyric(id: doc.lyrics[0].id, text: "New")
            checkEqual(doc.lyrics[0].text, "New", "update: text")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 5.0, text: "A")
            doc.addLyric(at: 10.0, text: "B")
            doc.addLyric(at: 15.0, text: "C")
            doc.moveLyric(id: doc.lyrics[0].id, to: 12.0)
            checkEqual(doc.lyrics[0].text, "B", "move: B first")
            checkEqual(doc.lyrics[1].text, "A", "move: A second")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 5.0, text: "X")
            doc.clearLyrics()
            checkEqual(doc.lyrics.count, 0, "clear: 0 lyrics")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 5.0, text: "Old")
            doc.replaceLyrics([LyricLine(timestamp: 1.0, text: "New")])
            checkEqual(doc.lyrics.count, 1, "replace: 1 lyric")
            checkEqual(doc.lyrics[0].text, "New", "replace: text")
        }

        // ── Tap-to-Set ──
        print("\n── Tap-to-Set ──")
        do {
            let doc = SongDocument()
            doc.importText(content: "Hello\nWorld", fileExtension: "txt")
            doc.duration = 100
            let idx = doc.stampNextLine(at: 5.0)
            checkEqual(idx, 0, "stamp: index 0")
            checkEqual(doc.lyrics.count, 1, "stamp: 1 lyric")
            checkEqual(doc.lyrics[0].text, "Hello", "stamp: text")
            checkEqual(doc.nextLineIndex, 1, "stamp: advanced")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "A\nB\nC", fileExtension: "txt")
            doc.duration = 100
            _ = doc.stampNextLine(at: 1.0)
            _ = doc.stampNextLine(at: 2.0)
            _ = doc.stampNextLine(at: 3.0)
            checkEqual(doc.lyrics.count, 3, "stamp all: 3 lyrics")
            checkEqual(doc.nextLineIndex, 3, "stamp all: exhausted")
        }
        do {
            let doc = SongDocument()
            doc.importText(content: "Only", fileExtension: "txt")
            doc.duration = 100
            _ = doc.stampNextLine(at: 1.0)
            let result = doc.stampNextLine(at: 2.0)
            checkNil(result, "exhausted: returns nil")
        }

        // ── Export ──
        print("\n── Export ──")
        do {
            let doc = SongDocument()
            doc.fileName = "Test"
            doc.duration = 100
            doc.addLyric(at: 1.5, text: "Hello")
            let lrc = doc.exportLRC()
            check(lrc.contains("[ti:Test]"), "exportLRC: has title")
            check(lrc.contains("Hello"), "exportLRC: has lyric")
        }
        do {
            let doc = SongDocument()
            doc.duration = 100
            doc.addLyric(at: 1.5, text: "Hello")
            let text = doc.exportPlainText()
            check(text.contains("Hello"), "exportText: has text")
        }

        // ── Results ──
        print("\n────────────────────────────")
        print("Results: \(passed) passed, \(failed) failed, \(passed + failed) total")
        if failed == 0 {
            print("✅ All tests passed!")
        } else {
            print("❌ \(failed) test(s) failed")
            exit(1)
        }
    }
}
