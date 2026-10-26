import AppKit
import SwiftUI

/// A small floating status pill near the bottom of the active screen (R4).
/// It never becomes key or main, so the target app keeps focus.
@MainActor
final class IndicatorPanel {
    private let controller: MacDictationController
    private let panel: NSPanel

    init(controller: MacDictationController) {
        self.controller = controller
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: IndicatorView(controller: controller))
        observe()
    }

    private func observe() {
        withObservationTracking {
            update(controller.phase)
        } onChange: {
            Task { @MainActor [weak self] in self?.observe() }
        }
    }

    private func update(_ phase: MacDictationController.Phase) {
        guard phase != .idle else {
            panel.orderOut(nil)
            return
        }
        if !panel.isVisible, let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.minY + 48))
        }
        panel.orderFrontRegardless()
    }
}

private struct IndicatorView: View {
    let controller: MacDictationController

    var body: some View {
        HStack(spacing: 8) {
            switch controller.phase {
            case .idle:
                EmptyView()
            case .recording:
                Circle().fill(.red).frame(width: 10, height: 10)
                LevelMeter(level: controller.level)
            case .transcribing:
                ProgressView().controlSize(.small)
                Text("Transcribing…")
            case .message(let text, let isError):
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? .yellow : .secondary)
                Text(text).lineLimit(2)
            }
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LevelMeter: View {
    let level: Float

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<12, id: \.self) { index in
                Capsule()
                    .fill(Float(index) / 12 < level ? Color.primary : Color.secondary.opacity(0.3))
                    .frame(width: 4, height: 16)
            }
        }
        .animation(.linear(duration: 0.08), value: level)
    }
}
