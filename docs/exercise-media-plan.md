# Exercise media plan

How demo clips get into Wrathspeed, why the sources are what they are, and what to do when
they need to change.

## What shipped

58 movements are addressable by the app, and all 58 now have a bundled looping clip. Total
bundle cost is **2.3 MB**.

| | Count |
| --- | --- |
| Anatomical render (house style) | 30 |
| Photographic | 27 |
| Flat illustration | 1 |
| SF Symbol fallback | 0 |

The illustration is `bird-dog`. No free source carries it in the house style — the
ExerciseDB render family was searched exhaustively (seven mirrors, ~25,000 files, plus the
alternate names quadruped, contralateral, opposite-arm and all-fours) and it is absent from
all of them. It comes instead from RepDB's free tier, whose licence permits in-app use with
attribution. Its pale ground is recoloured to white by the build script so it sits with the
rest; the source is an isometric hold, which is the position at the top of each rep.

Content breaks down as 20 strength exercises (pre-existing), 10 warm-up mobility movements,
12 running form drills, and 16 cool-down stretches — the last three groups are new.

## Decisions and why

**Bundled, not streamed.** Wrathspeed is offline-first: the watch app and the audio cue
player assume no network. Streaming demos from an API would have made the one screen you
look at mid-workout the only screen that needs signal. At 2.3 MB for the whole library the
tradeoff isn't close.

**Media is decoration over content that stands alone.** Every movement carries a name, a
cue, and an SF Symbol. The clip is layered on top. `MediaLibrary` is deliberately total — a
missing manifest, a missing entry, and a missing file all resolve to "no clip" and the UI
renders the symbol. Nothing in the media path can take a workout screen down.

**Never substitute a different movement.** Where neither source had the actual movement, the
mapping records `"source": "none"` and the app falls back to a symbol. A clip of the wrong
exercise is worse than no clip, because it teaches the wrong thing silently.

## Sources

The art direction target was a 3D anatomical render — faceless model, working muscles
highlighted red, white background.

| Source | Style | Used for |
| --- | --- | --- |
| [ExerciseGymGifsDB](https://github.com/JahelCuadrado/ExerciseGymGifsDB) | anatomical render | strength, most static stretches |
| [free-exercise-db](https://github.com/yuhonas/free-exercise-db) | photographic | running drills, foam rolling, gaps |

The render set covers gym strength thoroughly and static stretching well, but has almost no
running drills (no skips, butt kicks, carioca, or bounds) and no foam rolling. That gap is
the entire reason for the photographic tier — it is a coverage fallback, not a style choice.

Sources considered and rejected: **YMove** (cleanest license, but only ~25 free clips and
the domain is unreachable from the build sandbox), **MuscleWiki API** (500 calls/month and
online-only, at odds with offline bundling), **Precision Nutrition** (link-out model, not
embeddable), **Everkinetic** (illustrated and CC-BY-SA, but zero stretches and zero drills,
and a line-art style further from the target than the render set).

## Licensing status

**This is a personal build and the clips are not cleared for distribution.** See
`Content/LICENSE.md`. The pipeline is built so that re-sourcing is cheap: replace the refs
in `media_sources.json`, re-run the build script, and the manifest, the app, and the tests
all follow automatically.

## How the pipeline works

```
Tools/exercise-media/media_sources.json     mapping: movement id -> source + ref
Tools/exercise-media/build_media.py         fetch, render, encode, emit manifest
        |
        v
WrathspeedCore/Sources/WrathspeedCore/Media/*.mp4                 58 clips
WrathspeedCore/Sources/WrathspeedCore/Resources/media_manifest.json
```

Three source kinds are handled:

- **Animated GIF** — transcoded to H.264, resampled to a constant 24fps while preserving the
  source's real per-frame timing. This matters: these GIFs hold ~1s at the top and bottom of
  each rep and run ~100ms per frame between. Encoding one output frame per source frame
  would play an entire squat in half a second.
- **Image pair** — a start and end photo, crossfaded into a ping-pong loop (hold, fade, hold,
  fade back) so it loops seamlessly.
- **Single image** — a held still, for an isometric hold where there is no movement to
  animate. Deliberately given no synthetic pan or zoom, which would imply motion the source
  does not show. Its near-uniform coloured ground is repainted white first, sampling the
  corner and replacing only pixels close to it so the figure is untouched.

All three are letterboxed onto a 480px white square, encoded as silent H.264 yuv420p with
`+faststart`.

```bash
pip install pillow imageio-ffmpeg
python3 Tools/exercise-media/build_media.py --check          # validate mappings only
python3 Tools/exercise-media/build_media.py                  # build everything
python3 Tools/exercise-media/build_media.py --only bw-squat  # rebuild one
```

Downloads are cached in `.media-cache/` (gitignored), so reruns are cheap.

### The coverage check

`--check` fails the build if any movement in `strength_catalog.json` or
`movement_catalog.json` lacks a `media_sources.json` entry, or if the mapping names a
movement no catalog contains. This is the guard that stops a movement from silently drifting
out of media coverage when someone adds an exercise. Run it in CI alongside the tests.

## How the app consumes it

- `MovementCatalog` / `Movement` — the new mobility, drill and stretch content.
- `MobilityPlanner` — builds warm-up, drill and cool-down routines per workout kind. Quality
  days get a longer warm-up and the only drill block; easy days get neither. Selection is
  deterministic so the same session renders identically on phone, watch, and in tests.
- `MediaLibrary` — resolves a movement id to a bundled file URL. Total; never throws at the
  call site.
- `MovementMediaView` — loops the clip via `AVPlayerLooper`, muted, falling back to the
  symbol. Muted matters: these play behind spoken cues and the user's music.
- Routines surface in `WorkoutDetailView` under "Prep and recovery"; every movement is
  browsable via Settings → Movement library.

## Swapping the media later

1. Edit the `ref` values in `Tools/exercise-media/media_sources.json`, or add a new entry to
   `sources` with its own `rawBase` and `kind`.
2. Run `python3 Tools/exercise-media/build_media.py`.
3. Run the tests — `MediaLibraryTests` asserts every manifest entry resolves to a real file.
4. Update `Content/LICENSE.md`.

No Swift changes are needed for a re-source. That was the point of the manifest indirection.

## Known gaps

- `bird-dog` is a flat illustration and a still, not an animated house-style render. It is
  the only clip that does not move, because its source is an isometric hold.
- `reverse-lunge` uses a walking lunge render; the pattern is right, the step direction isn't.
  Flagged as `approximate` in the manifest.
- 27 clips are photographic rather than the house render style, concentrated in the drills and
  foam-rolling groups. Closing that gap needs a source with real running-drill coverage.
- The Apple Watch target does not show clips. Its storage budget and screen size want a
  different asset (a still keyframe, or a much smaller loop) rather than these files.
