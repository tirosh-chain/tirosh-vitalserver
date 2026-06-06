import Foundation
import SwiftUI

struct RecorderActivityChart: View {
    let buckets: [RecorderActivityChartBucket]
    let intervalTitle: String

    var body: some View {
        GeometryReader { proxy in
            let plotFrame = plotFrame(in: proxy.size)
            let bars = chartBars(in: proxy.size)
            ZStack {
                chartGrid(in: plotFrame)
                chartAxes(in: plotFrame)
                ForEach(bars) { bar in
                    RoundedRectangle(cornerRadius: bar.cornerRadius)
                        .fill(Color.accentColor)
                        .frame(width: bar.rect.width, height: bar.rect.height)
                        .position(x: bar.rect.midX, y: bar.rect.midY)
                }
                ForEach(yAxisLabels(in: plotFrame)) { label in
                    Text(label.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: chartInsets.leading - 10, alignment: .trailing)
                        .position(x: (chartInsets.leading - 10) / 2, y: label.position)
                }
                ForEach(xAxisLabels(in: plotFrame)) { label in
                    Text(label.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: label.width, alignment: label.alignment)
                        .position(x: label.clampedPosition(in: plotFrame), y: plotFrame.maxY + 18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topLeading) {
            Text("Packets / \(intervalTitle)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .overlay(alignment: .topTrailing) {
            Text("\(buckets.reduce(0) { $0 + $1.messageCount }) packets")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
    }

    private var chartInsets: EdgeInsets {
        EdgeInsets(top: 32, leading: 54, bottom: 30, trailing: 14)
    }

    private var maxMessageCount: Int {
        max(buckets.map(\.messageCount).max() ?? 0, 1)
    }

    private var yAxisMax: Int {
        niceAxisMax(for: maxMessageCount)
    }

    private func chartGrid(in plotFrame: CGRect) -> some View {
        Path { path in
            for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let y = plotFrame.maxY - plotFrame.height * fraction
                path.move(to: CGPoint(x: plotFrame.minX, y: y))
                path.addLine(to: CGPoint(x: plotFrame.maxX, y: y))
            }
        }
        .stroke(Color.secondary.opacity(0.14), lineWidth: 1)
    }

    private func chartAxes(in plotFrame: CGRect) -> some View {
        Path { path in
            path.move(to: CGPoint(x: plotFrame.minX, y: plotFrame.minY))
            path.addLine(to: CGPoint(x: plotFrame.minX, y: plotFrame.maxY))
            path.addLine(to: CGPoint(x: plotFrame.maxX, y: plotFrame.maxY))
        }
        .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
    }

    private func chartBars(in size: CGSize) -> [RecorderActivityBar] {
        let frame = plotFrame(in: size)
        let width = max(frame.width, 1)
        let height = max(frame.height, 1)
        let maxValue = yAxisMax
        let slotWidth = max(width / CGFloat(max(buckets.count, 1)), 1)
        let barWidth = min(max(slotWidth * 0.68, 1), slotWidth > 4 ? 18 : 2)
        let cornerRadius = min(barWidth / 2, 3)

        return buckets.enumerated().map { index, bucket in
            let normalized = CGFloat(bucket.messageCount) / CGFloat(maxValue)
            let barHeight = max(height * normalized, bucket.messageCount > 0 ? 2 : 0)
            let x = frame.minX + slotWidth * CGFloat(index) + slotWidth / 2
            let y = frame.minY + height - barHeight
            return RecorderActivityBar(
                id: bucket.id,
                rect: CGRect(x: x - barWidth / 2, y: y, width: barWidth, height: barHeight),
                cornerRadius: cornerRadius
            )
        }
    }

    private func plotFrame(in size: CGSize) -> CGRect {
        let width = max(size.width - chartInsets.leading - chartInsets.trailing, 1)
        let height = max(size.height - chartInsets.top - chartInsets.bottom, 1)
        return CGRect(x: chartInsets.leading, y: chartInsets.top, width: width, height: height)
    }

    private func yAxisLabels(in plotFrame: CGRect) -> [RecorderActivityAxisLabel] {
        let maxValue = yAxisMax
        let top = RecorderActivityAxisLabel(id: "y-top", title: "\(maxValue)", position: plotFrame.minY)
        let bottom = RecorderActivityAxisLabel(id: "y-bottom", title: "0", position: plotFrame.maxY)
        guard maxValue > 1 else {
            return [top, bottom]
        }
        let middle = RecorderActivityAxisLabel(
            id: "y-middle",
            title: "\(Int((Double(maxValue) / 2).rounded()))",
            position: plotFrame.midY
        )
        return [top, middle, bottom]
    }

    private func xAxisLabels(in plotFrame: CGRect) -> [RecorderActivityAxisLabel] {
        let datedBuckets = buckets.compactMap { bucket -> (String, Date)? in
            guard let date = RuntimeRecorderActivityDateParser.date(from: bucket.bucketStartedAt) else {
                return nil
            }
            return (bucket.bucketStartedAt, date)
        }
        guard let first = datedBuckets.first,
              let last = datedBuckets.last else {
            return []
        }

        let start = RecorderActivityAxisLabel(
            id: "x-start",
            title: RuntimeRecorderActivityDateParser.axisText(first.1),
            position: plotFrame.minX
        )
        let end = RecorderActivityAxisLabel(
            id: "x-end",
            title: RuntimeRecorderActivityDateParser.axisText(last.1),
            position: plotFrame.maxX
        )
        guard datedBuckets.count > 2 else {
            return plotFrame.width > 220 ? [start, end] : [end]
        }
        let middleIndex = datedBuckets.count / 2
        let middleDate = datedBuckets[middleIndex].1
        let ratio = CGFloat(middleIndex) / CGFloat(max(datedBuckets.count - 1, 1))
        let middle = RecorderActivityAxisLabel(
            id: "x-middle",
            title: RuntimeRecorderActivityDateParser.axisText(middleDate),
            position: plotFrame.minX + plotFrame.width * ratio
        )
        if plotFrame.width < 260 {
            return [end]
        }
        if plotFrame.width < 480 {
            return [start, end]
        }
        return [start, middle, end]
    }

    private func niceAxisMax(for value: Int) -> Int {
        guard value > 0 else {
            return 1
        }
        let magnitude = pow(10.0, floor(log10(Double(value))))
        for multiplier in [1.0, 2.0, 5.0, 10.0] {
            let candidate = Int(multiplier * magnitude)
            if candidate >= value {
                return max(candidate, 1)
            }
        }
        return value
    }
}

struct RecorderActivityAxisLabel: Identifiable {
    let id: String
    let title: String
    let position: CGFloat
    var width: CGFloat = 74
    var alignment: Alignment = .center

    func clampedPosition(in plotFrame: CGRect) -> CGFloat {
        min(max(position, plotFrame.minX + width / 2), plotFrame.maxX - width / 2)
    }
}

struct RecorderActivityBar: Identifiable {
    let id: String
    let rect: CGRect
    let cornerRadius: CGFloat
}
