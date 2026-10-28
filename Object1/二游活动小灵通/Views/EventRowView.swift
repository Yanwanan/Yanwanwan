import SwiftUI

struct EventRowView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showReadStamp = false
    @State private var showCompletionFlash = false
    @State private var completionEffectCount = 0
    @State private var isCompleting = false
    @State private var urgencyPulse = false
    @State private var completionArrivalVisible = false
    @State private var completionTask: Task<Void, Never>? = nil
    let event:         RemoteEvent
    var showGameTag:   Bool          = true
    var isMuted:       Bool          = false
    var onTap:         (() -> Void)? = nil
    var onToggleMute:  (() -> Void)? = nil
    var playCompletionArrival: Bool = false
    let onToggleDone:  () -> Void

    private var isUrgent: Bool {
        event.urgency == .critical || event.urgency == .warning
    }

    private var isCriticalSoon: Bool {
        !event.isDone && event.remaining > 0 && event.remaining <= 86400
    }

    private var compactRemaining: String {
        if event.isDone { return "已完成" }
        let rem = Int(event.remaining)
        if rem <= 0 { return "已结束" }
        let days    = rem / 86400
        let hours   = (rem % 86400) / 3600
        let minutes = (rem % 3600) / 60
        if days  > 0 { return "\(days)天\(hours)时" }
        if hours > 0 { return "\(hours)时\(minutes)分" }
        return "\(minutes)分"
    }

    private var pillColor: Color {
        if event.isDone || event.remaining <= 0 { return .gray.opacity(0.25) }
        return isUrgent ? Color.hoyoPink : Color.hoyoYellow
    }

    private var pillTextColor: Color {
        if event.isDone || event.remaining <= 0 { return .secondary }
        return isUrgent ? .white : Color.hoyoNavy
    }

    private var borderColor: Color {
        if event.isDone || event.remaining <= 0 { return Color.hoyoNavy.opacity(0.15) }
        return isUrgent ? Color.hoyoPink : Color.hoyoNavy.opacity(0.20)
    }

    private var borderWidth: CGFloat {
        (event.isDone || event.remaining <= 0) ? 1.5 : (isUrgent ? 2.5 : 2)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            Capsule()
                .fill(event.urgency.color.opacity(event.isDone ? 0.25 : 0.85))
                .frame(width: 4)
                .padding(.vertical, 10)
                .padding(.leading, 12)

            // Main tappable content
            Button {
                onTap?()
            } label: {
                HStack(spacing: 10) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(isUrgent
                                  ? Color.hoyoPink.opacity(0.12)
                                  : event.game.cardHeaderColor.opacity(0.10))
                            .frame(width: 32, height: 32)
                        if event.isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Color.hoyoMint)
                        } else if event.remaining <= 0 {
                            Text("✕")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.gray)
                        } else if isUrgent {
                            Text("!")
                                .font(.system(size: 14, weight: .black))
                                .foregroundStyle(Color.hoyoPink)
                        } else {
                            Text("▶")
                                .font(.system(size: 10, weight: .black))
                                .foregroundStyle(event.game.cardHeaderColor)
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        // Game tag / mute icon row
                        if showGameTag || isMuted {
                            HStack(spacing: 5) {
                                if isMuted {
                                    Image(systemName: "bell.slash.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if showGameTag {
                                    Text(event.game.emoji + " " + event.game.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(event.game.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(event.game.accentColor.opacity(0.12), in: Capsule())
                                }
                            }
                        }

                        Text(event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.hoyoNavy.opacity(event.isDone ? 0.40 : 1.0))
                            .strikethrough(event.isDone, color: Color.hoyoNavy.opacity(0.35))
                            .lineLimit(1)

                        if !event.isDone && event.remaining > 0 {
                            Text("\(event.endDateShort)结束 · \(event.category)")
                                .font(.caption2)
                                .foregroundStyle(Color.hoyoNavy.opacity(0.35))
                        }
                    }

                    Spacer(minLength: 4)

                    // Countdown pill
                    HStack(spacing: 3) {
                        Image(systemName: showReadStamp ? "checkmark" : "clock")
                            .font(.system(size: 10, weight: .bold))
                        Text(showReadStamp ? "已阅" : compactRemaining)
                            .font(.system(size: 12, weight: .black))
                    }
                    .foregroundStyle(showReadStamp ? Color.white : pillTextColor)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(showReadStamp ? Color.hoyoMint : pillColor)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule().stroke(
                            (event.isDone || event.remaining <= 0) ? Color.clear : Color.hoyoNavy,
                            lineWidth: 1.5
                        )
                    )
                    .overlay(alignment: .topTrailing) {
                        if showReadStamp && !reduceMotion {
                            Image(systemName: "sparkle")
                                .font(.system(size: 11, weight: .black))
                                .foregroundStyle(Color.hoyoYellow)
                                .offset(x: 6, y: -7)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                                .symbolEffect(.bounce, value: completionEffectCount)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if showReadStamp && !reduceMotion {
                            Image(systemName: "star.fill")
                                .font(.system(size: 7, weight: .black))
                                .foregroundStyle(Color.hoyoPink)
                                .offset(x: -4, y: 5)
                                .transition(.scale(scale: 0.2).combined(with: .opacity))
                                .symbolEffect(.bounce, value: completionEffectCount)
                        }
                    }
                    .shadow(color: showReadStamp ? Color.hoyoMint.opacity(0.58) : .clear,
                            radius: showReadStamp ? 8 : 0)
                    .scaleEffect(showReadStamp && !reduceMotion ? 1.06 : (isCriticalSoon && urgencyPulse && !reduceMotion ? 1.035 : 1))
                    .contentTransition(.opacity)
                    .animation(HoyoMotion.card, value: showReadStamp)
                    .animation(
                        isCriticalSoon && !showReadStamp && !reduceMotion
                            ? .easeInOut(duration: 1.25).repeatForever(autoreverses: true)
                            : nil,
                        value: urgencyPulse
                    )
                }
                .padding(.leading, 10)
                .padding(.trailing, 4)
                .contentShape(Rectangle())
                .fontDesign(.rounded)
            }
            .buttonStyle(.plain)

            // Done toggle
            Button {
                handleCompletionTap()
            } label: {
                Image(systemName: (event.isDone || showReadStamp) ? "checkmark.circle.fill" : "circle")
                    .imageScale(.large)
                    .foregroundStyle((event.isDone || showReadStamp) ? Color.hoyoMint : Color.hoyoNavy.opacity(0.25))
                    .scaleEffect((event.isDone || showReadStamp) && !reduceMotion ? 1.18 : 1.0)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.45), value: event.isDone)
                    .symbolEffect(.bounce, value: completionEffectCount)
            }
            .buttonStyle(.plain)
            .disabled(isCompleting)
            .padding(.trailing, 14)
            .padding(.leading, 4)
            .accessibilityLabel(event.isDone ? "标记为未完成" : "标记为完成")
        }
        .padding(.vertical, 8)
        .background(Color.hoyoCardBg, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(borderColor, lineWidth: borderWidth))
        .overlay {
            if showCompletionFlash {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.hoyoMint.opacity(0.22))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .shadow(
            color: (event.isDone || event.remaining <= 0)
                ? Color.clear
                : (isUrgent ? Color.hoyoPink.opacity(0.35) : Color.hoyoNavy.opacity(0.20)),
            radius: 0, x: 2, y: 2
        )
        .opacity(event.isDone ? 0.65 : 1)
        .scaleEffect(playCompletionArrival ? (completionArrivalVisible ? 1 : 0.96) : 1)
        .offset(y: playCompletionArrival ? (completionArrivalVisible ? 0 : 8) : 0)
        .opacity(playCompletionArrival ? (completionArrivalVisible ? 1 : 0) : 1)
        .contextMenu {
            if let toggleMute = onToggleMute, !event.isDone, event.remaining > 0 {
                Button {
                    toggleMute()
                } label: {
                    Label(isMuted ? "恢复通知" : "静音此活动通知",
                          systemImage: isMuted ? "bell.fill" : "bell.slash")
                }
            }
            Button {
                onToggleDone()
            } label: {
                Label(event.isDone ? "标记为未完成" : "标记为完成",
                      systemImage: event.isDone ? "arrow.uturn.backward.circle" : "checkmark.circle")
            }
        }
        .onAppear {
            if isCriticalSoon && !reduceMotion { urgencyPulse = true }
        }
        .task(id: playCompletionArrival) {
            guard playCompletionArrival else { return }
            completionArrivalVisible = false
            guard !reduceMotion else {
                completionArrivalVisible = true
                return
            }
            await Task.yield()
            withAnimation(HoyoMotion.card) {
                completionArrivalVisible = true
            }
        }
        .onDisappear { completionTask?.cancel() }
    }

    private func handleCompletionTap() {
        guard !isCompleting else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        guard !event.isDone, !reduceMotion else {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.82)) {
                onToggleDone()
            }
            return
        }

        isCompleting = true
        completionEffectCount += 1
        withAnimation(HoyoMotion.card) {
            showReadStamp = true
            showCompletionFlash = true
        }
        completionTask?.cancel()
        completionTask = Task { @MainActor in
            do { try await Task.sleep(for: .milliseconds(200)) }
            catch { return }
            withAnimation(.easeOut(duration: 0.18)) { showCompletionFlash = false }
            do { try await Task.sleep(for: .milliseconds(220)) }
            catch { return }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(HoyoMotion.layout) {
                onToggleDone()
            }
            isCompleting = false
        }
    }
}
