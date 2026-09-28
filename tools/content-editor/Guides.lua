-- GUIDES tab: step-by-step guides, grouped by topic.
--
-- The content is plain data in GuidesData.lua:
--   categories = { { id =, label = }, ... }
--   guides = { { id, category, title, summary, gen3 = true (FireRed / LeafGreen
--     only), steps = { { text, go = { tab = "maps", set = { g3GfxMode = "blocks" } } } } } }
-- `go` gives a step a "Take me there" button: it switches to that tab and
-- sets the panel state in `set`. Keep button and tab names as on screen
-- (tabs in capitals: MAPS).

local M = {}

local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepCopy(x) end
  return out
end
M.deepCopy = deepCopy

--- (Re)load the guides from GuidesData.lua.
function M.load()
  package.loaded.GuidesData = nil
  local ok, data = pcall(require, "GuidesData")
  if not ok or type(data) ~= "table" then data = { categories = {}, guides = {} } end
  M.CATEGORIES = data.categories or {}
  M.GUIDES = data.guides or {}
end
M.load()

--- Use `data` ({ categories, guides }) as the guides from now on.
function M.use(data)
  M.CATEGORIES = data.categories
  M.GUIDES = data.guides
end

function M.data()
  return { categories = M.CATEGORIES, guides = M.GUIDES }
end

function M.byCategory(id, guides)
  local out = {}
  for _, g in ipairs(guides or M.GUIDES) do if g.category == id then out[#out + 1] = g end end
  return out
end

function M.find(id, guides)
  for _, g in ipairs(guides or M.GUIDES) do if g.id == id then return g end end
end

--- Follow a step's "Take me there".
function M.go(S, go)
  if not go or not go.tab then return end
  S.tab = go.tab
  for k, v in pairs(go.set or {}) do S[k] = v end
  S._tabBarNeedsReveal = true
end

return M
