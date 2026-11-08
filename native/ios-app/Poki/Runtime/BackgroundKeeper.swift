import CoreLocation
import Foundation

/// Keeps Poki running in the background while it is on, so the relay connection and the launcher stay
/// up: silent audio, plus, with Always Allow, location updates at the coarsest accuracy. With Always
/// Allow iOS keeps the location indicator out of the status bar and Dynamic Island; with While Using
/// it would show the pill all the time Poki is on, so Poki uses silent audio alone then. The location
/// is never read or sent anywhere.
@MainActor
@Observable
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var activity: CLBackgroundActivitySession?
    private let audio = KeepAlive()
    private(set) var authorization: CLAuthorizationStatus
    private(set) var isOn = false

    override init() {
        authorization = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.distanceFilter = CLLocationDistanceMax
        manager.pausesLocationUpdatesAutomatically = false
    }

    var allowed: Bool { authorization == .authorizedWhenInUse || authorization == .authorizedAlways }
    var denied: Bool { authorization == .denied || authorization == .restricted }

    /// Always Allow lets Poki stay up without the location pill. iOS asks for While Using first and
    /// offers the upgrade on the second request.
    var always: Bool { authorization == .authorizedAlways }

    func requestPermission() {
        if authorization == .notDetermined { manager.requestWhenInUseAuthorization() } else { manager.requestAlwaysAuthorization() }
    }

    /// Called while Poki is in front (iOS only starts background location from the foreground).
    func start() {
        guard !isOn else { return }
        isOn = true
        if always { startLocation() } else if authorization == .notDetermined { requestPermission() }
        try? audio.start()
    }

    /// A voice conversation needs the audio session for the microphone; the voice-chat session keeps
    /// Poki running meanwhile. The silent audio comes back when it ends, if Poki is still on.
    func pauseAudio() { audio.stop() }
    func resumeAudio() { if isOn { try? audio.start() } }

    func stop() {
        guard isOn else { return }
        isOn = false
        stopLocation()
        audio.stop()
    }

    private func startLocation() {
        guard always else { stopLocation(); return }
        manager.allowsBackgroundLocationUpdates = true
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
    }

    private func stopLocation() {
        manager.stopUpdatingLocation()
        activity?.invalidate(); activity = nil
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if self.isOn { self.startLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
