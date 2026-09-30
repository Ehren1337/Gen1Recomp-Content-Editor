-- Original Pokemon pictures and in-game trades, from the imported cache.
local M={}
function M.shiny(S,species,back)
  return M.formPicture(S,species,back,0,0,true)
end
-- A 64x64 picture. The cache bakes each Castform frame with its own palette
-- as <index>_<frame>.rgba, so the palette frame always follows the frame.
function M.formPicture(S,species,back,frame,_,shiny)
  if type(species)~="number" or species%1~=0 or species<0 or species>439 then
    return nil,"This species has no original artwork"
  end
  frame=frame or 0
  -- "handled" is Emerald's second Deoxys picture (Speed Forme).
  local suffix=frame=="handled" and "_handled" or frame>0 and "_"..frame or ""
  local path="data/generated/gba/pokemon/"..(back and "back" or "front")..(shiny and "_shiny" or "")
    .."/"..species..suffix..".rgba"
  local read=S.data and S.data._gen3Read or require("src.import.CacheFs").readActive
  local bytes=read(path)
  if not bytes or #bytes~=64*64*4 then return nil,"Missing Gen 3 cache: "..path end
  return love.image.newImageData(64,64,"rgba8",bytes)
end
-- The game's in-game trades, from the imported cache (src/data/ingame_trades.h).
function M.trades(S)
  if S.data._g3RomTrades then return S.data._g3RomTrades end
  local path="data/generated/gba/trades/ingame_trades.lua"
  local bytes=S.data._gen3Read and S.data._gen3Read(path)
  if not bytes then return {},"Missing Gen 3 cache: "..path end
  local pack,err=require("Gen3Decode").decode(bytes,{allowArray=true,allowComments=true})
  if type(pack)~="table" or type(pack.trades)~="table" then return {},path..": "..tostring(err) end
  local species={};for id,rec in pairs(require("Gen3").catalog(S.data,"pokemon")) do species[rec.index]=id end
  local out={}
  for i,t in pairs(pack.trades) do
    out["ROM_"..i]={give=species[t.requestedSpecies],get=species[t.species],nickname=t.nickname,otName=t.otName,
      otId=t.otId,ivs=t.ivs,abilityNum=t.abilityNum,personality=t.personality,heldItem=t.heldItem,otGender=t.otGender,nativeIndex=i}
  end
  S.data._g3RomTrades=out;return out
end
return M
