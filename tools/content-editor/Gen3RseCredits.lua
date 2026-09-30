-- Emerald end credits: 5-line pages from the imported credits_rse manifest.
local M={}
local Copy=require("src.mods.Merge").deepCopy
M.MANIFEST="data/generated/gba/credits_rse/manifest.lua"
local function rgb(c) return {(c%32)/31,(math.floor(c/32)%32)/31,(math.floor(c/1024)%32)/31,1} end
function M.manifest(S)
 if not S.data._g3RseCredits then
  local m=require("Gen3Resources").readTable(S.data,M.MANIFEST)
  if not m.pages then return nil,"Missing Gen 3 cache: "..M.MANIFEST end
  S.data._g3RseCredits=m
 end
 return S.data._g3RseCredits
end
function M.validate(pages)
 assert(type(pages)=="table" and #pages>0 and #pages<=200,"Choose between 1 and 200 credits pages")
 for _,page in ipairs(pages) do
  assert(#page==5,"Each credits page has 5 lines")
  for _,line in ipairs(page) do assert(type(line.text)=="string" and #line.text<=60,"Credit lines are limited to 60 characters") end
 end
end
local function preview(S,page,palette)
 S._g3RseCreditsCanvas=S._g3RseCreditsCanvas or love.graphics.newCanvas(240,160)
 local g=love.graphics;local old=g.getCanvas();g.push("all");g.setCanvas(S._g3RseCreditsCanvas);g.origin();g.setScissor();g.clear(0,0,0,1)
 local Font=require("src.ui.game3.frlg_font")
 for i,line in ipairs(page) do if line.text~="" then
  local colors=line.isTitle and {fg=rgb(palette[4]),shadow=rgb(palette[5]),bg={0,0,0,0}} or {fg=rgb(palette[2]),shadow=rgb(palette[3]),bg={0,0,0,0}}
  local x=math.floor((240-Font.measure(line.text,{letterSpacing=1}))/2)
  Font.draw(line.text,x,81+(i-1)*16,{colors=colors,letterSpacing=1})
 end end
 g.setCanvas(old);g.pop();g.setColor(1,1,1,1)
 return S._g3RseCreditsCanvas
end
function M.draw(S,x,y,w,h,App)
 local K,C=require("Kit"),require("ChoicePicker");local s=K.scale;local fh=28*s
 local m,err=M.manifest(S);if not m then K.caption(x,y,err);return end
 local config=S.project.gen3Screens or {};local pages=config.emeraldCredits or m.pages
 local selected=math.min(S.g3RseCreditsPage or 1,#pages);local page=pages[selected]
 local function edit()
  S.project.gen3Screens=S.project.gen3Screens or {};local c=S.project.gen3Screens
  c.emeraldCredits=c.emeraldCredits or Copy(m.pages);c.emeraldCreditsEnabled=true;App.markDirty()
  return c.emeraldCredits[selected],c.emeraldCredits
 end
 local ids,labels={},{}
 for i,p in ipairs(pages) do
  local name="";for _,line in ipairs(p) do if line.text~="" then name=line.text;break end end
  ids[i]=i;labels[i]=i..". "..name
 end
 C.field(S,{x=x,y=y,w=w*.62,h=fh,ids=ids,labels=labels,current=selected,title="Choose a credits page",onPick=function(v) S.g3RseCreditsPage=v end})
 local on=config.emeraldCredits and config.emeraldCreditsEnabled~=false
 if K.button(x+w*.65,y,w*.35,fh,on and "Disable in game" or "Enable in game",{}) then
  if on then config.emeraldCreditsEnabled=false;App.markDirty() else edit() end
 end
 y=y+40*s
 local fw=w*.54;local px=x+w*.58;local scale=math.min((w*.42)/240,(h-100*s)/160,3)
 local canvas=preview(S,page,m.palette);canvas:setFilter("nearest","nearest");love.graphics.draw(canvas,px,y,0,scale,scale)
 K.caption(px,y+160*scale+8*s,"Plays after the Hall of Fame.")
 local fy=y
 for i,line in ipairs(page) do
  local text=K.textfield("g3rsecredit"..selected.."_"..i,x,fy,fw*.74,fh,line.text,"")
  if text~=line.text then edit()[i].text=text end
  if K.button(x+fw*.76,fy,fw*.24,fh,line.isTitle and "Heading" or "Name",{}) then local p=edit();p[i].isTitle=not p[i].isTitle end
  fy=fy+36*s
 end
 fy=fy+8*s
 if K.button(x,fy,fw*.48,fh,"Add page",{}) then
  local _,r=edit();local blank={};for i=1,5 do blank[i]={isTitle=false,text=""} end
  blank[2]={isTitle=true,text="New credit"};blank[3]={isTitle=false,text="Your name"}
  table.insert(r,selected+1,blank);S.g3RseCreditsPage=selected+1
 end
 if #pages>1 and K.button(x+fw*.52,fy,fw*.48,fh,"Delete page",{kind="danger"}) then local _,r=edit();table.remove(r,selected);S.g3RseCreditsPage=math.min(selected,#r) end
 fy=fy+40*s
 if K.button(x,fy,fw*.48,fh,"Move earlier",{}) and selected>1 then local _,r=edit();r[selected],r[selected-1]=r[selected-1],r[selected];S.g3RseCreditsPage=selected-1 end
 if K.button(x+fw*.52,fy,fw*.48,fh,"Move later",{}) and selected<#pages then local _,r=edit();r[selected],r[selected+1]=r[selected+1],r[selected];S.g3RseCreditsPage=selected+1 end
 fy=fy+40*s
 if config.emeraldCredits and K.button(x,fy,fw,fh,"Revert to original credits",{}) then config.emeraldCredits=nil;config.emeraldCreditsEnabled=nil;S.g3RseCreditsPage=1;App.markDirty() end
end
return M
