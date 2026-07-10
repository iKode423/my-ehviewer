import AVFoundation
import AVKit
import SwiftUI

/// Plays one persistent shared video with native controls and resume support.
struct SharedVideoPlayerView: View {
    @EnvironmentObject private var store: SharedMediaStore
    let recordID: UUID
    @State private var player: AVPlayer?
    @State private var didCompletePlayback = false

    var body: some View {
        Group {
            if let player {
                NativeVideoPlayer(player: player)
                    .ignoresSafeArea(edges: .bottom)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .navigationTitle(record?.displayName ?? AppCopy.sharedMediaVideoTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let record {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { store.toggleFavorite(record) } label: {
                        Image(systemName: record.isFavorite ? "heart.fill" : "heart")
                            .foregroundStyle(record.isFavorite ? .pink : .primary)
                    }
                    .accessibilityLabel(AppCopy.sharedMediaFavorite)
                }
            }
        }
        .task(id: recordID) { preparePlayer() }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard let player, notification.object as? AVPlayerItem === player.currentItem else { return }
            didCompletePlayback = true
            if let record { store.updatePlayback(record, position: 0, completed: true) }
        }
        .onDisappear { persistPlaybackPosition() }
    }

    private var record: SharedMediaRecord? {
        store.records.first { $0.id == recordID }
    }

    /// Configures audio, creates the native player, and restores the saved position.
    private func preparePlayer() {
        guard player == nil, let record else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let player = AVPlayer(url: store.fileURL(for: record))
        if record.lastPlaybackPosition > 0 {
            player.seek(to: CMTime(seconds: record.lastPlaybackPosition, preferredTimescale: 600))
        }
        self.player = player
        player.play()
    }

    /// Saves the current position unless the video already reached its end.
    private func persistPlaybackPosition() {
        guard !didCompletePlayback, let record, let player else { return }
        let seconds = player.currentTime().seconds
        store.updatePlayback(record, position: seconds.isFinite ? seconds : 0, completed: false)
        player.pause()
    }
}

/// Embeds AVPlayerViewController for full native playback controls and Picture in Picture.
private struct NativeVideoPlayer: UIViewControllerRepresentable {
    let player: AVPlayer

    /// Creates the system video player with modern playback features enabled.
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.updatesNowPlayingInfoCenter = true
        controller.entersFullScreenWhenPlaybackBegins = false
        controller.exitsFullScreenWhenPlaybackEnds = true
        return controller
    }

    /// Keeps the controller attached to the current player instance.
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player !== player {
            uiViewController.player = player
        }
    }
}
