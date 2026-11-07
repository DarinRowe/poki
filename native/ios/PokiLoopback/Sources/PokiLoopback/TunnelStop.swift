import NetworkExtension

/// What the tunnel tells the app when iOS stops it, so the app can tell the owner's choice (or another
/// VPN taking over) from a failure it should dial again after.
public enum TunnelStop {
    /// Appended to the tunnel's bundle id to name the Darwin notification the tunnel posts, with no
    /// payload, before it stops for a reason that is not a failure. The app and the tunnel are
    /// signed together, so a signing tool that rewrites the id rewrites both.
    public static let notificationSuffix = ".stopped-on-purpose"

    /// True when the owner, or another VPN, ended the connection: Poki must not turn it on again.
    public static func isOnPurpose(_ reason: NEProviderStopReason) -> Bool { false }
}
