local M={}
-- Types.isPhysical only gets a type, so the move in use is tracked around
-- the calls that reach it: every one takes the move third.
function M.install(mod,split)
  local Runtime=require("src.mods.Runtime")
  local Types=require("src.core.game3.battle.types")
  local Damage=require("src.core.game3.battle.damage")
  local Engine=require("src.core.game3.battle.engine")
  local Moves=require("src.core.game3.battle.moves")
  if not Types._editorSplit then
    Types._editorSplit=true
    local isPhysical,base,calc,resolve,resume=Types.isPhysical,Damage.base,Damage.calc,Engine.resolveMove,Engine.resumeChoice
    Types.isPhysical=function(...) return Runtime.call("editor.gen3.split.physical",isPhysical,...) end
    Damage.base=function(...) return Runtime.call("editor.gen3.split.base",base,...) end
    Damage.calc=function(...) return Runtime.call("editor.gen3.split.calc",calc,...) end
    Engine.resolveMove=function(...) return Runtime.call("editor.gen3.split.resolve",resolve,...) end
    Engine.resumeChoice=function(...) return Runtime.call("editor.gen3.split.resume",resume,...) end
  end
  local categories
  -- Raw ROM rows: Moves.get calls Types.isPhysical itself.
  local function category(num)
    if not categories then
      categories={}
      for n,c in pairs(split.defaults) do categories[tonumber(n)]=c end
      for id,c in pairs(split.moves) do
        local rec=mod.content.moves:get(id)
        if rec and rec.index then categories[rec.index]=c end
      end
    end
    if categories[num]==nil then
      local row=Moves.romRows()[num]
      categories[num]=row and ((row.power or 0)==0 and "status" or Types.PHYSICAL[row.type] and "physical" or "special") or false
    end
    return categories[num]
  end
  local current
  local function restore(previous,...) current=previous;return ... end
  local function using(move,proceed,...)
    local previous=current;current=Moves.numForName(move)
    return restore(previous,proceed(...))
  end
  for _,name in ipairs({"base","calc","resolve"}) do
    mod.hooks:wrap("editor.gen3.split."..name,function(proceed,a,b,move,...)
      return using(move,proceed,a,b,move,...)
    end)
  end
  mod.hooks:wrap("editor.gen3.split.resume",function(proceed,st,...)
    local pending=st and st.pendingChoice
    return using(pending and pending.M.move,proceed,st,...)
  end)
  mod.hooks:wrap("editor.gen3.split.physical",function(proceed,typeId)
    local c=current and category(current)
    if c then return c=="physical" end
    return proceed(typeId)
  end)
end
return M
