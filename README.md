# LyricSync

A macOS app for syncing timeline-based lyrics to audio files. Built with SwiftUI.

## Features

- **Tap-to-Set Mode** — Play a song, press Space to drop lyric markers in real time, then type lyrics for each marker
- **Visual Timeline** — Canvas-based waveform with draggable lyric markers and a glowing playhead
- **Lyric List Sidebar** — Inline editing with auto-scroll to current lyric during playback (highlighted in blue)
- **LRC Import/Export** — Standard-compliant `.lrc` files with `[lr:LyricSync]` and `[length:mm:ss]` tags
- **Embed Lyrics in Audio** — MP3 files get an ID3v2 SYLT frame; M4A/MP4 and others get a `.lrc` sidecar
- **Undo/Redo** — Up to 50 actions via ⌘Z / ⌘⇧Z, covering all mutations (drag coalesced into single action)

## Architecture

| File | Purpose |
|------|---------|
| `LyricSyncApp.swift` | App entry point + menu bar commands |
| `Models/SongDocument.swift` | Data model, LRC import/export |
| `ViewModels/LyricSyncViewModel.swift` | Main view model: file open, playback, lyric CRUD |
| `Utilities/AudioEngine.swift` | AVAudioEngine wrapper |
| `Utilities/AudioMetadataWriter.swift` | Embeds lyrics into audio file metadata |
| `Views/ContentView.swift` | Main layout |
| `Views/TimelineView.swift` | Canvas-based waveform + lyric markers |
| `Views/LyricListView.swift` | Sidebar list with inline editing |
| `Views/TransportBar.swift` | Playback controls + import/export menu |
| `Views/TapToSetOverlay.swift` | Tap-to-Set HUD |

## Requirements

- macOS 14+
- Xcode 15+

## Building

Open `LyricSync.xcodeproj` in Xcode and build, or use the included `build.sh` script.

## License

MIT
