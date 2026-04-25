# github-branch-delete-agent

A small local agent that safely prunes stale local git branches in this repository. It only deletes a branch after verifying — via the GitHub API — that the branch was merged into `main` through a pull request and that at least **7 days** have passed since that merge.

## What it does

For each local branch other than `main`, the agent checks GitHub for a matching pull request and deletes the local branch if and only if **all** of the following are true:

1. The PR was merged into `main` (not some other base branch).
2. The PR's head branch is owned by you (excludes PRs pushed from forks that happen to share a branch name).
3. The PR's `mergedAt` timestamp is at least 7 days in the past.

Every successful deletion is appended to a log file.

### Safety rails

- Refuses to run unless you are currently checked out on `main`.
- Never deletes `main`, regardless of filters.
- Never deletes the branch that HEAD points to.
- Defaults to **dry-run** — you must pass `--apply` to actually delete anything.

## Prerequisites

- **macOS or Linux** with a POSIX shell.
- **Bash 4+**. macOS ships with bash 3.2 at `/bin/bash`; install a newer bash:
  ```
  brew install bash
  ```
- **git** (any modern version).
- **[GitHub CLI (`gh`)](https://cli.github.com/)**, authenticated:
  ```
  brew install gh
  gh auth login
  ```
  Confirm with `gh auth status`.
- **[jq](https://jqlang.github.io/jq/)** for JSON parsing:
  ```
  brew install jq
  ```
- You must be working inside a git repository with a GitHub remote, and a local `main` branch must exist.

## Usage

From the repo root:

```
./cleanup-branches.sh [--apply] [--days N] [--main BRANCH] [--log PATH]
```

| Flag | Default | Purpose |
| --- | --- | --- |
| `--apply` | off | Actually delete. Without it, the script is a no-op preview. |
| `--days N` | `7` | Minimum number of days since the PR's merge before a branch is eligible. |
| `--main BRANCH` | `main` | Name of the protected base branch. |
| `--log PATH` | `./deleted-branches.log` | File to append deletion records to. |

### Typical workflow

```
git checkout main
git pull
./cleanup-branches.sh            # dry-run: shows what would be deleted
./cleanup-branches.sh --apply    # actually delete
```


## Expected output

### Dry-run (no flag)

```
$ ./cleanup-branches.sh
would delete: feature/add-search-filters  (merged 2026-04-10T18:22:04Z)
would delete: bugfix/login-redirect       (merged 2026-04-12T09:01:33Z)

--- summary ---
candidates:        2
(dry-run — pass --apply to actually delete)
skipped protected: 1  (main)
skipped current:   0
skipped no PR:     4
```

### With `--apply`

```
$ ./cleanup-branches.sh --apply
deleted: feature/add-search-filters  (merged 2026-04-10T18:22:04Z)
deleted: bugfix/login-redirect       (merged 2026-04-12T09:01:33Z)

--- summary ---
candidates:        2
deleted:           2
log:               ./deleted-branches.log
skipped protected: 1  (main)
skipped current:   0
skipped no PR:     4
```

### Common preflight errors

| Message | Meaning |
| --- | --- |
| `error: not inside a git repository` | You ran the script outside a git working tree. |
| `error: gh CLI not installed` | Run `brew install gh`. |
| `error: jq not installed` | Run `brew install jq`. |
| `error: gh is not authenticated` | Run `gh auth login`. |
| `error: protected branch 'main' does not exist locally` | The branch named by `--main` doesn't exist; repo may have no commits yet. |
| `error: refuse to run: must be on 'main'` | Checkout `main` first: `git checkout main`. |

## Why this agent is useful

- **Stale local branches accumulate silently.** After a PR is merged, most teams auto-delete the *remote* branch but the *local* copy stays around forever, cluttering `git branch` output and tab-completion.
- **`git branch --merged main` is not enough.** Modern GitHub PR merges usually use squash-merge or rebase-merge. In both cases the local branch's commit SHAs never land on `main`, so git's built-in merged-check returns nothing useful. Querying GitHub directly via `gh` is the only reliable way to know "this branch was merged via PR."
- **The 7-day cooling period protects you** from deleting a branch that was merged by mistake and is about to be reverted or re-opened — a common pattern when a deploy goes wrong.
- **Dry-run by default, log every deletion, refuse to run off `main`.** You get an auditable trail and a hard stop if the repository state isn't what the agent expects.

## Files in this repository

- [cleanup-branches.sh](cleanup-branches.sh) — the agent script.
- [plan.md](plan.md) — design doc with the full step-by-step plan, security tradeoffs, and verification strategy.
- [.gitignore](.gitignore) — keeps the log file (and other local-only files) out of commits.