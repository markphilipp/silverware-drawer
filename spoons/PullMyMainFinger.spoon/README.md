# PullMyMainFinger

Keeps every repo's default branch current without you thinking about it. It
scans `~/Projects` recursively, finds each git repo, and fast-forwards its
default branch (`main`/`master`/…, read from `origin/HEAD`) to match origin.

Best effort: only a repo needing a human ever notifies.

## When it runs

Triggers once you've been away from the keyboard for `idleMinutes` (default
**5**) **with the screen still unlocked**, and only if it's been at least
`minHoursBetweenRuns` (default **8**) since the last complete pass *and*
`retryAfterDeferralMinutes` (default **60**) since the last attempt of any kind. After a *cancelled* run it also waits
`retryAfterCancelMinutes` (default **30**), so sitting still while reading
doesn't restart the whole scan every `idleMinutes`.

Unlocked matters: locking the screen locks 1Password too, and its SSH agent then
refuses to sign, so every fetch stalls on an authorization prompt nobody is
there to answer. The second gate matters for the same reason in reverse —
1Password's own auto-lock fires on inactivity even with the screen unlocked, so
the idle window the job runs in is exactly the window where the agent may have
just locked itself. That's a deferral, not a failure: the success stamp doesn't
move, so without a gate that advances on *every* attempt the poll would retry
each minute for as long as you're away.

## Preflight

Before touching any repo the run proves two things: the remote is reachable at
all (a just-woken or VPN-less machine resolves nothing, and git's DNS timeout
runs into *minutes* per repo), and the agent will actually sign
(`ssh-add -l` doesn't prove that — it lists identities a locked agent still
refuses to use). Either failing mid-run aborts the rest, since every remaining
repo would fail the same way. A DNS failure is reported as a network problem,
not an auth one, even though git prints "Could not read from remote repository"
for both.

## Cancellation

Touch the machine (idle time drops below two poll intervals) — or lock it — and a run in flight is cancelled.
Cancellation is cooperative: the script finishes the repo it's on and stops
before the next one, so nothing is ever killed between `stash push` and
`stash pop`.

## Discovery

Walks the tree for each repo's `.git`/`.bare` marker, pruning `node_modules`,
`vendor`, and hidden dirs, and stops at each repo root — so a repo vendored
inside another repo's working tree is left alone. Multiple worktrees of the same
repo are refreshed once, at whichever checkout holds the default branch.

## Refresh behavior

Handles every layout uniformly — normal clones, bare-repo + worktree projects
(`repo/.bare` with `repo/main`), and shared worktrees — and refreshes the
default branch wherever it lives:

- **not checked out** → the ref is fast-forwarded directly, no working tree touched
- **checked out, clean** → `git pull --ff-only`
- **checked out with uncommitted changes** → stash → pull → restore. If the pull
  isn't a fast-forward, or restoring the stash conflicts, the repo is rolled back
  to *exactly* its prior state (branch, working tree, index, untracked, stash all
  intact) and skipped — handle it by hand, or let the next run try again.

Repos with no `origin` remote are skipped silently.

## Outcomes

| | |
| --- | --- |
| `ok` | fast-forwarded |
| `skip` | nothing to do, self-healing — diverged history, unstashable tree, no discoverable default branch, cancelled mid-run |
| `ATTN` | a human has to act — stash conflict, or a git error the script can't classify |
| `defer` | the run couldn't start or had to stop — no network, or the agent won't sign |

## Notifications

Every outcome goes to the Hammerspoon console. Notification Center only ever
sees `ATTN` — and only one notification at a time, since a newer one withdraws
the last, so you get the current state rather than a pile of history. It's
timestamped, because it doesn't auto-withdraw and an old one would otherwise
read as a fresh problem. Deferrals, diverged branches, unstashable trees, and
cancelled runs never notify: all of them clear themselves on a later pass, which
is the point of a best-effort job.

## Manual control

From the Hammerspoon console:

- `spoon.PullMyMainFinger:run()` — refresh now (ignores the idle and `minHoursBetweenRuns` gates, but still stamps the attempt, so the next automatic run waits `retryAfterDeferralMinutes`)
- `spoon.PullMyMainFinger:cancel()` — stop a run in flight

The work runs off the main thread via `hs.task`.

## Options

```lua
{ name = "PullMyMainFinger", opts = {
    root = os.getenv("HOME") .. "/Projects",  -- scanned root
    idleMinutes = 5,                          -- idle time before a run starts
    pollSeconds = 60,                         -- how often idle state is checked
    minHoursBetweenRuns = 8,                  -- min hours between complete passes
    retryAfterDeferralMinutes = 60,           -- min minutes between attempts of any kind
    retryAfterCancelMinutes = 30,             -- min minutes after a cancelled run
    sshAuthSock = "/path/to/agent.sock",      -- SSH agent for fetches outside a login shell
    notifyOnIssues = true,                    -- notify only on repos needing a human
} }
```

`sshAuthSock` defaults to the 1Password agent socket so SSH fetches authenticate
even though the scheduled run has no login shell; set it to your machine's agent
socket. `nil` falls back to the inherited `SSH_AUTH_SOCK`; `false` exports none.

## The script

The logic lives in `refresh-default-branches.sh` and can be run directly:

```sh
PROJECTS_ROOT=~/Projects ./refresh-default-branches.sh
```

| Exit | Meaning |
| --- | --- |
| `0` | complete pass (`ATTN` items included — that's repo state, not a run failure) |
| `3` | SSH agent can't sign |
| `4` | cancelled with `SIGTERM`/`SIGINT` |
| `5` | remote unreachable |

A non-zero exit means the pass didn't finish, so the caller should retry rather
than record a success.

Env: `NET_PROBE_HOST` (default `github.com`), `NET_PROBE_TIMEOUT`, and
`SSH_PROBE_TIMEOUT` tune the two preflight checks.
