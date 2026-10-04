import AVFoundation
import Foundation

/// Records a voice clip to a temp .m4a (AAC) file. One instance per
/// composer/input-bar; call `start` then either `stop()` or `cancel()` —
/// never both concurrently on the same instance.
@Observable
final class AudioRecorder {
    enum State: Equatable {
        case idle
        case recording(elapsedSeconds: Int)
        case failed(String)
    }

    private(set) var state: State = .idle

    private var recorder: AVAudioRecorder?
    private var timerTask: Task<Void, Never>?
    private var startDate: Date?
    private var maxSeconds: Int = 60
    private var onAutoStop: ((URL, Int) -> Void)?

    /// Requests mic permission if needed, then starts recording to a fresh
    /// temp file. Auto-stops (and calls `onAutoStop`) once `maxSeconds` is hit.
    func start(maxSeconds: Int, onAutoStop: @escaping (URL, Int) -> Void) {
        self.maxSeconds = maxSeconds
        self.onAutoStop = onAutoStop
        Task { @MainActor in
            let granted = await AVAudioApplication.requestRecordPermission()
            guard granted else {
                state = .failed("Microphone access is off. You can turn it on in Settings.")
                return
            }
            beginRecording()
        }
    }

    @MainActor
    private func beginRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            state = .failed("Couldn't access the microphone.")
            return
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.record()
            self.recorder = recorder
            startDate = Date()
            state = .recording(elapsedSeconds: 0)
            startTimer()
        } catch {
            state = .failed("Couldn't start recording.")
        }
    }

    private func startTimer() {
        timerTask?.cancel()
        timerTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                guard let startDate else { return }
                let elapsed = Int(Date().timeIntervalSince(startDate).rounded())
                state = .recording(elapsedSeconds: elapsed)
                if elapsed >= maxSeconds {
                    if let (url, seconds) = stopInternal() {
                        onAutoStop?(url, seconds)
                    }
                    return
                }
            }
        }
    }

    /// Stops recording and returns the file URL + duration in seconds, or
    /// nil if nothing was recording.
    @discardableResult
    func stop() -> (url: URL, seconds: Int)? {
        stopInternal()
    }

    @discardableResult
    private func stopInternal() -> (url: URL, seconds: Int)? {
        timerTask?.cancel()
        timerTask = nil
        guard let recorder, let startDate else {
            state = .idle
            return nil
        }
        let seconds = max(1, Int(Date().timeIntervalSince(startDate).rounded()))
        recorder.stop()
        self.recorder = nil
        self.startDate = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return (recorder.url, seconds)
    }

    /// Clears a `.failed` state so the composer shows its normal input again —
    /// a denied mic permission must never lock the user out of typing.
    func dismissFailure() {
        if case .failed = state { state = .idle }
    }

    /// Stops and discards the recording — used when the user cancels.
    func cancel() {
        timerTask?.cancel()
        timerTask = nil
        if let recorder {
            recorder.stop()
            try? FileManager.default.removeItem(at: recorder.url)
        }
        recorder = nil
        startDate = nil
        state = .idle
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
