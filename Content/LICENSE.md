# Bundled content licenses

## Personal build — not for distribution

Wrathspeed now bundles third-party exercise demonstration clips. They were sourced for a
private build used by the author and friends, **not** for App Store release or any other
public distribution.

The rights position for the bundled clips has not been cleared for redistribution. Before
this app is shipped, sold, or otherwise handed to people outside that circle, the clips in
`WrathspeedCore/Sources/WrathspeedCore/Media/` must be either re-licensed or replaced. See
`docs/exercise-media-plan.md` for the swap procedure — the media layer was built so that
replacing the files and re-running the build script is the whole job.

## What is bundled

| Asset | Source | Count |
| --- | --- | --- |
| `Media/*.mp4` (anatomical render) | [JahelCuadrado/ExerciseGymGifsDB](https://github.com/JahelCuadrado/ExerciseGymGifsDB) | 30 |
| `Media/*.mp4` (photographic) | [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) | 27 |
| `Media/bird-dog.mp4` (illustration) | [RepDB/exercise-dataset](https://github.com/RepDB/exercise-dataset) | 1 |

`WrathspeedCore/Sources/WrathspeedCore/Resources/media_manifest.json` records the source
repository and the exact source asset for every clip. `Tools/exercise-media/media_sources.json`
records the mapping that produced them, including the cases where the artwork shows a close
variant rather than the exact movement.

`free-exercise-db` publishes its exercise images under the Unlicense (public domain).
`ExerciseGymGifsDB` republishes ExerciseDB-derived renders; ExerciseDB's own terms restrict
redistribution of that artwork, which is the specific reason the table above is fenced behind
the personal-use note.

RepDB's free tier is the one row that is already cleared for release: it permits use inside
applications, personal or commercial, provided a visible credit — "Exercise data by RepDB
(repdb.co)" — appears in the app. That credit is in Settings → Content → Content Licenses.
Its terms allow resizing and recolouring for in-app use, which is what the build script's
white-ground normalisation does, but forbid republishing the images as a dataset. Only the
bird dog is used; no other RepDB asset is bundled.

## Original to this app

- Movement names and cues in `strength_catalog.json` and `movement_catalog.json`.
- Warm-up, drill and cool-down routine construction in `MobilityPlanner.swift`.
- Training paces use the published Jack Daniels VDOT formulas and the Riegel race-time formula.
- Exercise stills fall back to Apple SF Symbols wherever no clip is bundled. Every one of
  the 58 movements now has a clip, so the fallback is a safety net rather than a routine path.
