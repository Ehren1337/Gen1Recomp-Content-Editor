package.path='tools/content-editor/?.lua;runtime/gen1recomp/?.lua;'..package.path
local root=assert(os.getenv('POKEPORT_GEN3_CACHE'))..'/data/generated/gba/scripts/'
local scripts=dofile(root..'scripts.lua');local maps=dofile(root..'events.lua');local movements=dofile(root..'movements.lua')
local texts=dofile(root..'text.lua')
local P=require('Gen3CutscenePreview');local contexts={};local cases={};local attachments=0
for mapId,map in pairs(maps) do
 for _,kind in ipairs({'objects','bgEvents','coordEvents'}) do
  for i,event in ipairs(map[kind] or {}) do if event.scriptKey then contexts[event.scriptKey]={map=map,actor=kind=='objects' and (event.localId or i) or nil};attachments=attachments+1;cases[#cases+1]={id=event.scriptKey,ctx=contexts[event.scriptKey],attachment=mapId..'/'..kind..'/'..i} end end
 end
end
for mapId,map in pairs(maps) do
 local function hooks(value,path)
  if type(value)=='string' and scripts[value] then
   attachments=attachments+1;cases[#cases+1]={id=value,ctx={map=map},attachment=mapId..'/mapScripts/'..path}
  elseif type(value)=='table' then for k,v in pairs(value) do hooks(v,path..'/'..tostring(k)) end end
 end
 hooks(map.mapScripts,'')
end
local totals={scripts=0,runs=0,complete=0,bounded=0,errors=0,crashes=0};local failures,omitted={},{}
for id in pairs(scripts) do totals.scripts=totals.scripts+1;cases[#cases+1]={id=id,ctx=contexts[id]} end
local eventStops,eventRuns,eventComplete=0,0,0;local eventFailures={};local details={}
table.sort(cases,function(a,b) return (a.attachment or a.id)<(b.attachment or b.id) end)
for _,case in ipairs(cases) do
 local detail={id=case.id,location=case.attachment or 'Standalone script',runs={},references={}};details[#details+1]=detail
 local visited={}
 local function inspect(id)
  if visited[id] then return end;visited[id]=true
  if not scripts[id] then detail.references[#detail.references+1]='Missing script '..tostring(id);return end
  for i,r in ipairs(scripts[id]) do
   local op=r.op
   if op=='call' or op=='goto' or op=='call_if' or op=='goto_if' then inspect(r.target or r[(op=='call' or op=='goto') and 1 or 2]) end
   if op=='applymovement' then local key=r.movement or r[2];if type(key)~='table' and not movements[key] then detail.references[#detail.references+1]=id..':'..i..' missing movement '..tostring(key) end end
   if op=='message' or (op=='loadword' and (r.dest or r[1])==0) then
    local key=op=='message' and (r.ptr or r[1]) or (r.value or r[2])
    if type(key)=='string' and not texts[key] then detail.references[#detail.references+1]=id..':'..i..' missing text '..key end
   end
  end
 end
 inspect(case.id)
 local id=case.id;local rows=scripts[id] or {{op='missing_script'}}
 for _,value in ipairs({0,1,127}) do
  totals.runs=totals.runs+1
  local ctx=case.ctx or {};if case.attachment then eventRuns=eventRuns+1 end
  local p=P.new(rows,ctx.map,function(r) local key=r.op=='loadword' and (r.value or r[2]) or (r.ptr or r[1]);local ir=texts[key];if ir then return type(ir)=='string' and ir or '[Resolved imported dialogue]' end end,ctx.actor,function(k) return scripts[k] end,id);p.movements=movements
  local ok,err=pcall(function()
   for n=1,300 do
    if p.prompt then local kind=p.prompt.kind;P.answer(p,kind=='flag' and value==1 or value) end
    P.step(p);if p.done or p.error then break end
   end
  end)
  local notes={};for op in pairs(p.notes) do notes[#notes+1]=op end;table.sort(notes)
  detail.runs[#detail.runs+1]={input=value,status=not ok and 'CRASH' or p.error and 'STOP' or p.done and (#notes>0 and 'COMPLETED_WITH_OMISSIONS' or 'COMPLETED') or 'LIMIT',reason=tostring(err or p.error or ''),script=p.script,command=p.index,omissions=notes}
  for op in pairs(p.notes) do omitted[op]=(omitted[op] or 0)+1 end
  if not ok or p.error then
   if case.attachment then eventStops=eventStops+1;eventFailures[#eventFailures+1]=case.attachment.." / "..tostring(p.script).." command "..p.index end
   local reason=tostring(err or p.error);local key=reason
   failures[key]=failures[key] or {count=0,example=id};failures[key].count=failures[key].count+1
   if not ok then totals.crashes=totals.crashes+1 else totals.errors=totals.errors+1 end
  elseif p.done then totals.complete=totals.complete+1;if case.attachment then eventComplete=eventComplete+1 end else totals.bounded=totals.bounded+1 end
 end
end
local out={'# Imported FireRed cutscene preview audit','','Three sampled input policies (0, 1, 127), at most 300 commands each. This checks preview execution, not every branch or game-effect fidelity. Dialogue references use the imported text table; direct map-event and map-hook contexts are included. Static checks traverse every reachable branch for missing scripts, movement routes and text. The on-disk firered_hgss_voxel mod contains no event overrides or editor_project.lua; unsaved editor changes are not available to this audit.',''}
for _,key in ipairs({'scripts','runs','complete','bounded','errors','crashes'}) do out[#out+1]=key..': '..totals[key] end
out[#out+1]='\nMap-event attachments: '..attachments..'; runs: '..eventRuns..'; completed: '..eventComplete..'; stops: '..eventStops..'; bounded: '..(eventRuns-eventComplete-eventStops)
 out[#out+1]='\nCompletion includes omitted effects and automatically answered prompts; it does not establish game fidelity.\n'
 for _,failure in ipairs(eventFailures) do out[#out+1]='- Map-event stop: '..failure end
 out[#out+1]='\n## Remaining execution stops\n'
local keys={};for k in pairs(failures) do keys[#keys+1]=k end;table.sort(keys)
for _,k in ipairs(keys) do out[#out+1]='- '..failures[k].count..' runs: '..k..' (example '..failures[k].example..')' end
out[#out+1]='\n## Effects omitted or approximated\n';keys={};for k in pairs(omitted) do keys[#keys+1]=k end;table.sort(keys)
for _,k in ipairs(keys) do out[#out+1]='- '..k..': '..omitted[k]..' runs' end
local json=require('src.link.Json');local results=assert(io.open('tests/content-editor/cutscene-event-results.json','w'));results:write(json.encode(details));results:close()
out[#out+1]='\nPer-event results: cutscene-event-results.json ('..#details..' records).\n'
local f=assert(io.open('tests/content-editor/cutscene-audit.md','w'));f:write(table.concat(out,'\n'));f:close()
for k,v in pairs(totals) do print(k,v) end
