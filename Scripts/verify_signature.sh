#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 1 || ! -e "$1" ]]; then
  echo "Usage: Scripts/verify_signature.sh <app-or-dmg>" >&2; exit 2
fi
# Apple's Developer ID Application leaf extension excludes ad-hoc and development certificates.
codesign --verify --deep --strict --verbose=2 \
  -R='anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$1"
details=$(codesign --display --verbose=4 "$1" 2>&1)
if ! [[ "$details" == *"Timestamp="* ]]; then
  echo "ERROR: Missing secure signing timestamp." >&2; exit 1
fi
if [[ "$1" == *.app && "$details" != *"(runtime)"* ]]; then
  echo "ERROR: App signature does not enable hardened runtime." >&2; exit 1
fi
