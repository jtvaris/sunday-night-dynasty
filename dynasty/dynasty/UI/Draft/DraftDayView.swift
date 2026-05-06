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
        ZStack {
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

            // Drama overlays at the top of the Z stack — banners, curtains,
            // gem flashes, Mr. Irrelevant.
            DramaOverlayView(coordinator: coord)

            // Reaction toasts pinned to the bottom edge — owner / media /
            // locker room / fans react to user picks.
            VStack {
                Spacer()
                ReactionToast(coordinator: coord)
                    .padding(.bottom, DSSpacing.xl)
            }

            // Trade offer banner pinned to the top edge when an AI partner
            // proposes a deal.
            if let offer = coord.pendingTradeOffer {
                VStack {
                    TradeOfferBanner(
                        motive: offer.motive,
                        outgoing: offer.partnerReceives.map { "#\($0.pickNumber)" }.joined(separator: " + "),
                        incoming: offer.partnerGives.map { "#\($0.pickNumber)" }.joined(separator: " + "),
                        onAccept: { coord.acceptTradeOffer() },
                        onDecline: { coord.declineTradeOffer() }
                    )
                    .padding(.top, DSSpacing.md)
                    .padding(.horizontal, DSSpacing.md)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background {
            ZStack {
                Image("BgDraft")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.30)
                LinearGradient(
                    colors: [
                        Color.backgroundPrimary.opacity(0.55),
                        Color.backgroundPrimary.opacity(0.85)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: Binding(
            get: { coord.mode == .userPick },
            set: { _ in }
        )) {
            PickSheetView(coordinator: coord)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(
            get: { coord.pendingRoundRecap != nil },
            set: { _ in }
        )) {
            if let recap = coord.pendingRoundRecap {
                RoundRecapSheet(coordinator: coord, recap: recap)
            }
        }
    }
}
