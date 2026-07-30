#if DEBUG
import Foundation

// MARK: - Face bundle audit (phase-4 stage-4 gate)
//
// Answers, from inside a running build, the one question the phase-4 plan
// cannot answer by reading source: **did the packaged face library actually
// make it into the app, and does the code find it where it landed?**
//
// It matters because the two halves of the pipeline are joined only by a
// filesystem convention. `tools/faces/package_faces.py` writes
// `tools/faces/out/`, a human copies that into the Xcode tree, and the
// project's filesystem-synchronized root group bundles whatever it finds —
// FLATTENING subdirectories on the way, so `Resources/Faces/face_00000.heic`
// ships as `dynasty.app/face_00000.heic`. Nothing in the project file records
// that contract, which is exactly why it needs measuring rather than
// documenting.
//
// Run it on a simulator build:
//
//     xcrun simctl launch --console-pty --terminate-running-process \
//       <device> com.brewcrow.dynasty  # with SIMCTL_CHILD_FACE_BUNDLE_AUDIT=1
//
// A bundle with ZERO images is a PASS. The images generate out-of-band and the
// app is required to render a placeholder silhouette for every one of them
// (`PersonFaceView.placeholder`), so "no pictures yet" is the designed state,
// not a defect. What the audit fails on is an inconsistency that would silently
// degrade the shipped product:
//
//   * an empty catalog — nothing could be assigned at all;
//   * `faces_manifest.json` in the bundle that did NOT become the catalog
//     (corrupt / empty / wrong schema), because the silent fallback to the
//     synthesized catalog would hide a broken packaging step;
//   * HEICs in the bundle the catalog does not list — a stale manifest,
//     i.e. images that ship and can never be shown.
@MainActor
enum FaceBundleAudit {

    /// The repo path packaged output must be copied to. Single source of truth
    /// for the drop location: `Resources/Faces/.gitkeep` quotes it, the plan
    /// quotes it, and this line is what the audit prints.
    static let dropPath = "dynasty/dynasty/Resources/Faces/"

    /// One measured bundle state.
    struct Result {
        var catalogSource = ""
        var catalogCount = 0
        /// Where `faces_manifest.json` resolved: "absent", "bundle-root" or
        /// "Faces/".
        var manifestLocation = "absent"
        /// Manifest file present but the catalog came from synthesis anyway.
        var manifestPresentButUnused = false
        /// Catalog ids whose HEIC resolves through the renderer's own lookup.
        var imagesResolved = 0
        /// Which lookup arm found the first hit ("Faces/" or "bundle-root").
        var imageLocation = "-"
        /// `.heic` files sitting in the bundle, whatever the catalog says.
        var heicsInBundle = 0
        /// Bundled HEICs that no catalog id claims — a stale manifest.
        var orphanImages = 0
        var bytes = 0
        /// Catalog ids in the female half. Reported because it is the number that
        /// decides whether a female coach can get a portrait at all: the whole
        /// gender-strict ladder in `FaceLibrary.pickLocked` bottoms out at this
        /// count, and a manifest cut before the female range would show 0 here
        /// while every other number in this audit still looked healthy.
        var femaleFaces = 0
        /// Of `femaleFaces`, how many have a bundled image. A female id whose HEIC
        /// is missing renders the `coach_f*` placeholder — the same fallback a nil
        /// `faceID` gets, so it is invisible in the other counters.
        var femaleImagesResolved = 0
        var failures: [String] = []

        var isPass: Bool { failures.isEmpty }
    }

    /// Measures the bundle and prints one `FACEBUNDLE:` block + a verdict.
    @discardableResult
    static func run() -> Result {
        var result = Result()
        let library = FaceLibrary.shared
        library.ensureCatalogLoaded()

        result.catalogSource = library.catalogSource.rawValue
        result.catalogCount = library.entries.count
        result.femaleFaces = library.entries.reduce(0) { $1.bucket.isFemale ? $0 + 1 : $0 }
        if result.catalogCount == 0 {
            result.failures.append("catalog is EMPTY — no person could be assigned a portrait")
        }

        // --- Manifest -------------------------------------------------------
        if let manifestURL = FaceLibrary.manifestURL() {
            let parent = manifestURL.deletingLastPathComponent().lastPathComponent
            result.manifestLocation = parent == FaceGeneratorConstants.facesFolder
                ? "\(FaceGeneratorConstants.facesFolder)/"
                : "bundle-root"
            if library.catalogSource != .manifest {
                result.manifestPresentButUnused = true
                result.failures.append(
                    "faces_manifest.json IS bundled (\(result.manifestLocation)) but the catalog "
                    + "fell back to synthesis — the file did not decode, or lists no faces"
                )
            }
        }

        // --- Images, resolved through the renderer's own lookup ------------
        var claimed: Set<String> = []
        for entry in library.entries {
            guard let url = FaceImageCache.bundleURL(for: entry.id) else { continue }
            result.imagesResolved += 1
            if entry.bucket.isFemale { result.femaleImagesResolved += 1 }
            claimed.insert(url.lastPathComponent)
            if result.imageLocation == "-" {
                let parent = url.deletingLastPathComponent().lastPathComponent
                result.imageLocation = parent == FaceGeneratorConstants.facesFolder
                    ? "\(FaceGeneratorConstants.facesFolder)/"
                    : "bundle-root"
            }
            result.bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }

        // --- Cross-check: what is physically there vs. what the catalog knows
        let bundled = physicalHEICs()
        result.heicsInBundle = bundled.count
        let orphans = bundled.subtracting(claimed)
        result.orphanImages = orphans.count
        if !orphans.isEmpty {
            let examples = orphans.sorted().prefix(3).joined(separator: ", ")
            result.failures.append(
                "\(orphans.count) bundled .heic files are not in the catalog (stale manifest — "
                + "these images can never be shown): \(examples)"
            )
        }

        report(result)
        return result
    }

    // MARK: - Reporting

    private static func report(_ result: Result) {
        let missing = max(0, result.catalogCount - result.imagesResolved)
        let mib = Double(result.bytes) / (1024 * 1024)
        print("FACEBUNDLE: dropPath=\(dropPath) (packaged output goes here; the "
              + "filesystem-synchronized group flattens it into the bundle root)")
        // Three distinct bands, printed as three ranges. The old line printed
        // `generatedPoolSize..<poolSize` as "the reserve range", which stopped
        // being true the moment the pool grew past 2 560: it swallowed the whole
        // 1 024-id female range into a band the picker treats as a last resort.
        // `FaceGeneratorConstants.isReserve` is the bounded window and this line
        // now agrees with it.
        let reserveEnd = FaceGeneratorConstants.generatedPoolSize
            + FaceGeneratorConstants.reservePoolSize
        print("FACEBUNDLE: catalog=\(result.catalogSource)/\(result.catalogCount) "
              + "manifest=\(result.manifestLocation) "
              + "generatedRange=0..<\(FaceGeneratorConstants.generatedPoolSize) "
              + "reserveRange=\(FaceGeneratorConstants.generatedPoolSize)..<\(reserveEnd) "
              + "femaleRange=\(reserveEnd)..<\(FaceGeneratorConstants.poolSize) "
              + "femaleFaces=\(result.femaleFaces) "
              + "femaleImages=\(result.femaleImagesResolved)/\(result.femaleFaces)")
        print(String(
            format: "FACEBUNDLE: images resolved=%d/%d (%.1f%%) at=%@  placeholderFallback=%d  "
            + "heicsInBundle=%d orphans=%d  bytes=%.2f MiB",
            result.imagesResolved, result.catalogCount,
            result.catalogCount == 0
                ? 0 : 100 * Double(result.imagesResolved) / Double(result.catalogCount),
            result.imageLocation, missing, result.heicsInBundle, result.orphanImages, mib
        ))
        if result.imagesResolved == 0 {
            print("FACEBUNDLE: no face images in this build — every portrait renders the "
                  + "placeholder silhouette. This is the DESIGNED pre-shipment state.")
        }
        for failure in result.failures { print("FACEBUNDLE: FAIL — \(failure)") }
        print("FACEBUNDLE: ===== verdict: \(result.isPass ? "PASS" : "FAIL") =====")
    }

    /// Every `.heic` physically present in the product, from both the bundle
    /// root and a `Faces/` subdirectory — independent of `Bundle.url(forResource:)`
    /// so a lookup bug cannot hide files from the cross-check.
    private static func physicalHEICs() -> Set<String> {
        guard let root = Bundle.main.resourceURL else { return [] }
        var names: Set<String> = []
        for directory in [root, root.appendingPathComponent(FaceGeneratorConstants.facesFolder)] {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil
            )) ?? []
            for url in contents where url.pathExtension.lowercased() == "heic" {
                names.insert(url.lastPathComponent)
            }
        }
        return names
    }
}
#endif
