local M={}
-- Emerald's Beauty evolution reads mon.beauty, but Pokeblocks raise mon.contest.beauty.
function M.install(mod,rows)
  local Pokemon=require("src.core.game3.pokemon")
  local EVO_BEAUTY=require("src.core.game3.evolution").EVO_BEAUTY
  local conditions
  local function lookup()
    if conditions then return conditions end
    conditions={}
    for _,row in ipairs(rows) do
      local from,into=mod.content.pokemon:get(row.from),mod.content.pokemon:get(row.into)
      if from and into then conditions[from.index.."|"..into.index.."|"..row.param]=row.condition end
    end
    return conditions
  end
  mod.hooks:wrap("evolution.check",function(proceed,game,mon,view,ctx)
    if view.methodId~=EVO_BEAUTY then return proceed(game,mon,view,ctx) end
    local from=tonumber(Pokemon.speciesOf(mon) or mon.species) or 0
    local condition=lookup()[from.."|"..view.speciesId.."|"..view.param] or "beauty"
    local value=tonumber(mon.contest and mon.contest[condition]) or 0
    if condition=="beauty" then value=math.max(value,tonumber(mon.beauty) or 0) end
    return view.param<=value
  end)
end
return M
