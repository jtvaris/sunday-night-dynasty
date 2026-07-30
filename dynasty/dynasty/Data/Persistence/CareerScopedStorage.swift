import Combine
import SwiftUI

// MARK: - CareerScopedStorage
//
// The career-scoped replacement for `@AppStorage` on every key listed in
// `CareerScopedDefaults.keys`.
//
// ## Why `@AppStorage` cannot be used for these keys
//
// `@AppStorage("rosterNotes")` binds its key at PROPERTY-DECLARATION time, and
// the open career is not known then. That was survivable while the keys were
// global; it stopped being survivable the moment `migrateGlobalKeys` shipped,
// because that pass **moves** the legacy global value to the scoped key and then
// **deletes the global**. A view still reading the bare key therefore came up
// empty on the first launch after the update — the user's roster notes, prospect
// board, watchlist and priorities all read as "never written" — and a second
// career would have shared the first one's board anyway.
//
// `UserProspectGradeStore` solved this for the three prospect-grade keys by
// dropping `@AppStorage` and resolving the key per access. This is the same
// solution generalised, so the remaining ~15 read sites do not each hand-roll it.
//
// ## How it refreshes
//
// `@AppStorage` republishes through `UserDefaults`' own KVO. Resolving the key
// per access gives that up, so writes go through a shared, observed store: any
// view holding a `@CareerScopedStorage` (or a `@StateObject`/`@ObservedObject`
// on `CareerScopedDefaultsStore.shared`) is invalidated when any scoped key is
// written, from a view or from the engine. One notification for all of them is
// deliberate — these keys are read by several screens at once (roster notes live
// in both `RosterView` and `RosterEvaluationView`) and they are written by hand,
// a few times a session, never in a loop.

/// Value kinds a scoped key can hold. Exactly the three `@AppStorage` used.
protocol CareerScopedDefaultsValue {
    /// `nil` when the key is absent, so the caller can fall back to its default
    /// instead of `UserDefaults`' zero-value (`false` / `0` / `""`).
    static func readScoped(from defaults: UserDefaults, key: String) -> Self?
    func writeScoped(to defaults: UserDefaults, key: String)
}

extension String: CareerScopedDefaultsValue {
    static func readScoped(from defaults: UserDefaults, key: String) -> String? {
        defaults.string(forKey: key)
    }
    func writeScoped(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}

extension Bool: CareerScopedDefaultsValue {
    static func readScoped(from defaults: UserDefaults, key: String) -> Bool? {
        defaults.object(forKey: key) == nil ? nil : defaults.bool(forKey: key)
    }
    func writeScoped(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}

extension Int: CareerScopedDefaultsValue {
    static func readScoped(from defaults: UserDefaults, key: String) -> Int? {
        defaults.object(forKey: key) == nil ? nil : defaults.integer(forKey: key)
    }
    func writeScoped(to defaults: UserDefaults, key: String) {
        defaults.set(self, forKey: key)
    }
}

/// Change beacon for the scoped defaults. Holds no state — `UserDefaults` is
/// still the storage — it exists only so SwiftUI has something to observe now
/// that the key is resolved per access instead of bound to the property.
final class CareerScopedDefaultsStore: ObservableObject {
    static let shared = CareerScopedDefaultsStore()
    private init() {}

    /// Tells every view reading a scoped key to re-read. Safe from any thread;
    /// hops to the main actor because `objectWillChange` drives view updates.
    func notifyChanged() {
        if Thread.isMainThread {
            objectWillChange.send()
        } else {
            DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
        }
    }
}

/// Drop-in replacement for `@AppStorage` on a career-scoped key.
///
/// Usage is identical — `@CareerScopedStorage("rosterNotes") private var json: String = "{}"`
/// — but the key it reads is `rosterNotes.<career-uuid>` for the open save.
@propertyWrapper
struct CareerScopedStorage<Value: CareerScopedDefaultsValue>: DynamicProperty {

    /// The UNSUFFIXED key, exactly as listed in `CareerScopedDefaults.keys`.
    private let base: String
    private let defaultValue: Value

    @ObservedObject private var store = CareerScopedDefaultsStore.shared

    init(wrappedValue: Value, _ base: String) {
        self.base = base
        self.defaultValue = wrappedValue
    }

    var wrappedValue: Value {
        get { CareerScopedDefaults.value(base) ?? defaultValue }
        nonmutating set { CareerScopedDefaults.set(newValue, base) }
    }

    var projectedValue: Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0 }
        )
    }
}

// MARK: - Scoped read/write API

extension CareerScopedDefaults {

    /// The key for the open career, or the bare key when no career is bound.
    ///
    /// Read at every access rather than cached: a career switch inside one
    /// launch has to be picked up without anyone remembering to notify. The
    /// unbound fallback (previews, and the moments before the first
    /// `WeekAdvancer.bind`) is also exactly what `migrateGlobalKeys` reads, so a
    /// value written before a career exists is migrated rather than orphaned.
    static func scopedKey(_ base: String) -> String {
        guard let careerID = WeekAdvancer.activeCareerID else { return base }
        return key(base, careerID: careerID)
    }

    /// Reads a scoped key, `nil` when it has never been written for this save.
    static func value<Value: CareerScopedDefaultsValue>(_ base: String) -> Value? {
        Value.readScoped(from: .standard, key: scopedKey(base))
    }

    /// Writes a scoped key and refreshes every view reading one.
    static func set<Value: CareerScopedDefaultsValue>(_ value: Value, _ base: String) {
        value.writeScoped(to: .standard, key: scopedKey(base))
        CareerScopedDefaultsStore.shared.notifyChanged()
    }

    /// Clears a scoped key (`@AppStorage` has no equivalent; the two call sites
    /// that need it used `removeObject` on the bare key).
    static func remove(_ base: String) {
        UserDefaults.standard.removeObject(forKey: scopedKey(base))
        CareerScopedDefaultsStore.shared.notifyChanged()
    }

    /// Convenience for the non-view call sites (`WeekAdvancer`, the shell's
    /// task list) that used `UserDefaults.standard.bool(forKey:)` directly.
    static func bool(_ base: String) -> Bool {
        value(base) ?? false
    }

    /// Convenience for the same call sites' `string(forKey:)`.
    static func string(_ base: String) -> String? {
        value(base)
    }
}
