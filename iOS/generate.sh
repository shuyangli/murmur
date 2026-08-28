#!/usr/bin/env bash
# Regenerates iOS/Murmur.xcodeproj from project.yml.
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "xcodegen not found. Install it with: brew install xcodegen" >&2
    exit 1
fi

xcodegen generate --spec project.yml
echo "==> Generated iOS/Murmur.xcodeproj"
