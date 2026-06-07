import AVFoundation

/// Utility for extracting waveform data and playing audio
class AudioEngine: ObservableObject {
    private var audioFile: AVAudioFile?
    private var audioEngine = AVAudioEngine()
    private var playerNode = AVAudioPlayerNode()
    private var timer: Timer?

    @Published var currentTime: TimeInterval = 0
    @Published var isPlaying: Bool = false
    @Published var duration: TimeInterval = 0

    /// Called every tick during playback with the current time
    var onTimeUpdate: ((TimeInterval) -> Void)?

    // Timer tracking state
    private var timerStartTime: Date = Date()
    private var timerStartOffset: TimeInterval = 0

    func loadFile(url: URL) async throws -> (waveform: [Float], duration: TimeInterval) {
        let file = try AVAudioFile(forReading: url)
        self.audioFile = file

        let format = file.processingFormat
        let frameCount = UInt32(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw AudioError.bufferCreationFailed
        }
        try file.read(into: buffer)

        let dur = Double(file.length) / format.sampleRate
        self.duration = dur

        // Extract waveform: downsample to ~200 points (was 1000 — too many)
        let samples = buffer.floatChannelData![0]
        let totalFrames = Int(frameCount)
        let targetSampleCount = 200
        let samplesPerBlock = max(1, totalFrames / targetSampleCount)
        var waveform = [Float](repeating: 0, count: targetSampleCount)

        for i in 0..<targetSampleCount {
            let start = i * samplesPerBlock
            let end = min(start + samplesPerBlock, totalFrames)
            var maxVal: Float = 0
            for j in start..<end {
                maxVal = max(maxVal, abs(samples[j]))
            }
            waveform[i] = maxVal
        }

        if let max = waveform.max(), max > 0 {
            waveform = waveform.map { $0 / max }
        }

        setupAudioEngine(format: format)

        return (waveform, dur)
    }

    private func setupAudioEngine(format: AVAudioFormat) {
        audioEngine.stop()
        audioEngine.reset()

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
        try? audioEngine.start()
    }

    func play() {
        guard let file = audioFile else { return }
        if isPlaying {
            playerNode.stop()
        }
        playerNode.scheduleFile(file, at: nil)
        playerNode.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        playerNode.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        playerNode.stop()
        isPlaying = false
        currentTime = 0
        stopTimer()
    }

    func seek(to time: TimeInterval) {
        guard let file = audioFile else { return }
        let wasPlaying = isPlaying
        playerNode.stop()

        let format = file.processingFormat
        let framePosition = AVAudioFramePosition(time * format.sampleRate)
        let framesToPlay = AVAudioFrameCount(file.length - framePosition)

        playerNode.scheduleSegment(file, startingFrame: framePosition, frameCount: framesToPlay, at: nil)

        currentTime = time

        if wasPlaying {
            playerNode.play()
            // Reset the timer so playhead position is calculated from the new position
            restartTimer()
        } else {
            stopTimer()
        }
    }

    // MARK: - Timer

    private func startTimer() {
        stopTimer()
        timerStartTime = Date()
        timerStartOffset = currentTime

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.playerNode.isPlaying {
                self.currentTime = self.timerStartOffset + Date().timeIntervalSince(self.timerStartTime)
                self.onTimeUpdate?(self.currentTime)
                if self.currentTime >= self.duration {
                    self.stop()
                }
            }
        }
    }

    private func restartTimer() {
        // Reset timer base to current seek position
        stopTimer()
        timerStartTime = Date()
        timerStartOffset = currentTime

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.playerNode.isPlaying {
                self.currentTime = self.timerStartOffset + Date().timeIntervalSince(self.timerStartTime)
                self.onTimeUpdate?(self.currentTime)
                if self.currentTime >= self.duration {
                    self.stop()
                }
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stopTimer()
        audioEngine.stop()
    }
}

enum AudioError: LocalizedError {
    case bufferCreationFailed
    case fileLoadFailed

    var errorDescription: String? {
        switch self {
        case .bufferCreationFailed: return "Failed to create audio buffer"
        case .fileLoadFailed: return "Failed to load audio file"
        }
    }
}
