// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Wyllys Ingersoll
//
// PopoverView — the SwiftUI content displayed when the user clicks the
// solarbar menu bar icon. Shows two hand-drawn circular gauges (charge %
// and lux) plus a small action footer.
//
// Gauges are drawn as stacked Circles rather than SwiftUI's built-in Gauge
// so we can control ring thickness, colors, and center readout independently.
//

import SwiftUI
import AppKit
import SolarCore

struct PopoverView: View {
    @ObservedObject var store: ReadingStore

    var body: some View {
        VStack(spacing: 14) {
            Text("Logitech K750")
                .font(.headline)

            if let r = store.reading {
                HStack(spacing: 20) {
                    CircularGauge(
                        progress: Double(r.charge) / 100,
                        readout: "\(r.charge)%",
                        caption: "Charge",
                        tint: chargeColor(r.charge)
                    )
                    CircularGauge(
                        progress: min(Double(r.lux) / 500, 1),
                        readout: "\(r.lux)",
                        caption: "Lux",
                        tint: .yellow
                    )
                }

                if let t = store.lastUpdate {
                    Text("Updated \(t.formatted(date: .omitted, time: .standard))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let err = store.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            } else {
                ProgressView("Waiting for reading…")
                    .font(.caption)
                    .padding(.vertical, 20)
            }

            Divider()

            HStack {
                Button("Refresh") { store.refresh() }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .font(.callout)
        }
        .padding(14)
        .frame(width: 280)
    }

    private func chargeColor(_ pct: Int) -> Color {
        switch pct {
        case ..<20:  return .red
        case ..<50:  return .orange
        default:     return .green
        }
    }
}

private struct CircularGauge: View {
    let progress: Double        // 0...1
    let readout: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: max(0, min(progress, 1)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.4), value: progress)
                Text(readout)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .frame(width: 96, height: 96)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
