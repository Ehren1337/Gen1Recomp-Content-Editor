-- GAME PATCHES > System Clock (Emerald): on a new game the bedroom clock is
-- set from the PC's clock, with no clock screen.
local M={}
function M.enabled(p) return p.gen3SystemClock==true end
function M.setEnabled(p,on)
  if M.enabled(p)==on then return false end
  p.gen3SystemClock=on or nil
  return true
end
function M.emit(p,out)
  if not M.enabled(p) then return end
  assert((p.game or p.version)=="emerald","The System Clock patch needs Emerald")
  out[#out+1]="local systemClock=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3SystemClockRuntime.lua")).."\nend)()\nsystemClock.install(mod)"
end
return M
