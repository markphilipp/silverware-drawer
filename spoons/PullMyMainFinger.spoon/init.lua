--- === PullMyMainFinger ===
---
--- Fast-forward every repo's default branch under ~/Projects while you're away
--- from the keyboard.
---
--- Scans the projects root for git repos and brings each one's default branch
--- (main/master/…) up to date with origin. A branch checked out with
--- uncommitted changes is stashed, pulled, and restored; any conflict rolls the
--- repo back to its prior state and skips it, so nothing is ever clobbered.
---
--- Triggers once the Mac has been idle for `idleMinutes` **with the screen
--- still unlocked**, and only if it's been at least `minHoursBetweenRuns` since
--- the last successful run. The unlocked part is the whole point: a locked
--- screen also locks 1Password, and its SSH agent then refuses to sign, so
--- every fetch sits waiting on an authorization prompt nobody is there to
--- answer.
---
--- A run in flight is cancelled as soon as you touch the machine or the screen
--- locks. Cancellation is cooperative — the script finishes the repo it's on
--- and stops there, so no repo is ever left mid stash/pull/restore.
---
--- This is best effort, and the logging reflects that: every outcome goes to
--- the Hammerspoon console, and the only thing that reaches Notification
--- Center is a repo a human has to touch — never a locked agent, a dropped
--- network, or a branch that just can't be fast-forwarded. At most one such
--- notification is ever posted; a newer one replaces it.
---
--- The actual work lives in refresh-default-branches.sh, run off the main
--- thread via hs.task; call :run() to trigger a refresh by hand (this ignores
--- both the idle and minHoursBetweenRuns gates).
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("PullMyMainFinger")
---   spoon.PullMyMainFinger:start()

local obj = {}
obj.__index = obj

obj.name = "PullMyMainFinger"
obj.version = "0.3.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

-- Resolve the bundled shell script relative to this file (survives symlinking).
obj.spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

--- PullMyMainFinger.root
--- Variable
--- Projects root scanned for git repos. Default `~/Projects`. Change before `:start()`.
obj.root = os.getenv("HOME") .. "/Projects"

--- PullMyMainFinger.idleMinutes
--- Variable
--- Minutes of no keyboard/mouse activity (screen still unlocked) before a run
--- starts. Default 5.
obj.idleMinutes = 5

--- PullMyMainFinger.pollSeconds
--- Variable
--- How often idle state is checked, both to start a run and to cancel one
--- that's in flight. Default 60. A screen lock cancels immediately regardless,
--- via the caffeinate watcher.
obj.pollSeconds = 60

--- PullMyMainFinger.retryAfterCancelMinutes
--- Variable
--- Minutes to wait after a cancelled run before idle can trigger another.
--- Without it, sitting still while reading restarts the whole scan every
--- `idleMinutes`. Default 30.
obj.retryAfterCancelMinutes = 30

--- PullMyMainFinger.minHoursBetweenRuns
--- Variable
--- Minimum hours since the last successful run before going idle will trigger
--- another one. Default 8.
obj.minHoursBetweenRuns = 8

--- PullMyMainFinger.sshAuthSock
--- Variable
--- SSH agent socket exported to the refresh job so fetches over SSH authenticate
--- when run outside a login shell. Defaults to the 1Password agent socket, then
--- to the inherited `SSH_AUTH_SOCK`. Set to a path (or false to skip) per machine.
obj.sshAuthSock = os.getenv("HOME")
  .. "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

--- PullMyMainFinger.retryAfterDeferralMinutes
--- Variable
--- Minutes to wait after any attempt before another one may start. A run that
--- deferred (1Password locked, no network) would defer again a minute later,
--- and the poll interval is a minute — without this gate, which advances on
--- every attempt rather than only on success, one locked agent means a retry
--- (and a console line) every minute until you come back. Default 60.
obj.retryAfterDeferralMinutes = 60

--- PullMyMainFinger.notifyOnIssues
--- Variable
--- Post a single `hs.notify` when a run leaves a repo needing a human — a
--- stash conflict, or a git error the script can't classify. Default true. Set
--- false to silence notifications entirely; the console log is unaffected.
obj.notifyOnIssues = true

obj._lastSuccessKey = "PullMyMainFinger.lastSuccess"
obj._lastAttemptKey = "PullMyMainFinger.lastAttempt"

function obj:_env()
  local env = {
    HOME = os.getenv("HOME"),
    PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
    PROJECTS_ROOT = self.root,
  }
  local sock = self.sshAuthSock
  if sock == nil then sock = os.getenv("SSH_AUTH_SOCK") end
  if sock then env.SSH_AUTH_SOCK = sock end
  return env
end

--- PullMyMainFinger:run() -> self
--- Method
--- Refresh all default branches now, asynchronously. No-op if a run is already
--- in progress. The script itself proves the SSH agent can sign before it
--- touches any repo, and aborts the whole run on the first auth failure.
--- Ignores the idle and `minHoursBetweenRuns` gates, but still stamps the
--- attempt, so it pushes the next automatic run out by
--- `retryAfterDeferralMinutes`.
function obj:run()
  if self._task and self._task:isRunning() then
    hs.printf("[PullMyMainFinger] run already in progress")
    return self
  end
  local script = self.spoonPath .. "refresh-default-branches.sh"
  hs.printf("[PullMyMainFinger] refreshing default branches under %s", self.root)
  self._cancelled = false
  hs.settings.set(self._lastAttemptKey, os.time())
  self._task = hs.task.new("/bin/bash", function(code, stdout, stderr)
    local cancelled = self._cancelled
    self._task = nil
    if code == 0 then hs.settings.set(self._lastSuccessKey, os.time()) end
    self:_report(code, stdout or "", stderr or "", cancelled)
  end, { script })
  self._task:setEnvironment(self:_env())
  self._task:start()
  return self
end

--- PullMyMainFinger:cancel([reason]) -> self
--- Method
--- Stop a run in flight. The script finishes whichever repo it's on and stops
--- before the next one, so nothing is left half-done.
function obj:cancel(reason)
  if not (self._task and self._task:isRunning()) then return self end
  self._cancelled = true
  self._lastCancel = os.time()
  hs.printf("[PullMyMainFinger] cancelling run (%s)", reason or "requested")
  self._task:terminate()
  return self
end

-- One notification at a time: the previous one is withdrawn before the next is
-- posted, so Notification Center holds the current state rather than a history.
function obj:_notify(text)
  if self._notification then self._notification:withdraw() end
  self._notification = hs.notify.new({
    title = "PullMyMainFinger",
    -- This never auto-withdraws, so it must be dateable — otherwise one from
    -- days ago reads as a run that just finished.
    subTitle = os.date("%a %b %d, %I:%M %p"),
    informativeText = text,
    withdrawAfter = 0,
  })
  self._notification:send()
end

function obj:_report(code, stdout, stderr, cancelled)
  local refreshed = tonumber(stdout:match("refreshed=(%d+)")) or 0
  local skipped = tonumber(stdout:match("skipped=(%d+)")) or 0
  local attention = tonumber(stdout:match("attention=(%d+)")) or 0
  local deferred = tonumber(stdout:match("deferred=(%d+)")) or 0
  hs.printf("[PullMyMainFinger] %s: %d refreshed, %d skipped, %d needing attention, %d deferred (exit %d)",
    cancelled and "cancelled" or "done", refreshed, skipped, attention, deferred, code)
  if stdout ~= "" then hs.printf("[PullMyMainFinger]\n%s", stdout) end
  if stderr ~= "" then hs.printf("[PullMyMainFinger] stderr:\n%s", stderr) end

  -- A cancelled run stopped on purpose; whatever it hadn't reached isn't news.
  if cancelled or not self.notifyOnIssues then return end

  -- Everything above is already in the console. Only ATTN lines — a stash
  -- conflict, or a git error the script couldn't classify — describe a repo
  -- that stays stuck until someone opens it. A locked agent, a dropped
  -- network, and a branch that isn't fast-forwardable all clear themselves on
  -- a later run, which is the whole premise of a best-effort job.
  local stuck = {}
  for line in stdout:gmatch("[^\n]+") do
    local repo = line:match("^ATTN%s+(.+)$")
    if repo then table.insert(stuck, repo) end
  end
  if #stuck == 0 then return end
  if #stuck == 1 then
    self:_notify(stuck[1])
  else
    self:_notify(string.format("%d repos need attention — see the Hammerspoon console",
      #stuck))
  end
end

-- True once it's been minHoursBetweenRuns since the last complete pass AND
-- retryAfterDeferralMinutes since the last attempt of any kind. The second gate
-- is what keeps a deferral from looping: the success stamp doesn't move when a
-- run can't finish, so on its own the first gate stays open forever and the
-- poll retries every tick.
function obj:_dueForRun()
  local now = os.time()
  if (now - (hs.settings.get(self._lastSuccessKey) or 0)) < self.minHoursBetweenRuns * 3600 then
    return false
  end
  return (now - (hs.settings.get(self._lastAttemptKey) or 0))
    >= self.retryAfterDeferralMinutes * 60
end

-- Lock state comes from the caffeinate watcher; this only seeds it at :start(),
-- since Apple's session dictionary spells the key without the usual `k` prefix
-- and simply omits it while unlocked.
local function screenLockedNow()
  local props = hs.caffeinate.sessionProperties()
  if not props then return false end
  local locked = props.CGSSessionScreenIsLocked
  if locked == nil then locked = props.kCGSSessionScreenIsLockedKey end
  return locked ~= nil and locked ~= false and locked ~= 0
end

function obj:_screenLocked()
  return self._locked == true
end

-- Someone touched the machine since roughly the last poll (idleTime resets to
-- zero on any HID event), or the screen locked — which locks the SSH agent too.
function obj:_userIsBack()
  return self:_screenLocked() or hs.host.idleTime() < self.pollSeconds * 2
end

function obj:_tick()
  if self._task and self._task:isRunning() then
    if self:_userIsBack() then self:cancel("machine back in use") end
    return
  end
  if self:_screenLocked() then return end
  if hs.host.idleTime() < self.idleMinutes * 60 then return end
  if not self:_dueForRun() then return end
  if self._lastCancel
    and (os.time() - self._lastCancel) < self.retryAfterCancelMinutes * 60 then
    return
  end
  hs.printf("[PullMyMainFinger] idle %d min, unlocked, no complete pass in %dh — refreshing",
    self.idleMinutes, self.minHoursBetweenRuns)
  self:run()
end

--- PullMyMainFinger:start() -> self
--- Method
--- Poll idle state and refresh once the machine has been idle and unlocked for
--- `idleMinutes`, gated by `minHoursBetweenRuns`. Also cancels a run in flight
--- the moment the machine is used again or the screen locks.
function obj:start()
  self:stop()
  self._locked = screenLockedNow()
  local w = hs.caffeinate.watcher
  self._watcher = w.new(function(event)
    if event == w.screensDidLock then
      self._locked = true
      self:cancel("screen locked")
    elseif event == w.screensDidUnlock then
      self._locked = false
    end
  end)
  self._watcher:start()
  self._timer = hs.timer.new(self.pollSeconds, function() self:_tick() end)
  self._timer:start()
  hs.printf("[PullMyMainFinger] watching for %d min idle (root %s)", self.idleMinutes, self.root)
  return self
end

--- PullMyMainFinger:stop() -> self
--- Method
--- Stop polling. A run already in flight finishes — call `:cancel()` for that.
function obj:stop()
  if self._timer then self._timer:stop(); self._timer = nil end
  if self._watcher then self._watcher:stop(); self._watcher = nil end
  return self
end

return obj
