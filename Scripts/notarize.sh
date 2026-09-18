#!/usr/bin/env bash
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo "Usage: Scripts/notarize.sh <zip-or-dmg> <result.json>" >&2; exit 2
fi
: "${APPLE_API_KEY_ID:?Missing APPLE_API_KEY_ID}"
: "${APPLE_API_ISSUER_ID:?Missing APPLE_API_ISSUER_ID}"
: "${APPLE_API_KEY_PATH:?Missing APPLE_API_KEY_PATH (private .p8 file)}"
test -s "$APPLE_API_KEY_PATH"
AUTH=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
if ! xcrun notarytool submit "$1" "${AUTH[@]}" --wait --timeout 20m --output-format json > "$2"; then
  echo "ERROR: Notarization submission failed or timed out. No release will be emitted. See $2" >&2
  exit 1
fi
status=$(plutil -extract status raw -o - "$2")
if [[ "$status" != Accepted ]]; then
  echo "ERROR: Notarization status is '$status', not Accepted. See $2" >&2
  exit 1
fi
submission_id=$(plutil -extract id raw -o - "$2")
test -n "$submission_id"
# Preserve the accepted submission log so warnings can be reviewed before publication.
xcrun notarytool log "$submission_id" "${AUTH[@]}" "${2%.json}.log.json"
