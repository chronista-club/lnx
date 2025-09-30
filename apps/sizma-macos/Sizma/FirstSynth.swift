import Foundation
import AVFoundation

/// オーディオファイルの再生を管理するシンセサイザークラス
class FirstSynth: Loggable {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
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

    /// オーディオエンジンを起動する
    /// - Throws: オーディオエンジンの起動に失敗した場合
    func start() throws {
        #if os(macOS)
        // macOSではAVAudioSessionは使用しない
        #else
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif

        try audioEngine.start()
        log("Audio engine started")
    }

    func stop() {
        audioEngine.stop()
        log("Audio engine stopped")
    }

    /// オーディオファイルをスケジュールして再生する
    /// - Parameter url: 再生するオーディオファイルのURL
    private func scheduleAndPlay(at url: URL) {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            playerNode.stop()
            playerNode.scheduleFile(audioFile, at: nil) {
                // ファイル再生完了後のクリーンアップ
                // 次回再生のために状態をリセット
            }
            playerNode.play()
            isFileScheduled = true
            log("Playing audio file: \(url.lastPathComponent)")
        } catch {
            logError("Failed to play audio file: \(error)")
            isFileScheduled = false
        }
    }

    /// オーディオの再生を一時停止する
    func pause() {
        guard isPlaying else {
            logWarning("Audio is not playing")
            return
        }
        playerNode.pause()
        log("Audio playback paused")
    }

    /// 一時停止したオーディオを再開する
    func resume() {
        guard !isPlaying && isFileScheduled else {
            logWarning("Cannot resume: audio is already playing or no file is scheduled")
            return
        }
        playerNode.play()
        log("Audio playback resumed")
    }

    /// オーディオの再生を停止する
    func stopPlayback() {
        playerNode.stop()
        isFileScheduled = false
        log("Audio playback stopped")
    }

    /// オーディオの再生をトグルする（再生/一時停止/再開）
    /// - Parameter url: 再生するオーディオファイルのURL
    func togglePlayback(at url: URL) {
        if !isFileScheduled {
            // 初回再生 - ファイルをスケジュール
            scheduleAndPlay(at: url)
        } else if isPlaying {
            // 再生中 - 一時停止
            pause()
        } else {
            // 一時停止中 - 再開
            resume()
        }
    }

    /// オーディオファイルを再生する（互換性のため残されたメソッド）
    /// - Parameter url: 再生するオーディオファイルのURL
    @available(*, deprecated, message: "Use togglePlayback(at:) instead")
    func playAudioFile(at url: URL) {
        scheduleAndPlay(at: url)
    }
}