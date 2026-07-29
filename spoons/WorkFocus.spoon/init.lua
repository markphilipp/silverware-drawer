local obj = {}
obj.__index = obj

--- Keeps macOS Work Focus on while active and clears it after five minutes idle.
obj.name = "WorkFocus"
obj.version = "0.1.0"
obj.author = "Mark Philipp"
obj.homepage = "https://github.com/markphilipp/silverware-drawer"
obj.license = "MIT"

obj.idleAfter = 5 * 60
obj.checkEvery = 10
obj._desiredOn = nil
obj._running = false

--- Shortcuts.app shortcut names, each built with a single "Set Focus" action.
--- Create these once in Shortcuts.app (Work Focus On -> turn on, Work Focus Off -> turn off).
obj.shortcutOn = "Work Focus On"
obj.shortcutOff = "Work Focus Off"

function obj:_setFocus(on)
  self._desiredOn = on
  if self._task then return end

  local shortcutName = on and self.shortcutOn or self.shortcutOff
  self._task = hs.task.new("/usr/bin/shortcuts", function(code, _, stderr)
    self._task = nil
    if code ~= 0 then
      hs.printf("[WorkFocus] failed to run shortcut '%s': %s", shortcutName, stderr or code)
    end
    if self._running then self:_sync() end
  end, {"run", shortcutName})
  self._task:start()
end

function obj:_sync()
  local shouldBeOn = hs.host.idleTime() <= self.idleAfter
  if shouldBeOn ~= self._desiredOn then
    self:_setFocus(shouldBeOn)
  end
end

function obj:_handleEvent(event)
  local w = hs.caffeinate.watcher
  if event == w.screensDidUnlock then
    self:_setFocus(true)
  elseif event == w.screensDidLock then
    self:_setFocus(false)
  end
end

function obj:start()
  if self.timer then self.timer:stop() end
  if self.watcher then self.watcher:stop() end
  self._running = true
  self._desiredOn = nil
  self.watcher = hs.caffeinate.watcher.new(function(event)
    self:_handleEvent(event)
  end)
  self.watcher:start()
  self:_sync()
  self.timer = hs.timer.doEvery(self.checkEvery, function() self:_sync() end)
  return self
end

function obj:stop()
  self._running = false
  if self.watcher then
    self.watcher:stop()
    self.watcher = nil
  end
  if self.timer then
    self.timer:stop()
    self.timer = nil
  end
  if self._task then
    self._task:terminate()
    self._task = nil
  end
  return self
end

return obj
