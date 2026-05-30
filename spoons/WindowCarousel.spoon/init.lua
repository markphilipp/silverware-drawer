--- === WindowCarousel ===
---
--- Cycle through the focused app's windows with a hotkey.
---
--- Presses the hotkey to move focus to the next standard window belonging to
--- the frontmost application, in a stable order (sorted by window ID) so the
--- cycle is predictable. Wraps around at the end and is a no-op when the app
--- has one window or fewer.
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("WindowCarousel")
---   spoon.WindowCarousel:start()
---
--- Rebind the hotkey before :start():
---   spoon.WindowCarousel.mods = {"ctrl", "alt"}
---   spoon.WindowCarousel.key  = "tab"

local obj = {}
obj.__index = obj

obj.name = "WindowCarousel"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

--- WindowCarousel.mods
--- Variable
--- Modifier keys for the cycle hotkey. Change before calling `:start()`.
obj.mods = {"ctrl", "shift", "alt", "cmd"}

--- WindowCarousel.key
--- Variable
--- Key for the cycle hotkey. Change before calling `:start()`.
obj.key = "w"

-- Focus the next standard window of the frontmost app, in stable ID order.
function obj:cycle()
  local app = hs.application.frontmostApplication()
  if not app then return end

  local wins = hs.fnutils.filter(app:allWindows(), function(w)
    return w:isStandard()
  end)
  if #wins <= 1 then return end

  table.sort(wins, function(a, b) return a:id() < b:id() end)

  local focused = hs.window.focusedWindow()
  if not focused then wins[1]:focus() return end

  local index
  for i, w in ipairs(wins) do
    if w:id() == focused:id() then index = i break end
  end
  if not index then wins[1]:focus() return end

  wins[index % #wins + 1]:focus()
end

--- WindowCarousel:start() -> self
--- Method
--- Bind the cycle hotkey.
function obj:start()
  if self.hotkey then self.hotkey:delete() end
  self.hotkey = hs.hotkey.bind(self.mods, self.key, function() self:cycle() end)
  return self
end

--- WindowCarousel:stop() -> self
--- Method
--- Unbind the cycle hotkey.
function obj:stop()
  if self.hotkey then
    self.hotkey:delete()
    self.hotkey = nil
  end
  return self
end

return obj
