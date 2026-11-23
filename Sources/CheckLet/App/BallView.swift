import SwiftUI

struct BallView: View {
    @ObservedObject var vm: TodoViewModel
    let size: CGFloat

    var body: some View {
        let progress = vm.todayProgress
        let remaining = progress.total - progress.done
        let fraction = progress.total == 0 ? 0 : CGFloat(progress.done) / CGFloat(progress.total)

        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3)
                .padding(6)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    LinearGradient(colors: [Color(red: 0.36, green: 0.62, blue: 1), Color(red: 0.42, green: 0.86, blue: 0.62)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(6)

            Group {
                if progress.total > 0 && remaining == 0 {
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.32, weight: .bold))
                        .foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.5))
                } else if remaining > 0 {
                    Text("\(remaining)")
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Image(systemName: "checklist")
                        .font(.system(size: size * 0.3, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            if vm.hasUrgentDate {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: size * 0.28, y: -size * 0.28)
            }
        }
        .frame(width: size, height: size)
        .overlay(
            Circle().strokeBorder(vm.pinned ? Color.accentColor.opacity(0.85) : Color.white.opacity(0.2),
                                  lineWidth: vm.pinned ? 1.5 : 1)
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: progress.done)
        .help("今日待办 · 悬停查看，点击固定")
    }
}
