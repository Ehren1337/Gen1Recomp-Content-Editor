package.path="tools/content-editor/?.lua;"..package.path
local Rename=require("Gen3MapIdentity").rename
local S={mapId="OLD",builderMapId="OLD",data={maps={VANILLA={}}},project={
  maps={OLD={id="OLD",_isNew=true,name="Display name",_layeredSource="OLD"},
    OTHER={warps={{destMap="OLD"}},connections={{map="OLD"}}}},
  layeredMaps={OLD={id="OLD",layers={{cells={}}}}},
  mapWarpNodes={a={map="OLD"},b={targetMap="OLD",targetNode="a"}},
  gen3Terrain={OLD={[1]={coll=0}}},gen3MapLayouts={OLD={source="VANILLA"}},
  gen3={maps={OLD={id="OLD"}},map_scripts={TEST={{op="warp",map="OLD"},{op="message",text="OLD"}}}},
  gen3Modes={maps={OLD="register"}},gen3WorkspaceMaps={OLD=true}}}
assert(not Rename(S,"OLD","VANILLA"));assert(S.project.maps.OLD)
assert(not Rename(S,"OLD","bad id"));assert(S.project.maps.OLD)
assert(Rename(S,"OLD","NEW"))
local p=S.project
assert(not p.maps.OLD and p.maps.NEW.id=="NEW" and p.maps.NEW._layeredSource=="NEW")
assert(p.maps.NEW.name=="Display name" and p.maps.OTHER.warps[1].destMap=="NEW")
assert(p.maps.OTHER.connections[1].map=="NEW")
assert(p.layeredMaps.NEW.id=="NEW" and p.gen3Terrain.NEW[1].coll==0)
assert(p.mapWarpNodes.a.map=="NEW" and p.mapWarpNodes.b.targetMap=="NEW")
assert(p.gen3.map_scripts.TEST[1].map=="NEW" and p.gen3.map_scripts.TEST[2].text=="OLD")
assert(p.gen3Modes.maps.NEW=="register" and p.gen3WorkspaceMaps.NEW)
assert(S.mapId=="NEW" and S.builderMapId=="NEW")
assert(not Rename(S,"OTHER","ANOTHER"),"Vanilla map identity must stay stable")
assert(loadfile("tools/content-editor/Gen3MapEvents.lua"))
print("PASS: new map ID, project references, metadata, invalid IDs and collisions")
