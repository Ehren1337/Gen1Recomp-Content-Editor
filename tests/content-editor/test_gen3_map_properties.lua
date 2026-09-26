local runtime = assert(arg[1], "Pass the Gen 3 runtime directory")
package.path = "tools/content-editor/?.lua;tools/content-editor/panels/?.lua;"
  .. runtime .. "/?.lua;" .. package.path
local Properties = require("Gen3MapProperties")
local Moves = require("src.core.game3.field_moves")
local Workspace = require("Gen3Workspace")
local reads=0
local existing={id="FR_CINNABAR_ISLAND"}
local imported={data={maps={},_gen3Read=function(path)
  assert(path=="data/generated/gba/map_tree/maps/3_8/header.json")
  reads=reads+1
  return '{"mapType":1,"cave":0,"allowEscaping":0}'
end},project={maps={FR_CINNABAR_ISLAND=existing}}}
assert(Properties.resolve(imported,existing).mapType==1)
assert(Properties.resolve(imported,existing).allowEscaping==0 and reads==1)
assert(existing.mapType==nil,"Viewing must not mutate old project maps")
assert(Workspace.compile(imported))
assert(imported.project.gen3.maps.FR_CINNABAR_ISLAND.mapType==1)
existing.mapType=4;existing.allowEscaping=1
assert(Properties.resolve(imported,existing).mapType==4)
assert(Properties.resolve(imported,existing).allowEscaping==1)
existing.allowEscaping=0
assert(Properties.resolve(imported,existing).allowEscaping==0)
local original = {id="TEST",width=10,height=9,pair="test",warps={{x=1,y=2}},music=42}
local map = require("src.mods.Merge").deepCopy(original)
local S = {mapId="TEST",project={maps={TEST=map}}}
for _,id in ipairs(Properties.ids) do
  assert(Properties.apply(map,id))
  assert(Moves.isOutdoors(map.mapType)==map.outdoor)
  assert(Moves.isDungeon(map.mapType,map.cave==1)==(id=="4"))
  assert(map.allowEscaping==(id=="4" and 1 or 0))
  assert(map.music==42 and map.warps[1].x==1 and map.width==10)
end
assert(not Properties.apply(map,"invalid"))
assert(Properties.apply(map,"4"))
assert(Workspace.compile(S))
local exported = S.project.gen3.maps.TEST
assert(exported.mapType==4 and exported.cave==1 and exported.allowEscaping==1)
assert(exported.environment=="CAVE" and exported.kind=="cave")
assert(original.mapType==nil and original.allowEscaping==nil)
-- Exercise the actual controls and ensure a manual escape override survives export.
local selected,dirty
package.loaded.Kit={scale=1,caption=function() end,button=function() return true end}
package.loaded.ChoicePicker={field=function(_,opts) selected=opts.onPick end}
local convert=Workspace.convert
Workspace.convert=function() return {} end
Properties.draw(S,map,0,0,280,{markDirty=function() dirty=(dirty or 0)+1 end})
assert(map.allowEscaping==0 and dirty==1)
assert(Workspace.compile(S))
assert(S.project.gen3.maps.TEST.allowEscaping==0)
selected("3")
assert(map.mapType==3 and map.cave==0 and map.allowEscaping==0 and dirty==2)
assert(Moves.isOutdoors(map.mapType))
Workspace.convert=convert
-- Lua serialization/reload preserves the numeric header flags (0 is significant).
local Writer=require("ModWriter")
assert(Workspace.compile(S))
local saved=assert(loadstring("return "..Writer.encodeLua(S.project.gen3.maps.TEST)))()
assert(saved.mapType==3 and saved.cave==0 and saved.allowEscaping==0)
for _,path in ipairs({"tools/content-editor/Gen3MapEvents.lua",
    "tools/content-editor/LayeredMap.lua", "tools/content-editor/panels/Maps.lua",
    "tools/content-editor/panels/MapsWorkspace.lua"}) do
  assert(loadfile(path))
end
print("PASS: map types, runtime field-move predicates, escape override, export and reload")
