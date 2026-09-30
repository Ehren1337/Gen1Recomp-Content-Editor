-- Emerald evolutions by contest condition. The runtime only knows EVO_BEAUTY,
-- so the other four export as EVO_BEAUTY plus a condition table.
local M={}
M.METHODS={EVO_COOL="cool",EVO_BEAUTY="beauty",EVO_CUTE="cute",EVO_CLEVER="smart",EVO_TOUGH="tough"}
M.EXTRA={"EVO_COOL","EVO_CUTE","EVO_CLEVER","EVO_TOUGH"}
function M.enabled(p) return (p.game or p.version)=="emerald" end
function M.compile(p)
  local rows={}
  for id,rec in pairs((p.gen3 or {}).pokemon or {}) do
    for _,evo in ipairs(rec.evolutions or {}) do
      local condition=M.METHODS[evo.method]
      if condition then evo.level,evo.item=nil,nil end
      if condition and evo.method~="EVO_BEAUTY" then
        assert(M.enabled(p),"Contest condition evolutions need Emerald: "..id)
        assert(evo.species,"Choose the species "..id.." evolves into")
        evo.method="EVO_BEAUTY"
        rows[#rows+1]={from=id,into=evo.species,param=evo.param or 0,condition=condition}
      end
    end
  end
  table.sort(rows,function(a,b) return a.from..a.into<b.from..b.into end)
  return rows
end
function M.emit(p,rows,encode,out)
  if not M.enabled(p) then return end
  out[#out+1]="local contestEvo=(function()\n"..assert(love.filesystem.read("tools/content-editor/Gen3ContestEvoRuntime.lua")).."\nend)()\ncontestEvo.install(mod,"..encode(rows)..")"
end
return M
