import AVFoundation
import Speech

/// Dictée par l'appli (reconnaissance vocale d'Apple) pour le micro d'EDP :
/// plus fiable que la reconnaissance vocale des pages web dans une appli.
final class Dictation {
    static let shared = Dictation()
    var onText: ((String, Bool) -> Void)?
    var onEnd: (() -> Void)?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var running = false

    static func askPermissions(_ done: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { st in
            AVAudioSession.sharedInstance().requestRecordPermission { mic in
                DispatchQueue.main.async { done(st == .authorized && mic) }
            }
        }
    }

    func start(lang: String, _ done: @escaping (String?) -> Void) {
        Dictation.askPermissions { ok in
            guard ok else { done("not-allowed"); return }
            do { try self.begin(lang: lang); done(nil) } catch { done("audio-capture") }
        }
    }

    private func begin(lang: String) throws {
        finish(notify: false)
        guard let rec = SFSpeechRecognizer(locale: Locale(identifier: lang)), rec.isAvailable else {
            throw NSError(domain: "EDP", code: 1)
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req
        let input = engine.inputNode
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buf, _ in req.append(buf) }
        engine.prepare()
        try engine.start()
        running = true
        task = rec.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                if let r = result { self?.onText?(r.bestTranscription.formattedString, r.isFinal) }
                if error != nil || result?.isFinal == true { self?.finish(notify: true) }
            }
        }
    }

    /// Arrêt demandé : on coupe le micro, Apple renvoie le texte final, puis on termine.
    func stop() {
        guard running else { return }
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.finish(notify: true) }
    }

    private func finish(notify: Bool) {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio(); request = nil
        task?.cancel(); task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if running && notify { running = false; onEnd?() } else if !notify { running = false }
    }
}
