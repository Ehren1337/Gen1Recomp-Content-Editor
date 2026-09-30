-- Emerald berry flavors (what the Berry Blender makes) and Pokeblock names.
-- Exported through Gen3Native, which patches berries/berries.lua on read.
local M={}
M.PATH="data/generated/gba/berries/berries.lua"
M.FIELDS={"spicy","dry","sweet","bitter","sour","smoothness"}
M.LABELS={spicy="Spicy",dry="Dry",sweet="Sweet",bitter="Bitter",sour="Sour",smoothness="Smoothness"}
M.COLORS=14
function M.pack(S)
  if S.data._g3BerryPack==nil then
    local bytes=S.data._gen3Read and S.data._gen3Read(M.PATH)
    S.data._g3BerryPack=bytes and load(bytes,"=berries","t",{})() or false
  end
  return S.data._g3BerryPack or nil
end
function M.indexOf(S,item)
  local pack=M.pack(S);local name=tostring(item.id or ""):match("^(.+)_BERRY$")
  if not pack or not name then return end
  for i,row in pairs(pack.berries or {}) do if row.name==name then return i,row end end
end
function M.used(p) return next((p.gen3Berries or {}).flavors or {})~=nil or next((p.gen3Berries or {}).names or {})~=nil end
function M.validate(p)
  if not M.used(p) then return end
  assert((p.game or p.version)=="emerald","Berry flavors and Pokeblock names need Emerald")
  for index,row in pairs(p.gen3Berries.flavors or {}) do
    assert(type(index)=="number" and index%1==0 and index>=0,"Invalid berry number")
    for _,key in ipairs(M.FIELDS) do
      local n=row[key];assert(type(n)=="number" and n%1==0 and n>=0 and n<=255,"Berry "..key.." must be 0 to 255")
    end
  end
  for color,name in pairs(p.gen3Berries.names or {}) do
    assert(type(color)=="number" and color>=1 and color<=M.COLORS and type(name)=="string","Invalid Pokeblock name")
  end
end
function M.draw(S,item,App,x,y,w,fh,s)
  if require("Generation").id(S)~="emerald" then return y end
  local Kit,PAL=require("Kit"),require("Theme").PAL
  local index,base=M.indexOf(S,item)
  local store=S.project.gen3Berries or {}
  if index then
    Kit.caption(x,y,"POKEBLOCK FLAVORS");y=y+22*s
    Kit.text("micro","Used by the Berry Blender to make Pokeblocks.",x,y,PAL.faint);y=y+20*s
    local row=(store.flavors or {})[index] or base
    for _,key in ipairs(M.FIELDS) do
      Kit.text("small",M.LABELS[key],x,y+6*s,PAL.caption)
      local cur=tonumber(row[key]) or 0
      local value=math.floor(math.max(0,math.min(255,require("RegList").num(App,"g3_berry_"..key,x+190*s,y,120*s,fh,cur))))
      if value~=cur then
        S.project.gen3Berries=store;store.flavors=store.flavors or {}
        local edit={};for _,k in ipairs(M.FIELDS) do edit[k]=tonumber(row[k]) or 0 end
        edit[key]=value;store.flavors[index]=edit;App.markDirty()
      end
      y=y+fh+8*s
    end
    if (store.flavors or {})[index] and Kit.button(x,y,160*s,fh,"Revert flavors",{}) then store.flavors[index]=nil;App.markDirty() end
    y=y+fh+8*s
  elseif item.id=="POKEBLOCK_CASE" then
    local names=(M.pack(S) or {}).pokeblockNames or {}
    Kit.caption(x,y,"POKEBLOCK NAMES");y=y+22*s
    for color=1,M.COLORS do
      local cur=(store.names or {})[color] or names[color] or ""
      Kit.text("small","Color "..color,x,y+6*s,PAL.caption)
      local value=Kit.textfield("g3_pokeblock_name_"..color,x+190*s,y,math.max(80*s,w-198*s),fh,cur,"")
      if value~=cur then
        S.project.gen3Berries=store;store.names=store.names or {}
        store.names[color]=value~=(names[color] or "") and value or nil;App.markDirty()
      end
      y=y+fh+8*s
    end
  end
  return y
end
return M
