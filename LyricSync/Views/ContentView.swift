import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = LyricSyncViewModel()
    @State private var isDragOver = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    WaveformView(viewModel: viewModel)
                        .frame(minHeight: 120)
                        .background(Color(NSColor.controlBackgroundColor))
                    Divider()
                    TransportBar(viewModel: viewModel)
                }
                Divider()
                LyricListView(viewModel: viewModel)
                    .frame(width: 300)
            }
            statusBar
        }
        .frame(minWidth: 860, minHeight: 480)
        .overlay(
            TapToSetKeyHandler(viewModel: viewModel)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .top) {
            if viewModel.tapToSetMode {
                TapToSetHUD(viewModel: viewModel)
                    .allowsHitTesting(true)
            }
        }
        .overlay(alignment: .center) {
            if viewModel.isTranscribing {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Auto-Detecting Lyrics")
                        .font(.headline)
                    Text(viewModel.transcriptionStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    ProgressView(value: viewModel.transcriptionProgress)
                        .frame(width: 200)
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(.regularMaterial)
                        .shadow(radius: 8)
                )
            }
        }
        .overlay {
            if isDragOver {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .background(Color.accentColor.opacity(0.05))
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 32))
                                .foregroundColor(.accentColor)
                            Text("Drop audio, .lrc, or .txt file")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                        }
                    }
                    .padding(4)
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDragOver) { providers in
            handleDrop(providers: providers)
        }
    }

    // MARK: - Drag and Drop

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, error in
            guard error == nil else { return }
            guard let data = item as? Data,
                  let url = URL(dataRepresentation: data, relativeTo: nil) else { return }

            let ext = url.pathExtension.lowercased()

            Task { @MainActor in
                switch ext {
                case "lrc", "txt":
                    self.viewModel.importTextFile(url: url)
                case "mp3", "m4a", "mp4", "aac", "wav", "aiff", "caf":
                    self.viewModel.loadAudioFile(url: url)
                default:
                    // Try as text file anyway (some .lrc files may not have proper UTType)
                    if ext == "lrc" || ext == "txt" {
                        self.viewModel.importTextFile(url: url)
                    }
                }
            }
        }
        return true
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("LyricSync", systemImage: "music.note")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Button(action: viewModel.openAudioFile) {
                Label("Open Audio", systemImage: "folder")
            }
            .keyboardShortcut("o", modifiers: .command)

            Button(action: { viewModel.importLRC() }) {
                Label("Import LRC", systemImage: "doc.text")
            }
            .keyboardShortcut("i", modifiers: .command)

            Button(action: { viewModel.autoTranscribe() }) {
                Label("Auto Lyrics", systemImage: "waveform")
            }
            .disabled(!viewModel.canAutoTranscribe)
            .help("Auto-detect lyrics from audio")

            Button(action: { viewModel.showAppearancePicker() }) {
                Image(systemName: "circle.lefthalf.filled")
            }
            .help("Appearance")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if viewModel.isLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading audio…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if let error = viewModel.errorMessage {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.red)
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if viewModel.document.hasFile {
                Image(systemName: "music.note")
                    .foregroundColor(.secondary)
                Text(viewModel.document.fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                if viewModel.document.hasImportedText {
                    Text("\(viewModel.document.nextLineIndex)/\(viewModel.document.rawTextLines.count) stamped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(viewModel.document.lyrics.count) lyrics")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Open an audio file to get started")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
