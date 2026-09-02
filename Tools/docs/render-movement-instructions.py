#!/usr/bin/env python3
"""Render docs/movement-instructions.md from the two catalogues.

The document has always claimed it is generated and "cannot drift from what ships". Until this
script existed that claim was untrue: nothing regenerated it and no test compared it. Run this
after editing either catalogue.

    python3 Tools/docs/render-movement-instructions.py [--check]

`--check` regenerates in memory and exits non-zero if the committed file differs, so CI or a
hook can enforce the claim rather than trusting it.
"""
from __future__ import annotations

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
STRENGTH = ROOT / "Wrathspeed" / "strength_catalog.json"
MOVEMENTS = ROOT / "WrathspeedCore" / "Sources" / "WrathspeedCore" / "Resources" / "movement_catalog.json"
OUT = ROOT / "docs" / "movement-instructions.md"

PREAMBLE = """# Beginner instructions — all {total} movements
Every movement the app can demonstrate, with the four fields the instruction card renders:
numbered steps, what it should feel like, the mistake to avoid, and the regression to fall
back on.

This file is **generated from the catalogues** — `Wrathspeed/strength_catalog.json` and
`WrathspeedCore/Sources/WrathspeedCore/Resources/movement_catalog.json` — so it cannot drift
from what ships. Edit the JSON, not this.

`TOO HARD? DO THIS` is deliberately absent on some movements. There is no easier ankle circle,
and `WSInstructionCard` renders only the headings that have content, so a movement with three
fields looks finished rather than broken.
"""

# Section title -> its standing intro line. Order here is the order in the document.
INTROS = {
    "Strength — repetitions": "Counted in reps. `TOO HARD? DO THIS` is a real regression for all of these.",
    "Strength — holds": "Timed, not repped. There is no rep to count, so `SHOULD FEEL` carries most of the teaching.",
    "Warm-up mobility": "Range and control rather than effort. Several have no meaningful regression, so `TOO HARD? DO THIS` is absent.",
    "Running drills": "The mechanic and its purpose. `COMMON MISTAKE` here names the drill each one gets confused with — the same wrong matches recorded in `exercise-drill-illustration-brief.md` while sourcing demo clips.",
    "Static stretches": "`SHOULD FEEL` is the load-bearing field: where you feel it is what tells you the set-up is right.",
    "Foam rolling": "`COMMON MISTAKE` carries the safety note here, because the risk is joint pressure rather than bad form.",
}


def entry(item: dict) -> str:
    # A hold names its duration in the heading; there is no rep count to carry it.
    hold = item.get("holdSeconds")
    heading = f"### `{item['id']}` — {item['name']}"
    if hold is not None:
        heading += f" · {hold}s hold"
    out = [heading, f"*Cue:* {item['cue']}", "", "**How to do it**"]
    out += [f"{n}. {step}" for n, step in enumerate(item["howToDoIt"], 1)]
    out += ["", f"**Should feel** — {item['shouldFeel']}", "", f"**Common mistake** — {item['commonMistake']}"]
    if item.get("easier"):
        out += ["", f"**Too hard? Do this** — {item['easier']}"]
    return "\n".join(out)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true", help="fail if the committed file is stale")
    args = parser.parse_args()

    strength = json.loads(STRENGTH.read_text())["exercises"]
    movements = json.loads(MOVEMENTS.read_text())["movements"]

    def in_phase(phase):
        return [m for m in movements if m["phase"] == phase]

    cooldown = in_phase("cooldown")
    # The rolls are the `-smr` ids; everything else in the cooldown is a static stretch.
    sections = [
        ("Strength — repetitions", [e for e in strength if e.get("holdSeconds") is None]),
        ("Strength — holds", [e for e in strength if e.get("holdSeconds") is not None]),
        ("Warm-up mobility", in_phase("warmup")),
        ("Running drills", in_phase("drills")),
        ("Static stretches", [m for m in cooldown if not m["id"].endswith("-smr")]),
        ("Foam rolling", [m for m in cooldown if m["id"].endswith("-smr")]),
    ]

    total = len(strength) + len(movements)
    parts = [PREAMBLE.format(total=total)]
    for title, items in sections:
        parts.append(f"## {title} ({len(items)})\n{INTROS[title]}\n")
        parts.append("\n\n".join(entry(i) for i in items) + "\n")
    rendered = "\n".join(parts)

    if args.check:
        current = OUT.read_text() if OUT.exists() else ""
        if current != rendered:
            print(f"{OUT.relative_to(ROOT)} is stale — run Tools/docs/render-movement-instructions.py", file=sys.stderr)
            return 1
        print(f"{OUT.relative_to(ROOT)} is up to date ({total} movements)")
        return 0

    OUT.write_text(rendered)
    print(f"wrote {OUT.relative_to(ROOT)} — {total} movements across {len(sections)} sections")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
