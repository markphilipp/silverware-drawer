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
#   PROJECTS_ROOT       colon-separated roots scanned for repos (default: $HOME/Projects)
#   SSH_PROBE_TIMEOUT   seconds to wait on the agent signing probe (default 10)
#   NET_PROBE_HOST      host TCP-probed for reachability (default github.com)
#   NET_PROBE_TIMEOUT   seconds to wait on that probe (default 8)
#
# This is best effort: a repo that simply can't be fast-forwarded right now is
# not a failure. Per-repo outcomes land in one of four buckets, each with its
# own line prefix, so the caller can decide what deserves a human's attention
# without re-parsing prose:
#
#   ok     fast-forwarded
#   skip   nothing to do, self-healing — diverged history, unstashable tree,
#          no discoverable default branch, cancelled mid-run
#   ATTN   a human has to act — stash conflict, or an error we can't classify
#   defer  the run couldn't start or had to stop: no network, or the SSH agent
#          won't sign. Every remaining repo would fail identically, so we stop.
#
# Exit: 0 for a complete pass (ATTN items included — they're repo state, not a
# run failure), 3 if the SSH agent can't sign, 4 if cancelled via SIGTERM/SIGINT,
# 5 if the remote is unreachable. A non-zero exit means the pass was incomplete,
# so the caller should retry rather than record a success. Emits per-repo lines
# plus a trailing
# `PULLSPOON_SUMMARY refreshed=N skipped=N attention=N deferred=N` line.
set -o pipefail

IFS=':' read -ra ROOTS <<< "${PROJECTS_ROOT:-$HOME/Projects}"

# Never block on a prompt: git should fail fast rather than sit waiting for
# credentials or a host-key answer in a context with no terminal.
export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh -o BatchMode=yes -o ConnectTimeout=10}"

refreshed=()
skipped=()
attention=()
deferred=()
seen=""       # shared git dirs already processed, so worktrees aren't refreshed twice
auth_error="" # set when auth dies; the whole run stops, since every repo would fail too
net_error=""  # ditto for an unreachable remote
cancelled=""

# Cancellation is cooperative: the flag is checked between repos, so we never
# get killed between `stash push` and `stash pop` and strand someone's changes.
trap 'cancelled=1' TERM INT

# Git's real error is usually followed by boilerplate ("...and the repository
# exists."), so a plain tail throws away the only useful line.
err_line() {
  printf '%s\n' "$1" \
    | grep -m1 -E 'Could not resolve|Resolving timed out|Temporary failure in name resolution|not known|Network is unreachable|Operation timed out|Connection (timed out|refused)|Permission denied|Could not read from remote|Authentication failed|authorization|refused operation|Host key verification|^fatal:|^error:' \
    || printf '%s\n' "$1" | grep -v '^[[:space:]]*$' | tail -n1
}

# network  → can't reach the remote at all; transient, and every repo would fail
# auth     → the agent won't sign; every remaining repo would fail the same way
# diverged → local commits ahead of origin; routine, nothing to fix
# error    → anything else, worth a human's attention
#
# Network is tested first on purpose: a DNS failure also prints "Could not read
# from remote repository", so matching auth first would blame 1Password for an
# outage.
classify() {
  case "$1" in
    *"Could not resolve"*|*"Resolving timed out"*|*"Temporary failure in name resolution"* \
      |*"nodename nor servname"*|*"Network is unreachable"*|*"Operation timed out"* \
      |*"Connection timed out"*|*"Connection refused"*|*"kex_exchange_identification"*)
      printf 'network' ;;
    *"Permission denied"*|*"Could not read from remote"*|*"Authentication failed"* \
      |*authorization*|*"refused operation"*|*"Host key verification failed"*)
      printf 'auth' ;;
    *"non-fast-forward"*|*"Not possible to fast-forward"*|*"rejected"* \
      |*diverged*|*"unrelated histories"*)
      printf 'diverged' ;;
    *)
      printf 'error' ;;
  esac
}

# Run a command, killing it after N seconds. Returns 124 on timeout, like
# coreutils `timeout` (which macOS doesn't ship).
run_bounded() {
  local secs="$1" pid elapsed=0
  shift
  "$@" >/dev/null 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$secs" ]; then
      kill -TERM "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$pid"
}

# `ssh-add -l` only *lists* identities — it succeeds even when 1Password is
# locked and will refuse to sign. Signing is what every fetch actually needs,
# so prove that before grinding through twenty repos' worth of 60s prompt
# timeouts. Bounded, because a locked agent answers by not answering.
preflight_ssh() {
  [ -n "${SSH_AUTH_SOCK:-}" ] || return 0
  if [ ! -S "$SSH_AUTH_SOCK" ]; then
    auth_error="agent socket missing ($SSH_AUTH_SOCK)"
    return 1
  fi
  local keys rc
  keys="$(mktemp -t pullspoon)" || return 0
  if ! ssh-add -L > "$keys" 2>/dev/null; then
    rm -f "$keys"
    auth_error="agent has no identities"
    return 1
  fi
  run_bounded "${SSH_PROBE_TIMEOUT:-10}" ssh-add -T "$keys"
  rc=$?
  rm -f "$keys"
  case "$rc" in
    0)   return 0 ;;
    124) auth_error="agent did not answer a signing request in ${SSH_PROBE_TIMEOUT:-10}s (locked?)" ;;
    *)   auth_error="agent refused to sign (locked?)" ;;
  esac
  return 1
}

# A machine that just woke, or is on a captive/VPN-less network, resolves
# nothing — and git's DNS timeout is minutes long, per repo. One cheap TCP
# connect settles it before any of that. (nc rather than bash's /dev/tcp: some
# endpoint-security setups SIGKILL /bin/bash for opening a socket.)
preflight_net() {
  local secs="${NET_PROBE_TIMEOUT:-8}"
  run_bounded "$secs" nc -z -G "$secs" -w "$secs" "${NET_PROBE_HOST:-github.com}" 443
}

if ! preflight_net; then
  printf 'defer network unavailable — nothing attempted (%s unreachable)\n' \
    "${NET_PROBE_HOST:-github.com}"
  printf 'PULLSPOON_SUMMARY refreshed=0 skipped=0 attention=0 deferred=1\n'
  exit 5
fi

if ! preflight_ssh; then
  printf 'defer ssh auth unavailable — nothing attempted: %s\n' "$auth_error"
  printf 'PULLSPOON_SUMMARY refreshed=0 skipped=0 attention=0 deferred=1\n'
  exit 3
fi

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
  [ -n "$cancelled" ] && break
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
    skipped+=("$name: no discoverable default branch")
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
      case "$(classify "$out")" in
        network)  net_error="$(err_line "$out")"; break ;;
        auth)     auth_error="$(err_line "$out")"; break ;;
        diverged) skipped+=("$name ($branch): not fast-forwardable — left untouched") ;;
        *)        attention+=("$name ($branch): $(err_line "$out")") ;;
      esac
    fi
    continue
  fi

  # --- checked out, clean tree → plain fast-forward pull ---------------------
  if [ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    if out="$(git -C "$wt" pull --ff-only origin "$branch" 2>&1)"; then
      refreshed+=("$name → $branch")
    else
      case "$(classify "$out")" in
        network)  net_error="$(err_line "$out")"; break ;;
        auth)     auth_error="$(err_line "$out")"; break ;;
        diverged) skipped+=("$name ($branch): not fast-forwardable — left untouched") ;;
        *)        attention+=("$name ($branch): $(err_line "$out")") ;;
      esac
    fi
    continue
  fi

  # --- checked out, dirty tree → stash, pull, restore (rollback on conflict) -
  orig="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  if ! git -C "$wt" stash push -u -m "pull-spoon auto-stash" >/dev/null 2>&1; then
    skipped+=("$name ($branch): could not stash local changes — left untouched")
    continue
  fi

  if out="$(git -C "$wt" pull --ff-only origin "$branch" 2>&1)"; then
    if git -C "$wt" stash pop >/dev/null 2>&1; then
      refreshed+=("$name → $branch (local changes preserved)")
    else
      # Reapplying the stash onto the new commit conflicts. Roll the branch back
      # to its prior commit, then the stash reapplies cleanly onto its own base.
      git -C "$wt" reset --hard "$orig" >/dev/null 2>&1
      git -C "$wt" stash pop >/dev/null 2>&1
      attention+=("$name ($branch): stash conflict — left untouched for manual merge")
    fi
  else
    # The pull didn't happen, so the working tree is exactly as the stash left
    # it and the pop restores the changes onto the unchanged branch — whatever
    # the reason for the failure.
    git -C "$wt" stash pop >/dev/null 2>&1
    case "$(classify "$out")" in
      network)  net_error="$(err_line "$out")"; break ;;
      auth)     auth_error="$(err_line "$out")"; break ;;
      diverged) skipped+=("$name ($branch): not fast-forwardable — left untouched") ;;
      *)        attention+=("$name ($branch): $(err_line "$out")") ;;
    esac
  fi
done < <(find_repos)

if [ -n "$net_error" ]; then
  deferred+=("network unavailable — aborted after ${#refreshed[@]} repos: $net_error")
fi
if [ -n "$auth_error" ]; then
  deferred+=("ssh auth unavailable — aborted after ${#refreshed[@]} repos: $auth_error")
fi

for r in "${refreshed[@]}"; do printf 'ok    %s\n' "$r"; done
for s in "${skipped[@]}";   do printf 'skip  %s\n' "$s"; done
for a in "${attention[@]}"; do printf 'ATTN  %s\n' "$a"; done
for d in "${deferred[@]}";  do printf 'defer %s\n' "$d"; done
[ -n "$cancelled" ] && printf 'skip  cancelled — machine back in use\n'

printf 'PULLSPOON_SUMMARY refreshed=%d skipped=%d attention=%d deferred=%d\n' \
  "${#refreshed[@]}" "${#skipped[@]}" "${#attention[@]}" "${#deferred[@]}"

if [ -n "$auth_error" ]; then exit 3; fi
if [ -n "$cancelled" ]; then exit 4; fi
if [ -n "$net_error" ]; then exit 5; fi
exit 0
