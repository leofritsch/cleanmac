import SwiftUI

struct CleanSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let session = model.cleanSession {
                switch session.phase {
                case .confirm: confirm(session)
                case .running(let title, let fraction): running(title, fraction)
                case .done(let outcome): done(outcome)
                }
            }
        }
        .padding(26)
        .frame(width: 540)
    }

    // MARK: Confirm

    private func confirm(_ session: CleanSession) -> some View {
        @Bindable var model = model
        let fileItems = session.items.filter(\.action.touchesFiles)
        let commandItems = session.items.filter {
            if case .command = $0.action { return true } else { return false }
        }
        let personal = session.items.filter { $0.safety == .personal }
        let permanent = model.cleanMode == .delete || fileItems.isEmpty

        return VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.bytes > 0 ? "Clean \(Fmt.bytes(session.bytes))?" : "Clean \(session.items.count) item\(session.items.count == 1 ? "" : "s")?")
                    .font(.system(size: 22, weight: .semibold))
                Text("\(session.items.count) item\(session.items.count == 1 ? "" : "s") selected")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(session.items) { item in
                        HStack(spacing: 10) {
                            SafetyDot(safety: item.safety)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.title).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                                Text(detail(item))
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(item.bytes < 0 ? "—" : Fmt.bytes(item.bytes))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                    }
                }
            }
            .frame(maxHeight: 220)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if !fileItems.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $model.cleanMode) {
                        Text("Move to Trash").tag(CleanMode.trash)
                        Text("Delete immediately").tag(CleanMode.delete)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .tint(Theme.accent)
                    Text(model.cleanMode == .trash
                         ? "You can put files back until you empty the Trash. The space comes back once you do."
                         : "Files are removed right away and can't be restored. The space comes back immediately.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if session.items.contains(where: { if case .removeContents(_, true) = $0.action { true } else { false } }) {
                Label("Emptying the Trash deletes what's in it now for good. Files this clean moves to the Trash stay there.", systemImage: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !commandItems.isEmpty {
                Label("Simulators, runtimes and snapshots are removed with Apple's own tools (simctl, tmutil) and can't be put back.", systemImage: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !personal.isEmpty {
                Label("\(personal.count) of these contain your data, such as settings, messages or documents. Make sure you don't need them.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.personal)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.cleanSession = nil }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button(permanent ? "Delete" : "Move to Trash") { model.runClean() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .tint(permanent ? Theme.personal : Theme.accent)
            }
        }
    }

    /// The exact path or command, so the person confirms what actually happens.
    private func detail(_ item: StorageItem) -> String {
        switch item.action {
        case .remove(let urls):
            urls.count == 1 ? Paths.tilde(urls[0]) : "\(urls.count) folders, starting with \(Paths.tilde(urls[0]))"
        case .removeContents(let dir, _):
            "Everything inside \(Paths.tilde(dir))"
        case .command(let tool, let args, _):
            "\((tool as NSString).lastPathComponent) \(args.joined(separator: " "))"
        case .none:
            item.action.describe
        }
    }

    // MARK: Running

    private func running(_ title: String, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Cleaning…")
                .font(.system(size: 22, weight: .semibold))
            ProgressView(value: fraction)
                .tint(Theme.accent)
            Text(title.isEmpty ? "Finishing up" : title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: Done

    private func done(_ outcome: CleanOutcome) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: outcome.failures.isEmpty ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(outcome.failures.isEmpty ? Theme.safe : Theme.review)
                VStack(alignment: .leading, spacing: 2) {
                    Text(outcome.freed > 0 ? "Freed \(Fmt.bytes(outcome.freed))" : "Done")
                        .font(.system(size: 22, weight: .semibold))
                    Text("\(outcome.cleaned) cleaned" + (outcome.failures.isEmpty ? "" : ", \(outcome.failures.count) couldn't be removed"))
                        .foregroundStyle(.secondary)
                }
            }
            if outcome.usedTrash && outcome.freed > 0 {
                Text("The files are in the Trash. Empty it to get the space back.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            if !outcome.failures.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(outcome.failures) { f in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.title).font(.system(size: 12.5, weight: .medium))
                                Text(f.reason)
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                }
                .frame(maxHeight: 180)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack {
                Spacer()
                Button("Done") { model.cleanSession = nil }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .tint(Theme.accent)
            }
        }
    }
}
