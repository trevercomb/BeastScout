-- Prints how many beasts BeastScout's own data covers, as a changelog line.
-- Run from the repo root: lua tools/coverage.lua
local ns = {}
for _, file in ipairs({ "Data.lua", "Community.lua", "Handbook.lua" }) do
    assert(loadfile(file))(nil, ns)
end
local c = ns.Coverage()
print(("- Data: %d beasts tracked by BeastScout players (%d the Hunter's Handbook doesn't have); "
    .. "%d still come only from the Handbook. Plus %d with spawn points only."):format(c.ours, c.new, c.handbookOnly, c.spotsOnly))
