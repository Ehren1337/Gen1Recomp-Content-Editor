-- Emerald's Professor Birch intro. Lines are the game's own gText_ strings,
-- saved as ordinary Gen 3 text edits so the Dialog export carries them.
local M={}
local Dialog=require("Gen3Dialog")
M.order={"gText_Birch_Welcome","gText_ThisIsAPokemon","gText_Birch_MainSpeech","gText_Birch_AndYouAre","gText_Birch_BoyOrGirl","gText_BirchBoy","gText_BirchGirl",
  "gText_Birch_WhatsYourName","gText_Birch_SoItsPlayer","gText_Birch_YourePlayer","gText_Birch_AreYouReady"}
M.labels={gText_Birch_Welcome="Welcome and professor introduction",gText_ThisIsAPokemon="Showing Lotad",gText_Birch_MainSpeech="The Pokemon world",
  gText_Birch_AndYouAre="Asking who you are",gText_Birch_BoyOrGirl="Choosing boy or girl",gText_BirchBoy="Boy option",gText_BirchGirl="Girl option",
  gText_Birch_WhatsYourName="Asking your name",gText_Birch_SoItsPlayer="Confirming your name",
  gText_Birch_YourePlayer="Moving to Littleroot",gText_Birch_AreYouReady="Starting the adventure"}
local function line(S,key) return S.project.text[key] or S.data.text[key] end
function M.scene(S,x,y,w,h,App)
  local K,C=require("Kit"),require("ChoicePicker");local scale=K.scale
  local settings=S.project.gen3BirchScene or {};local left=math.min(350*scale,w*.36)
  K.caption(x,y,"Text speed");local yy=y+26*scale
  C.field(S,{x=x,y=yy,w=left,h=30*scale,ids={"0","1","2"},labels={["0"]="Slow",["1"]="Normal",["2"]="Fast"},current=tostring(settings.textSpeed or 1),onPick=function(id)
    S.project.gen3BirchScene={textSpeed=tonumber(id)};App.markDirty()
  end});yy=yy+48*scale
  if K.button(x,yy,left,30*scale,"Play / restart intro",{kind="good"}) then require("Gen3IntroPreview").play(S,"birch") end;yy=yy+42*scale
  local p=S.g3IntroPreview
  if p and p.kind=="birch" then
    if K.button(x,yy,left,28*scale,p.paused and "Resume" or "Pause",{}) then p.paused=not p.paused end;yy=yy+38*scale
    for i,key in ipairs({"a","b","up","down","left","right","start","select"}) do
      local col=(i-1)%2;local row=math.floor((i-1)/2)
      if K.button(x+col*(left/2+2*scale),yy+row*34*scale,left/2-4*scale,28*scale,key:upper(),{}) then p.keys=p.keys or {};p.keys[key]=true;p.paused=false end
    end
    local canvas=require("Gen3IntroPreview").render(S)
    if canvas then local zoom=math.min((w-left-24*scale)/240,(h-70*scale)/160);love.graphics.setColor(1,1,1,1);love.graphics.draw(canvas,x+left+24*scale,y,0,zoom,zoom) end
    if p.error then K.caption(x,y+h-28*scale,K.ellipsize("micro",p.error,w))
    elseif p.birch and p.birch.result then K.caption(x+left+24*scale,y+h-28*scale,"Intro finished. Restart to play again.") end
  else K.caption(x+left+24*scale,y,"Play the full intro, then use the buttons to advance and choose a name.") end
  K.caption(x,y+h-52*scale,"Restart the preview after changing settings or dialogue.")
end
function M.draw(S,x,y,w,h,App)
  local K,C=require("Kit"),require("ChoicePicker");local scale=K.scale
  require("Gen3ContentAdapter").prepare(S)
  local top=require("RegList").modeChips(S,"g3OakMode",{{id="scene",label="Full intro"},{id="dialogue",label="Dialogue"},{id="artwork",label="Artwork"}},x,y,scale)
  h=h-(top-y);y=top
  if S.g3OakMode=="artwork" then
    return require("Gen3Assets").draw(S,x,y,w,h,App,function(path) return path:find("/birch/",1,true) end)
  end
  if S.g3OakMode~="dialogue" then return M.scene(S,x,y,w,h,App) end
  S.g3BirchLine=S.g3BirchLine or M.order[1];local id=S.g3BirchLine
  C.field(S,{x=x,y=y,w=w,h=30*scale,ids=M.order,labels=M.labels,current=id,onPick=function(v) S.g3BirchLine=v;S.g3OakPage=1 end});y=y+42*scale
  local original=line(S,id)
  if not original then K.caption(x,y,"Missing Gen 3 cache text: "..id);return end
  K.caption(x,y,"Edit the speech. Keep {PLAYER} where the player's name should appear.");y=y+30*scale
  K.caption(x,y,"Use \\n for a new line and \\p for the next dialogue page.");y=y+30*scale
  local field=Dialog.toField(Dialog.display(original))
  local edited=K.textfield("g3_birch_text_"..id,x,y,w,40*scale,field,"");y=y+52*scale
  if edited~=field then
    S.project.text[id]=Dialog.encode((edited:gsub("\\p","\n\n"):gsub("\\n","\n")),original);App.markDirty()
  end
  local text=Dialog.display(line(S,id)):gsub("\n\n","\f")
  Dialog.preview(S,text,x,y,math.min(w,700*scale),{page=S.g3OakPage or 1})
  y=y+180*scale
  for i,d in ipairs({-1,1}) do if K.button(x+(i-1)*150*scale,y,140*scale,28*scale,d==-1 and "Previous page" or "Next page",{}) then S.g3OakPage=select(1,Dialog.step(text,S.g3OakPage,d)) end end
  y=y+40*scale
  if K.button(x,y,220*scale,28*scale,"Restore this original line",{}) then S.project.text[id]=nil;App.markDirty() end
  y=y+40*scale;K.caption(x,y,"Use Artwork to change Birch, the player and the intro background.")
end
function M.emit(p,encode,out)
  local settings=p.gen3BirchScene
  if not settings then return end
  assert(settings.textSpeed==0 or settings.textSpeed==1 or settings.textSpeed==2,"Invalid intro text speed")
  out[#out+1]="  local birchScene="..encode(settings)
  out[#out+1]=[=[
  local Birch=require("src.ui.game3.rse.birch_speech")
  local Runtime=require("src.mods.Runtime")
  if not Birch._editorBirchBridge then
    Birch._editorBirchBridge=true;local original=Birch.new
    Birch.new=function(...) return Runtime.call("editor.gen3.birchScene",original,...) end
  end
  mod.hooks:wrap("editor.gen3.birchScene",function(proceed,...)
    local scene=proceed(...)
    scene.textSpeedOption=birchScene.textSpeed
    scene.textSpeed=require("src.ui.game3.rse.scene_kit").textSpeedDelay(birchScene.textSpeed)
    return scene
  end)
]=]
end
return M
