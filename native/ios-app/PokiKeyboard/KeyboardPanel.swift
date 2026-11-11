import SwiftUI

/// What the panel shows. The keyboard has no keys: Poki types through it, and the owner types on
/// their own keyboard.
@MainActor
final class PanelModel: ObservableObject {
    enum Mode: Equatable { case idle, typing, needsFullAccess }
    @Published var mode = Mode.idle
    /// 0...1 of the text typed so far.
    @Published var progress = 0.0
    var takeOver: () -> Void = {}
    var switchKeyboard: () -> Void = {}
}

/// The keyboard's whole face: a line saying what Poki is doing and one button, on the system's own
/// keyboard backdrop. Native controls only (a ProgressView, a glass button on iOS 26 and a bordered
/// one before it), in the system's fonts and colours, so it follows light and dark with the keyboard.
struct KeyboardPanel: View {
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack(spacing: 14) {
            switch model.mode {
            case .typing:
                VStack(spacing: 10) {
                    Label(Words.typing, systemImage: "keyboard").font(.headline)
                    ProgressView(value: model.progress).frame(maxWidth: 220)
                }
                button(Words.takeOver, action: model.takeOver)
            case .idle:
                text(Words.idleTitle, Words.idleDetail)
                button(Words.switchKeyboard, action: model.switchKeyboard)
            case .needsFullAccess:
                text(Words.idleTitle, Words.fullAccess)
                button(Words.switchKeyboard, action: model.switchKeyboard)
            }
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.default, value: model.mode)
    }

    private func text(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.headline)
            Text(detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        if #available(iOS 26, *) {
            Button(title, action: action).buttonStyle(.glass)
        } else {
            Button(title, action: action).buttonStyle(.bordered)
        }
    }
}

/// The panel's few words, in English or Simplified Chinese after the iPhone's language.
enum Words {
    static let chinese = Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
    static var typing: String { chinese ? "Poki 正在输入…" : "Poki is typing…" }
    static var takeOver: String { chinese ? "我来输入" : "Take Over" }
    static var idleTitle: String { chinese ? "Poki 键盘" : "Poki Keyboard" }
    static var idleDetail: String { chinese ? "Poki 工作时通过这里输入。要自己输入，请切换到你的键盘。" : "Poki types through here while it works. To type yourself, switch to your own keyboard." }
    static var fullAccess: String { chinese ? "请在“设置”里为 Poki 键盘打开“允许完全访问”，它才能收到 Poki 要输入的文字。" : "Turn on Allow Full Access for the Poki keyboard in Settings, so it can receive the text Poki types." }
    static var switchKeyboard: String { chinese ? "切换键盘" : "Switch Keyboard" }
    static var nextKeyboard: String { chinese ? "下一个键盘" : "Next Keyboard" }
}
