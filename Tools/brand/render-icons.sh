#!/bin/bash
# Compile the icon renderer against the shared mark geometry and run it from the repo root.
# See render-icons.swift for what it produces and why.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
binary="$(mktemp -t ws-render-icons)"
trap 'rm -f "$binary"' EXIT

swiftc -O -swift-version 6 \
    "$root/Design/WSMarkGeometry.swift" \
    "$root/Tools/brand/render-icons.swift" \
    -o "$binary"

cd "$root"
"$binary" "$@"
