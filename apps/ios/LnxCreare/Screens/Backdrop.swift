import SwiftUI

/// 全画面の下地。暗い空に、ほのかな紫
struct Backdrop: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.06, blue: 0.10),
                Color(red: 0.16, green: 0.10, blue: 0.24),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
