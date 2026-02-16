import SwiftUI
import AVKit

struct LoopingVideoPlayer: UIViewRepresentable {
    let videoURL: URL
    
    func makeUIView(context: Context) -> UIView {
        return PlayerUIView(frame: .zero, url: videoURL)
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // No update needed for static URL
    }
}

class PlayerUIView: UIView {
    private var playerLayer = AVPlayerLayer()
    private var playerLooper: AVPlayerLooper?
    
    init(frame: CGRect, url: URL) {
        super.init(frame: frame)
        
        let playerItem = AVPlayerItem(url: url)
        let queuePlayer = AVQueuePlayer(playerItem: playerItem)
        playerLayer.player = queuePlayer
        playerLayer.videoGravity = .resizeAspectFill
        
        // Loop the video
        playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)
        
        layer.addSublayer(playerLayer)
        
        queuePlayer.isMuted = true
        queuePlayer.play()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
