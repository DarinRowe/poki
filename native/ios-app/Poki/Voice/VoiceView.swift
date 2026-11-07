import AVFoundation
import SwiftUI

/// Talk to Poki: say what to do, Poki does it on this iPhone and answers out loud.
struct VoiceView: View {
    @Environment(AppModel.self) private var app
    @State private var bridgeText = ""
    @State private var editingBridge = false
    @State private var bridgeRejected = false
    @State private var micDenied = false

    private var voice: VoiceModel { app.voice }

    var body: some View {
        @Bindable var voice = voice
        NavigationStack {
            List {
                // A tap that sends, pays, deletes or calls waits for the person in the Dynamic Island and the
                // Live Activity (or the notification), like every other approval.
                Section {
                    HStack(spacing: 14) {
                        Image(systemName: symbol).font(.title).foregroundStyle(voice.isOn ? Site.blue : .secondary)
                            .symbolEffect(.variableColor.iterative, isActive: voice.phase == .speaking || voice.phase == .hearing)
                            .frame(width: 40)
                        VStack(alignment: .leading) {
                            Text(voice.phase.label).font(.headline)
                            if let ms = voice.lastTurnMS { Text("Last answer \(ms) ms after you stopped").font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                    }
                    Button(voice.isOn ? "End conversation" : "Talk to Poki", systemImage: voice.isOn ? "stop.fill" : "mic.fill") {
                        if voice.isOn { voice.stop() } else { Task { await begin() } }
                    }
                    .buttonStyle(.glassProminent).controlSize(.large).frame(maxWidth: .infinity)
                    .disabled(voice.bridge == nil)
                    if voice.isOn {
                        Button("Stop talking", systemImage: "speaker.slash") { voice.stopTalking() }
                        Toggle("Mute Poki's voice", isOn: $voice.muted)
                    }
                } footer: {
                    if micDenied { Text("Poki can't use the microphone. Allow it in Settings, Privacy, Microphone.").foregroundStyle(.orange) }
                    else { Text("Stop talking ends Poki's reply; a step already running on the phone still finishes and Poki tells you how it went.") }
                }
                bridgeSection
                if !voice.lines.isEmpty {
                    Section("Conversation") {
                        ForEach(voice.lines) { line in
                            Label(line.text, systemImage: Self.icon(line.role))
                                .foregroundStyle(line.role == .note || line.role == .tool ? .secondary : .primary)
                                .font(line.role == .tool ? .subheadline : .body)
                        }
                    }
                }
            }
            .navigationTitle("Voice")
        }
    }

    @ViewBuilder private var bridgeSection: some View {
        Section {
            if let bridge = voice.bridge, !editingBridge {
                LabeledContent("Voice bridge") { Text(bridge.display).font(.body.monospaced()) }
                Button("Change address") { bridgeText = bridge.base.absoluteString; bridgeRejected = false; editingBridge = true }
            } else {
                TextField("http://your-mac.local:47830/voice/…", text: $bridgeText)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.body.monospaced())
                    .onSubmit(saveBridge)
                Button("Save address", action: saveBridge).disabled(bridgeText.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Your Mac")
        } footer: {
            if bridgeRejected { Text("That is not a voice bridge address. It looks like http://192.168.1.10:47830/voice/ followed by a long code.").foregroundStyle(.orange) }
            else { Text("Run bin/voice-bridge.mjs on your Mac and enter the address it gives. The Mac holds your OpenAI key and gives this phone a key that works for one minute, so the phone never stores it. Audio goes straight from this phone to OpenAI.") }
        }
    }

    private func saveBridge() {
        bridgeRejected = !voice.setBridge(bridgeText)
        if !bridgeRejected { editingBridge = false }
    }

    private func begin() async {
        micDenied = !(await AVAudioApplication.requestRecordPermission())
        guard !micDenied else { return }
        // Taps that send, pay, delete or call ask for the person's OK, also by notification.
        ApprovalNotice.requestPermission()
        await voice.start()
    }

    private var symbol: String {
        switch voice.phase {
        case .off: "waveform.slash"
        case .connecting: "antenna.radiowaves.left.and.right"
        case .listening, .hearing: "waveform"
        case .thinking: "hand.tap.fill"
        case .speaking: "speaker.wave.2.fill"
        case .lost: "exclamationmark.triangle.fill"
        }
    }

    private static func icon(_ role: VoiceLine.Role) -> String {
        switch role {
        case .you: "person.wave.2"
        case .poki: "pawprint.fill"
        case .tool: "hand.tap"
        case .note: "info.circle"
        }
    }
}
