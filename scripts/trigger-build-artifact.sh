#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# trigger-build-artifact.sh — encode a JSON config as base64 and dispatch
# the Build Artifact workflow via `gh workflow run`.
#
# Validates the JSON locally (jq syntax + ajv schema) before dispatching,
# mirroring the workflow's own checks.
#
# Usage:
#   scripts/trigger-build-artifact.sh [options] <path-to-json>
#
# Options:
#   --ref <branch>       Git ref to run the workflow on (default: dev)
#   --workflow <name>    Workflow name or file (default: "Build Artifact")
#   --schema <path>      JSON Schema path (default: .github/schemas/build-config.schema.json)
#   --dry-run            Validate + print base64 + decoded JSON, do not dispatch
#   --watch              After dispatch, watch the run until completion (gh run watch)
#   -h, --help           Show this help
#
# Examples:
#   scripts/trigger-build-artifact.sh config.json
#   scripts/trigger-build-artifact.sh --ref dev --dry-run /tmp/demo-config.json
#   scripts/trigger-build-artifact.sh --watch infra/configs/poc.json
#
# Requires: jq, base64, gh (and for schema validation: npx with ajv-cli)
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

REF="dev"
WORKFLOW="Build Artifact"
SCHEMA=".github/schemas/build-config.schema.json"
DRY_RUN=false
WATCH=false
CONFIG_PATH=""

usage() {
  sed -n '2,/^# ──/p' "$0" | sed 's/^# \?//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    --ref) REF="$2"; shift 2 ;;
    --workflow) WORKFLOW="$2"; shift 2 ;;
    --schema) SCHEMA="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --watch) WATCH=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; CONFIG_PATH="${1:-}"; break ;;
    -*) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    *) CONFIG_PATH="$1"; shift ;;
  esac
done

if [ -z "$CONFIG_PATH" ]; then
  echo "error: missing <path-to-json>" >&2
  usage >&2
  exit 2
fi

if [ ! -f "$CONFIG_PATH" ]; then
  echo "error: file not found: $CONFIG_PATH" >&2
  exit 1
fi

for dep in jq base64 gh; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "error: required tool not found: $dep" >&2
    exit 1
  fi
done

echo "==> Validating JSON syntax: $CONFIG_PATH"
if ! jq empty "$CONFIG_PATH" 2>&1; then
  echo "error: $CONFIG_PATH is not valid JSON" >&2
  exit 1
fi
echo "    JSON syntax OK."

if [ -f "$SCHEMA" ]; then
  echo "==> Validating against schema: $SCHEMA"
  if command -v npx >/dev/null 2>&1; then
    if ! npx --yes ajv-cli@5 validate -s "$SCHEMA" -d "$CONFIG_PATH" --strict=false --spec=draft7 2>&1; then
      echo "error: schema validation failed" >&2
      exit 1
    fi
    echo "    Schema OK."
  else
    echo "    warn: npx not found, skipping schema validation (install Node.js to enable)" >&2
  fi
else
  echo "    warn: schema not found at $SCHEMA, skipping schema validation" >&2
fi

# Base64 without newlines (GNU -w0 or BSD fallback)
if base64 -w0 </dev/null >/dev/null 2>&1; then
  B64="$(base64 -w0 < "$CONFIG_PATH")"
else
  B64="$(base64 < "$CONFIG_PATH" | tr -d '\n')"
fi

echo "==> Decoded config (pretty-printed):"
jq . "$CONFIG_PATH"
echo "==> Base64 length: ${#B64}"

if [ "$DRY_RUN" = true ]; then
  echo "==> --dry-run: not dispatching workflow."
  echo "    To dispatch manually:"
  echo "      gh workflow run \"$WORKFLOW\" --ref $REF -f config_b64=\"$B64\""
  exit 0
fi

echo "==> Dispatching workflow \"$WORKFLOW\" on ref \"$REF\" ..."
gh workflow run "$WORKFLOW" --ref "$REF" -f config_b64="$B64"
echo "    Dispatched."

if [ "$WATCH" = true ]; then
  echo "==> Watching latest run for \"$WORKFLOW\" ..."
  sleep 3
  RUN_ID="$(gh run list --workflow="$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId' 2>&1 || true)"
  if [ -n "$RUN_ID" ]; then
    echo "    Run ID: $RUN_ID"
    gh run watch "$RUN_ID" 2>&1 || true
    gh run view "$RUN_ID" --json conclusion,status --jq '{status, conclusion}' 2>&1 || true
  else
    echo "    warn: could not determine run ID to watch" >&2
  fi
else
  echo "    Tip: watch with: gh run watch \$(gh run list --workflow=\"$WORKFLOW\" --limit 1 --json databaseId --jq '.[0].databaseId')"
  echo "    Logs: gh run view --log \$(gh run list --workflow=\"$WORKFLOW\" --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
