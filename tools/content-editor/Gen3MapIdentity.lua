local M={}
function M.rename(S,oldId,newId)
  newId=tostring(newId or ""):match("^%s*(.-)%s*$")
  local p=S.project
  local map=p and p.maps and p.maps[oldId]
  if not map or not map._isNew then return false,"Only new project maps can change ID" end
  if newId==oldId then return false,"Map ID is unchanged" end
  if not newId:match("^[%w_]+$") then return false,"Use letters, numbers and underscores for the map ID" end
  if p.maps[newId] or ((S.data or {}).maps or {})[newId]
      or ((S.data or {})._editorMaps or {})[newId] then return false,"That map ID already exists" end
  -- Rewrite exact identifier values and map-keyed registries, never substrings
  -- in dialogue or script source. Preserve the separately authored display name.
  local seen={}
  local function rewrite(t)
    if seen[t] then return end
    seen[t]=true
    local keys={};for k in pairs(t) do keys[#keys+1]=k end
    for _,k in ipairs(keys) do
      local v=t[k]
      if type(v)=="table" then rewrite(v)
      elseif v==oldId and k~="name" and k~="label" and k~="text" then t[k]=newId end
      if k==oldId then t[newId]=t[k];t[k]=nil end
    end
  end
  rewrite(p)
  S.mapId,S.builderMapId=newId,newId
  S._g3NameMap,S._g3EventIdentity,S._mapCenteredFor=nil,nil,nil
  if S.data then S.data._gen3DerivedLayouts=nil end
  return true
end
return M
