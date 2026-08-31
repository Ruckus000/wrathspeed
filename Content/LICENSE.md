# Bundled content licenses

## Personal build — not for distribution

Wrathspeed bundles third-party exercise demonstration clips. They were sourced for a private
build used by the author and friends, **not** for App Store release or any other public
distribution.

The rights position for the bundled clips has not been cleared for redistribution. Before
this app is shipped, sold, or otherwise handed to people outside that circle, the clips in
`WrathspeedCore/Sources/WrathspeedCore/Media/` must be either re-licensed or replaced. See
`docs/exercise-media-plan.md` for the swap procedure — the media layer was built so that
replacing the files and re-running the build script is the whole job.

## What is bundled

| Asset | Source | Style | Count |
| --- | --- | --- | --- |
| `Media/*.mp4` | [JahelCuadrado/ExerciseGymGifsDB](https://github.com/JahelCuadrado/ExerciseGymGifsDB) | anatomical render | 32 |
| `Media/*.mp4` | [fitnessprogramer.com](https://fitnessprogramer.com) | anatomical render | 23 |
| `Media/*.mp4` | [yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db) | photographic | 5 |

`WrathspeedCore/Sources/WrathspeedCore/Resources/media_manifest.json` records the source
repository and the exact source asset for every clip. `Tools/exercise-media/media_sources.json`
records the mapping that produced them, including the cases where the artwork shows a close
variant rather than the exact movement.

`free-exercise-db` publishes its exercise images under the Unlicense (public domain).

The two anatomical-render tiers are the same underlying artwork: both republish
ExerciseDB/GymVisual renders, whose terms restrict redistribution. That is the specific
reason the table above is fenced behind the personal-use note. Eight GitHub mirrors of that
render family were enumerated and diffed while re-sourcing — they carry the same ~1,324
clips and every one traces back to GymVisual, so **switching mirrors does not improve the
distribution position**. `fitnessprogramer.com` is a wider selection of the same family, not
a cleaner licence. Its clips carry a site logo, which the build script paints out; that is a
presentation fix and is not a rights clearance.

No RepDB asset is bundled any more — the bird dog it used to supply now comes from the
render family, so the attribution its free tier required has been removed from
Settings → Content → Content Licenses rather than left standing as a false claim.

## Original to this app

- Movement names and cues in `strength_catalog.json`, `movement_catalog.json` and
  `mobility_catalog.json`.
- Warm-up, drill and cool-down routine construction in `MobilityPlanner.swift`.
- Training paces use the published Jack Daniels VDOT formulas and the Riegel race-time formula.
- Exercise stills fall back to Apple SF Symbols wherever no clip is bundled. All 58 catalog
  movements have a clip, as do two extra clips reached only by the guided mobility routines.
  One movement in those routines (Thoracic Rotation) deliberately has none, because nothing
  in the library depicts it.
