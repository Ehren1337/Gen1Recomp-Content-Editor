-- Mini-game images already decoded in the imported cache. Entries with `key`
-- take file and size from that folder's manifest. Each game's list keeps
-- the order the animation preview draws from.
local M={}
M.emerald={
 slots={dir="rse_slot_machine",
  {name="Reel symbols",file="reel_symbols.png"},
  {name="Reel Time Pikachu",file="reel_time_pikachu.png"},
  {name="Reel Time machine",file="reel_time_machine_0.png"},
  {name="Reel Time explosion",file="reel_time_explosion.png"},
  {name="Reel background",file="reel_background_0.png"},
  {name="Numbers",file="numbers.png"},
 },
 crush={dir="berry_crush",
  {name="Berry Crush background",key="bg"},
  {name="Crusher graphics",key="crusher_base"},
  {name="Impact animation frames",key="impact"},
  {name="Powder sparkles",key="sparkle"},
  {name="Timer numbers",key="timer_digits"},
 },
 jump={dir="pokemon_jump",
  {name="Pokemon Jump background",key="bg"},
  {name="Venusaur graphics",key="venusaur"},
  {name="Bonus graphics",key="bonuses"},
  {name="Vine animation 1",key="vine1"},
  {name="Vine animation 2",key="vine2"},
  {name="Vine animation 3",key="vine3"},
  {name="Vine animation 4",key="vine4"},
  {name="Star animation",key="star"},
 },
 dodrio={dir="dodrio_berry_picking",
  {name="Berry Picking background",key="bg"},
  {name="Dodrio animation frames",key="dodrio"},
  {name="Berries",key="berries"},
  {name="Cloud",key="cloud"},
  {name="Status icons",key="status"},
  {name="Tree border tiles",key="tree_border_left"},
 },
}
-- FireRed and LeafGreen share Emerald's wireless mini-game folders; only
-- the Game Corner slot machine differs.
M.kanto={
 slots={dir="slot_machine",
  {name="Slot machine background",key="bg"},
  {name="Winning combinations",key="combos_window"},
  {name="Reel symbols",key="reel_icons"},
  {name="Clefairy animation frames",key="clefairy"},
  {name="Pressed button",key="button_pressed"},
 },
 crush=M.emerald.crush,jump=M.emerald.jump,dodrio=M.emerald.dodrio,
}
local function lists(S) return require("Generation").id(S)=="emerald" and M.emerald or M.kanto end
function M.list(S,game) return lists(S)[game] end
local function cacheImage(S,game,rec)
 local dir="data/generated/gba/"..lists(S)[game].dir.."/"
 if rec.file then
  local bytes=S.data._gen3Read(dir..rec.file);if not bytes then return nil,"Missing Gen 3 cache: "..dir..rec.file end
  return love.image.newImageData(love.filesystem.newFileData(bytes,rec.file))
 end
 local entry=require("Gen3Resources").readTable(S.data,dir.."manifest.lua")[rec.key]
 if not entry then return nil,"Missing Gen 3 cache: "..dir.."manifest.lua" end
 local file=entry.file or rec.key..".rgba"
 local bytes=S.data._gen3Read(dir..file)
 if not bytes or #bytes<entry.width*entry.height*4 then return nil,"Missing Gen 3 cache: "..dir..file end
 return love.image.newImageData(entry.width,entry.height,"rgba8",bytes:sub(1,entry.width*entry.height*4))
end
function M.image(S,game,index)
 local cache=S.data._miniGameImages or {};S.data._miniGameImages=cache
 local key=game.."/"..index;if cache[key] then return cache[key] end
 local rec=assert(M.list(S,game) and M.list(S,game)[index],"Unknown mini-game image")
 local img,err=cacheImage(S,game,rec);if not img then return nil,err end
 cache[key]=img;return img
end
return M
