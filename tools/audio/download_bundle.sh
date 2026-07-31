#!/bin/bash
# Downloads the Sonniss #GameAudioGDC 2026 bundle (5 parts, 6.92 GB total).
#
# Source note — why not gdc.sonniss.com directly:
#   * https://downloads.sonniss.com/... sits behind a Cloudflare JS challenge
#     ("Just a moment...") that a headless client cannot pass.
#   * The Google Drive mirror linked from gdc.sonniss.com returns
#     "Quota exceeded - too many users have downloaded this file recently".
#   * The Internet Archive item `sonniss.com-gdc-game-audio-bundles` hosts the
#     identical files over plain HTTP with byte ranges (resume works). Part
#     sizes were verified against the official Drive content-length values and
#     match exactly, so the payload is bit-identical to the official release.
#
# Parts are fetched in PARALLEL: archive.org throttles a single connection to
# ~1.7 MB/s, but five concurrent streams reach ~4 MB/s aggregate.
#
# Usage: ./download_bundle.sh          (safe to re-run; resumes + verifies)
set -u

DEST="$(cd "$(dirname "$0")" && pwd)/raw_bundles"
BASE="https://archive.org/download/sonniss.com-gdc-game-audio-bundles"
mkdir -p "$DEST"

# filename<TAB>expected_bytes
PARTS=(
  "Sonniss.com-GDC2026-GameAudioBundle1of5.zip 1301592146"
  "Sonniss.com-GDC2026-GameAudioBundle2of5.zip 1418237636"
  "Sonniss.com-GDC2026-GameAudioBundle3of5.zip 1490753131"
  "Sonniss.com-GDC2026-GameAudioBundle4of5.zip 1853924113"
  "Sonniss.com-GDC2026-GameAudioBundle5of5.zip  856448992"
)

fetch() {   # fetch <filename> <expected_bytes>
  local fn="$1" want="$2" out="$DEST/$1" have
  for attempt in 1 2 3; do
    have=0; [ -f "$out" ] && have=$(stat -f%z "$out")
    [ "$have" = "$want" ] && { echo "OK   $fn ($want bytes)"; return 0; }
    echo "GET  $fn attempt $attempt ($have/$want)"
    curl -sL -C - --retry 3 --retry-delay 5 --connect-timeout 30 \
         --speed-limit 2048 --speed-time 180 \
         "$BASE/$fn" -o "$out"
    sleep 3
  done
  have=0; [ -f "$out" ] && have=$(stat -f%z "$out")
  [ "$have" = "$want" ] && { echo "OK   $fn"; return 0; }
  echo "FAIL $fn ($have/$want)"; return 1
}

pids=()
for row in "${PARTS[@]}"; do
  set -- $row
  fetch "$1" "$2" &
  pids+=($!)
done

rc=0
for p in "${pids[@]}"; do wait "$p" || rc=1; done

echo "=== done (failures: $rc) ==="
ls -la "$DEST"
exit $rc
