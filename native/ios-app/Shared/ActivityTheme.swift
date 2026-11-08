// The Live Activity's colours, type and motion in one place. `ActivityMotion.phase` and the row
// transition are taken from leepokai/Codync (commit 848070d, apps/ios/Kit/Sources/CodyncKit/Design/
// Motion.swift and ActivityCards.swift), Copyright 2026 Po Kai Lee, Apache License 2.0. See
// THIRD_PARTY_NOTICES.md.
import SwiftUI

/// The website's colours (poki-site, ESP-139's token table and its final boards 01 to 05): the one
/// table the app's screens and the Live Activity both draw with.
enum Site {
    static let blue = Color(hex: 0x0077FD)
    static let sky = Color(hex: 0x5AA7FF)
    /// The page in dark mode (the docs site's blue); the boards draw light mode only.
    static let night = Color(hex: 0x0A2F6B)
    #if POKI_APP
    // The app's screens use the system's own colours, light and dark (grouped backgrounds, labels,
    // separators); only the Live Activity keeps the website's palette below.
    static let ink = Color.accentColor
    static let ok = Color(.systemGreen)
    static let bad = Color(.systemRed)
    static let c3 = Color(.secondaryLabel)
    static let c4 = Color(.secondaryLabel)
    static let glass = Color(.secondarySystemGroupedBackground)
    static let glass2 = Color(.tertiarySystemGroupedBackground)
    static let edge = Color(.separator)
    static let edgeTop = Color(.separator)
    static let text = Color(.label)
    static let text2 = Color(.secondaryLabel)
    static let text3 = Color(.tertiaryLabel)
    static let hair = Color(.separator)
    static let tint = Color(.systemFill)
    static let okInk = Color(.systemGreen)
    static let danger = Color(.systemRed)
    #else
    /// Blue text on white: the text of a white capsule button.
    static let ink = Color(hex: 0x0060D8)
    static let ok = Color(hex: 0x5BE37A)
    static let bad = Color(hex: 0xFF5F57)
    /// White text on blue, second and third level (--site-c3, --site-c4).
    static let c3 = Color.white.opacity(0.84)
    static let c4 = Color.white.opacity(0.72)
    /// Glass on blue: the card, the capsule and badge fill, the edge (with a brighter top line).
    static let glass = Color.white.opacity(0.08)
    static let glass2 = Color.white.opacity(0.16)
    static let edge = Color.white.opacity(0.28)
    static let edgeTop = Color.white.opacity(0.55)
    /// Inside the white cards: text, secondary text, placeholder and values, dividers.
    static let text = Color(hex: 0x111111)
    static let text2 = Color(hex: 0x6B6B70)
    static let text3 = Color(hex: 0x8A8A8E)
    static let hair = Color(hex: 0xE0E1E9)
    /// Light blue: tags, secondary buttons and the countdown on white.
    static let tint = Color(hex: 0xE5F1FF)
    /// Green and red text on white.
    static let okInk = Color(hex: 0x12A150)
    static let danger = Color(hex: 0xD93A32)
    #endif
}

/// What a piece of the Live Activity is coloured by. Each face picks one; the surface's palette says
/// what it is, so the blue card and the black island can colour the same word differently.
enum ActivityTone: Hashable {
    /// Secondary: the app's name while working, the meta values.
    case quiet
    /// The text colour itself.
    case plain
    case accent, approval, done, problem
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
    /// Secondary buttons (Stop, Deny).
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
        }
    }
}

/// Every colour, font and size the Live Activity draws with: the website's design language.
struct ActivityTheme {
    /// White words on the blue card: the status word itself says which phase it is.
    var lock = ActivityPalette(
        quiet: .white.opacity(0.72), accent: .white, approval: .white, done: .white,
        problem: .white, segmentDone: .white, track: .white.opacity(0.28), finished: .white)
    var island = ActivityPalette(
        quiet: Color(hex: 0x9A9A96), accent: Site.sky, approval: Site.sky, done: Site.ok,
        problem: Color(hex: 0xFF6961), segmentDone: Site.ok, track: Color(hex: 0x3A3A3A),
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

    /// Two text sizes and no more (ESP-162): `contentSize` only for the content line, the one thing
    /// that matters in a state; `textSize` for everything else.
    static let textSize: CGFloat = 15
    static let contentSize: CGFloat = 20
    /// Geist for English, as on the board; the system font for Chinese. Geist has no Chinese
    /// characters, and with it the Lock Screen and the island laid Chinese lines out narrower than
    /// they drew them, cutting off their ends (seen on the iPhone 17 Pro simulator).
    static let usesGeist = Bundle.main.preferredLocalizations.first?.hasPrefix("zh") != true
    private static func font(_ name: String, _ weight: Font.Weight, _ size: CGFloat) -> Font {
        usesGeist ? .custom(name, size: size) : .system(size: size, weight: weight)
    }
    var status = font("Geist-SemiBold", .semibold, textSize)
    var meta = font("Geist-Regular", .regular, textSize)
    var button = font("Geist-SemiBold", .semibold, textSize)
    /// Words in the compact island ("Step 7", "2/6").
    var compact = font("Geist-SemiBold", .semibold, textSize)
    /// The pairing code in the compact island, with tabular digits.
    var compactCode = font("Geist-Bold", .bold, textSize).monospacedDigit()
    /// Countdowns are SF Mono.
    var countdown = Font.system(size: textSize, weight: .semibold, design: .monospaced)
    var content = font("Geist-Bold", .bold, contentSize)
    var contentTracking: CGFloat = usesGeist ? -0.2 : 0

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
