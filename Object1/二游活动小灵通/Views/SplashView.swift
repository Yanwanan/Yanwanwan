import SwiftUI

struct SplashView: View {
    let onDismiss: @MainActor @Sendable () -> Void
    var body: some View { SplashWanwanView(onDismiss: onDismiss) }
}

// MARK: - 婉婉探头

private struct SplashWanwanView: View { // still private — only SplashView uses it
    let onDismiss: @MainActor @Sendable () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var headX:       CGFloat = -420
    @State private var greeting     = false
    @State private var swaying      = false
    @State private var hopY:        CGFloat = 0
    @State private var rootOpacity: Double  = 1
    @State private var floatY:      CGFloat = 0

    private let slackTexts = ["婉婉加载中…", "清点活动中", "翻公告中", "整理待办中", "等老大吩咐中"]

    var body: some View {
        ZStack {
            Color.hoyoBg.ignoresSafeArea()

            // 漂浮的摸鱼字
            VStack(spacing: 28) {
                ForEach(Array(slackTexts.enumerated()), id: \.offset) { i, text in
                    Text(text)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(Color.hoyoPink.opacity(0.25))
                        .offset(x: [CGFloat(-70), 50, -30, 90, -55][i])
                }
            }
            .offset(y: floatY)

            // 婉婉的像素大头：白色贴纸描边 + 卡通投影，从左边冲进来后左右摆头
            wanwanHead
                .frame(width: 190, height: 190)
                .rotationEffect(.degrees(swaying ? 7 : -7), anchor: .bottom)
                .offset(x: headX, y: hopY)

            if greeting {
                Text("👀  老大来啦，婉婉在呢！")
                    .font(.headline).fontWeight(.black)
                    .foregroundStyle(Color.hoyoPink)
                    .offset(y: 160)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .opacity(rootOpacity)
        .onAppear {
            if !reduceMotion {
                // 摸鱼字漂浮
                withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                    floatY = 18
                }
            }

            // 婉婉从左边冲进来
            after(0.4) {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.45, dampingFraction: 0.58)) {
                    headX = 0
                }
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            }

            // 打招呼：开始摆头，蹦一下
            after(1.0) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { greeting = true }
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) { swaying = true }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                hop()
            }

            // 退出
            after(2.5) {
                withAnimation(.easeOut(duration: 0.35)) { rootOpacity = 0 }
                after(0.35) { onDismiss() }
            }
        }
    }

    private var wanwanHead: some View {
        let outline: [CGSize] = [
            .init(width: -4, height: 0), .init(width: 4, height: 0), .init(width: 0, height: -4), .init(width: 0, height: 4),
            .init(width: -3, height: -3), .init(width: 3, height: -3), .init(width: -3, height: 3), .init(width: 3, height: 3),
        ]
        return ZStack {
            ForEach(outline.indices, id: \.self) { i in
                Image("WanwanHead")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .offset(outline[i])
            }
            Image("WanwanHead")
                .resizable()
                .scaledToFit()
        }
        .compositingGroup()
        .shadow(color: Color.hoyoNavy.opacity(0.22), radius: 0, x: 3, y: 3)
        .accessibilityLabel("婉婉")
    }

    private func hop() {
        withAnimation(.easeOut(duration: 0.14)) { hopY = -16 }
        after(0.14) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.45)) { hopY = 0 }
        }
    }
}

// MARK: - Helper

@MainActor
private func after(_ seconds: Double, action: @escaping @MainActor @Sendable () -> Void) {
    let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
    Task { @MainActor in
        try? await Task.sleep(nanoseconds: nanoseconds)
        action()
    }
}
