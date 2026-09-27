package.path="tools/content-editor/?.lua;runtime/gen1recomp/?.lua;"..package.path
local root=assert(os.getenv("POKEPORT_GEN3_CACHE"),"Set POKEPORT_GEN3_CACHE").."/data/generated/gba/scripts/"
local scripts=dofile(root.."scripts.lua")
local P=require("Gen3CutscenePreview")
for _,id in ipairs({"EventScript_AccessHallOfFame","EventScript_AfterWhiteOutHeal","g3:0816eb5d"}) do
 for _,flag in ipairs({false,true}) do
  local p=P.new(scripts[id],{objects={{localId=1,x=1,y=1}}},function(r) return r.ptr or r.value or r[2] or r[1] end,1,function(k) return scripts[k] end,id)
  p.movements=dofile(root.."movements.lua")
  for i=1,1000 do
   if p.prompt then P.answer(p,p.prompt.kind=="flag" and flag or 127) end
   P.step(p)
   if p.error or p.done then break end
  end
  assert(p.done and not p.error, id..": "..tostring(p.error or "did not finish"))
  print("PASS",id,tostring(flag))
 end
end

