-- GAME PATCHES > Physical/Special split (Emerald): each move is Physical or
-- Special by itself, as in Gen 4, instead of by its type.
local M={}
-- Gen 4 categories of the Gen 3 moves whose type says otherwise.
M.GEN4={
  [7]="physical",[8]="physical",[9]="physical",[13]="special",[16]="special",[22]="physical",
  [44]="physical",[49]="special",[51]="special",[63]="special",[75]="physical",[101]="special",
  [123]="special",[124]="special",[127]="physical",[128]="physical",[129]="special",[152]="physical",
  [161]="special",[168]="physical",[172]="physical",[173]="special",[177]="special",[185]="physical",
  [188]="special",[189]="special",[200]="physical",[209]="physical",[221]="physical",[228]="physical",
  [237]="special",[242]="physical",[246]="special",[247]="special",[251]="physical",[253]="special",
  [255]="special",[282]="physical",[291]="physical",[299]="physical",[301]="physical",[302]="physical",
  [304]="special",[311]="special",[314]="special",[318]="special",[324]="special",[331]="physical",
  [333]="physical",[337]="physical",[341]="special",[344]="physical",[348]="physical",[353]="special",
}
function M.enabled(p) return p.gen3Split==true end
function M.setEnabled(p,on)
  if M.enabled(p)==on then return false end
  p.gen3Split=on or nil
  return true
end
-- The Moves tab's Category starts at the Gen 4 one.
function M.applyDefaults(moves)
  for _,rec in pairs(moves) do
    local category=M.GEN4[tonumber(rec.index)]
    if category and (tonumber(rec.power) or 0)>0 then rec.category=category end
  end
end
function M.emit(p,encode,out)
  if not M.enabled(p) then return end
  assert((p.game or p.version)=="emerald","The Physical/Special split needs Emerald")
  local moves={}
  for id,rec in pairs((p.gen3 or {}).moves or {}) do
    if rec.category~=nil then moves[id]=rec.category end
  end
  out[#out+1]="local split=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3SplitRuntime.lua")).."\nend)()\nsplit.install(mod,"..encode({defaults=M.GEN4,moves=moves})..")"
end
return M
