-- be-right-back loader.
--
-- Symlinked to ~/.hammerspoon/be-right-back.lua by install.sh and pulled in from
-- ~/.hammerspoon/init.lua with a single stable line:
--
--   require("be-right-back")
--
-- It reads the per-machine enabled set from be-right-back.config.lua (generated
-- by install.sh, never committed) and loads + starts each enabled spoon. The
-- config file lives next to Hammerspoon's config so the shared repo stays
-- machine-agnostic.
--
-- Config entries are either a spoon name string, or a table:
--   { name = "BarPeekaboo", opts = { builtinPattern = "Built%-in" } }
-- opts are assigned onto the spoon object before :start().

local cfg_path = hs.configdir .. "/be-right-back.config.lua"

local f = io.open(cfg_path)
if not f then
  hs.printf("[be-right-back] no config at %s — run install.sh", cfg_path)
  return
end
f:close()

local ok, config = pcall(dofile, cfg_path)
if not ok or type(config) ~= "table" then
  hs.printf("[be-right-back] failed to load config: %s", tostring(config))
  return
end

for _, entry in ipairs(config) do
  local name = type(entry) == "table" and entry.name or entry
  local started, err = pcall(function()
    hs.loadSpoon(name)
    if type(entry) == "table" and entry.opts then
      for k, v in pairs(entry.opts) do spoon[name][k] = v end
    end
    spoon[name]:start()
  end)
  if not started then
    hs.printf("[be-right-back] failed to start %s: %s", tostring(name), tostring(err))
  end
end
