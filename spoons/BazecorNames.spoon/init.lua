local obj = {}
obj.__index = obj

--- Syncs Bazecor layer/macro/superkey names between machines through an iCloud file.
obj.name = "BazecorNames"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

obj.python = "/usr/bin/python3"
obj.checkEvery = 600
obj.debounce = 3
obj.configDir = os.getenv("HOME") .. "/Library/Application Support/Bazecor"
obj.sharedDir = os.getenv("HOME") .. "/Library/Mobile Documents/com~apple~CloudDocs/Bazecor"
obj.stateFile = os.getenv("HOME") .. "/.local/state/bazecor-sync/last-hash"

local script = hs.spoons.scriptPath() .. "sync.py"

function obj:_sync()
  if self._task then
    self._again = true
    return
  end
  local task
  task = hs.task.new(self.python, function(code, stdout, stderr)
    if self._task ~= task then return end
    self._task = nil
    if code ~= 0 then
      hs.printf("[BazecorNames] sync failed: %s", stderr ~= "" and stderr or code)
    elseif stdout:find("pushed") or stdout:find("pulled") then
      hs.printf("[BazecorNames] %s", stdout:gsub("%s+$", ""))
    end
    if not self._running then return end
    if self._sharedMissing and hs.fs.attributes(self.sharedDir) then self:_arm() end
    if self._again then
      self._again = false
      self:_sync()
    end
  end, {"-I", script})
  self._task = task
  -- sync.py reads its paths from the environment, so the options reach it here.
  local env = task:environment()
  env.BAZECOR_CONFIG = self.configDir .. "/config.json"
  env.BAZECOR_SYNC_FILE = self.sharedDir .. "/names.json"
  env.BAZECOR_SYNC_STATE = self.stateFile
  task:setEnvironment(env)
  if not task:start() then
    self._task = nil
    hs.printf("[BazecorNames] could not launch %s", self.python)
  end
end

function obj:_schedule()
  if self._debounce then self._debounce:stop() end
  self._debounce = hs.timer.doAfter(self.debounce, function() self:_sync() end)
end

function obj:_watch(dir, file)
  local suffix = "/" .. file:gsub("%p", "%%%0")
  return hs.pathwatcher.new(dir, function(paths)
    for _, p in ipairs(paths) do
      if p:match(suffix .. "$") then
        self:_schedule()
        return
      end
    end
  end)
end

function obj:_arm()
  for _, w in ipairs(self._watchers or {}) do w:stop() end
  -- A watcher on a folder that doesn't exist yet (iCloud's Bazecor/ before the first push) never fires.
  self._sharedMissing = not hs.fs.attributes(self.sharedDir)
  self._watchers = {
    self:_watch(self.configDir, "config.json"),
    self:_watch(self.sharedDir, "names.json"),
  }
  for _, w in ipairs(self._watchers) do w:start() end
end

function obj:start()
  self:stop()
  self._running = true
  self:_arm()
  self._apps = hs.application.watcher.new(function(name, event)
    if name == "Bazecor" and event == hs.application.watcher.terminated then
      self:_schedule()
    end
  end)
  self._apps:start()
  self._timer = hs.timer.doEvery(self.checkEvery, function() self:_sync() end)
  self:_sync()
  return self
end

function obj:stop()
  self._running = false
  for _, w in ipairs(self._watchers or {}) do w:stop() end
  self._watchers = nil
  self._sharedMissing = nil
  if self._apps then self._apps:stop(); self._apps = nil end
  if self._timer then self._timer:stop(); self._timer = nil end
  if self._debounce then self._debounce:stop(); self._debounce = nil end
  if self._task then
    local task = self._task
    self._task = nil
    task:terminate()
  end
  self._again = false
  return self
end

return obj
