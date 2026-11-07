import SwiftUI

struct PhonesView: View {
    @EnvironmentObject var model: AppModel
    @State private var forgetting: Record?

    var body: some View {
        Group {
            if model.records.isEmpty {
                EmptyState(symbol: "iphone.gen3", title: "No iPhones Yet", message: "iPhones you set up with Poki Setup appear here, with how long Poki stays signed.")
            } else {
                Form {
                    ForEach(model.records) { r in section(r) }
                }
                .formStyle(.grouped)
            }
        }
        .confirmationDialog("Forget \(forgetting?.phoneName ?? "this iPhone")?", isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } }), presenting: forgetting) { r in
            Button("Forget", role: .destructive) { Task { await model.forget(udid: r.udid) } }
        } message: { _ in
            Text("Poki stays on the iPhone, but Poki Setup stops renewing it.")
        }
        .task { await model.refreshRecords() }
    }

    @ViewBuilder private func section(_ r: Record) -> some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: "iphone.gen3").font(.system(size: 28, weight: .light)).foregroundStyle(Color.pokiBlue).frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(r.phoneName).font(.headline)
                    Text("iOS \(r.ios) · Poki \(r.version) (\(r.build))").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                ExpiryBadge(record: r)
            }
            .padding(.vertical, 4)
            LabeledContent("Signed") { Text(Date(timeIntervalSince1970: TimeInterval(r.signedAt)).formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
            LabeledContent("Stays Signed Until") { Text(r.expires.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary) }
            LabeledContent("Team") { Text(r.teamIsFree ? "\(r.teamName), free" : r.teamName).foregroundStyle(.secondary) }
            LabeledContent("Bundle ID") { Text(r.bundleId).foregroundStyle(.secondary).textSelection(.enabled) }
            if let e = r.lastError {
                Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.callout)
            }
            if let steps = model.steps["renew"], !steps.isEmpty, model.busyJobs.contains("renew") {
                StepsView(steps: steps)
            }
            HStack {
                Button("Forget…", role: .destructive) { forgetting = r }
                Spacer()
                Button("Renew Now") {
                    Task {
                        do { try await model.renew(udid: r.udid) } catch { model.report(error) }
                    }
                }
                .disabled(model.busyJobs.contains("renew"))
            }
        }
    }
}

struct ExpiryBadge: View {
    var record: Record

    var body: some View {
        let color: Color = record.isExpired ? .red : (record.daysLeft <= 2 ? .orange : .green)
        Text(relativeDays(record))
            .font(.callout.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(color)
            .background(color.opacity(0.14), in: Capsule())
    }
}
