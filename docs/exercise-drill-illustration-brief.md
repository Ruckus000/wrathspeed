# Illustration brief: eight running-form drills

A commissioning spec for the eight clips that could not be sourced. Written to be handed to
an illustrator or 3D animator as-is. Background on why this is a commission rather than a
purchase is in `exercise-media-plan.md` — the short version is that these eight were
searched across every coaching tradition with an illustrated literature and do not exist in
this style anywhere, free or paid.

## What is being made

Eight short looping animations of running-form drills, matching a library of 55 clips the
app already ships.

Five of the eight (`carioca`, `single-leg-butt-kick`, `hurdle-hops`, `arm-drill`,
`claw-series`) are still photographs, and are not really animated at all — two stills
crossfaded together. The other three (`diagonal-bound`, `fast-skipping`, `groiners`)
currently show a house-style render of a **near-neighbour** movement, flagged `approximate`.
Those three are correct in style but wrong in detail, so commissioning them still improves
the app — just less urgently than the five photographs.

## House style — non-negotiable, and easy to check

Measured from the shipping clips, not described from memory. Open any of
`WrathspeedCore/Sources/WrathspeedCore/Media/*.mp4` to see it:

- **A faceless, hairless 3D anatomical model.** No face, no hair, no clothing, no shoes. The
  musculature is visible, rendered in translucent grey/white.
- **Working muscles washed red-orange**, and only the working muscles. Whole-body red is
  wrong — the highlight is what teaches the movement.
- **Pure white background.** No ground plane, no shadow, no mat, no props except equipment
  the drill genuinely requires.
- **No watermark, no logo, no text, no leader lines, no annotation of any kind.** The app
  supplies its own name and coaching cue beneath every clip. This rules out most existing
  reference material and is the single most common reason a candidate was rejected.
- **One consistent model** across all eight. The existing library is predominantly male; a
  small number of clips use a female model, so either is acceptable, but do not mix within
  the set.
- Side profile wherever the movement reads best that way. Three-quarter only if a side view
  would hide the mechanic.

## Technical delivery

- **Format**: animated GIF or a numbered PNG sequence. Either is fine — the build script
  transcodes both.
- **Canvas**: square, 480×480 or larger. Sources are letterboxed down to 480px, so anything
  larger is safely downscaled; anything smaller is not upscaled and will look soft.
- **Frames**: 12–24 per cycle. The pipeline resamples to a constant 24 fps while preserving
  real per-frame timing, so uneven timing is fine and often better — holding a beat at the
  top and bottom of a rep reads well.
- **Loop**: must be seamless. The last frame has to flow into the first. These play on a
  continuous loop with no gap, so a jump at the boundary is very visible.
- **One full cycle** of the movement, not a highlight. For alternating drills, that means
  both sides.

## The eight

The cue text is what the app displays under each clip. **The animation must match the cue** —
a viewer reads both at once, and a mismatch actively teaches the wrong thing.

◆ = currently has an approximate house-style stand-in; the other five are photographs.

| id | Name | Cue shown in the app | What the animation must show |
| --- | --- | --- | --- |
| `carioca` | Carioca | *Travel sideways, trail leg crossing front then behind. Let the hips rotate.* | Lateral travel. Trail leg crosses **in front**, then **behind** — both crossings, in one cycle. Visible hip rotation. Arms out to the sides for balance. |
| `fast-skipping` ◆ | Fast skipping | *Skip for height off a stiff ankle. Opposite arm drives with the knee.* | A skip — double contact on one foot before switching. Off a **stiff ankle**, so bounce comes from the ankle, not a deep knee bend. Opposite arm drives with the lead knee. |
| `single-leg-butt-kick` | Single-leg butt kick | *One leg cycles, the other stays quiet. Stay tall through the hips.* | **One leg only** flicks heel to glute repeatedly; the other stays in a normal running rhythm. This is the distinguishing feature — an alternating both-legs version is a different drill and is the single most common wrong match. Tall hips, no sitting back. |
| `diagonal-bound` ◆ | Alternate leg diagonal bound | *Long diagonal bounds, alternating legs. Cover ground, land quietly.* | Alternating single-leg take-off and landing, travelling **diagonally**, not straight ahead and not laterally. Long flight phase, opposite arm driving. |
| `hurdle-hops` | Hurdle hops | *Hop over low obstacles off both feet. Stiff ankles, minimal ground time.* | **Both feet together**, hopping over a **row** of low hurdles — at least three, consecutively. Not a single hurdle, and not a depth jump off a box. Stiff ankles, minimal ground contact. |
| `arm-drill` | Kneeling arm drill | *Tall kneeling. Drive elbows back, hands cheek to pocket, relaxed hands.* | Tall kneeling or half-kneeling, **legs still**. Arms drive through full sprint range — hand travels from **cheek to pocket**. Amplitude matters: a small pumping motion in front of the torso is wrong. Elbows stay bent, hands relaxed. |
| `claw-series` | Moving claw series | *Reach the foot forward, then paw it back under the hip. Quick ground contact.* | The foot reaches forward, then actively **paws backward** to land under the hip rather than in front of it. The backward sweep before contact is the whole point of the drill. |
| `groiners` ◆ | Groiners | *From a push-up position, step a foot outside the hand. Alternate.* | From a push-up position **on the hands** (not forearms), one foot steps up and plants **outside** the hand, then back. Alternating. A knee driving under the chest is a mountain climber, not this. |

## Reference material

None of these is usable as an asset — all fail on watermark, annotation, or style — but they
depict the movements correctly and are useful for pose reference. Rejection reasons are in
`exercise-media-plan.md`.

- **Carioca, fast skipping, bounding**, drawn as ordered pose sequences:
  [vlamingo.de Lauf-ABC](https://www.vlamingo.de/lauf-abc/) — see `Seitwaerts-ueberkreuzen`,
  `Fussgelenksarbeit`, `Sprunglauf`.
- **Bounding (9 poses) and the pawing action (5 poses)**, the best-staged sequences found:
  [JAAF coaching handbook](https://www.jaaf.or.jp/files/upload/202003/jhs-003-007.pdf) p.42
  and [sprint chapter](https://www.jaaf.or.jp/files/upload/202003/jhs-003-001.pdf) p.17.
- **Kneeling arm drill** — the only rendered depiction found anywhere:
  `goodlooker.ru/wp-content/uploads/2021/03/Vypad_na_meste_beg_rukami.gif`. Note its arm
  amplitude is too small; the brief above is what to draw instead.
- **Groiners** — `goodlooker.ru/wp-content/uploads/2020/12/Skalolaz_s_shagom.gif` shows the
  foot planting outside the hand correctly.

## Accepting the work

Check each delivered clip on three axes independently. A clip passing two and failing one is
a rejection — this is the exact standard applied to every sourced candidate:

1. **Movement** — the named drill, not a neighbour. The traps, all of which were hit by real
   candidates during sourcing: an A-skip is not fast skipping; an alternating butt kick is
   not a single-leg one; one hop over one hurdle is not hurdle hops; a mountain climber is
   not a groiner; a lateral bound is not a diagonal one.
2. **Style** — faceless grey model, white ground, isolated red highlight, no watermark, no
   text. One consistent model across the set.
3. **Motion** — the figure genuinely changes position across frames. Beware the colour-pulse
   fake, which is common in commercial libraries: a body that is pixel-identical frame to
   frame while only the red saturation ramps. Test it objectively — threshold each frame to
   a binary silhouette and frame-difference it. A pulse scores ~0.2; real movement scores >2.

## Integrating them

No Swift changes are needed. Add a source tier to `Tools/exercise-media/media_sources.json`
pointing at wherever the files live, repoint the eight ids from `photo` to it, and run:

```bash
.media-venv/bin/python Tools/exercise-media/build_media.py --only arm-drill claw-series \
  carioca fast-skipping single-leg-butt-kick diagonal-bound hurdle-hops groiners
```

Once no mapping uses `photo`, `frames_from_pair()`, `HOLD_FRAMES` and `FADE_FRAMES` become
dead and should go. Leave `ClipStyle.photo` in `MovementMedia.swift` — removing an enum case
breaks decoding of any older manifest.
