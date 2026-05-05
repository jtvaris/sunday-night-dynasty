import Foundation
import SwiftData
import OSLog

/// Persists `DraftEvent` records as the draft unfolds. Owned by `DraftDayCoordinator`.
@MainActor
final class DraftStoryRecorder {

    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.dynasty.app", category: "DraftStoryRecorder")

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Inserts a `DraftEvent` and saves the context. Save failures are logged, never thrown —
    /// a missed event must not crash the live draft loop.
    func record(_ event: DraftEvent) {
        modelContext.insert(event)
        do {
            try modelContext.save()
        } catch {
            logger.error("Failed to save DraftEvent (sequence=\(event.sequence, privacy: .public)): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns all persisted events for the given draft year, ordered by sequence.
    func events(forYear year: Int) -> [DraftEvent] {
        let descriptor = FetchDescriptor<DraftEvent>(
            predicate: #Predicate { $0.draftYear == year },
            sortBy: [SortDescriptor(\.sequence, order: .forward)]
        )
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch DraftEvents for year \(year, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
