--!strict
-- Quests: quest data rows consumed by the pure QuestRules engine. Starter set (tutorial + harbor/
-- island unlocks + key specialist chains); expand to the full 310 by appending rows — never logic.
-- step.kind values are emitted by systems via Quest.report: talk, plant, harvest, harvest_mut, sell,
-- fish, catch_bug, mine, forage, cook, buy_animal, collect_animal, breed, upgrade, decorate, trade,
-- sail, buy_vehicle, buy_boat, find_treasure, rebirth. (Early tutorial uses plant/harvest/sell which
-- already work; later kinds complete once their blocks land.)

local Q = {}

local Quests: { any } = {
	-- ── Tutorial questline (guided core loop) ──
	{ id = "tut_01", giver = "willow", name = "First Steps", steps = { { kind = "talk", target = "pip", count = 1 } }, reward = { coins = 25, xp = 10 } },
	{ id = "tut_02", giver = "pip", name = "Plant a Seed", steps = { { kind = "plant", target = "any", count = 3 } }, reward = { coins = 30, xp = 15 }, prereq = "tut_01" },
	{ id = "tut_03", giver = "sunny", name = "First Harvest", steps = { { kind = "harvest", target = "any", count = 3 } }, reward = { coins = 40, xp = 20 }, prereq = "tut_02" },
	{ id = "tut_04", giver = "marge", name = "Market Day", steps = { { kind = "sell", count = 3 } }, reward = { coins = 40, xp = 20 }, prereq = "tut_03" },
	{ id = "tut_05", giver = "hank", name = "Sparkle Hunt", steps = { { kind = "harvest_mut", count = 1 } }, reward = { coins = 75, xp = 40 }, prereq = "tut_04", level = 2 },
	{ id = "tut_06", giver = "finn", name = "Gone Fishin'", steps = { { kind = "fish", count = 3 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_04" },
	{ id = "tut_07", giver = "wwhisper", name = "Bug Buddy", steps = { { kind = "catch_bug", count = 2 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_06" },
	{ id = "tut_08", giver = "dan", name = "Rock Bottom", steps = { { kind = "mine", count = 5 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_04" },
	{ id = "tut_09", giver = "rowan", name = "Gather Round", steps = { { kind = "forage", count = 4 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_07" },
	{ id = "tut_10", giver = "chef", name = "Soup's On", steps = { { kind = "cook", count = 1 } }, reward = { coins = 80, xp = 40 }, prereq = "tut_08" },
	{ id = "tut_11", giver = "bella", name = "Farm Friends", steps = { { kind = "collect_animal", count = 3 } }, reward = { coins = 90, xp = 45 }, prereq = "tut_04", level = 3 },
	{ id = "tut_12", giver = "bolt", name = "Sharper Tools", steps = { { kind = "upgrade", count = 1 } }, reward = { coins = 60, xp = 30 }, prereq = "tut_02", level = 3 },
	{ id = "tut_13", giver = "daisy", name = "Home Sweet Home", steps = { { kind = "decorate", count = 3 } }, reward = { coins = 70, xp = 35 }, prereq = "tut_04" },
	{ id = "tut_14", giver = "willow", name = "Good Neighbors", steps = { { kind = "trade", count = 1 } }, reward = { coins = 60, xp = 30 }, prereq = "tut_13" },
	{ id = "tut_15", giver = "rusty", name = "Fast Wheels", steps = { { kind = "buy_vehicle", count = 1 } }, reward = { coins = 60, xp = 30 }, prereq = "tut_04", level = 4 },
	{ id = "tut_16", giver = "bay", name = "Sea Legs", steps = { { kind = "sail", count = 1 } }, reward = { coins = 100, xp = 50 }, prereq = "tut_14", level = 5 },

	-- ── Harbor & island unlocks (critical path) ──
	{ id = "harbor_01", giver = "bay", name = "Your First Boat", steps = { { kind = "buy_boat", count = 1 } }, reward = { coins = 150, xp = 80, unlock = "boat" }, prereq = "tut_16", level = 5 },
	{ id = "isle_beach", giver = "sandy", name = "Set Sail: Beach", steps = { { kind = "sail", target = "1", count = 1 } }, reward = { coins = 100, xp = 50, unlock = "island1" }, prereq = "harbor_01" },
	{ id = "isle_woods", giver = "wwhisper", name = "Path Through the Woods", steps = { { kind = "sail", target = "2", count = 1 } }, reward = { coins = 120, xp = 60, unlock = "island2" }, prereq = "isle_beach", level = 7 },
	{ id = "isle_frost", giver = "frost", name = "Chart the Ice", steps = { { kind = "sail", target = "3", count = 1 } }, reward = { coins = 160, xp = 90, unlock = "island3" }, prereq = "isle_woods", level = 10 },
	{ id = "isle_volcano", giver = "ember", name = "Through the Smoke", steps = { { kind = "sail", target = "4", count = 1 } }, reward = { coins = 200, xp = 110, unlock = "island4" }, prereq = "isle_frost", level = 13 },
	{ id = "isle_dunes", giver = "dune", name = "Cross the Sea Sands", steps = { { kind = "sail", target = "5", count = 1 } }, reward = { coins = 200, xp = 110, unlock = "island5" }, prereq = "isle_volcano", level = 15 },
	{ id = "isle_cove", giver = "geode", name = "Into the Deep Caves", steps = { { kind = "sail", target = "6", count = 1 } }, reward = { coins = 240, xp = 130, unlock = "island6" }, prereq = "isle_dunes", level = 17 },
	{ id = "isle_grove", giver = "fungus", name = "Spore Route", steps = { { kind = "sail", target = "7", count = 1 } }, reward = { coins = 240, xp = 130, unlock = "island7" }, prereq = "isle_cove", level = 19 },
	{ id = "isle_cliffs", giver = "gale", name = "Ride the Wind", steps = { { kind = "sail", target = "8", count = 1 } }, reward = { coins = 280, xp = 150, unlock = "island8" }, prereq = "isle_grove", level = 22 },
	{ id = "isle_reef", giver = "marina", name = "Dive the Reef", steps = { { kind = "sail", target = "9", count = 1 } }, reward = { coins = 320, xp = 170, unlock = "island9" }, prereq = "isle_cliffs", level = 25 },
	{ id = "isle_mist", giver = "misty", name = "Beyond the Mist", steps = { { kind = "sail", target = "10", count = 1 } }, reward = { coins = 400, xp = 220, unlock = "island10" }, prereq = "isle_reef", level = 30 },
	{ id = "isle_enchanted", giver = "fae", name = "The Moonlit Voyage", steps = { { kind = "sail", target = "11", count = 1 } }, reward = { coins = 600, xp = 350, unlock = "island11" }, prereq = "isle_mist", level = 35 },

	-- ── Pip "Seed Master" ──
	{ id = "pip_01", giver = "pip", name = "Berry Beginner", steps = { { kind = "harvest", target = "strawberry", count = 5 } }, reward = { coins = 40, xp = 20 }, prereq = "tut_04" },
	{ id = "pip_02", giver = "pip", name = "Pumpkin Patch", steps = { { kind = "harvest", target = "pumpkin", count = 10 } }, reward = { coins = 60, xp = 30 }, prereq = "pip_01" },
	{ id = "pip_03", giver = "pip", name = "Mutation Master", steps = { { kind = "harvest_mut", count = 5 } }, reward = { coins = 250, xp = 130 }, prereq = "pip_02", level = 6 },

	-- ── Marge "Market Mogul" ──
	{ id = "marge_01", giver = "marge", name = "First Coins", steps = { { kind = "sell", count = 10 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_04" },
	{ id = "marge_02", giver = "marge", name = "Bumper Day", steps = { { kind = "sell", count = 50 } }, reward = { coins = 90, xp = 45 }, prereq = "marge_01" },

	-- ── Hank "Green Thumb" ──
	{ id = "hank_01", giver = "hank", name = "Big Bloom", steps = { { kind = "harvest", target = "any", count = 25 } }, reward = { coins = 60, xp = 30 }, prereq = "tut_05" },
	{ id = "hank_02", giver = "hank", name = "Mutation Hunt", steps = { { kind = "harvest_mut", count = 3 } }, reward = { coins = 120, xp = 60 }, prereq = "hank_01", level = 6 },

	-- ── Finn "Reel Master" ──
	{ id = "finn_01", giver = "finn", name = "Small Fry", steps = { { kind = "fish", count = 10 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_06" },
	{ id = "finn_02", giver = "finn", name = "Big One", steps = { { kind = "fish", count = 25 } }, reward = { coins = 120, xp = 60 }, prereq = "finn_01", level = 6 },

	-- ── Dan "Deep Dig" ──
	{ id = "dan_01", giver = "dan", name = "Stone Age", steps = { { kind = "mine", count = 20 } }, reward = { coins = 50, xp = 25 }, prereq = "tut_08" },
	{ id = "dan_02", giver = "dan", name = "Gem Hunter", steps = { { kind = "mine", count = 50 } }, reward = { coins = 150, xp = 80 }, prereq = "dan_01", level = 8 },

	-- ── Daily (repeatable-flavored) ──
	{ id = "daily_harvest", giver = "sunny", name = "Daily Harvest", steps = { { kind = "harvest", target = "any", count = 15 } }, reward = { coins = 50, xp = 25 } },

	-- ══ THE HERO'S PATH (Tibia-style questline: fight, gather, deliver, long chain, big rewards) ══
	-- Multi-step quests (do this, THEN that, THEN come back). Uses combat (kill/loot) + varied rewards
	-- (coins, xp, trophy items, island access unlocks, an earned hero aura).
	{ id = "hero_01", giver = "bay", name = "A Hero Rises", steps = { { kind = "sail", target = "1", count = 1 }, { kind = "kill", target = "slime", count = 5 } }, reward = { coins = 200, xp = 100, item = "loot|slimegel" }, prereq = "harbor_01", level = 5 },
	{ id = "hero_02", giver = "sandy", name = "Slime Trouble", steps = { { kind = "kill", target = "slime", count = 10 }, { kind = "loot", target = "slimegel", count = 3 } }, reward = { coins = 300, xp = 150, item = "loot|herocrest" }, prereq = "hero_01" },
	{ id = "hero_03", giver = "wwhisper", name = "Wolves at the Door", steps = { { kind = "sail", target = "2", count = 1 }, { kind = "kill", target = "wolf", count = 8 } }, reward = { coins = 450, xp = 220, unlock = "island2" }, prereq = "hero_02", level = 7 },
	{ id = "hero_04", giver = "wwhisper", name = "Pelts for the Tailor", steps = { { kind = "loot", target = "wolfpelt", count = 5 }, { kind = "sell", count = 1 } }, reward = { coins = 500, xp = 260, item = "loot|woolcloak" }, prereq = "hero_03" },
	{ id = "hero_05", giver = "frost", name = "Into the Cold", steps = { { kind = "sail", target = "3", count = 1 }, { kind = "kill", target = "yeti", count = 3 }, { kind = "loot", target = "frostcore", count = 1 } }, reward = { coins = 900, xp = 450, unlock = "island3" }, prereq = "hero_04", level = 10 },
	{ id = "hero_06", giver = "ember", name = "The Bone Legion", steps = { { kind = "sail", target = "4", count = 1 }, { kind = "kill", target = "skeleton", count = 10 }, { kind = "find_treasure", count = 2 } }, reward = { coins = 1400, xp = 700, item = "loot|knightblade" }, prereq = "hero_05", level = 13 },
	{ id = "hero_07", giver = "ember", name = "Slay the Dragon", steps = { { kind = "kill", target = "dragon", count = 1 }, { kind = "loot", target = "dragonscale", count = 1 } }, reward = { coins = 5000, xp = 2000, item = "loot|dragoncrown", unlock = "perk_heroaura" }, prereq = "hero_06", level = 16 },
	{ id = "hero_08", giver = "misty", name = "Ghosts of the Mist", steps = { { kind = "sail", target = "10", count = 1 }, { kind = "kill", target = "wraith", count = 8 }, { kind = "loot", target = "ectoplasm", count = 3 } }, reward = { coins = 3000, xp = 1500, unlock = "island10" }, prereq = "hero_07", level = 25 },
	{ id = "hero_09", giver = "fae", name = "The Enchanted Trial", steps = { { kind = "sail", target = "11", count = 1 }, { kind = "kill", target = "fae", count = 5 }, { kind = "loot", target = "faedust", count = 3 } }, reward = { coins = 8000, xp = 4000, item = "loot|faecrown", unlock = "island11" }, prereq = "hero_08", level = 35 },
	{ id = "hero_10", giver = "willow", name = "Bloomly Champion", steps = { { kind = "talk", target = "willow", count = 1 }, { kind = "rebirth", count = 1 } }, reward = { coins = 20000, xp = 10000, item = "loot|championtrophy", unlock = "perk_champion" }, prereq = "hero_09", level = 40 },
}

Q.list = Quests
local byId: { [string]: any } = {}
local byGiver: { [string]: { any } } = {}
for _, quest in Quests do
	byId[quest.id] = quest
	byGiver[quest.giver] = byGiver[quest.giver] or {}
	table.insert(byGiver[quest.giver], quest)
end
function Q.get(id: string): any
	return byId[id]
end
function Q.forGiver(giverId: string): { any }
	return byGiver[giverId] or {}
end
return Q
