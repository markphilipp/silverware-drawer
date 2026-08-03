--- === PullMyMainFinger ===
---
--- Fast-forward every repo's default branch under ~/Projects, whenever the
--- screen locks.
---
--- Scans the projects root for git repos and brings each one's default branch
--- (main/master/…) up to date with origin. A branch checked out with
--- uncommitted changes is stashed, pulled, and restored; any conflict rolls the
--- repo back to its prior state and skips it, so nothing is ever clobbered.
---
--- Triggers on screen lock (you're stepping away, so it's a good time to hit
--- the network), gated so it only actually runs if it's been at least
--- `minHoursBetweenRuns` since the last successful run, and skipped outright if
--- the SSH agent has no usable identities (e.g. 1Password is locked) — no point
--- running a batch of fetches we already know will fail auth. The actual work
--- lives in refresh-default-branches.sh, run off the main thread via hs.task;
--- call :run() to trigger a refresh by hand (this still checks the SSH agent,
--- but ignores the minHoursBetweenRuns gate).
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("PullMyMainFinger")
---   spoon.PullMyMainFinger:start()

local obj = {}
obj.__index = obj

obj.name = "PullMyMainFinger"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

-- Resolve the bundled shell script relative to this file (survives symlinking).
obj.spoonPath = debug.getinfo(1, "S").source:sub(2):match("(.*/)")

--- PullMyMainFinger.root
--- Variable
--- Projects root scanned for git repos. Default `~/Projects`. Change before `:start()`.
obj.root = os.getenv("HOME") .. "/Projects"

--- PullMyMainFinger.minHoursBetweenRuns
--- Variable
--- Minimum hours since the last successful run before a screen-lock will
--- trigger another one. Default 8.
obj.minHoursBetweenRuns = 8

--- PullMyMainFinger.sshAuthSock
--- Variable
--- SSH agent socket exported to the refresh job so fetches over SSH authenticate
--- when run outside a login shell. Defaults to the 1Password agent socket, then
--- to the inherited `SSH_AUTH_SOCK`. Set to a path (or false to skip) per machine.
obj.sshAuthSock = os.getenv("HOME")
  .. "/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"

--- PullMyMainFinger.notifyOnIssues
--- Variable
--- Post an `hs.notify` summary, including each skip/failure line, only when a
--- run has skips or failures. Default true. Set false to silence
--- notifications entirely.
obj.notifyOnIssues = true

obj._lastSuccessKey = "PullMyMainFinger.lastSuccess"

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

local function shQuote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- ssh-add exits non-zero both when it can't reach the agent and when the
-- agent is reachable but has no identities (1Password locked) — either way
-- fetches would fail auth, so treat both as "not usable right now".
function obj:_sshAgentUnusable()
  local sock = self.sshAuthSock
  if sock == nil then sock = os.getenv("SSH_AUTH_SOCK") end
  if not sock then return false end
  local _, ok = hs.execute("SSH_AUTH_SOCK=" .. shQuote(sock) .. " /usr/bin/ssh-add -l >/dev/null 2>&1")
  return not ok
end

--- PullMyMainFinger:run() -> self
--- Method
--- Refresh all default branches now, asynchronously. No-op if a run is
--- already in progress, or if the SSH agent has no usable identities (we
--- already know every fetch would fail auth).
function obj:run()
  if self._task and self._task:isRunning() then
    hs.printf("[PullMyMainFinger] run already in progress")
    return self
  end
  if self:_sshAgentUnusable() then
    hs.printf("[PullMyMainFinger] SSH agent has no usable identities (locked?) — skipping run")
    return self
  end
  local script = self.spoonPath .. "refresh-default-branches.sh"
  hs.printf("[PullMyMainFinger] refreshing default branches under %s", self.root)
  self._task = hs.task.new("/bin/bash", function(code, stdout, stderr)
    self._task = nil
    if code == 0 then hs.settings.set(self._lastSuccessKey, os.time()) end
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
  hs.printf("[PullMyMainFinger] done: %d refreshed, %d skipped, %d failed (exit %d)",
    refreshed, skipped, failed, code)
  if stdout ~= "" then hs.printf("[PullMyMainFinger]\n%s", stdout) end
  if stderr ~= "" then hs.printf("[PullMyMainFinger] stderr:\n%s", stderr) end

  if self.notifyOnIssues then
    -- Diverged-history skips are routine and already logged above; they don't
    -- need a human's attention the way a stash conflict or a real failure does.
    local issues = {}
    for line in stdout:gmatch("[^\n]+") do
      if (line:match("^skip%s") or line:match("^FAIL%s"))
        and not line:match("not fast%-forwardable") then
        table.insert(issues, line)
      end
    end
    if #issues > 0 then
      hs.notify.new({
        title = "PullMyMainFinger",
        informativeText = string.format("%d refreshed · %d skipped · %d failed\n%s",
          refreshed, skipped, failed, table.concat(issues, "\n")),
        withdrawAfter = 0,
      }):send()
    end
  end
end

-- True once it's been at least minHoursBetweenRuns since the last successful run.
function obj:_dueForRun()
  local last = hs.settings.get(self._lastSuccessKey) or 0
  return (os.time() - last) >= self.minHoursBetweenRuns * 3600
end

function obj:_onScreenLock()
  if not self:_dueForRun() then return end
  hs.printf("[PullMyMainFinger] screen locked, no successful run in %dh — attempting refresh",
    self.minHoursBetweenRuns)
  self:run()
end

--- PullMyMainFinger:start() -> self
--- Method
--- Watch for the screen locking and attempt a refresh each time, gated by
--- minHoursBetweenRuns and the SSH agent check.
function obj:start()
  self:stop()
  local w = hs.caffeinate.watcher
  self._watcher = w.new(function(event)
    if event == w.screensDidLock then self:_onScreenLock() end
  end)
  self._watcher:start()
  hs.printf("[PullMyMainFinger] watching for screen lock (root %s)", self.root)
  return self
end

--- PullMyMainFinger:stop() -> self
--- Method
--- Stop watching for screen lock. A run already in flight finishes.
function obj:stop()
  if self._watcher then self._watcher:stop(); self._watcher = nil end
  return self
end

return obj
