// The Live Activity's colours, type and motion in one place. `ActivityMotion.phase` and the row
// transition are taken from leepokai/Codync (commit 848070d, apps/ios/Kit/Sources/CodyncKit/Design/
// Motion.swift and ActivityCards.swift), Copyright 2026 Po Kai Lee, Apache License 2.0. See
// THIRD_PARTY_NOTICES.md.
import SwiftUI

/// Poki's brand colours, used by the app's screens.
enum Brand {
    static let blue = Color(red: 0x20 / 255, green: 0x84 / 255, blue: 0xFD / 255)
}

/// The website's colours (poki-site, ESP-139's token table and its final board 02).
enum Site {
    static let blue = Color(hex: 0x0077FD)
    /// Blue text on white: the text of a white capsule button.
    static let ink = Color(hex: 0x0060D8)
    /// Blue text on black: the Dynamic Island.
    static let sky = Color(hex: 0x5AA7FF)
    static let ok = Color(hex: 0x5BE37A)
    static let bad = Color(hex: 0xFF5F57)
}

/// What a piece of the Live Activity is coloured by. Each face picks one; the surface's palette says
/// what it is, so the blue card and the black island can colour the same word differently.
enum ActivityTone: Hashable {
    /// Secondary: the app's name while working, the meta values, most subtitles.
    case quiet
    /// The text colour itself.
    case plain
    case accent, approval, done, problem
    /// The approval's reason line: white on the card, dimmed on the island.
    case reason
}

/// The Lock Screen card is the website's blue with glass on it; the Dynamic Island is always black.
enum ActivitySurface { case lockScreen, island }

struct ActivityPalette {
    var text = Color.white
    var quiet: Color
    var accent: Color
    var approval: Color
    var done: Color
    var problem: Color
    var reason: Color
    /// Secondary buttons (Stop, Don't Allow) and the answer on its way.
    var buttonFill = Color.white.opacity(0.16)
    /// The setup steps already done, and those still to do.
    var segmentDone: Color
    var track: Color
    /// The step line of a finished run.
    var finished: Color
    /// The one main button (Allow, Open Poki): a white capsule with blue text.
    var primaryFill = Color.white
    var primaryText = Site.ink

    func color(_ tone: ActivityTone) -> Color {
        switch tone {
        case .quiet: quiet
        case .plain: text
        case .accent: accent
        case .approval: approval
        case .done: done
        case .problem: problem
        case .reason: reason
        }
    }
}

/// Every colour, font and size the Live Activity draws with: the website's design language.
struct ActivityTheme {
    /// White words on the blue card: the status word itself says which phase it is.
    var lock = ActivityPalette(
        quiet: .white.opacity(0.72), accent: .white, approval: .white, done: .white,
        problem: .white, reason: .white, segmentDone: .white, track: .white.opacity(0.28), finished: .white)
    var island = ActivityPalette(
        quiet: Color(hex: 0x9A9A96), accent: Site.sky, approval: Site.sky, done: Site.ok,
        problem: Color(hex: 0xFF6961), reason: .white.opacity(0.72), segmentDone: Site.ok, track: Color(hex: 0x3A3A3A),
        finished: Color(hex: 0x3CCF7A))
    var lockBackground = Site.blue
    /// The glass edge on the blue card: a 1 pt white line, brighter along the top.
    var glassEdge = Color.white.opacity(0.28)
    var glassHighlight = Color.white.opacity(0.55)
    /// The island's outline while an approval waits.
    var approvalOutline = Site.blue
    /// The step line: steps that went through, one that did not, the hollow current step's centre.
    /// A finished run takes the surface's `finished` colour.
    var stepLine = Color.white
    var stepMissed = Site.bad
    var stepHole = Color.black
    /// The Face ID glyph on Allow.
    var primaryIcon = Color.black

    var status = Font.custom("Geist-SemiBold", size: 15)
    var meta = Font.custom("Geist-Regular", size: 13)
    var title = Font.custom("Geist-Bold", size: 20)
    var titleTracking: CGFloat = -0.2
    var subtitle = Font.custom("Geist-Regular", size: 13)
    var button = Font.custom("Geist-SemiBold", size: 15)
    /// Words in the compact island ("Step 7", "2/6").
    var compact = Font.custom("Geist-SemiBold", size: 13)
    /// The pairing code in the compact island, with tabular digits.
    var compactCode = Font.custom("Geist-Bold", size: 13).monospacedDigit()
    /// The compact island's "!".
    var compactMark = Font.custom("Geist-Bold", size: 17)
    /// Countdowns are SF Mono.
    var countdown = Font.system(size: 13, weight: .semibold, design: .monospaced)
    /// The pairing code, large.
    var code = Font.custom("Geist-Black", size: 46).monospacedDigit()
    var codeTracking: CGFloat = -0.92

    func palette(_ surface: ActivitySurface) -> ActivityPalette { surface == .lockScreen ? lock : island }

    static let current = ActivityTheme()
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

enum ActivityMotion {
    /// A phase change (working, needs you, done): a soft spring that finishes well inside the 2 s iOS
    /// gives Live Activity updates.
    static let phase = Animation.spring(duration: 0.6, bounce: 0.3)
}

extension AnyTransition {
    /// Rows a new phase brings (the buttons, the step line): rise and fade in.
    static var activityRow: AnyTransition {
        .asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity)
    }
}
