-- Passive ranks checked by hand in a pet's spellbook and swing timer. Until
-- 0.13.15 BeastScout misread Faster Attack II and III a rank low (and IV as
-- V); old reports are translated now, but a 1 or 5 the Hunter's Handbook
-- can't settle stays as read. A line here beats every tame report for that
-- beast; the build writes it out as a tame. Add one only after checking a
-- pet's spellbook (and swing timer, without haste buffs) with /beastscout pet.
-- author: maintainer-checked
    -- Juvenile Snow Leopard: two tames recorded Faster Attack II; a level 5 tame's
    -- spellbook showed Faster Attack III, swing 1.474 unbuffed (the Handbook agrees).
    [1199] = { name="Juvenile Snow Leopard", family="Cat", levelMin=5, levelMax=6, speed=1.5, speedSource="checked", teaches={ {"Cower", 1}, {"Faster Attack", 3} }, teachesSource="checked", zones={ "Dun Morogh" } },
    -- Mystmane: tame showed Faster Attack I; spellbook showed Faster Attack II at
    -- levels 13 and 15, swing 1.569 unbuffed (1.364 under Might of Stormwind).
    [259388] = { name="Mystmane", family="Bear", levelMin=13, levelMax=13, speed=1.6, speedSource="checked", teaches={ {"Faster Attack", 2}, {"Swipe", 1} }, teachesSource="checked", rare=true, zones={ "Zephras Isle" } },
