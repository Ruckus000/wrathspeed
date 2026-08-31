#!/usr/bin/env python3
"""Build the bundled exercise demo clips.

Reads Tools/exercise-media/media_sources.json, pulls the source artwork, renders one
seamless looping H.264 clip per movement into WrathspeedCore/Sources/WrathspeedCore/Media/,
and writes Resources/media_manifest.json describing what landed where.

Two source kinds:
  animated-gif  transcoded straight to MP4, preserving the original frame timing.
  image-pair    a start and end photo, crossfaded into a ping-pong loop.

Every movement id in strength_catalog.json and movement_catalog.json must appear in
media_sources.json, or the build fails. That check is the whole point: it stops a
movement from silently drifting out of media coverage when the catalogs change.

Usage:
    python3 Tools/exercise-media/build_media.py            # build everything
    python3 Tools/exercise-media/build_media.py --check    # validate mappings, fetch nothing
    python3 Tools/exercise-media/build_media.py --only bw-squat push-up

Requires: pillow, imageio-ffmpeg  (pip install pillow imageio-ffmpeg)
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image
import imageio_ffmpeg

REPO = Path(__file__).resolve().parents[2]
CORE = REPO / "WrathspeedCore" / "Sources" / "WrathspeedCore"
RESOURCES = CORE / "Resources"
# The strength catalog is owned by the app bundle; only the movement catalog and the
# generated media live in the WrathspeedCore resources.
STRENGTH_CATALOG = REPO / "Wrathspeed" / "strength_catalog.json"
# The guided mobility routines linked from Today. This catalog addresses clips indirectly,
# through `mediaExerciseID`, so its own ids are not media ids and the set comparison in
# main() cannot see it. It needs the separate check below -- and went without one, which is
# how all nine of its movements sat on a bare SF Symbol while --check reported full coverage.
MOBILITY_CATALOG = REPO / "Wrathspeed" / "mobility_catalog.json"
MEDIA_OUT = CORE / "Media"
SOURCES_FILE = Path(__file__).resolve().parent / "media_sources.json"
CACHE = REPO / ".media-cache"

# Output geometry and timing. 480px square keeps a 58-clip bundle in the low tens of MB
# while still looking sharp on a phone; the sources top out at 360-850px anyway.
CANVAS = 480
FPS = 24
# image-pair loop: hold start, fade to end, hold end, fade back
HOLD_FRAMES = 16
FADE_FRAMES = 12

FFMPEG = imageio_ffmpeg.get_ffmpeg_exe()


def log(msg: str) -> None:
    print(msg, flush=True)


def fetch(url: str, dest: Path) -> Path:
    """Download url to dest, caching by URL hash so reruns are cheap."""
    key = hashlib.sha256(url.encode()).hexdigest()[:16]
    cached = CACHE / f"{key}{Path(url).suffix or '.bin'}"
    if not cached.exists():
        CACHE.mkdir(parents=True, exist_ok=True)
        req = urllib.request.Request(url, headers={"User-Agent": "wrathspeed-media-build"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r, open(cached, "wb") as f:
                shutil.copyfileobj(r, f)
        except urllib.error.HTTPError as e:
            raise SystemExit(f"  ! {e.code} fetching {url}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(cached, dest)
    return dest


def fit_to_canvas(im: Image.Image) -> Image.Image:
    """Letterbox onto a white CANVAS-square. Sources are all white-background."""
    im = im.convert("RGB")
    im.thumbnail((CANVAS, CANVAS), Image.LANCZOS)
    canvas = Image.new("RGB", (CANVAS, CANVAS), (255, 255, 255))
    canvas.paste(im, ((CANVAS - im.width) // 2, (CANVAS - im.height) // 2))
    return canvas


def frames_from_gif(
    path: Path,
    watermark: list[int] | None = None,
    watermark_source_size: list[int] | None = None,
) -> list[Image.Image]:
    """Resample a GIF to a constant FPS, preserving its real per-frame timing.

    These GIFs are not evenly timed: they hold ~1s at the top and bottom of the rep and
    run ~100ms per frame through the movement. Encoding one output frame per source frame
    would throw that away and play a whole squat in half a second. Accumulating against
    elapsed source time keeps the holds and avoids rounding drift over the clip.

    `watermark` is an [x0, y0, x1, y1] rect in SOURCE pixels, painted white before the
    frame is letterboxed. It has to happen here, on the composited frame: these GIFs store
    partial sub-frames with disposal=1, so patching the raw sub-frame data would miss the
    frames that do not redraw that corner. Seeking sequentially and copying makes Pillow
    hand back a fully composited image, which is what gets painted.

    Because that rect is absolute pixels, it is only correct at the size it was measured
    against, which `watermark_source_size` records. A larger source would leave part of the
    logo showing and a smaller one would paint over the figure -- and either way the build
    would report success, with the damage visible only by opening the clip. So a mismatch
    is a hard failure rather than a silent one.
    """
    im = Image.open(path)
    if watermark and watermark_source_size and list(im.size) != list(watermark_source_size):
        raise SystemExit(
            f"ERROR: {path.name} is {im.size[0]}x{im.size[1]}, but its source declares a "
            f"watermark rect measured on {watermark_source_size[0]}x{watermark_source_size[1]}. "
            f"Re-measure 'watermark' in media_sources.json for this size, or the logo will "
            f"be only partly painted out."
        )
    frames: list[Image.Image] = []
    elapsed = 0.0
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        composited = im.copy().convert("RGB")
        if watermark:
            composited.paste((255, 255, 255), tuple(watermark))
        rendered = fit_to_canvas(composited)
        elapsed += (im.info.get("duration") or 100) / 1000.0
        n = max(1, round(elapsed * FPS) - len(frames))
        frames.extend([rendered] * n)
    # A still source -- an isometric hold with no rep -- otherwise encodes to a couple of
    # frames, and AVPlayerLooper restarting an 80ms clip forever is wasteful for something
    # that never changes. Hold it for a second instead; it looks identical and loops rarely.
    #
    # `frames` first: a truncated GIF can report n_frames as 0, and dividing by that raised
    # a bare ZeroDivisionError from inside here, naming neither the movement nor the file.
    # Falling through empty instead lets `encode` fail with the context to act on.
    if frames and len(frames) < FPS:
        frames = frames * (FPS // len(frames) + 1)
    return frames


def frames_from_pair(a: Path, b: Path) -> list[Image.Image]:
    """Ping-pong crossfade: start -> end -> start, so the clip loops seamlessly."""
    start, end = fit_to_canvas(Image.open(a)), fit_to_canvas(Image.open(b))
    frames = [start] * HOLD_FRAMES
    for i in range(1, FADE_FRAMES + 1):
        frames.append(Image.blend(start, end, i / (FADE_FRAMES + 1)))
    frames += [end] * HOLD_FRAMES
    for i in range(1, FADE_FRAMES + 1):
        frames.append(Image.blend(end, start, i / (FADE_FRAMES + 1)))
    return frames


def flatten_ground_to_white(im: Image.Image, tolerance: int = 12) -> Image.Image:
    """Repaint a near-uniform coloured ground white.

    The illustration tier ships on a pale blue ground, which reads as a coloured box
    beside the white-background renders. Sampling the corner and replacing only pixels
    within `tolerance` of it leaves the figure alone -- its blues are far more saturated
    than the ground. RepDB's free tier explicitly allows recolouring for in-app use.
    """
    im = im.convert("RGB")
    ground = im.getpixel((0, 0))
    if max(ground) - min(ground) > 60:
        return im  # not a flat ground; leave it alone
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            if (abs(r - ground[0]) <= tolerance
                    and abs(g - ground[1]) <= tolerance
                    and abs(b - ground[2]) <= tolerance):
                px[x, y] = (255, 255, 255)
    return im


def frames_from_single(path: Path) -> list[Image.Image]:
    """A held still. Used for isometric holds, where there is no movement to animate.

    Deliberately not given synthetic motion: inventing a pan or a zoom would imply a
    movement the source does not show.
    """
    still = fit_to_canvas(flatten_ground_to_white(Image.open(path)))
    return [still] * (HOLD_FRAMES * 2)


def encode(frames: list[Image.Image], dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as td:
        for i, f in enumerate(frames):
            f.save(Path(td) / f"{i:05d}.png")
        cmd = [
            FFMPEG, "-y", "-loglevel", "error",
            "-framerate", str(FPS),
            "-i", str(Path(td) / "%05d.png"),
            "-an",
            "-c:v", "libx264",
            "-profile:v", "high", "-level", "4.0",
            "-pix_fmt", "yuv420p",
            "-crf", "26",
            "-movflags", "+faststart",
            str(dest),
        ]
        subprocess.run(cmd, check=True)


def load_catalog_ids() -> dict[str, str]:
    """Every clip id the app can reach, mapped to what reaches it.

    Three routes, not two. The strength and movement catalogs name clips by their own id,
    so their ids ARE clip ids. The guided mobility catalog instead points at a clip through
    `mediaExerciseID`, which lets it reach a clip that no other catalog names -- a standing
    hamstring fold, say, which is not in the movement library but is in a recovery routine.
    Those referenced ids belong here too, or the orphan check rejects their mapping as
    unreachable and the build loop never builds them.
    """
    ids: dict[str, str] = {}
    strength = json.loads(STRENGTH_CATALOG.read_text())
    for e in strength["exercises"]:
        ids[e["id"]] = "strength"
    movements = json.loads((RESOURCES / "movement_catalog.json").read_text())
    for m in movements["movements"]:
        ids[m["id"]] = "movement"
    mobility = json.loads(MOBILITY_CATALOG.read_text())
    for routine in mobility["routines"]:
        for m in routine["movements"]:
            ref = m.get("mediaExerciseID")
            if ref:
                ids.setdefault(ref, "mobility")
    return ids


def check_mobility_links(mappings: dict) -> tuple[list[str], list[str]]:
    """Validate the guided mobility routines' indirect links to the clip library.

    Returns (dangling, unlinked). A dangling `mediaExerciseID` names a clip that does not
    exist and is an error -- the screen silently falls back to a symbol, which looks
    identical to having meant no clip at all. An unlinked movement is only reported: some
    are unlinked on purpose, because nothing in the library depicts them and a near-enough
    clip would teach the wrong movement.
    """
    catalog = json.loads(MOBILITY_CATALOG.read_text())
    dangling: list[str] = []
    unlinked: list[str] = []
    seen: set[str] = set()
    for routine in catalog["routines"]:
        for m in routine["movements"]:
            if m["id"] in seen:
                continue
            seen.add(m["id"])
            ref = m.get("mediaExerciseID")
            if ref is None:
                unlinked.append(f"{m['id']} ({m['name']})")
            elif ref not in mappings:
                dangling.append(f"{m['id']} -> {ref}")
    return dangling, unlinked


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate mappings only")
    ap.add_argument("--only", nargs="*", help="build just these movement ids")
    args = ap.parse_args()

    spec = json.loads(SOURCES_FILE.read_text())
    sources, mappings = spec["sources"], spec["mappings"]
    catalog_ids = load_catalog_ids()

    # Ids a catalog names directly. Clips reached only through mobility's `mediaExerciseID`
    # are excluded because `check_mobility_links` reports those, alongside the movement that
    # points at them -- counted here as well, one broken link surfaced as two separate
    # faults under two headings, inviting a fix in two places.
    named_by_catalog = {mid for mid, via in catalog_ids.items() if via != "mobility"}
    missing = sorted(named_by_catalog - set(mappings))
    # Orphans still compare against the full set: a mapping that only mobility reaches is
    # legitimately reachable and must not be reported as unused.
    orphaned = sorted(set(mappings) - set(catalog_ids))
    if missing:
        log("ERROR: catalog movements with no entry in media_sources.json:")
        for m in missing:
            log(f"  - {m}")
    if orphaned:
        log("ERROR: media_sources.json entries with no matching catalog movement:")
        for m in orphaned:
            log(f"  - {m}")
    dangling, unlinked = check_mobility_links(mappings)
    if dangling:
        log("ERROR: mobility_catalog.json mediaExerciseID values naming no known clip:")
        for m in dangling:
            log(f"  - {m}")
    if missing or orphaned or dangling:
        return 1
    # Counted apart, because `catalog_ids` also holds clips only mobility reaches. Reporting
    # the total as "catalog movements" gave a number that does not reconcile against the
    # catalogs, which reads as the check having gone stale.
    mobility_only = len(catalog_ids) - len(named_by_catalog)
    covered = f"✓ mappings cover all {len(named_by_catalog)} catalog movements"
    log(f"{covered} and {mobility_only} mobility-only clips" if mobility_only else covered)
    if unlinked:
        log(f"! {len(unlinked)} guided mobility movements show a symbol, not a clip:")
        for m in unlinked:
            log(f"  - {m}")
    if args.check:
        return 0

    wanted = set(args.only) if args.only else set(catalog_ids)
    manifest: dict[str, dict] = {}
    # Keyed off the declared sources rather than a fixed list, so adding a tier to
    # media_sources.json does not KeyError its way out of the build.
    counts = {name: 0 for name in list(sources) + ["none"]}

    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        for mid in sorted(catalog_ids):
            m = mappings[mid]
            src = m["source"]
            if src == "none":
                counts["none"] += 1
                log(f"  – {mid}: no artwork ({m.get('reason', '')}) → SF Symbol fallback")
                continue
            if mid not in wanted:
                # not rebuilding, but keep its manifest row if the file is already there
                kept = MEDIA_OUT / f"{mid}.mp4"
                if kept.exists():
                    counts[src] += 1
                    # Size passed even though this clip is not being rebuilt. Omitting it
                    # made `bytes` a property of how the build was invoked rather than of
                    # the clip: one `--only` run stripped the field from every other row.
                    manifest[mid] = build_row(mid, m, sources, size=kept.stat().st_size)
                continue

            cfg = sources[src]
            dest = MEDIA_OUT / f"{mid}.mp4"
            # Dispatch on the declared kind, not the source key. This read `src == "gifdb"`
            # while gifdb was the only animated tier, which quietly meant a second GIF
            # source would be routed to the image-pair branch and fetched as `<ref>/0.jpg`.
            if cfg["kind"] == "animated-gif":
                gif = fetch(f"{cfg['rawBase']}/{m['ref']}", work / f"{mid}.gif")
                frames = frames_from_gif(
                    gif,
                    watermark=cfg.get("watermark"),
                    watermark_source_size=cfg.get("watermarkSourceSize"),
                )
            elif cfg["kind"] == "image-single":
                still = fetch(f"{cfg['rawBase']}/{m['ref']}", work / f"{mid}{Path(m['ref']).suffix}")
                frames = frames_from_single(still)
            else:
                a = fetch(f"{cfg['rawBase']}/{m['ref']}/0.jpg", work / f"{mid}-0.jpg")
                b = fetch(f"{cfg['rawBase']}/{m['ref']}/1.jpg", work / f"{mid}-1.jpg")
                frames = frames_from_pair(a, b)
            encode(frames, dest)
            counts[src] += 1
            kb = dest.stat().st_size // 1024
            log(f"  ✓ {mid}: {src} {len(frames)}f → {kb} KB")
            manifest[mid] = build_row(mid, m, sources, size=dest.stat().st_size)

    RESOURCES.mkdir(parents=True, exist_ok=True)
    (RESOURCES / "media_manifest.json").write_text(
        json.dumps({"clips": manifest}, indent=2, sort_keys=True) + "\n"
    )

    total_mb = sum(p.stat().st_size for p in MEDIA_OUT.glob("*.mp4")) / 1_048_576
    log("")
    # Tallied by declared style, not by source key. Keyed off source names, this reported
    # "anatomical render: 32" on a build that produced 48 of them, because a second
    # render-style tier existed by then and only gifdb was being counted.
    by_style: dict[str, int] = {}
    for name, n in counts.items():
        if name == "none":
            continue
        by_style[sources[name]["style"]] = by_style.get(sources[name]["style"], 0) + n
    for style, n in sorted(by_style.items(), key=lambda kv: -kv[1]):
        log(f"{style:18}: {n}")
    log(f"{'symbol fallback':18}: {counts['none']}")
    log(f"bundle size       : {total_mb:.1f} MB across {len(manifest)} clips")
    return 0


def build_row(mid: str, m: dict, sources: dict, size: int | None = None) -> dict:
    cfg = sources[m["source"]]
    row = {
        "file": f"{mid}.mp4",
        "style": cfg["style"],
        "sourceRepo": cfg["repo"],
        "sourceRef": m["ref"],
    }
    if m.get("approximate"):
        row["approximate"] = m["approximate"]
    if size is not None:
        row["bytes"] = size
    return row


if __name__ == "__main__":
    sys.exit(main())
