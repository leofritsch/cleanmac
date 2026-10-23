import Charts
import SwiftUI

struct OverviewView: View {
    @Environment(AppModel.self) private var model
    @State private var hovered: LayerID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 44) {
                header
                if !model.hasFullDiskAccess { AccessBanner() }
                if let report = model.overview {
                    coreSample(report)
                    if report.complete {
                        changes(report)
                        largest(report)
                        reclaimable
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 30)
            .padding(.bottom, 120)
            .frame(maxWidth: 1000, alignment: .leading)
        }
    }

    // MARK: Header

    private var header: some View {
        let v = model.volume
        let low = v.total > 0 && Double(v.important) / Double(v.total) < 0.05
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Fmt.bytes(v.used))
                    .font(.system(size: 46, weight: .semibold))
                    .tracking(-1)
                    .monospacedDigit()
                Text("used of \(Fmt.bytes(v.total))")
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                Spacer()
                if let status = model.overviewStatus {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(status).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12))
                } else if let date = model.overview?.date {
                    Text("Measured \(Fmt.ago(date))")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    model.scanAll()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.glass)
                .disabled(model.isBusy)
                .help("Measure everything again (⌘R)")
            }
            Group {
                if v.purgeable > 100_000_000 {
                    Text("\(Fmt.bytes(v.available)) free right now, plus \(Fmt.bytes(v.purgeable)) macOS can reclaim on its own.")
                } else {
                    Text("\(Fmt.bytes(v.important)) free.")
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
            if low {
                Text("Your disk is nearly full. Below about 20 GB free, macOS slows down and updates can fail to install.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.personal)
            }
        }
    }

    // MARK: Core sample

    private func coreSample(_ report: OverviewReport) -> some View {
        let layers = report.layers
        let unmeasured = report.complete ? 0 : max(0, report.volume.used - report.measured)
        let baseline = model.baseline
        return HStack(alignment: .top, spacing: 36) {
            CoreSample(
                free: model.volume.important,
                layers: layers,
                unmeasured: unmeasured,
                hovered: $hovered)
                .padding(5)
                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                .background(
                    RoundedRectangle(cornerRadius: 23, style: .continuous)
                        .fill(hovered.map { Theme.layer($0) } ?? Color.clear)
                        .blur(radius: 28)
                        .opacity(0.55)
                        .animation(.easeOut(duration: 0.2), value: hovered)
                )
                .frame(width: 102)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(layers) { layer in
                    LayerRow(
                        layer: layer,
                        total: report.volume.total,
                        delta: baseline.flatMap { b in b.layers[layer.kind.rawValue].map { layer.bytes - $0 } },
                        hovered: $hovered,
                        denied: layer.kind == .system && report.denied > 0 && !model.hasFullDiskAccess
                    )
                    .onTapGesture { model.go(layer.kind.destination) }
                }
                if unmeasured > 0 {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 2.5).strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                            .frame(width: 10, height: 10)
                        Text("Still measuring")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(Fmt.bytes(unmeasured))
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 84, alignment: .trailing)
                        Color.clear.frame(width: 40 + 10 + 12)
                    }
                    .padding(.vertical, 9)
                    .padding(.horizontal, 10)
                }
            }
            .animation(.smooth(duration: 0.4), value: layers.map(\.kind))
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Changes

    @ViewBuilder
    private func changes(_ report: OverviewReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if let base = model.baseline {
                let growth = report.volume.used - base.used
                SectionTitle(
                    title: "Since \(Fmt.day(base.date))",
                    detail: "\(Fmt.signedBytes(growth)) overall, \(Fmt.ago(base.date)).")
                if model.history.count >= 2 { HistoryChart(history: model.history) }
                let deltas = folderDeltas(report, base)
                if deltas.isEmpty {
                    Text("No folder changed by more than 100 MB.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(deltas, id: \.path) { d in
                            FolderRow(title: d.title, subtitle: subtitle(for: d.path), bytes: d.delta, signed: true, fraction: nil, tint: Theme.layer(d.layer))
                                .onTapGesture { open(d.path) }
                        }
                    }
                }
            } else {
                SectionTitle(
                    title: "What grows over time",
                    detail: "This scan is saved. Scan again in a few days and Clean Mac shows which folders grew, and by how much.")
            }
        }
    }

    private struct Delta { let path: String; let title: String; let layer: LayerID; let delta: Int64 }

    private func folderDeltas(_ report: OverviewReport, _ base: Snapshot) -> [Delta] {
        report.folders.compactMap { f -> Delta? in
            let before = base.folders[f.path] ?? 0
            let d = f.bytes - before
            return abs(d) >= 100_000_000 ? Delta(path: f.path, title: f.title, layer: f.layer, delta: d) : nil
        }
        .sorted { abs($0.delta) > abs($1.delta) }
        .prefix(8)
        .map { $0 }
    }

    // MARK: Largest

    private func largest(_ report: OverviewReport) -> some View {
        let top = Array(report.folders.sorted { $0.bytes > $1.bytes }.prefix(14))
        let maxBytes = top.first?.bytes ?? 1
        return VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Largest folders", detail: "Measured individually, so you can see exactly which app or folder holds the space.")
            VStack(spacing: 0) {
                ForEach(top) { f in
                    FolderRow(
                        title: f.title, subtitle: subtitle(for: f.path), bytes: f.bytes, signed: false,
                        fraction: Double(f.bytes) / Double(maxBytes), tint: Theme.layer(f.layer))
                        .onTapGesture { open(f.path) }
                }
            }
        }
    }

    private func subtitle(for path: String) -> String {
        path == OverviewReport.runtimePath
            ? "Managed by simctl in /Library/Developer/CoreSimulator"
            : Paths.tilde(URL(fileURLWithPath: path))
    }

    private func open(_ path: String) {
        if path == OverviewReport.runtimePath { model.go(.section(.xcode)) }
        else { model.go(.folder(URL(fileURLWithPath: path))) }
    }

    // MARK: Reclaimable

    private var reclaimable: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "Ready to clean", detail: "Space Clean Mac considers safe to reclaim, grouped by where it lives.")
            VStack(spacing: 0) {
                ForEach(SectionID.scannable) { s in
                    let report = model.reports[s]
                    HStack(spacing: 14) {
                        Image(systemName: s.symbol)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.title).font(.system(size: 13, weight: .medium))
                            Text(report.map { "\(Fmt.bytes($0.total)) found" } ?? (model.status[s] ?? "Not scanned"))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let report {
                            Text(Fmt.bytes(report.recommendedBytes))
                                .font(.system(size: 14, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(report.recommendedBytes > 0 ? Theme.safe : .secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button("Review") {
                            model.selectRecommended(in: s)
                            model.go(.section(s))
                        }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(report == nil)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    Divider().opacity(0.5)
                }
            }
        }
    }
}

// MARK: - Core sample

/// The disk drawn as a drill core: free space on top, then each layer, largest first.
struct CoreSample: View {
    let free: Int64
    let layers: [Layer]
    let unmeasured: Int64
    @Binding var hovered: LayerID?

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 1.5
            let bands = 1 + layers.count + (unmeasured > 0 ? 1 : 0)
            let usable = max(0, geo.size.height - gap * CGFloat(bands - 1))
            let values = [free] + layers.map(\.bytes) + (unmeasured > 0 ? [unmeasured] : [])
            let heights = Self.heights(values, total: usable, minimum: 3)

            VStack(spacing: gap) {
                FreeCap().frame(height: heights[0])
                ForEach(Array(layers.enumerated()), id: \.element.id) { i, layer in
                    Rectangle()
                        .fill(Theme.layer(layer.kind))
                        .frame(height: heights[i + 1])
                        .opacity(hovered == nil || hovered == layer.kind ? 1 : 0.28)
                        .onHover { hovered = $0 ? layer.kind : (hovered == layer.kind ? nil : hovered) }
                        .help("\(layer.kind.title): \(Fmt.bytes(layer.bytes))")
                }
                if unmeasured > 0 {
                    MeasuringBand().frame(height: heights.last ?? 0)
                }
            }
            .overlay(cylinder)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .animation(.smooth(duration: 0.45), value: values)
            .animation(.easeOut(duration: 0.18), value: hovered)
        }
        .frame(minHeight: 420)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Disk layers")
    }

    /// Light falling on a cylinder: a highlight on the left, a shadow on the right.
    private var cylinder: some View {
        LinearGradient(
            stops: [
                .init(color: .white.opacity(0.22), location: 0),
                .init(color: .white.opacity(0.06), location: 0.28),
                .init(color: .clear, location: 0.55),
                .init(color: .black.opacity(0.16), location: 1),
            ],
            startPoint: .leading, endPoint: .trailing)
            .allowsHitTesting(false)
    }

    /// Proportional heights with a floor so thin layers stay visible.
    static func heights(_ values: [Int64], total: CGFloat, minimum: CGFloat) -> [CGFloat] {
        let sum = CGFloat(values.reduce(0) { $0 + max(0, $1) })
        guard sum > 0, total > 0 else { return values.map { _ in 0 } }
        var h = values.map { CGFloat(max(0, $0)) / sum * total }
        var pinned = Set<Int>()
        for _ in 0..<6 {
            let small = h.indices.filter { h[$0] < minimum && !pinned.contains($0) }
            if small.isEmpty { break }
            pinned.formUnion(small)
            let rest = total - CGFloat(pinned.count) * minimum
            let restSum = h.indices.filter { !pinned.contains($0) }.reduce(CGFloat(0)) { $0 + CGFloat(max(0, values[$1])) }
            for i in h.indices {
                h[i] = pinned.contains(i) ? minimum : (restSum > 0 ? CGFloat(max(0, values[i])) / restSum * rest : 0)
            }
        }
        return h
    }
}

private struct FreeCap: View {
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.primary.opacity(0.04)))
            var lines = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 6
            }
            ctx.stroke(lines, with: .color(.primary.opacity(0.13)), lineWidth: 1)
        }
        .help("Free space")
    }
}

private struct MeasuringBand: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.05 + 0.04 * (1 + sin(t * 2.4)) / 2
            Rectangle().fill(Color.primary.opacity(pulse))
        }
        .help("Still measuring")
    }
}

// MARK: - Rows

private struct LayerRow: View {
    let layer: Layer
    let total: Int64
    let delta: Int64?
    @Binding var hovered: LayerID?
    var denied = false

    var body: some View {
        let isHovered = hovered == layer.kind
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Theme.layer(layer.kind))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(layer.kind.title)
                    .font(.system(size: 13, weight: .medium))
                Text(denied ? "Includes folders Clean Mac can't read yet" : layer.kind.note)
                    .font(.system(size: 11.5))
                    .foregroundStyle(denied ? AnyShapeStyle(Theme.review) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }
            Spacer(minLength: 16)
            if let delta, abs(delta) >= 50_000_000 {
                Text(Fmt.signedBytes(delta))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(delta > 0 ? Theme.review : Theme.safe)
            }
            Text(Fmt.bytes(layer.bytes))
                .font(.system(size: 14, weight: .semibold))
                .monospacedDigit()
                .frame(minWidth: 84, alignment: .trailing)
            Text(percent)
                .font(.system(size: 11.5))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 40, alignment: .trailing)
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .opacity(isHovered ? 1 : 0)
                .frame(width: 10)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Theme.layer(layer.kind).opacity(0.12) : .clear))
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? layer.kind : (hovered == layer.kind ? nil : hovered) }
    }

    private var percent: String {
        guard total > 0 else { return "" }
        let p = Double(layer.bytes) / Double(total) * 100
        return p < 1 ? "<1%" : "\(Int(p.rounded()))%"
    }
}

struct FolderRow: View {
    let title: String
    let subtitle: String
    let bytes: Int64
    let signed: Bool
    let fraction: Double?
    let tint: Color
    @State private var hover = false

    var body: some View {
        HStack(spacing: 14) {
            Circle().fill(tint).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 16)
            if let fraction {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint.opacity(0.55))
                        .frame(width: max(3, geo.size.width * fraction), height: 4)
                        .frame(maxHeight: .infinity)
                }
                .frame(width: 140, height: 10)
            }
            Text(signed ? Fmt.signedBytes(bytes) : Fmt.bytes(bytes))
                .font(.system(size: 13, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(signed ? (bytes > 0 ? Theme.review : Theme.safe) : .primary)
                .frame(minWidth: 84, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Color.primary.opacity(0.045) : .clear))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
    }
}

struct SectionTitle: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 10)
    }
}

private struct HistoryChart: View {
    let history: [Snapshot]

    var body: some View {
        Chart(history) { snap in
            AreaMark(x: .value("Date", snap.date), y: .value("Used", Double(snap.used) / 1e9))
                .foregroundStyle(Theme.accent.opacity(0.12))
                .interpolationMethod(.monotone)
            LineMark(x: .value("Date", snap.date), y: .value("Used", Double(snap.used) / 1e9))
                .foregroundStyle(Theme.accent)
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.hairline)
                AxisValueLabel { if let gb = value.as(Double.self) { Text("\(Int(gb)) GB") } }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .frame(height: 90)
        .padding(.horizontal, 10)
    }
}
