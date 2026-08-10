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

            // THE ROOM'S ONE AMBIENT OVERLAY (#105 Wave 3b). Four views used to
            // hang here — a full-screen drama queue, a bottom reaction toast, a
            // top trade cut-in and a top trade-offer card — each with its own
            // lifecycle, so three of them could be on screen at once. §3 family
            // 8 called that out as the war room's defect: "five simultaneous
            // overlay mechanisms reduced to the standard set".
            //
            // The standard set is three, and each answers a different question:
            //
            //   the sheet ....... the room needs an answer AND owns the screen
            //                     (his turn, a round recap, the move-up board)
            //   the action bar .. he is being asked to COMMIT — the trade offer
            //                     moved onto `DraftControlBar` (P5)
            //   this rail ....... the broadcast is telling him something and
            //                     will get out of the way
            //
            // Nothing else may raise a view over the board.
            DraftBroadcastRail(coordinator: coord)
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
