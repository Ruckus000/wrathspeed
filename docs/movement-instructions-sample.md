# Beginner instructions — sample of 5

Draft copy for the instruction card the redesign adds to three surfaces: the strength
player, the mobility player, and Movement Detail. Five of ~58 movements, chosen to span the
patterns: a bilateral squat, an isometric hold, a hinge, an upper-body push, and a
unilateral drill.

Judge the **voice and the depth** here. If both land, the other 53 follow this shape.

## Proposed data shape

Four new fields per movement, added to `strength_catalog.json` (20 entries) and
`movement_catalog.json` (38 entries). All four optional — the design already gates the whole
block behind `sxHasHow`, so a movement with none of them simply renders the cue as it does
today.

```json
{
  "id": "bw-squat",
  "cue": "Sit back, knees track over toes, stand tall.",
  "howToDoIt": ["…", "…", "…"],
  "shouldFeel": "…",
  "commonMistake": "…",
  "easier": "…"
}
```

`howToDoIt` is an array because the design numbers each step in its own red circle
(`sc-for` over `sxHowSteps`, placeholder count 3). Three steps is the drawn case; the layout
takes more.

---

## bw-squat — Bodyweight squat

**How to do it**
1. Stand with your feet about shoulder-width apart, toes turned out slightly.
2. Push your hips back and bend your knees, letting them travel out over your toes. Chest stays up.
3. Go as low as you can with your heels flat and your lower back neutral, then drive through the floor to stand tall.

**Should feel** — Work through the thighs and glutes. Your heels stay down the whole time.

**Common mistake** — Knees collapsing inward, or heels lifting near the bottom. Either one means you have gone past the depth you currently own.

**Too hard? Do this** — Sit down to a chair or bench and stand back up. Same movement, less depth.

## plank — Front plank *(hold)*

**How to do it**
1. Set your forearms on the floor under your shoulders, elbows bent about 90 degrees.
2. Step your feet back until your body makes one straight line from head to heels.
3. Squeeze your glutes, push the floor away with your forearms, and breathe normally for the whole hold.

**Should feel** — A deep brace across the entire midsection. Shoulders and glutes should be working too.

**Common mistake** — Hips drifting up into a pike, or sagging toward the floor. Both take the work off the abdominals.

**Too hard? Do this** — Drop to your knees, or set your forearms on a bench so your body sits at an angle.

## rdl — Romanian deadlift

**How to do it**
1. Stand tall holding the weight in front of your thighs, knees softly bent.
2. Push your hips straight back and let the weight slide down your legs, back flat.
3. Stop when you feel a strong stretch in the hamstrings, then drive your hips forward to stand tall.

**Should feel** — A clear stretch down the back of the thighs on the way down, glutes at the top.

**Common mistake** — Rounding the lower back, or turning it into a squat. The knee angle barely changes through the whole rep.

**Too hard? Do this** — Go lighter, or with no weight at all, and shorten the range — stop halfway down.

## push-up — Push-up

**How to do it**
1. Hands under your shoulders, body plank-stiff from head to heels.
2. Lower until your chest is about a fist's height off the floor, elbows tracking back at roughly 45 degrees.
3. Push the floor away and return to the top without letting your hips sag.

**Should feel** — Chest, shoulders and triceps working, midsection braced throughout.

**Common mistake** — Hips sagging toward the floor, or elbows flaring straight out to the sides.

**Too hard? Do this** — Put your hands on a bench, a step, or a wall. The more upright you are, the easier it gets.

## single-leg-bridge — Single-leg glute bridge

**How to do it**
1. Lie on your back with one foot planted close to your glutes, the other leg lifted.
2. Drive through the planted heel to lift your hips, keeping both hip bones level.
3. Pause at the top, then lower with control. Finish all reps on one side before switching.

**Should feel** — The glute of the planted leg doing the work.

**Common mistake** — Letting the lifted side drop so the hips twist, or pushing through the toes instead of the heel.

**Too hard? Do this** — Do a two-leg glute bridge, or rest the lifted foot lightly on the floor for support.
