#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────
# simulate-changes.sh — local logic check for the ci-cd.yml `changes` job.
#
# Emulates (without GitHub) the exact decision chain from the real pipeline:
#   1. dorny/paths-filter          → git diff --name-only BASE..HEAD + component globs
#   2. the `changes` job meta step  → full_rebuild folding (migrations stays RAW)
#   3. create-manifest derivation   → run_migration / migrations_changed
#   4. deploy-side effective flag   → "Migration task: <bool> (policy=…, migrations_changed=…)"
#
# Usage:
#   scripts/simulate-changes.sh [--base REF] [--head REF] [--files 'a b c']
#       [--event push|workflow_dispatch] [--branch dev|master]
#       [--run-migration-input true|false] [--full-rebuild-input true|false]
#       [--run-migration] [--assert]
#
#   --files '…'        simulate a changed-file set directly (history-independent)
#   --base/--head REF  diff two real refs (paths-filter equivalent on a push).
#                      NOTE: with the ci-cd.yml `base: ''` config, dorny diffs a
#                      dev push against merge-base(HEAD, master) — everything since
#                      the last master merge — NOT the previous commit. Pass the
#                      merge-base as BASE to reproduce the real signal; pass the
#                      previous commit to model a per-push diff.
#   --run-migration    actually run `alembic upgrade head` against demo.db when task=true
#   --assert           run the built-in scenarios and exit non-zero on any mismatch
# ──────────────────────────────────────────────────────────────────────────

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

EVENT=push
BRANCH=dev
RUN_MIGRATION_INPUT=true
FULL_REBUILD_INPUT=false
FILES=""
FILES_SET=false
BASE=""
HEAD=""
RUN_REAL_MIGRATION=false
ASSERT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --event) EVENT="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --run-migration-input) RUN_MIGRATION_INPUT="$2"; shift 2 ;;
    --full-rebuild-input) FULL_REBUILD_INPUT="$2"; shift 2 ;;
    --files) FILES="$2"; FILES_SET=true; shift 2 ;;
    --base) BASE="$2"; shift 2 ;;
    --head) HEAD="$2"; shift 2 ;;
    --run-migration) RUN_REAL_MIGRATION=true; shift ;;
    --assert) ASSERT=true; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# 1. paths-filter equivalent: the set of changed paths
if [ "$ASSERT" = true ]; then
  CHANGED=()   # assert mode re-invokes the script per scenario with real inputs
elif [ "$FILES_SET" = true ]; then
  if [ -z "$FILES" ]; then
    CHANGED=()
  else
    mapfile -t CHANGED < <(printf '%s\n' "$FILES")
  fi
elif [ -n "$BASE" ] && [ -n "$HEAD" ]; then
  mapfile -t CHANGED < <(git diff --name-only "$BASE" "$HEAD")
else
  echo "need --files or --base+--head" >&2
  exit 2
fi

# glob match against one changed path (bash case semantics)
matches() { local pat="$1" f="$2"; case "$f" in $pat) return 0 ;; *) return 1 ;; esac; }

component() {
  local name="$1"
  shift
  for f in "${CHANGED[@]}"; do
    for pat in "$@"; do
      if matches "$pat" "$f"; then echo true; return; fi
    done
  done
  echo false
}

FRONTEND="$(component frontend 'frontend/*')"
BACKEND="$(component backend 'backend/*')"
INFRA="$(component infra 'infra/*')"
DOCS="$(component docs 'docs/*')"
BOT="$(component bot 'bot/*')"
SUBCOMPONENT="$(component subcomponent 'subcomponent' '.gitmodules')"
# raw paths-filter output, NOT folded into full_rebuild (mirrors ci-cd.yml)
MIGRATIONS="$(component migrations 'backend/aci/alembic/*')"

# 2. meta step: full_rebuild folding
FULL_REBUILD=false
if [ "$EVENT" = workflow_dispatch ] || [ "$BRANCH" = master ] || [ "$FULL_REBUILD_INPUT" = true ]; then
  FULL_REBUILD=true
fi

emit() { if [ "$FULL_REBUILD" = true ]; then echo true; else echo "$2"; fi; }
BE="$(emit backend "$BACKEND")"
FE="$(emit frontend "$FRONTEND")"
IN="$(emit infra "$INFRA")"
DO="$(emit docs "$DOCS")"
BO="$(emit bot "$BOT")"
SUB="$(emit subcomponent "$SUBCOMPONENT")"

# 3. create-manifest flag derivation (Text #2 semantics)
if [ "$EVENT" = workflow_dispatch ]; then
  RUN_MIGRATION="$RUN_MIGRATION_INPUT"
  MIGRATIONS_CHANGED=true
else
  RUN_MIGRATION=true
  MIGRATIONS_CHANGED="$MIGRATIONS"
  [ "$MIGRATIONS_CHANGED" = true ] || MIGRATIONS_CHANGED=false
fi

# 4. deploy-side effective migration task
if [ "$RUN_MIGRATION" = true ] && [ "$MIGRATIONS_CHANGED" = true ]; then
  TASK=true
else
  TASK=false
fi

if [ "$ASSERT" != true ]; then
  echo "event=$EVENT branch=$BRANCH full_rebuild=$FULL_REBUILD"
  echo "changed: frontend=$FE backend=$BE infra=$IN docs=$DO bot=$BO subcomponent=$SUB"
  echo "migrations=$MIGRATIONS run_migration=$RUN_MIGRATION migrations_changed=$MIGRATIONS_CHANGED"
  echo "Migration task: $TASK (policy=$RUN_MIGRATION, migrations_changed=$MIGRATIONS_CHANGED)"

  # optional: run the real dummy migrations when the task would run
  if [ "$RUN_REAL_MIGRATION" = true ]; then
    if [ "$TASK" = true ]; then
      echo "--run-migration: executing alembic upgrade head against demo.db"
      (cd backend/aci && uv run --with alembic alembic upgrade head)
      echo "--run-migration: tables = $(sqlite3 backend/aci/demo.db '.tables' | tr '\n' ' ')"
    else
      echo "--run-migration: task=false → migration task skipped (no alembic run)"
    fi
  fi
fi

# ── built-in assertion scenarios ─────────────────────────────────────────
run_scenario() {
  local name="$1" shift_done=false
  shift
  local args=()
  while [ $# -gt 0 ] && [ "$1" != "expect" ]; do args+=("$1"); shift; done
  [ "${1:-}" = "expect" ] && shift
  local out
  out="$(bash "$0" "${args[@]}")"
  local ok=true missing=""
  for kv in "$@"; do
    if ! grep -qF "$kv" <<<"$out"; then ok=false; missing="$missing [$kv]"; fi
  done
  if [ "$ok" = true ]; then
    echo "PASS  $name"
  else
    echo "FAIL  $name — missing:$missing" >&2
    echo "      args: ${args[*]}" >&2
    echo "      output:" >&2
    sed 's/^/        /' <<<"$out" >&2
    return 1
  fi
}

if [ "$ASSERT" = true ]; then
  rc=0
  run_scenario "dev push adds alembic revision" \
    --files 'backend/aci/alembic/versions/migration_1_add_admin_analytics_tables.py' \
    expect \
    "full_rebuild=false" "backend=true" "migrations=true" "run_migration=true" \
    "migrations_changed=true" "Migration task: true (policy=true, migrations_changed=true)" \
    || rc=1

  # Submodule-only bump = different signal. Models the case where the diff
  # contains ONLY the subcomponent gitlink — e.g. a master promotion, or a dev
  # push once master has caught up. NOTE: on a dev push with base '' the diff is
  # merge-base(dev, master)..HEAD, so pending alembic files still flip
  # migrations=true until they're merged to master (see ci-cd.yml base comment).
  run_scenario "submodule-only bump = different signal" \
    --files 'subcomponent' \
    expect \
    "full_rebuild=false" "subcomponent=true" "backend=false" "migrations=false" \
    "run_migration=true" "migrations_changed=false" \
    "Migration task: false (policy=true, migrations_changed=false)" \
    || rc=1

  run_scenario "unrelated docs change" \
    --files 'docs/README.md' \
    expect \
    "docs=true" "migrations=false" "migrations_changed=false" \
    "Migration task: false (policy=true, migrations_changed=false)" \
    || rc=1

  run_scenario "master push full rebuild, no alembic in diff" \
    --branch master --files 'docs/README.md' \
    expect \
    "full_rebuild=true" "frontend=true" "backend=true" "docs=true" \
    "migrations=false" "migrations_changed=false" "Migration task: false" \
    || rc=1

  run_scenario "master push full rebuild, alembic in diff" \
    --branch master --files 'backend/aci/alembic/env.py' \
    expect \
    "full_rebuild=true" "backend=true" "migrations=true" "migrations_changed=true" \
    "Migration task: true" \
    || rc=1

  run_scenario "workflow_dispatch (run_migration input true)" \
    --event workflow_dispatch --branch dev --files '' \
    expect \
    "full_rebuild=true" "migrations_changed=true" "run_migration=true" "Migration task: true" \
    || rc=1

  run_scenario "workflow_dispatch operator override (run_migration input false)" \
    --event workflow_dispatch --branch dev --run-migration-input false --files '' \
    expect \
    "full_rebuild=true" "migrations_changed=true" "run_migration=false" "Migration task: false" \
    || rc=1

  if [ "$rc" -eq 0 ]; then
    echo "ALL SCENARIOS PASSED"
  else
    echo "SOME SCENARIOS FAILED" >&2
  fi
  exit "$rc"
fi
