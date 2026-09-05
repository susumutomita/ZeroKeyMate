import SwiftUI

struct MateView: View {
    @StateObject private var model = MateModel()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blinking = false

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 20) {
                HStack {
                    Text("ZeroKey Mate").font(.headline)
                    Spacer()
                    Label("LOCAL", systemImage: "iphone")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                if landscape {
                    HStack(spacing: 24) {
                        face(width: min(geometry.size.width * 0.14, 120))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        ScrollView {
                            controls
                        }
                        .frame(width: min(geometry.size.width * 0.43, 340))
                    }
                } else {
                    Spacer(minLength: 0)
                    face(width: min(geometry.size.width * 0.24, 140))
                        .frame(height: geometry.size.height * 0.3)
                    Spacer(minLength: 0)
                    ScrollView {
                        controls
                        Text("Your companion. Your rules.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    }
                    .frame(maxHeight: geometry.size.height * 0.42)
                }
            }
            .padding(landscape ? 20 : 28)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.black)
        .onAppear { model.setForeground(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { model.setForeground(false) }
            if phase == .active { model.setForeground(true) }
            // The system permission sheet temporarily makes the scene inactive.
        }
        .task(id: "\(model.cameraPhase.rawValue)-\(reduceMotion)") {
            blinking = false
            guard model.cameraPhase == .on, !reduceMotion else { return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(3.6))
                    withAnimation(.easeOut(duration: 0.10)) { blinking = true }
                    try await Task.sleep(for: .milliseconds(160))
                    withAnimation(.easeOut(duration: 0.16)) { blinking = false }
                }
            } catch {
                blinking = false
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 14) {
            Label(model.cameraPhase.rawValue, systemImage: model.cameraPhase == .off ? "camera.slash" : "camera")
                .font(.subheadline.weight(.medium))
            Text(dockStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let message = model.message ?? model.dockMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Text("マイク・保存・外部送信は使っていません。")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button {
                if model.captureRequested || model.cameraPhase != .off {
                    model.stopCapture()
                } else {
                    model.startCapture()
                }
            } label: {
                Label(
                    model.captureRequested || model.cameraPhase != .off ? "カメラを停止" : "カメラを開始",
                    systemImage: model.captureRequested || model.cameraPhase != .off ? "stop.fill" : "play.fill"
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.cyan)
            .foregroundStyle(.black)
            .accessibilityIdentifier("captureControl")
        }
        .multilineTextAlignment(.center)
    }

    private var dockStatus: String {
        if model.trackingEnabled == true { return "DockKit接続済み・システム追尾 ON" }
        if model.dockConnected {
            return model.trackingEnabled == nil ? "DockKit接続済み・追尾状態未確認" : "DockKit接続済み・追尾 OFF"
        }
        return "スタンド未接続・顔表示は利用できます"
    }

    private func face(width: CGFloat) -> some View {
        HStack(spacing: width * 0.45) {
            eye(width: width)
            eye(width: width)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.cameraPhase == .on ? "起きているメイト" : "休んでいるメイト")
    }

    private func eye(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: width * 0.45)
            .fill(.cyan)
            .frame(width: width, height: width * 0.85)
            .scaleEffect(y: model.cameraPhase == .on && !blinking ? 1 : 0.09)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: model.cameraPhase)
    }
}
