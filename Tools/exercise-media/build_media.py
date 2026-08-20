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


def frames_from_gif(path: Path) -> list[Image.Image]:
    """Resample a GIF to a constant FPS, preserving its real per-frame timing.

    These GIFs are not evenly timed: they hold ~1s at the top and bottom of the rep and
    run ~100ms per frame through the movement. Encoding one output frame per source frame
    would throw that away and play a whole squat in half a second. Accumulating against
    elapsed source time keeps the holds and avoids rounding drift over the clip.
    """
    im = Image.open(path)
    frames: list[Image.Image] = []
    elapsed = 0.0
    for i in range(getattr(im, "n_frames", 1)):
        im.seek(i)
        rendered = fit_to_canvas(im.copy())
        elapsed += (im.info.get("duration") or 100) / 1000.0
        n = max(1, round(elapsed * FPS) - len(frames))
        frames.extend([rendered] * n)
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
    """Every movement id the app can show, mapped to which catalog it came from."""
    ids: dict[str, str] = {}
    strength = json.loads(STRENGTH_CATALOG.read_text())
    for e in strength["exercises"]:
        ids[e["id"]] = "strength"
    movements = json.loads((RESOURCES / "movement_catalog.json").read_text())
    for m in movements["movements"]:
        ids[m["id"]] = "movement"
    return ids


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--check", action="store_true", help="validate mappings only")
    ap.add_argument("--only", nargs="*", help="build just these movement ids")
    args = ap.parse_args()

    spec = json.loads(SOURCES_FILE.read_text())
    sources, mappings = spec["sources"], spec["mappings"]
    catalog_ids = load_catalog_ids()

    missing = sorted(set(catalog_ids) - set(mappings))
    orphaned = sorted(set(mappings) - set(catalog_ids))
    if missing:
        log("ERROR: catalog movements with no entry in media_sources.json:")
        for m in missing:
            log(f"  - {m}")
    if orphaned:
        log("ERROR: media_sources.json entries with no matching catalog movement:")
        for m in orphaned:
            log(f"  - {m}")
    if missing or orphaned:
        return 1
    log(f"✓ mappings cover all {len(catalog_ids)} catalog movements")
    if args.check:
        return 0

    wanted = set(args.only) if args.only else set(catalog_ids)
    manifest: dict[str, dict] = {}
    counts = {"gifdb": 0, "photo": 0, "none": 0}

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
                if (MEDIA_OUT / f"{mid}.mp4").exists():
                    counts[src] += 1
                    manifest[mid] = build_row(mid, m, sources)
                continue

            cfg = sources[src]
            dest = MEDIA_OUT / f"{mid}.mp4"
            if src == "gifdb":
                gif = fetch(f"{cfg['rawBase']}/{m['ref']}", work / f"{mid}.gif")
                frames = frames_from_gif(gif)
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
    log(f"anatomical render : {counts['gifdb']}")
    log(f"photo             : {counts['photo']}")
    log(f"symbol fallback   : {counts['none']}")
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
