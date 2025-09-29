import Foundation
import AVFoundation

class FirstSynth: Loggable {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var audioFile: AVAudioFile?
    private var isFileScheduled = false
    var isPlaying: Bool {
        return playerNode.isPlaying
    }

    init() {
        self.audioEngine = AVAudioEngine()
        self.playerNode = AVAudioPlayerNode()

        audioEngine.attach(playerNode)
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: nil)

        log("FirstSynth initialized")
    }

    func start() {
        do {
            try audioEngine.start()
            log("Audio engine started")
        } catch {
            logError("Failed to start audio engine: \(error)")
        }
    }

    func stop() {
        audioEngine.stop()
        log("Audio engine stopped")
    }

    private func scheduleAndPlay(at url: URL) {
        do {
            audioFile = try AVAudioFile(forReading: url)
            if let audioFile = audioFile {
                playerNode.stop()
                playerNode.scheduleFile(audioFile, at: nil)
                playerNode.play()
                isFileScheduled = true
                log("Playing audio file: \(url.lastPathComponent)")
            }
        } catch {
            logError("Failed to play audio file: \(error)")
        }
    }

    func pause() {
        playerNode.pause()
        log("Audio playback paused")
    }

    func resume() {
        playerNode.play()
        log("Audio playback resumed")
    }

    func stopPlayback() {
        playerNode.stop()
        isFileScheduled = false
        log("Audio playback stopped")
    }

    func togglePlayback(at url: URL) {
        if !isFileScheduled {
            // First time playing - schedule the file
            scheduleAndPlay(at: url)
        } else if isPlaying {
            // Currently playing - pause it
            pause()
        } else {
            // Currently paused - resume it
            resume()
        }
    }

    // Legacy method for compatibility
    func playAudioFile(at url: URL) {
        scheduleAndPlay(at: url)
    }
}