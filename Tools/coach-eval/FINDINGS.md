# Does the AI coach provide value? — audit findings

The coach runs Apple's on-device model. Its architecture is sound: the model only picks a typed
intent with bounded parameters, the app compiles the plan change, and nothing applies without an
explicit approval that re-validates against live state. What had never been measured was the
model step itself, because every XCTest run sees the model as unavailable by design. This harness
measures it. Numbers below are from single passes during the work; the committed `scorecard.md`
is the N=5 baseline against the final contract.

## What reading found first (all merged, PRs #31–#33)

- "I'M SORE" was blocked most of the week: the cut searched the calendar week, and the week's
  only quality session sits on its earliest run day. Rolling seven days now; a 196-combination
  weekday matrix test states where it works.
- The UI test for it could not tell — it asserted a button that renders on blocked cards too.
- Late in a plan the model saw zero upcoming workouts; the coach ignored an active NOT FEELING
  100% adjustment; no race-week awareness; the cut misdescribed itself; no health statement on
  the screen; plus five correctness items (empty-changes guard, timed steps, numeric sort,
  `today=` in the prompt, long run by date).

## What the harness found (this branch)

| pass | result | cause |
|---|---|---|
| first pass | 33/51 | contract, not model |
| + stray fields ignored, refusals mapped, canned asks | 32/51 | the model's own misreads now visible |
| + intent corroboration | 35/51, 2 forbidden | parameters still invented |
| + parameter corroboration | **44/51, 0 forbidden** | the seven left are model misreads turned into asks |

**Four contract defects**, each invisible to every test that had ever run:

1. **The mapper rejected any response carrying a field the intent did not need.** Guided
   generation fills unrelated optionals routinely (`targetVDOT: 30`, `targetWeekday: "Tuesday"`,
   `workoutReference: "w1"` on a travel request with perfect dates). Seven of the first eight
   correct intents became clarifications. On a device with Apple Intelligence, natural-language
   edits almost never reached a proposal; only the keyword gate's soreness phrasings survived.
2. **The model refuses injury language outright** — "May contain sensitive content" on shin
   pain, chest pain, a stress fracture, a swollen knee, dizziness. The app showed "The coach
   couldn't finish that response. Try again." A refusal is now a fixed reply: stop if anything
   is sharp, see a professional, your plan is unchanged.
3. **A demoted or incomplete edit still showed the model's promise** ("I'll reshape your week
   for September 20 to 12"), with no card. Canned asks replace the promise.
4. **The gate corroborated nothing but soreness.** The model returned `moveLongRun` for "add a
   sixth run day", `retargetVDOT` for "make every run a tempo", and an *applicable* travel
   reshape for "I need to move some things around". The apply gate would have held; the runner
   would have been shown a proposal they never asked for.

**Measured limits of the on-device model** (these are what the corroboration gate now contains):

- **Date arithmetic fails even with `today=` in the prompt.** "Tomorrow through Friday" on
  Wednesday the 2nd came back as the 4th–7th; "this weekend" as the 4th–5th; "next Monday to
  Wednesday" as the 4th–6th; a reversed range produced invented dates. The coach now asks for
  exact dates instead of guessing, and stated day numbers must bracket what the model returns.
- **Day-named workouts are unreliable.** In all five day-named indoor requests the model chose
  the wrong workout. The chosen run must now fall on the day named, within the coming week.
- **Numbers drift**: "VDOT 46" came back as 47. The number must appear in the message.
- **Intent confusion under compound or indirect phrasing**: "I'm sore and away Sept 14 to 18"
  → cut; "long run on Sundays instead" → travel; "September 14 to 18." after "I'm travelling."
  → cut. Each is now an ask, not an edit.
- **A slash date ("9/14-9/18") was refused twice** as sensitive content, then answered
  conversationally. Finding only.
- One runaway generation in ~250 calls (`exceededContextWindowSize`); the prompt itself is
  ~900 tokens. "Try again" is the right reply there.
- Replies invent facts when the context lacks them: "VDOT stands for Velocity Distance Over
  Time." The prompt carries `vdot=` but no pace zones, so any pace quoted is invented. The
  `UNGROUNDED_NUMBER` flag counts these.

## The value question

Judged against the UI path each intent duplicates:

- **Travel reshaping is the strongest case** — no UI does multi-workout moves — *when the
  runner states exact dates.* With the gate, it is safe; without exact dates it asks.
- **Soreness cut works** and is the same as the button; the value is phrasing freedom ("legs
  are wrecked, dial this week back" now recovers).
- **Move long run / move indoors** are weaker than the pickers would be: the model gets the
  day wrong often enough that the gate demotes most of them to an ask. A weekday picker and a
  workout picker (plan item A14) would serve every device, with or without Apple Intelligence.
- **Retarget VDOT** is the weakest: it needs a number a beginner does not have, and the FASTER
  PACES button computes one with no evidence (plan item A15).
- **Answer-only questions** are the most-used path and the least controlled: the model's text
  passes straight through. It is safe (injury refusals are now handled) but not grounded.

## Decisions that are yours

- A14: hide the long-run and indoors quick actions when the model is unavailable, or add pickers.
- A15: gate FASTER PACES on evidence, or remove the one-tap.
- Whether the cut's 80% quality reduction is the right coaching (unchanged; the copy now says it).
- Phase C (a DEBUG-only on-device run of the same golden set) was not built; the Mac harness
  is the primary signal and the model is the same framework.
