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
        // #152: the draft is named for the season its rookies debut in, which is
        // `currentSeason + 1` — the increment that produces the season these men
        // actually play does not fire until roster cuts. See `DraftYearLabel`.
        .navigationTitle("NFL Draft \(String(DraftYearLabel.classYear(duringSeason: career.currentSeason)))")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if coordinator.coord == nil {
                let c = DraftDayCoordinator(career: career, modelContext: modelContext)
                await c.loadData()
                coordinator.coord = c
                // Second line of defence behind `CareerShellView.isDraftRoomLive`:
                // the pick clock must never tick outside the draft phase. A save
                // opened in Week 1 of the regular season used to resume a running
                // 60 s clock here ("ON THE CLOCK: New York Giants") off stale
                // state. The board still renders — it just never starts.
                if career.currentPhase == .draft {
                    c.start()
                }
            }
        }
        // The draft room claims the soundtrack while it is on top. The base
        // context is already `.draft` during the draft phase, but the board is
        // reachable outside it (reviewing a completed draft), and the ticking
        // cues are the right score either way.
        .onAppear {
            MusicDirector.shared.pushOverride(.draft)
        }
        .onDisappear {
            MusicDirector.shared.clearOverride(.draft)
        }
    }

    @ViewBuilder
    private func contentView(coord: DraftDayCoordinator) -> some View {
        ZStack {
            if coord.mode == .complete {
                // R24 — draft summary + undrafted free agency stage.
                DraftUDFAPanel(coordinator: coord)
            } else {
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

            // League trades cut in over the board (AI-vs-AI swaps and the
            // user's own deals) — Wave 4 renders what was previously a
            // write-only `DraftEvent`.
            TradeBeatBanner(coordinator: coord)

            // Trade offer banner pinned to the top edge when an AI partner
            // proposes a deal (Wave 4 — picks, future picks and veterans).
            if let offer = coord.pendingTradeOffer, coord.mode != .userPick {
                VStack {
                    TradeOfferBanner(
                        motive: offer.motive,
                        outgoing: offer.givesLabel(currentSeason: coord.draftYear),
                        incoming: offer.getsLabel(currentSeason: coord.draftYear),
                        gmLine: "\(offer.gmName) · \(offer.gmStyle)",
                        valueSummary: "Chart value: you send \(offer.userGivesValue) pts · receive \(offer.userGetsValue) pts",
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
        // ONE sheet for the whole room (task #153a). Three `.sheet` modifiers
        // used to be stacked on this ZStack — the exact trap their own comments
        // warned about — and two of them drove their presentation off a computed
        // getter with a `set: { _ in }` no-op. SwiftUI writes
        // `false` through that binding when it dismisses; a setter that throws
        // the write away leaves the getter still saying `true`, so the sheet
        // re-presents on the next body pass — and the clock republished
        // `clockSeconds` once a second, guaranteeing one. That is why
        // "Continue Draft" took three to eight taps to stick.
        //
        // Now: one `.sheet(item:)`, one priority order, and a setter that
        // actually clears the state a system dismissal reports.
        .sheet(item: Binding(
            get: { activeModal(coord) },
            set: { newValue in
                guard newValue == nil else { return }
                if coord.pendingRoundRecap != nil {
                    coord.dismissRoundRecap()
                } else if coord.isTradeUpBoardOpen {
                    coord.closeTradeUpBoard()
                }
            }
        )) { modal in
            switch modal {
            case .roundRecap(let recap):
                RoundRecapSheet(coordinator: coord, recap: recap)
            case .userPick:
                PickSheetView(coordinator: coord)
                    .interactiveDismissDisabled()
            case .tradeUpBoard:
                TradeUpBoardSheet(coordinator: coord)
            }
        }
    }

    /// The one modal the room may raise, in priority order: a round recap the
    /// user owes an answer to, then his own turn, then the move-up call sheet.
    ///
    /// The move-up sheet is presented from INSIDE `PickSheetView` when he is on
    /// the clock (one view, one sheet), which is why it ranks last here.
    private enum DraftModal: Identifiable {
        case roundRecap(RoundRecapData)
        case userPick
        case tradeUpBoard

        var id: String {
            switch self {
            case .roundRecap(let recap): return "roundRecap-\(recap.round)"
            case .userPick:              return "userPick"
            case .tradeUpBoard:          return "tradeUpBoard"
            }
        }
    }

    private func activeModal(_ coord: DraftDayCoordinator) -> DraftModal? {
        if let recap = coord.pendingRoundRecap { return .roundRecap(recap) }
        if coord.mode == .userPick { return .userPick }
        if coord.isTradeUpBoardOpen { return .tradeUpBoard }
        return nil
    }
}
