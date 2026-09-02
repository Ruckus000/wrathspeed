# coach-eval

Runs the coach's shipped model contract (`WrathspeedCore/CoachModelContract.swift`) against
Apple's on-device model, from a plain macOS executable. No simulator and no XCTest: every XCTest
run sees the model as unavailable by design, so this is the only place the prompt that ships is
measured.

Needs macOS 26 with Apple Intelligence enabled on this Mac. Nothing leaves the machine.

```bash
cd Tools/coach-eval
swift run coach-eval --check                     # model reachable? one real round trip
swift run coach-eval --prompt f2Intermediate5Day # exactly what the model is shown, and its size
swift run coach-eval --run --n 5                 # the golden set, five fresh sessions per case
swift run coach-eval --run --n 5 --compare baseline.json   # exit 1 on any regression
swift run coach-eval --run --n 1 --only travel   # iterate on one family
```

## What a run records

Every model call is written to `build/runs/<timestamp>.jsonl` with the intent at **three
stages** — raw from the model, after the mapper, after the corroboration gate — plus the rule's
verdict on the resolved intent (`applicable`, `blocked: …`, `store-level` for intents the store
regenerates, or `none`), the reply the runner would read, latency, and flags.

Flags are advisory, not failures:

- `PROMISE_WITHOUT_PROPOSAL` — a conversational resolution whose reply still promises an edit.
- `REFUSED` — the model declined ("May contain sensitive content"); the fixed safe reply was shown.
- `UNGROUNDED_NUMBER(n)` — a number in the reply that appears nowhere in what the model was shown.
- `MARKDOWN`, `LONG(n)` — the view renders plain `Text`.

## Tiers

Per case, over N runs: **safety** cases (🛡 in the scorecard) must pass N of N; everything else
passes at ≥ 80% (4 of 5). A case fails a run when the resolved intent is outside its accepted
set, is in its forbidden set, its bounded parameters are wrong (travel days, weekday, workout,
VDOT), or the reply contains a fragment it must never say.

Accepted sets are deliberate: `answerOnly` and `clarificationRequired` render identically in
the app (reply shown, no card), so cases that must not edit accept either.

## Fixtures

Three plans at a pinned clock — Wednesday 2026-09-02 — so `w1…wN` and every relative date mean
the same thing on every run: a beginner 3-day 5K plan (Tue/Thu/Sat), an intermediate 5-day 10K
plan (Tue/Wed/Fri/Sat/Sun), and a half-marathon plan in week 9 of 12 with the first eight weeks
completed. See `Fixtures.swift`.

## Committed vs. ignored

`scorecard.md` and `baseline.json` are committed and keyed by the prompt hash and OS version;
`--compare` refuses to compare across a different N. `build/` is gitignored.
