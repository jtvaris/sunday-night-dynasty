import SwiftUI

/// Stub for the new event-driven Draft Day experience.
/// Full implementation arrives in Vaihe 1 tasks 1.13–1.20.
struct DraftDayView: View {
    let career: Career

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Draft Day")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(Color.textPrimary)
                Text("Under construction — Vaihe 1 implementation in progress.")
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .navigationTitle("NFL Draft \(career.currentSeason)")
        .navigationBarTitleDisplayMode(.inline)
    }
}
