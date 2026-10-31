import AVFoundation
import Foundation

// MARK: - SoundEngine
//
// Original, synthesised sounds — no copyrighted audio, no asset files.
// A short oscillator / noise burst per effect, played through AVAudioEngine.
// If audio fails, the game continues silently; sound is never load-bearing.
//
// FIX 27 Oct 2026 — crash on iPhone Duo simulator (iOS 27.1):
//   Terminating app due to uncaught exception 'com.apple.coreaudio.avfaudio',
//   reason: 'required condition is false: inputNode != nullptr || outputNode != nullptr'
//
// Root cause, in the old code:
//   1. play() called engine.start() inside a Swift do/catch. That cannot
//      catch this crash — it is an NSException raised inside AVAudioEngine,
//      not a Swift error. The search result for this exact assertion says
//      the same: start() can crash even wrapped in do/catch, with
//      [AVAudioEngineGraph.mm:1209:Initialize: (inputNode != nullptr ||
//      outputNode != nullptr)].
//   2. tone() / noise() read engine.mainMixerNode.outputFormat(forBus: 0)
//      BEFORE the engine was known to be running. On a simulator with no
//      audio output device, the engine graph has no input/output node yet,
//      so touching the mixer / starting the engine trips that assertion.
//   3. There was no AVAudioSession setup and no check that an audio
//      output route actually exists.
//
// Fix:
//   - On the simulator, sounds are a no-op. AVAudioEngine audio is
//     unreliable there (no guaranteed output device), and Foldfleet is
//     not an audio app — the game must never crash for a tap sound.
//     Real-device sound is unchanged.
//   - On a real device, check AVAudioSession.currentRoute.outputs first.
//     If there is no output route, mark audio unavailable once and never
//     retry — do not call engine.start() at all.
//   - Configure the session (.ambient, mixWithOthers) and activate it
//     before starting, with Swift errors caught.
//   - Build buffers with a fixed AVAudioFormat (44.1 kHz, mono) instead
//     of reading the mixer format before the engine is running.
//   - No force-unwraps on buffers / channel data anymore.

public enum SoundEffect {
    case tap
    case sonar
    case launch
    case splash   // miss
    case explosion // hit / sunk
    case victory
    case defeat
}

/// @MainActor: AVAudioEngine is driven from the main thread only, and all
/// callers are SwiftUI / the @MainActor ViewModel. Keeps Swift 6 happy.
@MainActor
public final class SoundEngine {
    public static let shared = SoundEngine()
    private let engine = AVAudioEngine()
    private var isRunning = false
    /// Latched once audio proves unavailable, so we never retry a
    /// start() that could raise an NSException.
    private var audioUnavailable = false

    private init() {}

    public func play(_ effect: SoundEffect, enabled: Bool) {
        guard enabled else { return }
        // Simulator: no sound at all. See the header comment — the
        // Duo simulator has no guaranteed audio output device, and
        // AVAudioEngine.start() can raise an uncatchable NSException
        // there. The game plays silently instead of crashing.
        #if targetEnvironment(simulator)
        return
        #endif
        guard ensureRunning() else { return }
        switch effect {
        case .tap: tone(frequency: 880, duration: 0.06, volume: 0.15)
        case .sonar: tone(frequency: 440, duration: 0.35, volume: 0.2, slideTo: 660)
        case .launch: noise(duration: 0.25, volume: 0.25, lowpass: 1200)
        case .splash: noise(duration: 0.4, volume: 0.3, lowpass: 800)
        case .explosion: noise(duration: 0.6, volume: 0.4, lowpass: 400)
        case .victory: arpeggio([523, 659, 784, 1047])
        case .defeat: arpeggio([392, 330, 262])
        }
    }

    /// Gentle looping water ambience is NOT in v1. Sounds are one-shot
    /// effects only; there is no looping track, and Settings no longer
    /// offers a toggle for one.

    @discardableResult
    private func ensureRunning() -> Bool {
        if isRunning { return true }
        if audioUnavailable { return false }
        #if targetEnvironment(simulator)
        audioUnavailable = true
        return false
        #endif

        // No output route (no speaker / headphones / AirPlay) means the
        // engine graph would have no output node. Do not call start().
        let session = AVAudioSession.sharedInstance()
        if session.currentRoute.outputs.isEmpty {
            audioUnavailable = true
            return false
        }
        do {
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            audioUnavailable = true
            return false
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true
        } catch {
            // Swift error from start(): safe to catch, unlike the
            // NSException above, which we avoid by the route check.
            audioUnavailable = true
            isRunning = false
        }
        return isRunning
    }

    /// A fixed format, so we never read the mixer format before the
    /// engine is running. Returns nil instead of force-unwrapping.
    private func makeBuffer(frames: Int) -> (buffer: AVAudioPCMBuffer, channel: UnsafeMutablePointer<Float>)? {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channel = buffer.floatChannelData?[0] else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        return (buffer, channel)
    }

    private func tone(frequency: Double, duration: Double, volume: Float, slideTo: Double? = nil) {
        guard isRunning else { return }
        let sampleRate = 44_100.0
        let frames = Int(sampleRate * duration)
        guard let (buffer, channel) = makeBuffer(frames: frames) else { return }
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let f = slideTo.map { frequency + ($0 - frequency) * (t / duration) } ?? frequency
            let envelope = 1.0 - (t / duration)
            channel[i] = Float(sin(2 * .pi * f * t) * envelope) * volume
        }
        playBuffer(buffer)
    }

    private func noise(duration: Double, volume: Float, lowpass: Double) {
        // White noise with a simple one-pole low-pass — a splash / boom.
        guard isRunning else { return }
        let sampleRate = 44_100.0
        let frames = Int(sampleRate * duration)
        guard let (buffer, channel) = makeBuffer(frames: frames) else { return }
        var last: Float = 0
        let alpha = Float(lowpass / sampleRate)
        for i in 0..<frames {
            let t = Double(i) / sampleRate
            let envelope = Float(1.0 - (t / duration))
            let white = Float.random(in: -1...1)
            last += alpha * (white - last)
            channel[i] = last * volume * envelope
        }
        playBuffer(buffer)
    }

    private func arpeggio(_ notes: [Double]) {
        // MainActor task (not DispatchQueue) so the delayed tones stay
        // on the actor that owns the audio engine. Each tone() re-checks
        // isRunning, so a late note is skipped if audio stopped.
        Task { @MainActor [weak self] in
            for (index, note) in notes.enumerated() {
                if index > 0 { try? await Task.sleep(for: .milliseconds(140)) }
                self?.tone(frequency: note, duration: 0.22, volume: 0.2)
            }
        }
    }

    private func playBuffer(_ buffer: AVAudioPCMBuffer) {
        // Only touch the mixer after the engine is actually running.
        guard isRunning, engine.isRunning else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: buffer.format)
        player.scheduleBuffer(buffer) {
            // Completion may arrive off the main thread; hop back.
            Task { @MainActor [weak self] in
                self?.engine.detach(player)
            }
        }
        player.play()
    }
}
