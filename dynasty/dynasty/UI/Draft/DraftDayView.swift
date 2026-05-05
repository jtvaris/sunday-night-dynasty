import SwiftUI
import SwiftData
import Combine

struct DraftDayView: View {
    let career: Career
    @Environment(\.modelContext) private var modelContext
    @StateObject private var coordinator: Wrapper

    init(career: Career) {
        self.career = career
        _coordinator = StateObject(wrappedValue: Wrapper())
    }

    @MainActor
    final class Wrapper: ObservableObject {
        @Published var coord: DraftDayCoordinator?
    }

    var body: some View {
        ZStack {
            Color.backgroundPrimary.ignoresSafeArea()
            if let coord = coordinator.coord {
                contentView(coord: coord)
            } else {
                ProgressView("Loading draft…")
                    .foregroundStyle(Color.textPrimary)
            }
        }
        .navigationTitle("NFL Draft \(career.currentSeason)")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if coordinator.coord == nil {
                let c = DraftDayCoordinator(career: career, modelContext: modelContext)
                await c.loadData()
                coordinator.coord = c
                c.start()
            }
        }
    }

    @ViewBuilder
    private func contentView(coord: DraftDayCoordinator) -> some View {
        VStack(spacing: 0) {
            DraftStickyHeader(coordinator: coord)
            HStack(spacing: 0) {
                LiveBigBoardPanel(coordinator: coord)
                    .frame(maxWidth: 320)
                Divider().overlay(Color.surfaceBorder)
                DraftTickerPanel(coordinator: coord)
                Divider().overlay(Color.surfaceBorder)
                WarRoomPanel(coordinator: coord)
                    .frame(maxWidth: 280)
            }
            DraftControlBar(coordinator: coord)
        }
        .sheet(isPresented: Binding(
            get: { coord.mode == .userPick },
            set: { _ in }
        )) {
            PickSheetView(coordinator: coord)
                .interactiveDismissDisabled()
        }
    }
}
