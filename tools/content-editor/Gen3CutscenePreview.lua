-- Isolated, deliberately limited storyboard player; never executes game effects.
local M={}
local copy=require("src.mods.Merge").deepCopy
function M.new(steps,map,text,talker,resolve,script)
  local actors={}
  for i,row in ipairs((map or {}).objects or {}) do
    actors[row.localId or i]=copy(row)
  end
  actors[255]={x=0,y=0,graphicsId=0}
  return {steps=copy(steps),actors=actors,text=text,index=0,wait=0,playing=false,talker=talker,
    resolve=resolve,script=script,stack={},flags={},vars={},executed=0,notes={},warnings={}}
end
local function warn(p,message)
  p.notice=message;p.warnings[#p.warnings+1]={script=p.script,index=p.index,message=message}
  p.notes.preview_approximation=true
end
function M.answer(p,value)
  if not p.prompt then return end
  if p.prompt.kind=="flag" then
    p.flags[p.prompt.id]=value==true;p.result=value and 1 or 0
  elseif p.prompt.kind=="skip" then p.result=nil
  elseif p.prompt.kind=="comparison" then p.result=math.max(0,math.min(2,value))
  else p.vars[p.prompt.id]=value;p.result=nil end
  p.prompt=nil
end
local function jump(p,target,call)
  local rows=p.resolve and p.resolve(target)
  if type(rows)~="table" then warn(p,"Linked script unavailable: "..tostring(target).."; continuing after this command.");return end
  if call then
    if #p.stack>=64 then p.error="Preview call depth exceeded (possible loop).";return end
    p.stack[#p.stack+1]={steps=p.steps,index=p.index,script=p.script}
  end
  p.steps=copy(rows);p.index=0;p.script=target
end
local harmless={lock=true,lockall=true,release=true,releaseall=true,faceplayer=true,waitmessage=true,waitmovement=true}
local presentation={playse=true,waitse=true,playfanfare=true,waitfanfare=true,playbgm=true,
  playmoncry=true,waitmoncry=true,normalmsg=true,signmsg=true,
  savebgm=true,fadeoutbgm=true,fadeinbgm=true,fadedefaultbgm=true,fadenewbgm=true,
  textcolor=true,showmoneybox=true,hidemoneybox=true,updatemoneybox=true}
function M.step(p)
  if p.done or p.error or p.prompt then return end
  p.executed=p.executed+1
  if p.executed>10000 then p.error="Preview command limit reached (possible loop).";p.playing=false;return end
  p.wait=0;p.waiting=false;p.index=p.index+1
  local row=p.steps[p.index]
  if row and row.op=="return" and #p.stack>0 then
    local frame=table.remove(p.stack);p.steps=frame.steps;p.index=frame.index;p.script=frame.script;return
  end
  if not row or row.op=="end" or row.op=="return" then p.done=true;p.playing=false;return end
  local op=row.op
  if presentation[op] then
    p.notice=op=="textcolor" and "Text color recorded; preview uses its standard dialogue palette."
      or "Preview continues without rendering "..op.."."
    p.notes[op]=true
  elseif op=="special" or op=="waitstate" then
    p.notice="Game routine "..tostring(row.special or row[1] or op).." omitted from preview; game playtest is required for its effects."
    p.notes[op]=true;p.result=nil;p.vars={}
  elseif op=="checkflag" then
    local id=row.flag or row[1]
    if id==nil then p.error="Missing flag ID."
    elseif p.flags[id]==nil then p.prompt={kind="flag",id=id};p.playing=false
    else p.result=p.flags[id] and 1 or 0 end
  elseif op=="setflag" or op=="clearflag" then
    local id=row.flag or row[1];if id==nil then p.error="Missing flag ID." else p.flags[id]=op=="setflag" end
  elseif op=="setvar" then p.vars[row.var or row[1]]=row.value or row[2] or 0
  elseif op=="copyvar" or op=="setorcopyvar" or op=="addvar" or op=="subvar" then
    local id=row.var or row[1];local value=row.value or row[2]
    local source=(op=="copyvar" or (op=="setorcopyvar" and value>=0x4000)) and value
    local missing=source and p.vars[source]==nil and source or
      ((op=="addvar" or op=="subvar") and p.vars[id]==nil and id)
    if missing then p.prompt={kind="variable",id=missing};p.index=p.index-1;p.playing=false
    else
      value=source and p.vars[source] or value
      if op=="addvar" then value=p.vars[id]+value elseif op=="subvar" then value=p.vars[id]-value end
      p.vars[id]=value%65536
    end
  elseif op=="compare_var_to_value" or op=="compare_var_to_var" then
    local id=row.var or row[1];local other=row.value or row[2]
    local missing=p.vars[id]==nil and id or (op=="compare_var_to_var" and p.vars[other]==nil and other)
    if missing then p.prompt={kind="variable",id=missing};p.index=p.index-1;p.playing=false
    else
      local a,b=p.vars[id],op=="compare_var_to_var" and p.vars[other] or other
      p.result=a<b and 0 or a==b and 1 or 2
    end
  elseif op=="goto" or op=="call" then jump(p,row.target or row[1],op=="call")
  elseif op=="goto_if" or op=="call_if" then
    local c=row.cond or row[1];local r=p.result
    if r==nil then p.prompt={kind="comparison",id="comparison result (0 = less/false, 1 = equal/true, 2 = greater)"};p.index=p.index-1;p.playing=false
    elseif not ({[0]=true,true,true,true,true,true})[c] then p.error="Invalid conditional comparison."
    elseif (c==0 and r==0) or (c==1 and r==1) or (c==2 and r==2) or (c==3 and r<=1) or (c==4 and r>=1) or (c==5 and r~=1) then
      jump(p,row.target or row[2],op=="call_if")
    end
  elseif op=="loadword" and (row.dest or row[1])==0 then p.loadedText=p.text(row)
  elseif (op=="callstd" or op=="gotostd") and ({[2]=true,[3]=true,[4]=true,[6]=true})[row.std or row[1]] then
    if not p.loadedText then p.error="Standard dialogue could not be resolved."
    else p.dialogue=p.loadedText;p.waiting=true;p.playing=false
      if op=="gotostd" then p.steps={};p.index=0 end
    end
  elseif op=="message" then
    p.dialogue=p.text(row)
    if not p.dialogue then p.error="Dialogue could not be resolved." end
  elseif op=="closemessage" then p.dialogue=nil
  elseif op=="waitbuttonpress" then p.waiting=true;p.playing=false
  elseif op=="delay" then p.wait=math.max(0,tonumber(row.frames or row[1]) or 0)/60
  elseif op=="addobject" or op=="removeobject" or op=="setobjectxy" or op=="setobjectxyperm" or op=="turnobject" then
    local id=row.localId or row[1]
    if id==32783 and p.talker then id=p.talker
    elseif type(id)=="number" and id>=0x4000 then
      if p.vars[id]==nil then p.prompt={kind="variable",id=id};p.index=p.index-1;p.playing=false;return end
      id=p.vars[id]
    end
    local actor=p.actors[id]
    if not actor then warn(p,"Character "..tostring(id).." is absent from this map; "..op.." omitted.")
    elseif op=="addobject" then actor.hidden=false
    elseif op=="removeobject" then actor.hidden=true
    elseif op=="turnobject" then actor.facing=row.direction or row[2]
    else actor.x=row.x or row[2] or actor.x;actor.y=row.y or row[3] or actor.y end
  elseif op=="applymovement" then
    local id=row.localId or row[1]
    if id==32783 and p.talker then id=p.talker
    elseif type(id)=="number" and id>=0x4000 then
      if p.vars[id]==nil then p.prompt={kind="variable",id=id};p.index=p.index-1;p.playing=false;return end
      id=p.vars[id]
    end
    local actor=p.actors[id]
    if not actor then p.error="Character position is unknown. Select a map event to preview its actors."
    else
      local route=row.movement or row[2]
      if type(route)~="table" then route=p.movements and p.movements[route] end
      if type(route)~="table" then p.error="Movement route unavailable: "..tostring(row.movement or row[2])
    else
      -- Validate the entire route before changing its preview position.
      local nextActor=copy(actor)
      for _,byte in ipairs(route) do
        if byte==254 or byte==255 then break end
        local base,distance
        for _,group in ipairs({{8,19,8,1},{20,23,20,2},{29,32,29,1},{53,68,53,1},{70,73,70,1},{78,81,78,1},{166,169,166,1}}) do
          if byte>=group[1] and byte<=group[2] then base=group[3];distance=group[4];break end
        end
        if base then
          local dirs={{0,1},{0,-1},{-1,0},{1,0}};local dir=dirs[(byte-base)%4+1]
          nextActor.x=nextActor.x+dir[1]*distance;nextActor.y=nextActor.y+dir[2]*distance
        elseif byte>=0 and byte<=7 then nextActor.facing=byte%4
        elseif byte>=33 and byte<=48 then nextActor.facing=(byte-33)%4
        elseif byte==96 then nextActor.hidden=true
        elseif byte==97 then nextActor.hidden=false
        elseif (byte>=74 and byte<=77) or (byte>=82 and byte<=95) or (byte>=24 and byte<=28) or (byte>=98 and byte<=105) then
          p.notice="Movement gesture "..byte.." previewed at its endpoint."
        else p.error="Movement "..tostring(byte).." needs game playtest.";break end
      end
      if not p.error then p.actors[id]=nextActor;p.activeActor=id end
    end
    end
  elseif not harmless[op] then
    warn(p,"Not simulated: "..tostring(op)..". Preview continues without this game effect.")
    p.result=nil;p.notes[op]=true
  end
  if p.error then
    warn(p,p.error.." Preview continues without this effect.");p.error=nil
  end
end
function M.update(p,dt)
  if not p.playing or p.done or p.error then return end
  p.wait=p.wait-math.min(math.max(dt,0),.25)
  if p.wait<=0 then M.step(p);if p.wait==0 then p.wait=.35 end end
end
return M
