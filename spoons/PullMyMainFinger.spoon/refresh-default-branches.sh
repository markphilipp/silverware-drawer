#!/usr/bin/env bash
# Fast-forward the default branch (main/master/etc.) of every git repo found
# anywhere under a root dir (default ~/Projects), matching origin. Repos are
# discovered recursively by their .git/.bare marker; node_modules, vendor, and
# hidden dirs are pruned. The search descends into a found repo's working tree
# too, so repos nested inside another repo (e.g. gitignored sibling clones) are
# also refreshed.
#
# For each repo:
#   - default branch comes from origin/HEAD (repaired via `remote set-head` if unset)
#   - if it is NOT checked out anywhere, the ref is fast-forwarded directly
#     (no working tree touched)
#   - if it IS checked out in a worktree:
#       - clean tree        → `git pull --ff-only`
#       - dirty tree        → stash → pull → restore. Any conflict (non-ff pull,
#                             or a stash-pop that can't reapply) rolls the repo
#                             back to exactly its prior state and skips it, so a
#                             human can handle it later (or the next run will).
#
# Handles normal repos, bare-repo + worktree layouts (repo/.bare with repo/main),
# and shared worktrees alike — the default branch is refreshed wherever it lives.
#
# Env:
#   PROJECTS_ROOT   colon-separated roots scanned for repos (default: $HOME/Projects)
#
# Exit: 0 if nothing failed, 1 if any repo failed. Emits per-repo lines plus a
# trailing `PULLSPOON_SUMMARY refreshed=N skipped=N failed=N` line for callers.
set -o pipefail

IFS=':' read -ra ROOTS <<< "${PROJECTS_ROOT:-$HOME/Projects}"

refreshed=()
skipped=()
failed=()
seen=""  # shared git dirs already processed, so worktrees aren't refreshed twice

last_line() { printf '%s' "${1##*$'\n'}"; }

# Print every repo root under the given roots: dirs holding a .git (normal repo
# or worktree) or a .bare (bare-repo project). Prunes node_modules/vendor and
# hidden dirs (tool data like .mcp_*, .cache, .Trash). The walk continues into a
# repo's working tree, so repos nested inside another repo (e.g. gitignored
# sibling clones under llp-local/applications) are discovered too. Worktrees of
# the same repo are de-duped later by their shared git-common-dir.
find_repos() {
  local root
  for root in "${ROOTS[@]}"; do
    [ -d "$root" ] || continue
    find "$root" \
      \( -name node_modules -o -name vendor -o -name '.?*' \) -prune -o \
      -type d -exec sh -c 'test -e "$1/.git" -o -e "$1/.bare"' _ {} \; -print
  done
}

while IFS= read -r dir; do
  [ -n "$dir" ] || continue
  name="${dir##*/}"

  # Confirm it's a git repo with an origin; skip quietly otherwise (local-only).
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue
  git -C "$dir" remote get-url origin >/dev/null 2>&1 || continue

  # Dedupe: multiple worktrees of one repo share a git dir — process it once.
  common="$(git -C "$dir" rev-parse --git-common-dir 2>/dev/null)" || continue
  case "$common" in /*) ;; *) common="$dir/$common" ;; esac
  common="$(cd "$common" 2>/dev/null && pwd -P)" || continue
  case "$seen" in *"|$common|"*) continue ;; esac
  seen="$seen|$common|"

  # Default branch from origin/HEAD; repair the ref if it was never set.
  branch="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  if [ -z "$branch" ]; then
    git -C "$dir" remote set-head origin --auto >/dev/null 2>&1
    branch="$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)"
  fi
  branch="${branch#origin/}"
  if [ -z "$branch" ]; then
    failed+=("$name: could not determine default branch")
    continue
  fi

  # Which worktree, if any, has the default branch checked out? git refuses to
  # fetch into a checked-out branch, so we must pull there instead of ff-ing the ref.
  wt=""
  cur=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)                 cur="${line#worktree }" ;;
      "branch refs/heads/$branch")  wt="$cur"; break ;;
    esac
  done < <(git -C "$dir" worktree list --porcelain 2>/dev/null)

  # --- not checked out anywhere → fast-forward the ref directly --------------
  if [ -z "$wt" ]; then
    if out="$(git -C "$dir" fetch origin "$branch:$branch" 2>&1)"; then
      refreshed+=("$name → $branch")
    else
      skipped+=("$name ($branch): $(last_line "$out")")
    fi
    continue
  fi

  # --- checked out, clean tree → plain fast-forward pull ---------------------
  if [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    if out="$(git -C "$wt" pull --ff-only origin "$branch" 2>&1)"; then
      refreshed+=("$name → $branch")
    else
      failed+=("$name ($branch): $(last_line "$out")")
    fi
    continue
  fi

  # --- checked out, dirty tree → stash, pull, restore (rollback on conflict) -
  orig="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if ! git -C "$wt" stash push -u -m "pull-spoon auto-stash" >/dev/null 2>&1; then
    failed+=("$name ($branch): could not stash local changes")
    continue
  fi

  if git -C "$wt" pull --ff-only origin "$branch" >/dev/null 2>&1; then
    if git -C "$wt" stash pop >/dev/null 2>&1; then
      refreshed+=("$name → $branch (local changes preserved)")
    else
      # Reapplying the stash onto the new commit conflicts. Roll the branch back
      # to its prior commit, then the stash reapplies cleanly onto its own base.
      git -C "$wt" reset --hard "$orig" >/dev/null 2>&1
      git -C "$wt" stash pop >/dev/null 2>&1
      skipped+=("$name ($branch): stash conflict — left untouched for manual merge")
    fi
  else
    # Not fast-forwardable (local commits diverged). Working tree was clean after
    # the stash, so the pop restores the changes onto the unchanged branch.
    git -C "$wt" stash pop >/dev/null 2>&1
    skipped+=("$name ($branch): not fast-forwardable — left untouched")
  fi
done < <(find_repos)

for r in "${refreshed[@]}"; do printf 'ok    %s\n' "$r"; done
for s in "${skipped[@]}";   do printf 'skip  %s\n' "$s"; done
for f in "${failed[@]}";    do printf 'FAIL  %s\n' "$f"; done

printf 'PULLSPOON_SUMMARY refreshed=%d skipped=%d failed=%d\n' \
  "${#refreshed[@]}" "${#skipped[@]}" "${#failed[@]}"

[ "${#failed[@]}" -eq 0 ]
