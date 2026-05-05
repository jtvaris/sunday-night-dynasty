import SwiftUI

struct DraftControlBar: View {
    @ObservedObject var coordinator: DraftDayCoordinator

    var body: some View {
        HStack(spacing: DSSpacing.md) {
            Button { coordinator.skipToMyPick() } label: {
                Label("My Pick", systemImage: "forward.end.fill")
            }
            Button { coordinator.skipToNextEvent() } label: {
                Label("Next Event", systemImage: "forward.fill")
            }
            Button { coordinator.skipToNextRound() } label: {
                Label("Next Round", systemImage: "forward.frame.fill")
            }
            Spacer()
            if coordinator.mode == .paused {
                Button { coordinator.resume() } label: {
                    Label("Resume", systemImage: "play.fill")
                }
            } else {
                Button { coordinator.pause() } label: {
                    Label("Pause", systemImage: "pause.fill")
                }
            }
            Menu {
                ForEach([0.5, 1.0, 2.0, 4.0], id: \.self) { sp in
                    Button("\(Int(sp))×") { coordinator.setSpeed(sp) }
                }
            } label: {
                Text("\(Int(coordinator.speed))×")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 6)
                    .background(Color.backgroundTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: DSCornerRadius.inline))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(Color.backgroundSecondary)
        .overlay(Rectangle().fill(Color.surfaceBorder).frame(height: 1), alignment: .top)
    }
}
