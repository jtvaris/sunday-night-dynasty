#!/bin/sh
# generate_audio.sh — R34 procedural match SFX for Sunday Night Dynasty.
#
# Synthesizes every audio asset the game bundles from pure ffmpeg filter
# chains (sine / noise / filter / envelope) — no recorded material, matching
# the retro non-photorealistic art direction. Output: 16-bit mono 44.1 kHz
# WAVs in dynasty/dynasty/Resources/Audio/ (picked up automatically by the
# Xcode filesystem-synchronized group).
#
# Usage:  sh tools/asset-pipeline/generate_audio.sh
# Requires: ffmpeg + ffprobe (brew install ffmpeg)
#
# Every file is verified after generation: duration via ffprobe, and
# amplitude statistics via volumedetect (no clipping: max_volume < -0.5 dB;
# not silent: mean_volume > -70 dB). The script exits non-zero on any
# failed check so CI/agents notice broken assets.

set -eu

FFMPEG="${FFMPEG:-ffmpeg}"
FFPROBE="${FFPROBE:-ffprobe}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/dynasty/dynasty/Resources/Audio"
RATE=44100
COMMON="-ar $RATE -ac 1 -c:a pcm_s16le"

mkdir -p "$OUT"

echo "== Generating match audio into $OUT =="

# ---------------------------------------------------------------------------
# 1. crowd_loop.wav — ~8 s seamless stadium murmur.
#    Two shaped noise beds (low murmur + faint high hiss) with slow tremolo
#    motion, then a 1 s overlap-add splice: the last second crossfades into
#    the first second of the source, so sample[end] == sample[start] and the
#    file loops without a click.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "anoisesrc=color=pink:r=$RATE:d=9:seed=4242" \
  -f lavfi -i "anoisesrc=color=white:r=$RATE:d=9:seed=1717" \
  -filter_complex "\
[0:a]highpass=f=180,lowpass=f=1100,tremolo=f=0.23:d=0.4,tremolo=f=0.57:d=0.25,volume=-15dB[murmur];\
[1:a]highpass=f=1200,lowpass=f=3200,tremolo=f=0.41:d=0.5,volume=-28dB[hiss];\
[murmur][hiss]amix=inputs=2:duration=shortest:normalize=0[src];\
[src]asplit=2[a][b];\
[a]atrim=1:9,asetpts=PTS-STARTPTS,afade=t=out:st=7:d=1:curve=qsin[main];\
[b]atrim=0:1,asetpts=PTS-STARTPTS,afade=t=in:d=1:curve=qsin,adelay=7000:all=1[head];\
[main][head]amix=inputs=2:duration=first:normalize=0[out]" \
  -map "[out]" $COMMON "$OUT/crowd_loop.wav"

# ---------------------------------------------------------------------------
# 2. crowd_swell.wav — ~3 s roar for big moments (TD, takeaway, big hit).
#    Same noise family, brighter band, fast flutter for "thousands of
#    voices", long symmetric rise/fall envelope.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "anoisesrc=color=pink:r=$RATE:d=3:seed=777" \
  -af "highpass=f=200,lowpass=f=1800,tremolo=f=9:d=0.10,volume=-9dB,\
afade=t=in:d=1.1:curve=qsin,afade=t=out:st=1.6:d=1.4:curve=qsin" \
  $COMMON "$OUT/crowd_swell.wav"

# ---------------------------------------------------------------------------
# 3. whistle.wav — referee pea whistle, ~0.6 s. Two close sine partials
#    (beat frequency shimmer) plus a 38 Hz tremolo for the pea trill.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "sine=f=2870:r=$RATE:d=0.6" \
  -f lavfi -i "sine=f=3110:r=$RATE:d=0.6" \
  -filter_complex "[0:a][1:a]amix=inputs=2:normalize=0,tremolo=f=38:d=0.55,\
volume=-6dB,afade=t=in:d=0.015,afade=t=out:st=0.48:d=0.12[out]" \
  -map "[out]" $COMMON "$OUT/whistle.wav"

# ---------------------------------------------------------------------------
# 4. snap.wav — short percussive tick for the C→QB exchange, ~0.12 s.
#    Bright filtered noise with a very fast exponential decay.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "anoisesrc=color=white:r=$RATE:d=0.12:seed=11" \
  -af "highpass=f=800,lowpass=f=4500,aeval=val(0)*exp(-40*t):c=same,\
volume=-5dB,afade=t=out:st=0.08:d=0.04" \
  $COMMON "$OUT/snap.wav"

# ---------------------------------------------------------------------------
# 5. catch_pop.wav — ball into hands, ~0.1 s. Mid sine ping + noise tick,
#    both gone in under 100 ms.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "sine=f=520:r=$RATE:d=0.1" \
  -f lavfi -i "anoisesrc=color=white:r=$RATE:d=0.1:seed=5" \
  -filter_complex "[1:a]highpass=f=1500,lowpass=f=5000,volume=-12dB[n];\
[0:a][n]amix=inputs=2:normalize=0,aeval=val(0)*exp(-45*t):c=same,volume=-4dB[out]" \
  -map "[out]" $COMMON "$OUT/catch_pop.wav"

# ---------------------------------------------------------------------------
# 6. hit_light.wav — routine tackle thud, ~0.22 s. Low-passed noise burst.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "anoisesrc=color=white:r=$RATE:d=0.22:seed=21" \
  -af "lowpass=f=750,aeval=val(0)*exp(-24*t):c=same,volume=-4dB,\
afade=t=out:st=0.16:d=0.06" \
  $COMMON "$OUT/hit_light.wav"

# ---------------------------------------------------------------------------
# 7. hit_big.wav — the de-cleater, ~0.4 s. Deeper noise burst + 72 Hz body
#    thump underneath.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "anoisesrc=color=brown:r=$RATE:d=0.4:seed=31" \
  -f lavfi -i "aevalsrc=exp(-14*t)*sin(2*PI*72*t):s=$RATE:d=0.4" \
  -filter_complex "[0:a]lowpass=f=420,aeval=val(0)*exp(-16*t):c=same,volume=2dB[n];\
[1:a]volume=-4dB[s];[n][s]amix=inputs=2:normalize=0,volume=-2dB,\
afade=t=out:st=0.3:d=0.1[out]" \
  -map "[out]" $COMMON "$OUT/hit_big.wav"

# ---------------------------------------------------------------------------
# 8. kick_thump.wav — foot into leather (punt/FG/kickoff), ~0.25 s.
#    Pitch-dropping low sine thump with a tiny contact click on top.
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=exp(-18*t)*sin(2*PI*(95-90*t)*t):s=$RATE:d=0.25" \
  -f lavfi -i "anoisesrc=color=white:r=$RATE:d=0.25:seed=41" \
  -filter_complex "[1:a]lowpass=f=900,aeval=val(0)*exp(-70*t):c=same,volume=-14dB[click];\
[0:a]volume=-3dB[thump];[thump][click]amix=inputs=2:normalize=0,\
afade=t=out:st=0.18:d=0.07[out]" \
  -map "[out]" $COMMON "$OUT/kick_thump.wav"

# ---------------------------------------------------------------------------
# 9. td_horn.wav — stadium air-horn riff, ~1.5 s: a short blast, a beat,
#    then the long blast. Harmonically stacked Bb3 (233 Hz) reads as a horn
#    rather than a pure test tone.
HORN="0.5*sin(2*PI*233*t)+0.28*sin(2*PI*466*t)+0.16*sin(2*PI*699*t)+0.09*sin(2*PI*932*t)"
$FFMPEG -hide_banner -loglevel error -y \
  -f lavfi -i "aevalsrc=$HORN:s=$RATE:d=0.45" \
  -f lavfi -i "aevalsrc=0:s=$RATE:d=0.08" \
  -f lavfi -i "aevalsrc=$HORN:s=$RATE:d=0.85" \
  -filter_complex "\
[0:a]afade=t=in:d=0.03,afade=t=out:st=0.35:d=0.1[b1];\
[2:a]afade=t=in:d=0.03,afade=t=out:st=0.55:d=0.3[b2];\
[b1][1:a][b2]concat=n=3:v=0:a=1,volume=-9dB[out]" \
  -map "[out]" $COMMON "$OUT/td_horn.wav"

# ---------------------------------------------------------------------------
# Verification: duration, clipping, silence. ffmpeg writes volumedetect
# stats to stderr; parse them per file.
echo ""
echo "== Verifying waveforms =="
FAIL=0
check() {
    file="$1"; want_min="$2"; want_max="$3"
    path="$OUT/$file"
    if [ ! -s "$path" ]; then
        echo "FAIL  $file: missing or empty file"; FAIL=1; return
    fi
    dur=$($FFPROBE -v error -show_entries format=duration -of default=nw=1:nk=1 "$path")
    stats=$($FFMPEG -hide_banner -i "$path" -af volumedetect -f null - 2>&1)
    maxv=$(printf '%s' "$stats" | sed -n 's/.*max_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p')
    meanv=$(printf '%s' "$stats" | sed -n 's/.*mean_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p')
    ok="OK  "
    # Duration window.
    if ! awk "BEGIN{exit !($dur >= $want_min && $dur <= $want_max)}"; then
        ok="FAIL"; FAIL=1
    fi
    # No clipping (max below -0.5 dBFS) and not silent (mean above -70 dB).
    if ! awk "BEGIN{exit !($maxv < -0.5)}"; then ok="FAIL"; FAIL=1; fi
    if ! awk "BEGIN{exit !($meanv > -70)}"; then ok="FAIL"; FAIL=1; fi
    printf '%s %-16s dur=%-8ss max=%-7s dB mean=%-7s dB\n' "$ok" "$file" "$dur" "$maxv" "$meanv"
}

check crowd_loop.wav  7.9 8.1
check crowd_swell.wav 2.9 3.1
check whistle.wav     0.55 0.65
check snap.wav        0.10 0.14
check catch_pop.wav   0.08 0.12
check hit_light.wav   0.20 0.24
check hit_big.wav     0.38 0.42
check kick_thump.wav  0.23 0.27
check td_horn.wav     1.3 1.5

# Loop-point continuity: first and last 5 ms of crowd_loop must carry the
# same energy (the overlap-add splice guarantees the exact boundary sample;
# this catches a broken splice wholesale).
head_rms=$($FFMPEG -hide_banner -i "$OUT/crowd_loop.wav" -af "atrim=0:0.005,volumedetect" -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p')
tail_rms=$($FFMPEG -hide_banner -i "$OUT/crowd_loop.wav" -af "atrim=7.995:8,volumedetect" -f null - 2>&1 | sed -n 's/.*mean_volume: \(-\{0,1\}[0-9.]*\) dB.*/\1/p')
if awk "BEGIN{d=$head_rms-($tail_rms); if (d<0) d=-d; exit !(d < 6)}"; then
    echo "OK   crowd_loop loop point: head $head_rms dB vs tail $tail_rms dB"
else
    echo "FAIL crowd_loop loop point mismatch: head $head_rms dB vs tail $tail_rms dB"
    FAIL=1
fi

echo ""
if [ "$FAIL" -ne 0 ]; then
    echo "== AUDIO GENERATION FAILED — see FAIL lines above =="
    exit 1
fi
echo "== All audio assets generated and verified =="
ls -la "$OUT"
