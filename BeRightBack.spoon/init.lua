--- === BeRightBack ===
---
--- Run automations when you lock and unlock your Mac.
---
--- Core behavior: keep the display awake (caffeinated) indefinitely while you
--- are unlocked, and release it on lock so the screen sleeps normally. Extra
--- lock/unlock actions can be added with `:register`.
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("BeRightBack")
---   spoon.BeRightBack:start()
---
--- Add more actions:
---   spoon.BeRightBack:register({
---     onLock   = function() hs.spotify.pause() end,
---     onUnlock = function() hs.spotify.play() end,
---   })

local obj = {}
obj.__index = obj

obj.name = "BeRightBack"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/be-right-back"
obj.license = "MIT"

--- BeRightBack.assertion
--- Variable
--- The `hs.caffeinate` sleep type to suppress while unlocked. Default
--- "displayIdle" keeps the screen awake; set to "systemIdle" to also keep the
--- whole system awake. Change before calling `:start()`.
obj.assertion = "displayIdle"

-- Registered actions. Each is a table with optional onLock/onUnlock functions.
-- The caffeinate action is always run first; registered actions follow.
obj.actions = {}

-- Core caffeinate action: awake while unlocked, asleep-capable while locked.
function obj:_caffeinate(awake)
  hs.caffeinate.set(self.assertion, awake)
end

--- BeRightBack:register(action) -> self
--- Method
--- Add a lock/unlock action. `action` is a table with optional `onLock` and
--- `onUnlock` functions. Returns self for chaining.
function obj:register(action)
  table.insert(self.actions, action)
  return self
end

function obj:_dispatch(hook, awake)
  self:_caffeinate(awake)
  for _, action in ipairs(self.actions) do
    local fn = action[hook]
    if fn then
      local ok, err = pcall(fn)
      if not ok then
        hs.printf("[BeRightBack] %s action error: %s", hook, tostring(err))
      end
    end
  end
end

--- BeRightBack:start() -> self
--- Method
--- Begin watching for lock/unlock events. Applies the unlocked state
--- immediately (you are unlocked when this runs).
function obj:start()
  if self.watcher then self.watcher:stop() end
  local w = hs.caffeinate.watcher
  self.watcher = w.new(function(event)
    if event == w.screensDidLock then
      self:_dispatch("onLock", false)
    elseif event == w.screensDidUnlock then
      self:_dispatch("onUnlock", true)
    end
  end)
  self.watcher:start()
  -- Running now means the session is unlocked: caffeinate immediately.
  self:_dispatch("onUnlock", true)
  return self
end

--- BeRightBack:stop() -> self
--- Method
--- Stop watching and release the caffeinate assertion.
function obj:stop()
  if self.watcher then
    self.watcher:stop()
    self.watcher = nil
  end
  self:_caffeinate(false)
  return self
end

return obj
