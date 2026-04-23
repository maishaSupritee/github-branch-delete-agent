#!/usr/bin/env bash
set -euo pipefail

if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
  echo "error: requires bash 4+ (found ${BASH_VERSION}). Try: brew install bash, then run with /opt/homebrew/bin/bash $0" >&2
  exit 1
fi

APPLY=0
DAYS=7
MAIN="main"
LOG="./deleted-branches.log"

usage() {
  cat <<EOF
Usage: $0 [--apply] [--days N] [--main BRANCH] [--log PATH]

Deletes local branches whose GitHub PR:
  - merged into \$MAIN (default: main)
  - head branch is owned by you
  - merged at least N days ago (default: 7)

Without --apply, runs in dry-run mode (no deletions).
Must be checked out on \$MAIN.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)      APPLY=1; shift ;;
    --days)       DAYS="$2"; shift 2 ;;
    --days=*)     DAYS="${1#--days=}"; shift ;;
    --main)       MAIN="$2"; shift 2 ;;
    --main=*)     MAIN="${1#--main=}"; shift ;;
    --log)        LOG="$2"; shift 2 ;;
    --log=*)      LOG="${1#--log=}"; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$DAYS" =~ ^[0-9]+$ ]] || { echo "error: --days must be a non-negative integer" >&2; exit 2; }

die() { echo "error: $*" >&2; exit 1; }

git rev-parse --git-dir >/dev/null 2>&1 \
  || die "not inside a git repository"

command -v gh >/dev/null 2>&1 \
  || die "gh CLI not installed. Install: brew install gh"
command -v jq >/dev/null 2>&1 \
  || die "jq not installed. Install: brew install jq"

gh auth status >/dev/null 2>&1 \
  || die "gh is not authenticated. Run: gh auth login"

git show-ref --verify --quiet "refs/heads/$MAIN" \
  || die "protected branch '$MAIN' does not exist locally"

CURRENT=$(git symbolic-ref --short HEAD 2>/dev/null || echo "")
if [[ "$CURRENT" != "$MAIN" ]]; then
  die "refuse to run: must be on '$MAIN' (currently on '${CURRENT:-detached HEAD}'). Run: git checkout $MAIN"
fi

ME=$(gh api user --jq .login) \
  || die "failed to resolve current GitHub user via 'gh api user'"

NOW=$(date -u +%s)
THRESHOLD_SECS=$(( DAYS * 86400 ))

PR_JSON=$(gh pr list --state merged --limit 200 \
  --json number,mergedAt,headRefName,baseRefName,headRepositoryOwner) \
  || die "failed to list merged PRs"

ELIGIBLE=$(jq -r \
  --arg main "$MAIN" \
  --arg me "$ME" \
  --argjson now "$NOW" \
  --argjson thresh "$THRESHOLD_SECS" \
  '.[]
   | select(.baseRefName == $main)
   | select(.headRepositoryOwner.login == $me)
   | select(.mergedAt != null)
   | select(($now - (.mergedAt | fromdateiso8601)) >= $thresh)
   | "\(.headRefName)\t\(.mergedAt)"' <<<"$PR_JSON")

declare -A MERGED_AT
if [[ -n "$ELIGIBLE" ]]; then
  while IFS=$'\t' read -r branch merged_at; do
    [[ -z "$branch" ]] && continue
    MERGED_AT["$branch"]="$merged_at"
  done <<<"$ELIGIBLE"
fi

CANDIDATES=0
DELETED=0
SKIPPED_PROTECTED=0
SKIPPED_HEAD=0
SKIPPED_NO_PR=0

while IFS= read -r branch; do
  if [[ "$branch" == "$MAIN" ]]; then
    SKIPPED_PROTECTED=$((SKIPPED_PROTECTED + 1))
    continue
  fi
  if [[ "$branch" == "$CURRENT" ]]; then
    SKIPPED_HEAD=$((SKIPPED_HEAD + 1))
    continue
  fi
  if [[ -z "${MERGED_AT[$branch]+x}" ]]; then
    SKIPPED_NO_PR=$((SKIPPED_NO_PR + 1))
    continue
  fi

  CANDIDATES=$((CANDIDATES + 1))
  merged_at="${MERGED_AT[$branch]}"

  if [[ "$APPLY" -eq 1 ]]; then
    if git branch -D "$branch" >/dev/null 2>&1; then
      ts=$(date '+%Y-%m-%d %H:%M:%S')
      printf '%s %s\n' "$ts" "$branch" >>"$LOG"
      echo "deleted: $branch  (merged $merged_at)"
      DELETED=$((DELETED + 1))
    else
      echo "FAILED to delete: $branch" >&2
    fi
  else
    echo "would delete: $branch  (merged $merged_at)"
  fi
done < <(git for-each-ref --format='%(refname:short)' refs/heads/)

echo
echo "--- summary ---"
echo "candidates:        $CANDIDATES"
if [[ "$APPLY" -eq 1 ]]; then
  echo "deleted:           $DELETED"
  echo "log:               $LOG"
else
  echo "(dry-run — pass --apply to actually delete)"
fi
echo "skipped protected: $SKIPPED_PROTECTED  ($MAIN)"
echo "skipped current:   $SKIPPED_HEAD"
echo "skipped no PR:     $SKIPPED_NO_PR"
