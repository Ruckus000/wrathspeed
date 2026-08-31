# Exercise media plan

How demo clips get into Wrathspeed, why the sources are what they are, and what to do when
they need to change.

## What shipped

58 movements are addressable by the app and all 58 have a bundled looping clip. Two further
clips (`standing-hamstring-fold`, `double-pigeon`) are reached only through the guided
mobility catalog's `mediaExerciseID`, for 60 in total. Bundle cost is **2.1 MB**.

| | Count |
| --- | --- |
| Anatomical render (house style) | 55 |
| Photographic | 5 |
| Flat illustration | 0 |
| SF Symbol fallback | 0 |

An earlier version of this document reported 30 / 27 / 1 and said the render family had been
searched exhaustively across seven mirrors. The first half of that was true and the
conclusion drawn from it was wrong. The GitHub mirrors *are* a closed set — eight of them
were enumerated and diffed and they carry the same ~1,324 clips, differing by at most one
exercise — but they are not the whole render family. `fitnessprogramer.com` publishes the
same GymVisual artwork with far wider selection, including the mobility, plyometric and
foam-rolling movements every GitHub mirror lacks. That single source moved 16 movements into
the house style, `bird-dog` among them, so the flat-illustration tier is now empty and no
RepDB asset is bundled.

Two further clips were in `gifdb` the whole time and had been missed because the mapping was
built by guessing filenames rather than reading the repo's own `api/en/exercises.json` index.
One of them, `hug-knees-to-chest`, is filed under a source-side misspelling —
`glutes/hug-keens-to-chest.gif` — which no amount of guessing was going to find.

Content breaks down as 20 strength exercises (pre-existing), 10 warm-up mobility movements,
12 running form drills, and 16 cool-down stretches — the last three groups are new.

## Decisions and why

**Bundled, not streamed.** Wrathspeed is offline-first: the watch app and the audio cue
player assume no network. Streaming demos from an API would have made the one screen you
look at mid-workout the only screen that needs signal. At 2.0 MB for the whole library the
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

| Source | Style | Used for | Count |
| --- | --- | --- | --- |
| [ExerciseGymGifsDB](https://github.com/JahelCuadrado/ExerciseGymGifsDB) | anatomical render | gym strength, static stretches | 32 |
| [fitnessprogramer.com](https://fitnessprogramer.com) | anatomical render | mobility, plyos, foam rolling, gaps | 23 |
| [free-exercise-db](https://github.com/yuhonas/free-exercise-db) | photographic | what neither render source has | 5 |

The GitHub render set covers gym strength thoroughly and static stretching well but has no
foam rolling and almost no running drills. `fitnessprogramer.com` closes most of that: all
four foam-rolling movements, the dynamic mobility work, butt kicks and the tuck jump come
from there. Its clips carry a site logo in the top-left corner, painted out by the build
script — see `watermark` in `media_sources.json`.

Its own site search (`https://fitnessprogramer.com/?s=<query>`) is the fastest way to look
for a movement; results embed a `-300x300` thumbnail whose URL is the full-size path with
that suffix stripped. Several clips missed by an index-driven search were found that way.

The photographic tier is a coverage fallback, not a style choice, and it is down from 27
clips to 5.

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

A source may also declare a `watermark` rect, painted white on each composited frame before
letterboxing. `fitnessprogramer` needs one. Painted rather than cropped: the figure reaches
the very top row in several of those clips, so cropping the band would take its head off. The
paint has to happen on the *composited* frame — these GIFs store partial sub-frames with
disposal=1, so patching raw sub-frame data would miss every frame that does not redraw that
corner.

A source that yields fewer frames than one second's worth is repeated up to a second. Without
that, a still — an isometric hold with no rep — encodes to two frames and `AVPlayerLooper`
restarts an 80ms clip forever for something that never changes.

```bash
# A venv, because imageio-ffmpeg is usually missing from the system Python and the
# script needs the exact ffmpeg build it vendors. venv writes its own .gitignore.
python3 -m venv .media-venv && .media-venv/bin/pip install pillow imageio-ffmpeg
.media-venv/bin/python Tools/exercise-media/build_media.py --check   # validate mappings only
.media-venv/bin/python Tools/exercise-media/build_media.py            # build everything
.media-venv/bin/python Tools/exercise-media/build_media.py --only bw-squat
```

Downloads are cached in `.media-cache/` (gitignored), so reruns are cheap.

### The coverage check

`--check` fails the build if any movement in `strength_catalog.json` or
`movement_catalog.json` lacks a `media_sources.json` entry, or if the mapping names a
movement no catalog contains. This is the guard that stops a movement from silently drifting
out of media coverage when someone adds an exercise. Run it in CI alongside the tests.

It also checks `mobility_catalog.json`, which needs its own pass because it addresses clips
*indirectly*, through `mediaExerciseID` — its own ids (`leg_swings`) are not media ids
(`leg-swings-front`), so the set comparison above cannot see it. A `mediaExerciseID` naming
no known clip is an error, because the screen falls back to a symbol and that looks
identical to having meant no clip at all. Movements with no `mediaExerciseID` are listed but
do not fail: some are deliberately unlinked.

That gap is not hypothetical. This catalog went unchecked, and all nine movements behind
Today → Mobility rendered a bare SF Symbol while `--check` reported full coverage.

## How the app consumes it

- `MovementCatalog` / `Movement` — the new mobility, drill and stretch content.
- `MobilityPlanner` — builds warm-up, drill and cool-down routines per workout kind. Quality
  days get a longer warm-up and the only drill block; easy days get neither. Selection is
  deterministic so the same session renders identically on phone, watch, and in tests.
- `MediaLibrary` — resolves a movement id to a bundled file URL. Total; never throws at the
  call site.
- `MovementMediaView` — loops the clip via `AVPlayerLooper`, muted, falling back to the
  symbol. Muted matters: these play behind spoken cues and the user's music. Playback is
  user-controllable: a corner play/pause button, the whole clip as a second tap target, and
  Reduce Motion starting it paused rather than removing it.
- Routines surface in `WorkoutDetailView` under "Prep and recovery"; every movement is
  browsable via Settings → Movement library.
- `MobilityPlayerView` — the routines linked from Today. Reads `mediaExerciseID` off the
  mobility catalog, which is the only surface that reaches clips by an indirect id.

## Swapping the media later

1. Edit the `ref` values in `Tools/exercise-media/media_sources.json`, or add a new entry to
   `sources` with its own `rawBase` and `kind`.
2. Run `python3 Tools/exercise-media/build_media.py`.
3. Run the tests — `MediaLibraryTests` asserts every manifest entry resolves to a real file.
4. Update `Content/LICENSE.md`.

No Swift changes are needed for a re-source. That was the point of the manifest indirection.

## Known gaps

- **5 clips are still photographic**: `arm-drill`, `claw-series`, `carioca`,
  `single-leg-butt-kick`, `hurdle-hops`. They are also the only clips that are not really
  animated — each is two stills crossfaded by `frames_from_pair`, so 56 frames of dissolve
  and no movement. **This has now been searched exhaustively. Do not search it again without
  reading the section below first.**
- **Three former members of that group now use a house-style render of a NEAR-NEIGHBOUR
  movement**, a deliberate, owner-approved exception to the never-substitute rule below.
  Each is flagged `approximate` with the difference written out:
  `diagonal-bound` → zig-zag hops over cones (lateral, not diagonally forward);
  `fast-skipping` → a short-stride run (high turnover, but a run, not a skip);
  `groiners` → a spider plank (on forearms, not hands). The trade was style consistency
  against movement precision, and it was taken knowingly. `carioca` was offered a side
  shuttle and **refused** — that clip has no crossover, which is the entire drill.
- `reverse-lunge` uses a walking lunge render; the pattern is right, the step direction isn't.
  Flagged as `approximate` in the manifest.
- `plank` is a single frame held for a second. Its source has no animation, which is honest
  for an isometric hold.
- **One guided-mobility movement has no clip**: Thoracic Rotation. The near-matches
  contradict its cue — the closest rotation render highlights the lumbar spine against a cue
  reading "rotate through upper back only" — so it keeps its symbol. `--check` lists it every
  run so it stays visible. Pigeon Prep is served by a double-pigeon render, flagged
  `approximate`: same glute and external-rotator target, but the shins stack rather than the
  rear leg extending, so it loses the hip-flexor component.
- The Apple Watch target does not show clips. Its storage budget and screen size want a
  different asset (a still keyframe, or a much smaller loop) rather than these files.

## The running drills: why they are photographs, and why that will not change

Searched to exhaustion across five independent sweeps. Recorded in full because the
tempting conclusion — "nobody looked hard enough" — is wrong, and re-running it costs days.

**The artwork family is GymVisual's, and it does not contain these drills.** Not "we could
not find them"; they were never drawn. Its full catalogue is **21,768 products, 6,337
animated GIFs**, indexed at `https://gymvisual.com/sitemap.xml`.

> **The trap:** that sitemap returns **403 to a default User-Agent** and 200 with a browser
> one. Several earlier sweeps silently graded a 403 error page as "no results", which is how
> the catalogue stayed hidden. Send a browser UA.

Grepping all 21,768 slugs: `carioca` 0, `grapevine` 0, `karaoke` 0, `claw` 0, `paw` 0,
`ankling` 0, `groiner` 0, `arm-drill` 0, `a-skip` 0, `b-skip` 0, `wall-drill` 0,
`sprint-drill` 0, `form-drill` 0. `bound` returns only *lateral* bound; `hurdle` only a
depth jump over a single hurdle; `skips` only high-amplitude A-skips. The one genuine match
is `3453-single-leg-butt-kick`, which is paid and whose free preview is watermarked across
the figure at 180×180.

The structural reason is visible in the data: GymVisual is a gym-and-machine library. Its
plyometric section reaches box jumps, lateral bounds and single-hurdle depth jumps, and
stops. Track-and-field coaching drills were never in scope.

**Six of the eight are absent at the source, so no mirror can carry them.** Verified
anyway: every free mirror is the same ~1,324-clip ExerciseDB subset. The largest is
`bootstrapping-lab/exercisedb-api` at 1,500 (a clean +176 superset, unwatermarked, correct
style, `https://static.exercisedb.dev/media/<id>.gif`) — and it has **zero** of the eight.
`lyfta.app`'s multilingual sitemaps give a 6,524-ID index of the same family across ~100
languages: also zero, so a translated-name miss is ruled out.

Also checked and rejected, with reasons worth keeping:

| Source | Why not |
| --- | --- |
| LottieFiles, Rive, VectorFitExercises | Flat cartoon vector — saturated kit, faces, coloured grounds. Near-zero drill coverage *and* categorically wrong. A cartoon beside a render reads as a broken asset; a photo at least reads as a different medium. |
| MoveKit | Right style, but 404s on all eight. Paid. |
| Mixamo, CMU mocap | Free, and the look is *not* the blocker — you render the rig yourself. The motion catalogues lack all eight. |
| ExerciseAnimatic, ActorCore, Everkinetic, wger, MuscleWiki, RepDB | Wrong style, no fitness category, or static pairs. |
| Wikimedia Commons | Pure false positives — "carioca" returns Brazilian samba, "groiners" returns hernia surgery. |
| kovofitness.com | Genuinely *has* the drills with real motion (`cariocadrill_wide_m.gif`, 1280×720, 89 frames, verified). But it is outdoor phone video of a person against a brick wall — a **third** visual medium — and only carioca's filename is derivable; the rest are JS-rendered. |
| Rotoscoping coaching footage | ~400 hand-drawn frames plus rights exposure, for a result that still would not match. |

### The international pass

The sweep above was English-language and therefore not conclusive. It was re-run across
every coaching tradition that has its own illustrated literature. **Result: still zero in
the house style, and the reason is now understood rather than merely observed.**

| Tradition | Best artwork found | Why it fails |
| --- | --- | --- |
| German `Lauf-ABC` ([vlamingo.de](https://www.vlamingo.de/lauf-abc/)) | Multi-pose drawn sequences; carioca as 4 poses | Flat cartoon, German leader-line labels, watermark, static. Covers only 4/8 — hurdle hops, arm drill, claw and groiners are not part of that curriculum |
| Japanese JAAF coaching handbook | Best-structured sequences anywhere: bounding as **9 poses**, pawing as 5 | Static, drawn faces, coloured kit, copyrighted |
| Russian `СБУ` | 18-pose ink kinogram of the sprint cycle | Static line art, and it is the running cycle, not the drills |
| Russian `goodlooker.ru` | Own 3D animations, ~4,000 GIFs — incl. the **only** rendered sprint arm drill found anywhere, plus groiners | Clothed, faced characters on a mat with a burned-in watermark |
| Taiwanese `careonline.com.tw` | The only **animated** groiner found | 2-frame pose flip, cartoon, watermark |
| German Dober *Animierte Lehrbildreihen* | Genuinely animated hand-drawn line figures | Competition events only — sprint, hurdles, jumps, throws. No drills |

**Why this is an empty set rather than bad luck.** The genre splits in two and neither half
can supply this:

1. *Free and drill-specific → always annotated.* Federation manuals, PE posters, vlamingo,
   even an 1829 Flaxman motion plate. The labels **are** the product; the drawing exists to
   hang leader lines on.
2. *Clean and multi-pose → monetized or generic.* GymVisual watermarks every preview. Stock
   libraries index by exercise nouns — squat, lunge, burpee — and these eight are coaching
   jargon no stock taxonomy contains. "Carioca" returns Rio de Janeiro; "groiners" returns
   hernia surgery.

Public domain has a hard floor underneath it: Muybridge's zoopraxiscope discs are clean,
sequential, hand-traced line art with no watermark — the only asset that passes the clean
filter outright — but carioca, A-skips and hurdle-hop rows are 20th-century coaching
inventions, so no pre-1929 source can depict them.

**One asset was a false positive and is recorded so nobody re-finds it.** GymVisual
`3453-single-leg-butt-kick` was twice reported as an exact match. It is not: the frames show
stand → squat → jump → land with one leg tucked. It is a **tuck jump, misnamed at source**.

**Known gap in the search:** Baidu and Sogou image search were unreachable (anti-scraping),
so the Chinese-web image long tail is genuinely unchecked. That needs China-reachable
networking, not another search.

**What would actually work:** commissioning the eight, or authoring them in Blender — rigged
figure, translucent grey material, red emission mask on the working muscle, white world,
orthographic camera, 48 frames each into the existing pipeline as a new `kind`. See
`docs/exercise-drill-illustration-brief.md`, which specifies all eight. It is the only path
that yields them in the house style.

**Why they were left as photographs:** partial replacement is worse than none. Swapping
three of eight to stock or outdoor video turns a two-way style split into a three-way one.
A crossfaded studio photograph is at least honest about being a photograph, and it teaches
the movement.
