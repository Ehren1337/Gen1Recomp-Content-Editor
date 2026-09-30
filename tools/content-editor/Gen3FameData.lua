-- Fame Checker defaults from the imported FireRed / LeafGreen cache
-- (data/generated/gba/fame_checker, extracted from fame_checker.c).
local M={}
M.names={"Professor Oak","Daisy","Brock","Misty","Lt. Surge","Erika","Koga","Sabrina","Blaine","Lorelei","Bruno","Agatha","Lance","Bill","Mr. Fuji","Giovanni"}
local DIR="data/generated/gba/fame_checker/"
-- pokefirered/src/fame_checker.c:265 sFameCheckerArrayNpcGraphicsIds
local ICON_GFX={
  {103,71,48,105,75,55},{55,48,61,105,35,105},{102,80,27,19,30,105},{102,81,43,39,29,105},
  {102,82,61,61,62,105},{102,83,22,29,83,105},{102,84,26,22,105,30},{102,25,85,85,105,41},
  {102,86,55,28,105,105},{77,77,32,105,17,35},{79,79,105,54,29,54},{75,54,54,105,75,35},
  {74,74,24,23,105,41},{72,18,32,89,89,89},{17,49,105,30,105,105},{87,55,55,87,91,55},
}
-- pokefirered/src/fame_checker.c:1342 CreatePersonPicSprite: people with their own art.
local OWN_ART={[1]=true,[2]=true,[14]=true,[15]=true}
-- Cache text marks pages with \p and scrolled lines with \l.
local function text(s) return (s:gsub("\\p","\f"):gsub("\\l","\n")) end
local function load(S)
  local read=S.data and S.data._gen3Read or require("src.import.CacheFs").readActive
  local function file(name) return assert(read(DIR..name),"Missing Gen 3 cache: "..DIR..name) end
  local function tbl(name) return assert(require("Gen3Decode").decode(file(name),{allowArray=true,allowComments=true})) end
  local function png(name,w,h)
    local bytes=file(name);assert(#bytes>=w*h*4,"Missing Gen 3 cache: "..DIR..name)
    local img=love.image.newImageData(w,h,"rgba8",bytes:sub(1,w*h*4))
    return love.data.encode("string","base64",img:encode("png"):getString())
  end
  local pack,info=tbl("pack.lua"),tbl("manifest.lua")
  local rows={}
  for i,name in ipairs(M.names) do
    local p=i-1
    local r={name=name,message=text(pack.quotes[p]),facts={},portrait=info.trainerPic[i],unlock="original"}
    if OWN_ART[i] then r.image=png(p..".rgba",info.portrait,info.portrait) end
    for j=1,6 do
      local body=text(pack.flavorText[p][j-1])
      local question,detail=body:match("^(.-)\f(.*)$")
      r.facts[j]={question=question or "About this person",text=detail or body,
        location=pack.originLocation[p][j-1],source=pack.originObject[p][j-1],graphics=ICON_GFX[i][j],unlock="original"}
    end
    rows[i]=r
  end
  rows[1].background=png("bg.rgba",info.width,info.height)
  return rows
end
function M.load(S)
  if S.data and S.data._g3Fame then return S.data._g3Fame end
  local ok,rows=pcall(load,S)
  if not ok then return nil,tostring(rows) end
  if S.data then S.data._g3Fame=rows end
  return rows
end
-- Upgrade metadata for existing projects without replacing edited text/artwork.
function M.enrich(rows,defaults)
  local copy=require("src.mods.Merge").deepCopy(rows)
  if defaults then
    copy[1].background=copy[1].background or defaults[1].background
    for i,r in ipairs(copy) do for j,f in ipairs(r.facts) do if f.graphics==nil then f.graphics=defaults[i].facts[j].graphics end end end
  end
  return copy
end
return M
