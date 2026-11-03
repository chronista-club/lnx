import SwiftUI

/// 最初の画面。今は看板だけ。ここにオーディオ入力とビジュアル生成が載る。
struct ContentView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.10),
                    Color(red: 0.16, green: 0.10, blue: 0.24),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Text(AppInfo.name)
                    .font(.system(size: 44, weight: .light, design: .rounded))
                    .foregroundStyle(.white)
                Text(AppInfo.tagline)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
