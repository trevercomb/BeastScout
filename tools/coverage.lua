-- Prints how many beasts players' data covers: first a changelog line, then
-- (not for the changelog) how many Handbook beasts nobody has confirmed yet.
-- Run from the repo root: lua tools/coverage.lua
local ns = {}
for _, file in ipairs({ "Data.lua", "Community.lua", "Handbook.lua" }) do
    assert(loadfile(file))(nil, ns)
end
local c = ns.Coverage()
print("- " .. ns.CoverageText(c) .. ".")
print(("(not for the changelog) %d Handbook beasts not confirmed yet."):format(c.handbookOnly))
