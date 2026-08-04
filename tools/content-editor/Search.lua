-- Shared list search for content-editor panels.

local Kit = require("Kit")

local Search = {}

function Search.filterIds(ids, query)
  query = tostring(query or ""):lower()
  query = query:match("^%s*(.-)%s*$") or ""
  if query == "" then return ids end
  local out = {}
  for _, id in ipairs(ids or {}) do
    if tostring(id):lower():find(query, 1, true) then
      out[#out + 1] = id
    end
  end
  return out
end

-- items: array of tables; textFor(item) -> searchable string
function Search.filterItems(items, query, textFor)
  query = tostring(query or ""):lower()
  query = query:match("^%s*(.-)%s*$") or ""
  if query == "" then return items end
  local out = {}
  for _, item in ipairs(items or {}) do
    local hay = textFor and textFor(item) or tostring(item)
    if tostring(hay):lower():find(query, 1, true) then
      out[#out + 1] = item
    end
  end
  return out
end

-- Draws a search field. Returns query, changed.
function Search.field(S, key, x, y, w, h, placeholder)
  local prev = S[key] or ""
  local v = Kit.textfield("ce_search_" .. key, x, y, w, h, prev,
    placeholder or "search...")
  v = v or ""
  S[key] = v
  return v, v ~= prev
end

return Search
