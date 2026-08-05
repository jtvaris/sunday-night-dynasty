import Foundation
import SwiftData

/// The ONE way any screen mutates the draft class.
///
/// Two mutation conventions used to coexist in the scouting UI (plan finding
/// F7). The correct one pulled `WeekAdvancer.currentDraftClass`, mutated it,
/// wrote it back, called `persistDraftClass` and saved. The other mutated a
/// view's `@Binding var prospects` — a local array handed down by whichever
/// screen happened to own the `@State` — and called `modelContext.save()` and
/// nothing else. The static class is the array every other screen and every
/// engine hook reads, and it is re-seeded from SwiftData on process restart, so
/// whatever survived a pro day was luck of object identity. That is why "after
/// a pro day runs, the results must appear on the player" read as broken.
///
/// This type exists so the correct convention is the only one there is:
///
/// ```swift
/// DraftClassMutator.mutate(modelContext) { klass in
///     guard let i = klass.firstIndex(where: { $0.id == prospect.id }) else { return }
///     ScoutingEngine.attendProDay(prospect: &klass[i], …)
/// }
/// ```
///
/// No call site may mutate a local `[CollegeProspect]` and hope.
enum DraftClassMutator {

    /// Applies `body` to the canonical draft class and persists the result.
    ///
    /// - Parameters:
    ///   - context: the model context to persist through.
    ///   - body: mutates the canonical class in place. Prospects are `@Model`
    ///     references, so mutating an element is enough; the array is `inout`
    ///     so a caller may also add or remove rows.
    /// - Returns: `false` when there is no class in memory to mutate (the
    ///   caller's action did not happen and it must not tell the user it did).
    @MainActor
    @discardableResult
    static func mutate(_ context: ModelContext,
                       _ body: (inout [CollegeProspect]) -> Void) -> Bool {
        var working = WeekAdvancer.currentDraftClass
        guard !working.isEmpty else { return false }

        body(&working)

        // Order is load-bearing: the static is the source of truth every other
        // surface reads THIS session, `persistDraftClass` is what survives the
        // next launch, and neither is sufficient alone.
        WeekAdvancer.currentDraftClass = working
        WeekAdvancer.persistDraftClass(working, to: context)
        try? context.save()
        return true
    }
}
