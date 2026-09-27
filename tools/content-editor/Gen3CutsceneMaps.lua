local M={}
-- Follow only script control-flow references, not arbitrary strings in dialogue.
function M.locations(base,edits,scripts,wanted)
  local maps={};for id,map in pairs(base or {}) do maps[id]=map end
  for id,map in pairs(edits or {}) do maps[id]=map end
  local reaches={[wanted]=true};local reverse={}
  for id,rows in pairs(scripts) do for _,row in ipairs(rows) do
    if row.op=="call" or row.op=="goto" or row.op=="call_if" or row.op=="goto_if" then
      local target=row.target or row[(row.op=="call" or row.op=="goto") and 1 or 2]
      if target then reverse[target]=reverse[target] or {};reverse[target][id]=true end
    end
  end end
  local queue={wanted};local i=1
  while queue[i] do
    for id in pairs(reverse[queue[i]] or {}) do if not reaches[id] then reaches[id]=true;queue[#queue+1]=id end end
    i=i+1
  end
  local out={}
  local function attached(value,seen)
    if type(value)=="string" then return reaches[value] end
    if type(value)~="table" or seen[value] then return false end
    seen[value]=true;for _,v in pairs(value) do if attached(v,seen) then return true end end
    return false
  end
  for id,map in pairs(maps) do
    for _,kind in ipairs({"objects","signs","bgEvents","coordEvents","mapScripts"}) do
      if kind~="bgEvents" or not map.signs then
        for index,event in pairs(map[kind] or {}) do
          if attached(event,{}) then
            out[#out+1]={key=id.."/"..kind.."/"..index,map=id,kind=kind,index=index,event=event,
              actor=kind=="objects" and (event.localId or index) or nil}
          end
        end
      end
    end
  end
  table.sort(out,function(a,b) return a.key<b.key end);return out,maps
end
function M.camera(width,height,w,h,focus,zoom,overview)
  local scale=overview and math.min((w-16)/(width*16),(h-16)/(height*16)) or (zoom or 3)
  scale=math.max(.05,scale)
  local vw,vh=math.min(width*16,(w-16)/scale),math.min(height*16,(h-16)/scale)
  local cx=math.max(0,math.min(width*16-vw,((focus and focus.x or 0)+.5)*16-vw/2))
  local cy=math.max(0,math.min(height*16-vh,((focus and focus.y or 0)+.5)*16-vh/2))
  return {scale=scale,x=cx,y=cy,w=vw,h=vh,ox=(w-vw*scale)/2,oy=(h-vh*scale)/2}
end
function M.draw(S,mapId,p,x,y,w,h)
  local K=require("Kit");K.card(x,y,w,h,5)
  if not mapId then K.caption(x+12,y+12,"No attached map found. Open this script from a map event.");return end
  local layered=(S.project.layeredMaps or {})[mapId]
  local layout,err=require("Gen3Map").layout(S.data,mapId,S.project)
  if not layout then K.caption(x+12,y+12,tostring(err));return end
  local width,height=layout.width,layout.height
  local focus=p.actors[p.activeActor or p.talker or 255] or p.actors[255]
  local camera=M.camera(width,height,w,h,focus,(S._cutsceneZoom or 3)*K.scale,S._cutsceneOverview)
  local scale=camera.scale
  local ox,oy=x+camera.ox,y+camera.oy
  K.pushClip(x,y,w,h);love.graphics.push("all");love.graphics.translate(ox,oy);love.graphics.scale(scale)
  if layered then
    require("LayeredMap").previewRenderer(S,layered,mapId):draw(camera.x,camera.y,camera.w,camera.h)
    love.graphics.translate(-camera.x,-camera.y)
  else
    love.graphics.translate(-camera.x,-camera.y)
    for cy=math.floor(camera.y/16),math.min(height-1,math.ceil((camera.y+camera.h)/16)) do
      for cx=math.floor(camera.x/16),math.min(width-1,math.ceil((camera.x+camera.w)/16)) do
      local cell=require("Gen3Map").cell(S.project,mapId,layout,cx,cy)
      require("Gen3Workspace").drawTile(S,{nativePair=layout.pair},cell.mid,cx*16,cy*16,16,1)
    end end
  end
  local actors={};for id,a in pairs(p.actors) do actors[#actors+1]={id=id,a=a} end
  table.sort(actors,function(a,b) return a.a.y<b.a.y end)
  for _,entry in ipairs(actors) do local a=entry.a
    if not a.hidden then
      if not require("Gen3MapSprites").draw(S,a,a.x*16,a.y*16) then
        love.graphics.setColor(.3,.7,1,1);love.graphics.rectangle("line",a.x*16,a.y*16,16,16)
      end
    end
  end
  if focus and not focus.hidden then
    love.graphics.setColor(1,.85,.25,1);love.graphics.setLineWidth(1/scale)
    love.graphics.rectangle("line",focus.x*16-1,focus.y*16-1,18,18)
  end
  love.graphics.pop();K.popClip()
end
return M
