-- Passive ranks checked in a pet's spellbook after the tame. Right at the tame
-- the game can show a lower Faster or Slower Attack rank than the pet really
-- has, so tames recorded then (before 0.13.13 corrected them) can outvote the
-- truth. A line here beats every tame report for that beast; the build writes
-- it out as a tame. Add one only after checking a pet's spellbook (and swing
-- timer, without haste buffs) with /beastscout pet.
-- author: maintainer-checked
    -- Mystmane: tame showed Faster Attack I; spellbook showed Faster Attack II at
    -- levels 13 and 15, swing 1.569 unbuffed (1.364 under Might of Stormwind).
    [259388] = { name="Mystmane", family="Bear", levelMin=13, levelMax=13, speed=1.6, speedSource="checked", teaches={ {"Faster Attack", 2}, {"Swipe", 1} }, teachesSource="checked", rare=true, zones={ "Zephras Isle" } },
