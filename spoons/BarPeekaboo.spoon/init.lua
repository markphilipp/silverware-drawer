--- === BarPeekaboo ===
---
--- Toggle the macOS menu bar based on which display is primary.
---
--- Built-in (laptop) display is main → menu bar always visible. External
--- display is main → menu bar always hidden. Reacts to display changes
--- (plug/unplug monitors, switching primary display) via `hs.screen.watcher`.
---
--- Usage in ~/.hammerspoon/init.lua:
---   hs.loadSpoon("BarPeekaboo")
---   spoon.BarPeekaboo:start()

local obj = {}
obj.__index = obj

obj.name = "BarPeekaboo"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

--- BarPeekaboo.builtinPattern
--- Variable
--- Lua pattern matched against the primary screen's name to decide whether the
--- built-in (laptop) display is main. Hammerspoon does not expose
--- `CGDisplayIsBuiltin`, so detection is name-based. Override per machine if the
--- built-in display reports a different name (e.g. "Color LCD", "Liquid Retina").
--- Change before calling `:start()`.
obj.builtinPattern = "Built%-in"

-- Last applied state ("builtin" / "external") for de-duping redundant toggles.
obj._lastState = nil

function obj:_isBuiltinMain()
  local primary = hs.screen.primaryScreen()
  if not primary then return false end
  return primary:name():find(self.builtinPattern) ~= nil
end

function obj:_setMenuBarAutoHide(hide)
  hs.osascript.applescript(string.format(
    'tell application "System Events" to tell dock preferences to set autohide menu bar to %s',
    tostring(hide)))
end

function obj:_apply()
  local state = self:_isBuiltinMain() and "builtin" or "external"
  if state == self._lastState then return end
  self._lastState = state

  if state == "builtin" then
    hs.printf("[BarPeekaboo] Built-in display is main — showing menu bar")
    self:_setMenuBarAutoHide(false)
  else
    hs.printf("[BarPeekaboo] External display is main — hiding menu bar")
    self:_setMenuBarAutoHide(true)
  end
end

--- BarPeekaboo:start() -> self
--- Method
--- Apply the menu bar state for the current display layout, then watch for
--- display configuration changes.
function obj:start()
  if self.watcher then self.watcher:stop() end
  self:_apply()
  self.watcher = hs.screen.watcher.new(function()
    -- Small delay to let macOS finish reconfiguring displays.
    hs.timer.doAfter(1, function() self:_apply() end)
  end)
  self.watcher:start()
  return self
end

--- BarPeekaboo:stop() -> self
--- Method
--- Stop watching for display changes.
function obj:stop()
  if self.watcher then
    self.watcher:stop()
    self.watcher = nil
  end
  return self
end

return obj
