import AppKit
import SwiftUI

// Poki's look on the Mac: Liquid Glass on macOS 26 and later, the same shapes in system
// materials on macOS 14 and 15. Every glass call goes through here, so older systems never
// reach an API they lack.

extension View {
    /// A glass surface in `shape`, tinted with Poki blue when `tinted`.
    @ViewBuilder
    func pokiGlass<S: Shape>(in shape: S, tinted: Bool = false, interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(Glass.regular.tint(tinted ? Color.pokiBlue.opacity(0.55) : nil).interactive(interactive), in: shape)
        } else {
            self.materialFallback(in: shape, tinted: tinted)
        }
        #else
        self.materialFallback(in: shape, tinted: tinted)
        #endif
    }

    @ViewBuilder
    fileprivate func materialFallback<S: Shape>(in shape: S, tinted: Bool) -> some View {
        self
            .background {
                ZStack {
                    shape.fill(.regularMaterial)
                    if tinted { shape.fill(Color.pokiBlue.gradient.opacity(0.85)) }
                }
            }
            .overlay { shape.stroke(.white.opacity(tinted ? 0.35 : 0.18), lineWidth: 1) }
            .shadow(color: .black.opacity(0.10), radius: 10, y: 3)
    }

    /// The main action of a page: a Poki-blue glass button (a filled blue button before macOS 26).
    @ViewBuilder
    func pokiProminentButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent).tint(.pokiBlue)
        } else {
            self.buttonStyle(.borderedProminent).tint(.pokiBlue)
        }
        #else
        self.buttonStyle(.borderedProminent).tint(.pokiBlue)
        #endif
    }

    /// A secondary action: glass on macOS 26, a bordered button before.
    @ViewBuilder
    func pokiSecondaryButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
        #else
        self.buttonStyle(.bordered)
        #endif
    }

    /// A page of grouped rows over Poki's blue backdrop.
    func pokiPage() -> some View {
        self
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background { BrandBackdrop() }
    }
}

/// A soft wash of Poki blue at the top of each page, fading into the window background, so the
/// glass has colour to pick up without making rows hard to read.
struct BrandBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack(alignment: .top) {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [Color.pokiBlue.opacity(scheme == .dark ? 0.45 : 0.30), Color.pokiSky.opacity(scheme == .dark ? 0.12 : 0.10), .clear],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 360)
            RadialGradient(colors: [Color.pokiSky.opacity(scheme == .dark ? 0.25 : 0.22), .clear], center: .topTrailing, startRadius: 10, endRadius: 420)
                .frame(height: 420)
        }
        .ignoresSafeArea()
    }
}

/// The app's own icon, for headers.
struct AppIconImage: View {
    var size: CGFloat

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The big header of a page: Poki's icon or a symbol in a blue glass circle, a title and a line.
struct PageHero<Trailing: View>: View {
    var symbol: String?
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 16) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .pokiGlass(in: Circle(), tinted: true)
                } else {
                    AppIconImage(size: 60)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.bold))
                Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 6)
    }
}

extension PageHero where Trailing == EmptyView {
    init(symbol: String?, title: String, subtitle: String) {
        self.init(symbol: symbol, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A hero row inside a grouped Form: no box of its own, the page backdrop shows through.
struct HeroSection<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Section {
            content()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }
}

extension Color {
    /// Poki's lighter blue, for gradients.
    static let pokiSky = Color(red: 90 / 255, green: 167 / 255, blue: 255 / 255)
}
