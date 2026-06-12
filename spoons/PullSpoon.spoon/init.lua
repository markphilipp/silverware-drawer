--- === PullSpoon ===
---
--- Fast-forward every repo's default branch under ~/Projects, daily at 4am.
---
--- Scans the projects root for git repos and brings each one's default branch
--- (main/master/…) up to date with origin. A branch checked out with
--- uncommitted changes is stashed, pulled, and restored; any conflict rolls the
--- repo back to its prior state and skips it, so nothing is ever clobbered.
---
--- Runs on a daily schedule and catches up on wake if the Mac was asleep at the
--- scheduled time. The actual work lives in refresh-default-branches.sh, run
--- off the main thread via hs.task; call :run() to trigger a refresh by hand.
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("PullSpoon")
---   spoon.PullSpoon:start()

local obj = {}
obj.__index = obj

obj.name = "PullSpoon"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

-- Resolve the bundled shell script relative to this file (survives symlinking).
obj.spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

--- PullSpoon.root
--- Variable
--- Projects root scanned for git repos. Default `~/Projects`. Change before `:start()`.
obj.root = os.getenv("HOME") .. "/Projects"

--- PullSpoon.at
--- Variable
--- Daily run time as "HH:MM" (24h). Default "04:00". Change before `:start()`.
obj.at = "04:00"

--- PullSpoon.sshAuthSock
--- Variable
--- SSH agent socket exported to the refresh job so fetches over SSH authenticate
--- when run outside a login shell. Defaults to the 1Password agent socket, then
--- to the inherited `SSH_AUTH_SOCK`. Set to a path (or false to skip) per machine.
obj.sshAuthSock = os.getenv("HOME")
  .. "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

--- PullSpoon.notifyOnIssues
--- Variable
--- Post an `hs.notify` summary only when a run has skips or failures. Default
--- true. Set false to silence notifications entirely.
obj.notifyOnIssues = true

obj._settingsKey = "PullSpoon.lastRun"

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

--- PullSpoon:run() -> self
--- Method
--- Refresh all default branches now, asynchronously. No-op if a run is already
--- in progress.
function obj:run()
  if self._task and self._task:isRunning() then
    hs.printf("[PullSpoon] run already in progress")
    return self
  end
  local script = self.spoonPath .. "refresh-default-branches.sh"
  hs.printf("[PullSpoon] refreshing default branches under %s", self.root)
  self._task = hs.task.new("/bin/bash", function(code, stdout, stderr)
    self._task = nil
    hs.settings.set(self._settingsKey, os.time())
    self:_report(code, stdout or "", stderr or "")
  end, { script })
  self._task:setEnvironment(self:_env())
  self._task:start()
  return self
end

function obj:_report(code, stdout, stderr)
  local refreshed = tonumber(stdout:match("refreshed=(%d+)")) or 0
  local skipped = tonumber(stdout:match("skipped=(%d+)")) or 0
  local failed = tonumber(stdout:match("failed=(%d+)")) or 0
  hs.printf("[PullSpoon] done: %d refreshed, %d skipped, %d failed (exit %d)",
    refreshed, skipped, failed, code)
  if stdout ~= "" then hs.printf("[PullSpoon]\n%s", stdout) end
  if stderr ~= "" then hs.printf("[PullSpoon] stderr:\n%s", stderr) end

  if self.notifyOnIssues and (skipped + failed) > 0 then
    hs.notify.new({
      title = "PullSpoon",
      informativeText = string.format("%d refreshed · %d skipped · %d failed",
        refreshed, skipped, failed),
      withdrawAfter = 0,
    }):send()
  end
end

-- Today's scheduled instant (os.time) from the "HH:MM" string.
function obj:_scheduledToday()
  local hh, mm = self.at:match("(%d+):(%d+)")
  local t = os.date("*t")
  t.hour, t.min, t.sec = tonumber(hh), tonumber(mm), 0
  return os.time(t)
end

-- Run if the scheduled time has passed today but we haven't run since (i.e. the
-- Mac was asleep when the timer should have fired).
function obj:_catchUp()
  local scheduled = self:_scheduledToday()
  local last = hs.settings.get(self._settingsKey) or 0
  if os.time() >= scheduled and last < scheduled then
    hs.printf("[PullSpoon] missed %s while asleep — catching up", self.at)
    self:run()
  end
end

--- PullSpoon:start() -> self
--- Method
--- Schedule the daily refresh and the wake-up catch-up.
function obj:start()
  self:stop()
  self._timer = hs.timer.doAt(self.at, "1d", function() self:run() end)
  self._wake = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then self:_catchUp() end
  end)
  self._wake:start()
  hs.printf("[PullSpoon] scheduled daily at %s (root %s)", self.at, self.root)
  return self
end

--- PullSpoon:stop() -> self
--- Method
--- Cancel the schedule and wake watcher. A run already in flight finishes.
function obj:stop()
  if self._timer then self._timer:stop(); self._timer = nil end
  if self._wake then self._wake:stop(); self._wake = nil end
  return self
end

return obj
