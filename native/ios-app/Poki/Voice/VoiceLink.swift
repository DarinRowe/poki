import AVFoundation
import Foundation
import WebRTC

/// One WebRTC connection to the OpenAI Realtime API: the microphone as the audio track, the model's
/// voice on the speaker, and the `oai-events` data channel for events. Opened with a short-lived client
/// secret; it never sees an API key. Callbacks arrive on the main actor.
final class VoiceLink: NSObject, RTCPeerConnectionDelegate, RTCDataChannelDelegate, @unchecked Sendable {
    private static let factory: RTCPeerConnectionFactory = {
        // Voice chat: echo cancellation on, so Poki's own voice from the speaker doesn't interrupt it.
        let audio = RTCAudioSessionConfiguration.webRTC()
        audio.category = AVAudioSession.Category.playAndRecord.rawValue
        audio.mode = AVAudioSession.Mode.voiceChat.rawValue
        audio.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        RTCAudioSessionConfiguration.setWebRTC(audio)
        return RTCPeerConnectionFactory()
    }()

    private let onEvent: @MainActor ([String: Any]) -> Void
    private let onClosed: @MainActor (String) -> Void
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var remoteAudio: RTCAudioTrack?
    private var volume = 1.0
    private var closing = false

    init(onEvent: @escaping @MainActor ([String: Any]) -> Void, onClosed: @escaping @MainActor (String) -> Void) {
        self.onEvent = onEvent
        self.onClosed = onClosed
    }

    func connect(secret: String) async throws {
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        guard let peer = Self.factory.peerConnection(with: config, constraints: constraints, delegate: self) else { throw VoiceError.realtime(0, "WebRTC could not start") }
        self.peer = peer
        let mic = Self.factory.audioTrack(with: Self.factory.audioSource(with: constraints), trackId: "poki-mic")
        peer.add(mic, streamIds: ["poki-voice"])
        let channel = peer.dataChannel(forLabel: "oai-events", configuration: RTCDataChannelConfiguration())
        channel?.delegate = self
        self.channel = channel

        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { done in
            peer.offer(for: constraints) { sdp, error in
                if let sdp { done.resume(returning: sdp) } else { done.resume(throwing: error ?? VoiceError.realtime(0, "no offer")) }
            }
        }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(offer) { error in if let error { done.resume(throwing: error) } else { done.resume() } }
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        request.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(offer.sdp.utf8)
        let (data, response) = try await URLSession.shared.data(for: request)
        let answer = String(decoding: data, as: UTF8.self)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw VoiceError.realtime(http.statusCode, String(answer.prefix(300)))
        }
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in if let error { done.resume(throwing: error) } else { done.resume() } }
        }
        let deadline = Date().addingTimeInterval(10)
        while channel?.readyState != .open {
            if Date() > deadline { throw VoiceError.timeout("Opening the voice connection") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @discardableResult
    func send(_ event: [String: Any]) -> Bool {
        guard let channel, channel.readyState == .open, let data = try? JSONSerialization.data(withJSONObject: event) else { return false }
        return channel.sendData(RTCDataBuffer(data: data, isBinary: false))
    }

    /// 0 mutes Poki's voice (silent test runs); 1 is normal.
    func setRemoteVolume(_ value: Double) {
        volume = value
        remoteAudio?.source.volume = value
    }

    func close() {
        closing = true
        channel?.close()
        peer?.close()
        channel = nil
        peer = nil
    }

    private func lost(_ reason: String) {
        guard !closing else { return }
        closing = true
        let onClosed = onClosed
        Task { @MainActor in onClosed(reason) }
    }

    // MARK: RTCDataChannelDelegate

    func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        if dataChannel.readyState == .closed { lost("the data channel closed") }
    }

    func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        guard let event = try? JSONSerialization.jsonObject(with: buffer.data) as? [String: Any] else { return }
        let onEvent = onEvent
        Task { @MainActor in onEvent(event) }
    }

    // MARK: RTCPeerConnectionDelegate

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        switch newState {
        case .failed: lost("the network path failed")
        case .disconnected: lost("the network dropped")
        default: break
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let track = rtpReceiver.track as? RTCAudioTrack else { return }
        remoteAudio = track
        track.source.volume = volume
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
