-- Writes record mode's fixture games as JSON (scripts/record-fixtures.sh): setup, events,
-- and what the engine's own record.build makes of them. arg[1] is a kubb-engine tree.
local src = arg[1]
local imported = {}
function import(name)
	if imported[name] then return nil end
	imported[name] = true
	return assert(loadfile(src .. "/" .. name .. ".lua"))()
end
import "core/tw"
import "version"
import "core/record"
import "session/json"
local record, json = tw.record, tw.web.json
local games = assert(loadfile(src .. "/tests/fixtures/record/games.lua"))()
local names = {}
for n in pairs(games) do names[#names+1] = n end
table.sort(names)
local out = {}
for _, n in ipairs(names) do
  local g = games[n]
  local r = record.build(g.setup, g.events)
  local text = record.render(r)
  local codes = {}
  for i, w in ipairs(r.warnings) do codes[i] = w.code end
  local setup = g.setup
  if setup.capture and next(setup.capture) == nil then setup.capture = json.object() end
  out[#out+1] = { name = n, setup = setup, events = g.events, text = text, warnings = codes,
    winner = r.winner, how = r.how }
end
io.write(json.encode(out))
