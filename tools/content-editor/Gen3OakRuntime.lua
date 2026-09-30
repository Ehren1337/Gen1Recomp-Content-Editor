local M={}
-- oakPrint looks its ROM line up by key; answer that one lookup with `line`.
function M.printLine(print,scene,key,speed,line)
  if not line then return print(scene,key,speed) end
  local RomText=require("src.core.game3.rom_text");local ascii=RomText.ascii
  RomText.ascii=function(_,ctx)
    RomText.ascii=ascii;ctx=ctx or {}
    return (line:gsub("{PLAYER}",function() return tostring(ctx.playerName or "") end)
      :gsub("{RIVAL}",function() return tostring(ctx.rivalName or "") end))
  end
  local ok,err=pcall(print,scene,key,speed);RomText.ascii=ascii
  if not ok then error(err,0) end
end
function M.configure(scene,settings,lines)
  settings=settings or {};scene._editorOakSettings=settings
  if settings.species then
    local picture=require("src.core.game3.pokemon").frontPic(settings.species)
    if picture then local assets={};for k,v in pairs(scene.assets) do assets[k]=v end;assets.nidoranFront=picture.image;scene.assets=assets end
  end
  if settings.textSpeed then scene.textSpeedOption=settings.textSpeed;scene.textSpeed=({[0]=8,4,1})[settings.textSpeed] end
  if settings.skipGuides then
    scene.bgVisible[0],scene.bgVisible[1]=true,true
    scene.tasks={};local task=scene:createTask(require("src.ui.game3.new_game_scene").Task_OakSpeech_Init,0);task.data.timer=0
  end
  if lines then
    local original=scene.oakPrint
    scene.oakPrint=function(self,key,speed) return M.printLine(original,self,key,speed,lines[key]) end
  end
  local frame=scene.frame
  scene.frame=function(self,...)
    local Audio=require("src.core.game3.audio");local cry=Audio.playCry
    Audio.playCry=function(species,...) return cry(species==29 and settings.species or species,...) end
    local result={pcall(frame,self,...)};Audio.playCry=cry
    if not result[1] then error(result[2]) end
    return unpack(result,2)
  end
  return scene
end
function M.install(mod,settings)
  local Scene=require("src.ui.game3.new_game_scene");local Runtime=require("src.mods.Runtime")
  if not Scene._editorOakScene then Scene._editorOakScene=true;local base=Scene.new
    Scene.new=function(...) return Runtime.call("editor.gen3.oakScene",base,...) end
  end
  mod.hooks:wrap("editor.gen3.oakScene",function(proceed,...)
    return M.configure(proceed(...),settings)
  end)
end
return M
