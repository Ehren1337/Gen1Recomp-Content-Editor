-- FireRed / LeafGreen credits and area previews, from the imported cache.
local M={}
M.areas={
  {id="altering_cave",name="Altering Cave",mapsec=183},
  {id="berry_forest",name="Berry Forest",mapsec=176},
  {id="cerulean_cave",name="Cerulean Cave",mapsec=141},
  {id="digletts_cave",name="Digletts Cave",mapsec=131},
  {id="dotted_hole",name="Dotted Hole",mapsec=180},
  {id="icefall_cave",name="Icefall Cave",mapsec=177},
  {id="lost_cave",name="Lost Cave",mapsec=181},
  {id="monean_chamber",name="Monean Chamber",mapsec=188},
  {id="mt_ember",name="Mt Ember",mapsec=175},
  {id="mt_moon",name="Mt Moon",mapsec=127},
  {id="pokemon_mansion",name="Pokemon Mansion",mapsec=135},
  {id="pokemon_tower",name="Pokemon Tower",mapsec=140},
  {id="power_plant",name="Power Plant",mapsec=142},
  {id="rock_tunnel",name="Rock Tunnel",mapsec=138},
  {id="rocket_hideout",name="Rocket Hideout",mapsec=133},
  {id="rocket_warehouse",name="Rocket Warehouse",mapsec=178},
  {id="safari_zone",name="Safari Zone",mapsec=136},
  {id="seafoam_islands",name="Seafoam Islands",mapsec=139},
  {id="silph_co",name="Silph Co",mapsec=134},
  {id="victory_road",name="Victory Road",mapsec=132},
  {id="viridian_forest",name="Viridian Forest",mapsec=126},
}
-- Files in data/generated/gba/credits; mon_<n>_<frame> follows the pack's mons order.
M.creditArt={
 {id="blastoise_1",name="Blastoise 1",file="mon_2_1",width=80,height=80},
 {id="blastoise_2",name="Blastoise 2",file="mon_2_2",width=80,height=96},
 {id="charizard_1",name="Charizard 1",file="mon_0_1",width=80,height=80},
 {id="charizard_2",name="Charizard 2",file="mon_0_2",width=96,height=104},
 {id="pikachu_1",name="Pikachu 1",file="mon_3_1",width=80,height=80},
 {id="pikachu_2",name="Pikachu 2",file="mon_3_2",width=96,height=96},
 {id="venusaur_1",name="Venusaur 1",file="mon_1_1",width=80,height=80},
 {id="venusaur_2",name="Venusaur 2",file="mon_1_2",width=96,height=80},
 {id="copyright",name="Copyright",file="copyright",width=240,height=160},
 {id="ground_city",name="Ground City",file="ground_city",width=64,height=256},
 {id="ground_dirt",name="Ground Dirt",file="ground_dirt",width=64,height=256},
 {id="ground_grass",name="Ground Grass",file="ground_grass",width=64,height=256},
 {id="player_female",name="Player Female",file="player_female",width=64,height=384},
 {id="player_male",name="Player Male",file="player_male",width=64,height=384},
 {id="rival",name="Rival",file="rival",width=64,height=384},
 {id="the_end",name="The End",file="the_end",width=240,height=160},
 {id="circle_screen",name="circle screen",file="circle",width=256,height=256},
 {id="copyright_screen",name="copyright screen",file="copyright",width=240,height=160},
 {id="the_end_screen",name="the end screen",file="the_end",width=240,height=160},
 {id="ball_charizard",name="ball charizard",file="pokeball_0",width=240,height=160},
 {id="ball_venusaur",name="ball venusaur",file="pokeball_1",width=240,height=160},
 {id="ball_blastoise",name="ball blastoise",file="pokeball_2",width=240,height=160},
 {id="ball_pikachu",name="ball pikachu",file="pokeball_3",width=240,height=160},
}
for id,species in pairs({charizard=6,venusaur=3,blastoise=9,pikachu=25}) do
 M.creditArt[#M.creditArt+1]={id=id.."_front",name=id.." normal pose",path="pokemon/front/"..species,width=64,height=64}
end
local function read(S,path)
 local reader=S.data and S.data._gen3Read or require("src.import.CacheFs").readActive
 return reader("data/generated/gba/"..path)
end
function M.image(S,kind,id)
 S.data=S.data or {}
 local cache=S.data._g3ScreenImages or {};S.data._g3ScreenImages=cache
 local key=kind..id;if cache[key] then return cache[key] end
 local rec;for _,r in ipairs(kind=="areas" and M.areas or M.creditArt) do if r.id==id then rec=r end end
 if not rec then return nil,"Choose an image" end
 local path=kind=="areas" and "map_preview/"..rec.mapsec or rec.path or "credits/"..rec.file
 local w,h=rec.width or 240,rec.height or 160
 local bytes=read(S,path..".rgba")
 if not bytes or #bytes<w*h*4 then return nil,"Missing Gen 3 cache: data/generated/gba/"..path..".rgba" end
 local img=love.image.newImageData(w,h,"rgba8",bytes:sub(1,w*h*4))
 cache[key]=img;return img
end
local function lines(text)
 local out={};for line in (text:gsub("{CLEAR_TO %d+}","").."\n"):gmatch("(.-)\n") do out[#out+1]=line end
 return out
end
function M.credits(S)
 S.data=S.data or {}
 if S.data._g3CreditPages then return S.data._g3CreditPages end
 local bytes=read(S,"credits/pack.lua")
 if not bytes then return nil,"Missing Gen 3 cache: data/generated/gba/credits/pack.lua" end
 local pack,err=require("Gen3Decode").decode(bytes,{allowArray=true,allowComments=true})
 if type(pack)~="table" or type(pack.texts)~="table" then return nil,"credits/pack.lua: "..tostring(err) end
 local rows={}
 for i=0,41 do
  local page=pack.texts[i] or {}
  local headings,names=lines(page.title or ""),lines(page.names or "")
  local text={}
  for j=1,math.max(#headings,#names) do
   if headings[j] and headings[j]:match("%S") then text[#text+1]=headings[j] end
   if names[j] and names[j]:match("%S") then text[#text+1]=names[j] end
  end
  local title=table.remove(text,1) or "Credits"
  rows[#rows+1]={title=title,text=table.concat(text,"\n"),seconds=6,art="none"}
 end
 local ordered={}
 for _,c in ipairs(require("Gen3CreditsSequence").commands) do if c.op=="text" and rows[c.page] then
  local row=rows[c.page];row.seconds=c.frames/60;ordered[#ordered+1]=row
 end end
 rows=ordered
 rows[#rows+1]={title="THE END",text="",seconds=6,art="the_end"}
 S.data._g3CreditPages=rows;return rows
end
return M
