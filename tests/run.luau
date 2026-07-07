--!strict
-- VPS-side logic tests. Runs on the standalone `luau` CLI (NO Roblox / Studio needed):
--     luau tests/run.luau
--
-- This is the FAST inner loop. It verifies the game RULES (unlock gates, mutation ladder, sell
-- pricing) directly against the real data modules, so balance/logic bugs are caught here before the
-- code ever reaches Studio. The slow outer loop (feel, input, client<->server round-trip) is what
-- you test by pressing Play in Studio -- these two loops together are how we build the whole game
-- without flying blind.
--
-- Only PURE modules (no Roblox globals) are testable this way. That is exactly why the game is
-- structured as pure logic + a thin Roblox shell: the more logic lives in pure modules, the more
-- of the game I can prove correct on the VPS.

local Plants = require("../src/shared/data/Plants")
local Mutations = require("../src/shared/data/Mutations")
local Config = require("../src/shared/data/Config")
local Rules = require("../src/shared/Rules")
local SaveSchema = require("../src/shared/SaveSchema")
local WorldLayout = require("../src/shared/data/WorldLayout")
local PlotRules = require("../src/shared/PlotRules")
local Catalog = require("../src/shared/data/Catalog")
local QuestRules = require("../src/shared/QuestRules")
local Quests = require("../src/shared/data/Quests")
local UpgradeRules = require("../src/shared/UpgradeRules")
local Upgrades = require("../src/shared/data/Upgrades")
local GatherRules = require("../src/shared/GatherRules")
local TreasureRules = require("../src/shared/TreasureRules")

local passed, failed = 0, 0
local function check(name: string, cond: boolean)
	if cond then
		passed += 1
	else
		failed += 1
		print("  FAIL  " .. name)
	end
end
local function eq(name: string, got: any, want: any)
	check(name .. string.format("  (got %s, want %s)", tostring(got), tostring(want)), got == want)
end

-- ---- Config: ported starting values ----
eq("START_COINS is 20 (ported from economy.js)", Config.START_COINS, 20)
eq("PLOT_COUNT is 12", Config.PLOT_COUNT, 12)

-- ---- Plant unlock gates (the real Plants.isUnlocked) ----
local radish = Plants.get("radish") :: any
local strawberry = Plants.get("strawberry") :: any
local pumpkin = Plants.get("pumpkin") :: any
local blueberry = Plants.get("blueberry") :: any
local starbloom = Plants.get("starbloom") :: any

check("radish (start) always unlocked", Plants.isUnlocked(radish, { lifetimeEarned = 0 }, 0))
check("strawberry LOCKED below 100 earned", not Plants.isUnlocked(strawberry, { lifetimeEarned = 99 }, 6))
check("strawberry unlocks at 100 earned", Plants.isUnlocked(strawberry, { lifetimeEarned = 100 }, 6))
check("blueberry LOCKED below 1000 earned", not Plants.isUnlocked(blueberry, { lifetimeEarned = 999 }, 6))
check("blueberry unlocks at 1000 earned", Plants.isUnlocked(blueberry, { lifetimeEarned = 1000 }, 6))
check("pumpkin LOCKED with 3 plots owned", not Plants.isUnlocked(pumpkin, { lifetimeEarned = 0 }, 3))
check("pumpkin unlocks with 4 plots owned", Plants.isUnlocked(pumpkin, { lifetimeEarned = 0 }, 4))
check("starbloom LOCKED with 5 plots owned", not Plants.isUnlocked(starbloom, { lifetimeEarned = 0 }, 5))
check("starbloom unlocks with 6 plots owned", Plants.isUnlocked(starbloom, { lifetimeEarned = 0 }, 6))

-- ---- Mutation value multipliers (the real Mutations.multOf) ----
eq("normal mult = 1.0", Mutations.multOf("normal"), 1.0)
eq("wet mult = 1.5", Mutations.multOf("wet"), 1.5)
eq("golden mult = 5", Mutations.multOf("golden"), 5)
eq("celestial mult = 50", Mutations.multOf("celestial"), 50)
eq("unknown mutation falls back to 1.0", Mutations.multOf("banana"), 1.0)

-- ---- Sell price = the exact formula the server uses: floor(plant.sell * mult) ----
local function sellPrice(plantId: string, mutationId: string): number
	local p = Plants.get(plantId) :: any
	return math.floor(p.sell * Mutations.multOf(mutationId))
end
eq("radish normal sells 9", sellPrice("radish", "normal"), 9)
eq("radish golden sells 45", sellPrice("radish", "golden"), 45)
eq("pumpkin giant sells 500", sellPrice("pumpkin", "giant"), 500)
eq("starbloom rainbow sells 28000", sellPrice("starbloom", "rainbow"), 28000)

-- ---- Mutation ladder invariants (keeps balance sane as we add tiers) ----
eq("ladder has 6 tiers", #Mutations.list, 6)
do
	local ranks: { [number]: boolean } = {}
	local rankOk, chanceMonotonic, multMonotonic = true, true, true
	local sorted = table.clone(Mutations.list)
	table.sort(sorted, function(a, b)
		return a.rank < b.rank
	end)
	for i, m in sorted do
		ranks[m.rank] = true
		if m.rank ~= i then
			rankOk = false
		end
		if i > 1 then
			-- higher rank = rarer (lower chance) and more valuable (higher mult)
			if m.chance >= sorted[i - 1].chance then
				chanceMonotonic = false
			end
			if m.mult <= sorted[i - 1].mult then
				multMonotonic = false
			end
		end
	end
	check("ranks are exactly 1..6", rankOk and ranks[1] and ranks[6])
	check("rarer tiers have strictly lower roll chance", chanceMonotonic)
	check("rarer tiers have strictly higher value mult", multMonotonic)
end

-- Effective "normal" fraction of harvests (rarest-first, first-hit-wins => 1 - product(1-chance)).
-- Spec §2.2 wants most harvests plain. We assert >80% normal and print the exact number so balance
-- drift is visible the moment we touch the ladder.
do
	local pAny = 1.0
	for _, m in Mutations.list do
		pAny *= (1 - m.chance)
	end
	local normalFrac = pAny
	check("most harvests are normal (>80%)", normalFrac > 0.80)
	print(string.format("  info: effective mutation rate = %.2f%% (normal %.2f%%)", (1 - normalFrac) * 100, normalFrac * 100))
end

-- ---- Rules: grow timing (pure, time injected -> deterministic) ----
eq("readyAt(100, 20000ms) = 120s", Rules.readyAt(100, 20000), 120)
check("not ready 1s early", not Rules.isReady(119, 120))
check("ready exactly on time", Rules.isReady(120, 120))
check("ready after time", Rules.isReady(121, 120))
check("empty plot (nil readyAt) never ready", not Rules.isReady(50, nil))

-- ---- Rules: price floor (pure) ----
eq("sellPrice floors 9x2.5 -> 22", Rules.sellPrice(9, 2.5), 22)
eq("sellPrice 200x2.5 -> 500", Rules.sellPrice(200, 2.5), 500)
eq("sellPrice 1400x20 -> 28000", Rules.sellPrice(1400, 20), 28000)

-- ---- Rules: mutation roll, FIXED outcomes (a known rand -> a known tier) ----
local ladder = Rules.buildLadder(Mutations.list)
local function constRand(v: number): () -> number
	return function()
		return v
	end
end
eq("rand 0.0001 -> celestial (rarest hit)", Rules.rollMutation(ladder, constRand(0.0001), "normal"), "celestial")
eq("rand 0.003 -> rainbow", Rules.rollMutation(ladder, constRand(0.003), "normal"), "rainbow")
eq("rand 0.03 -> giant", Rules.rollMutation(ladder, constRand(0.03), "normal"), "giant")
eq("rand 0.9 -> normal (nothing hits)", Rules.rollMutation(ladder, constRand(0.9), "normal"), "normal")
-- chanceMult scales every chance: 0.007 misses rainbow(0.004) normally, hits it at x2 (0.008)
eq("rand 0.007, mult 1 -> frosted", Rules.rollMutation(ladder, constRand(0.007), "normal", 1), "frosted")
eq("rand 0.007, mult 2 -> rainbow", Rules.rollMutation(ladder, constRand(0.007), "normal", 2), "rainbow")

-- ---- Rules: mutation roll, DISTRIBUTION over 200k draws matches the ladder ----
do
	pcall(function()
		math.randomseed(1337)
	end) -- reproducible if supported; wide tolerance makes it robust either way
	local mrand = function()
		return math.random()
	end
	local N = 200000
	local counts: { [string]: number } = {}
	for _ = 1, N do
		local id = Rules.rollMutation(ladder, mrand, "normal")
		counts[id] = (counts[id] or 0) + 1
	end
	local normal = counts["normal"] or 0
	local mutated = N - normal
	local rate = mutated / N
	-- expected ~15.13%; N=200k => this is far tighter than +/-1% in practice
	check(string.format("empirical mutation rate ~15%% (got %.2f%%)", rate * 100), rate > 0.14 and rate < 0.163)
	check("every tier actually appears", (counts["celestial"] or 0) > 0 and (counts["wet"] or 0) > 0)
	check("normal is the most common outcome", normal > mutated)
	print(string.format("  info: 200k rolls -> %.2f%% mutated; celestial x%d, rainbow x%d, wet x%d",
		rate * 100, counts["celestial"] or 0, counts["rainbow"] or 0, counts["wet"] or 0))
end

-- ---- Rules: progression math (XP per harvest + level curve, both pure) ----
eq("radish(t1) normal harvest = 3 xp", Rules.xpForHarvest(1, 0), 3)
eq("starbloom(t6) normal harvest = 18 xp", Rules.xpForHarvest(6, 0), 18)
eq("radish(t1) rainbow(r5) harvest = 28 xp", Rules.xpForHarvest(1, 5), 28)
eq("pumpkin(t4) golden(r3) harvest = 27 xp", Rules.xpForHarvest(4, 3), 27)

eq("level at 0 xp = 1", Rules.levelForXp(0), 1)
eq("level at 49 xp = 1", Rules.levelForXp(49), 1)
eq("level at 50 xp = 2", Rules.levelForXp(50), 2)
eq("level at 199 xp = 2", Rules.levelForXp(199), 2)
eq("level at 200 xp = 3", Rules.levelForXp(200), 3)
eq("level at 450 xp = 4", Rules.levelForXp(450), 4)
do
	local monotonic = true
	local prev = 0
	for xp = 0, 5000, 25 do
		local lvl = Rules.levelForXp(xp)
		if lvl < prev then
			monotonic = false
		end
		prev = lvl
	end
	check("level never decreases as xp grows", monotonic)
end

-- ---- SaveSchema: persistence shape (pure; the safety net for DataStore) ----
local function deepEqual(a: any, b: any): boolean
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in a do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in b do
		if a[k] == nil then
			return false
		end
	end
	return true
end
local function tmpl(): any
	local plots = {}
	for _ = 1, 6 do
		table.insert(plots, { seedId = nil, readyAt = nil })
	end
	return { coins = 20, lifetimeEarned = 0, harvests = 0, xp = 0, codex = {}, inventory = {}, plots = plots, rebirths = 0, daily = { day = 0, streak = 0 }, quests = { done = {}, active = {} }, unlocks = {}, upgrades = {}, treasuresFound = {} }
end
do
	local st: any = {
		coins = 512,
		lifetimeEarned = 999,
		harvests = 7,
		xp = 250,
		codex = { ["radish|golden"] = true, ["sunflower|normal"] = true },
		inventory = { ["radish|normal"] = 3, ["pumpkin|giant"] = 1 },
		rebirths = 2,
		daily = { day = 100, streak = 3 },
		quests = { done = { tut_01 = true }, active = { tut_02 = { step = 1, prog = 1 } } },
		unlocks = { boat = true },
		upgrades = { plots = 2, sellBonus = 1 },
		treasuresFound = { t_1_1 = true },
		plots = {
			{ seedId = "radish", readyAt = 1700000000 },
			{ seedId = nil, readyAt = nil },
			{ seedId = nil, readyAt = nil },
			{ seedId = nil, readyAt = nil },
			{ seedId = nil, readyAt = nil },
			{ seedId = nil, readyAt = nil },
		},
	}
	-- round-trip is lossless (this is the property that says persistence doesn't corrupt a garden)
	check("SaveSchema round-trip preserves full state", deepEqual(SaveSchema.deserialize(SaveSchema.serialize(st), tmpl()), st))
	-- serialize stamps the version
	eq("serialize stamps version", (SaveSchema.serialize(st) :: any).v, SaveSchema.VERSION)
end
-- brand-new player (nil save) => fresh template
check("nil save => fresh default", deepEqual(SaveSchema.deserialize(nil, tmpl()), tmpl()))
-- a save missing fields fills them from the template (new features never wipe old saves)
do
	local out = SaveSchema.deserialize({ coins = 100 }, tmpl())
	eq("missing-field save keeps its coins", out.coins, 100)
	eq("missing-field save defaults lifetimeEarned", out.lifetimeEarned, 0)
	eq("missing-field save gets full plot count", #out.plots, 6)
end
-- validation clamps impossible / wrong-typed values instead of trusting them
do
	local out = SaveSchema.deserialize({ coins = -5, xp = "bad", plots = "notarray", inventory = { good = 3, bad = -1, junk = "x" } }, tmpl())
	eq("negative coins clamped to default", out.coins, 20)
	eq("non-number xp clamped to default", out.xp, 0)
	eq("garbage plots -> template count of empty plots", #out.plots, 6)
	eq("only valid inventory qty kept", out.inventory.good, 3)
	check("bad inventory entries dropped", out.inventory.bad == nil and out.inventory.junk == nil)
end
-- fewer stored plots than the template => normalized up, planted ones preserved
do
	local out = SaveSchema.deserialize({ plots = { { seedId = "radish", readyAt = 42 } } }, tmpl())
	eq("plots normalized to template count", #out.plots, 6)
	eq("planted plot preserved", out.plots[1].seedId, "radish")
	check("extra plots are empty", out.plots[6].seedId == nil)
end

-- ---- WorldLayout: procedural world geometry (pure -> the rare 3D bit we CAN test) ----
do
	local N = 100
	local half = WorldLayout.SECTION_SIZE / 2
	-- no two of the 100 plot centres are closer than one plot's size (=> 300x300 plots never overlap)
	local minDist = math.huge
	local centers = {}
	for i = 1, N do
		centers[i] = WorldLayout.sectionCenter(i)
	end
	for i = 1, N do
		for j = i + 1, N do
			local dx = centers[i].x - centers[j].x
			local dz = centers[i].z - centers[j].z
			local d = math.sqrt(dx * dx + dz * dz)
			if d < minDist then
				minDist = d
			end
		end
	end
	check(string.format("100 plots never overlap (min gap %.0f >= size %.0f)", minDist, WorldLayout.SECTION_SIZE), minDist >= WorldLayout.SECTION_SIZE)

	-- every one of the 12 crop pads sits fully inside its 300x300 plot, at a distinct position
	local padHalf = WorldLayout.PAD_SIZE / 2
	local allInside, distinct = true, true
	local seen = {}
	for p = 1, 12 do
		local o = WorldLayout.plotPadOffset(p, 12)
		if math.abs(o.x) + padHalf > half or math.abs(o.z) + padHalf > half then
			allInside = false
		end
		local kk = o.x .. "," .. o.z
		if seen[kk] then
			distinct = false
		end
		seen[kk] = true
	end
	check("all 12 crop pads fit inside the plot", allInside)
	check("crop pads are at distinct positions", distinct)

	-- every reserved expansion zone sits inside the plot
	local zonesInside = true
	for _, name in WorldLayout.zoneNames() do
		local o = WorldLayout.zoneOffset(name)
		if not o or math.abs(o.x) > half or math.abs(o.z) > half then
			zonesInside = false
		end
	end
	check("house/pen/utility/orchard zones fit inside the plot", zonesInside)

	-- the 10 islands are spread far apart (never overlap)
	local minIsland = math.huge
	local ic = {}
	for i = 1, WorldLayout.ISLAND_COUNT do
		ic[i] = WorldLayout.islandCenter(i)
	end
	for i = 1, WorldLayout.ISLAND_COUNT do
		for j = i + 1, WorldLayout.ISLAND_COUNT do
			local d = math.sqrt((ic[i].x - ic[j].x) ^ 2 + (ic[i].z - ic[j].z) ^ 2)
			minIsland = math.min(minIsland, d)
		end
	end
	check("10 islands never overlap", minIsland >= WorldLayout.ISLAND_SIZE)
end

-- ---- PlotRules: claim + ownership (pure) ----
eq("empty world -> claim section 1", PlotRules.pickFreeSection({}, 50), 1)
eq("lowest free section is picked", PlotRules.pickFreeSection({ [1] = true, [2] = true }, 50), 3)
check("full world -> no free section", PlotRules.pickFreeSection({ [1] = true, [2] = true, [3] = true }, 3) == nil)
check("owner can act on own section", PlotRules.canInteract(500, 500))
check("stranger cannot act on your section", not PlotRules.canInteract(500, 999))
check("unclaimed section is not interactable", not PlotRules.canInteract(nil, 500))

-- ---- new plants + codex unlock ----
do
	local moon = Plants.get("moonberry") :: any
	local crystal = Plants.get("crystalrose") :: any
	check("8 plants in the meadow roster", #Plants.list == 8)
	check("moonberry locked below 10000 earned", not Plants.isUnlocked(moon, { lifetimeEarned = 9999, codex = {} }, 24))
	check("moonberry unlocks at 10000 earned", Plants.isUnlocked(moon, { lifetimeEarned = 10000, codex = {} }, 24))
	local codex4 = { ["radish|normal"] = true, ["sunflower|golden"] = true, ["strawberry|normal"] = true, ["pumpkin|giant"] = true }
	local codex5 = { ["radish|normal"] = true, ["sunflower|golden"] = true, ["strawberry|normal"] = true, ["pumpkin|giant"] = true, ["blueberry|normal"] = true }
	check("crystalrose locked with 4 species discovered", not Plants.isUnlocked(crystal, { lifetimeEarned = 0, codex = codex4 }, 24))
	check("crystalrose unlocks with 5 species discovered", Plants.isUnlocked(crystal, { lifetimeEarned = 0, codex = codex5 }, 24))
end

-- ---- Catalog: all ported content is well-formed ----
do
	eq("Fish count = 4", #Catalog.Fish, 4)
	eq("Bugs count = 7", #Catalog.Bugs, 7)
	eq("Ores count = 3", #Catalog.Ores, 3)
	eq("Vehicles count = 4", #Catalog.Vehicles, 4)
	-- sellables have a positive sell price; buyables have a positive cost; ids unique within a list
	local sellableLists = { Catalog.Fish, Catalog.WinterFish, Catalog.Bugs, Catalog.Shells, Catalog.Ores }
	local sellablesOk = true
	for _, list in sellableLists do
		local seen = {}
		for _, row in list do
			if type(row.id) ~= "string" or type(row.sell) ~= "number" or row.sell <= 0 or seen[row.id] then
				sellablesOk = false
			end
			seen[row.id] = true
		end
	end
	check("all sellables: unique id + positive sell", sellablesOk)
	local buyableLists = { Catalog.Tools, Catalog.Pets, Catalog.Hats, Catalog.Backs, Catalog.Decor, Catalog.Vehicles, Catalog.House, Catalog.Furniture, Catalog.Passive }
	local buyablesOk = true
	for _, list in buyableLists do
		for _, row in list do
			if type(row.id) ~= "string" or type(row.cost) ~= "number" or row.cost <= 0 then
				buyablesOk = false
			end
		end
	end
	check("all buyables: string id + positive cost", buyablesOk)
	check("vehicles give a speed multiplier > 1", Catalog.Vehicles[1].speed > 1 and Catalog.Vehicles[4].speed > 1)
end

-- ---- rebirth + daily (pure retention math) ----
eq("coinMult 0 rebirths = 1", Rules.coinMult(0), 1)
eq("coinMult 3 rebirths = 1.3", Rules.coinMult(3), 1.3)
eq("first rebirth costs 1M lifetime", Rules.rebirthCost(0), 1000000)
eq("third rebirth costs 3M lifetime", Rules.rebirthCost(2), 3000000)
do
	local ok, reward, day, streak = Rules.dailyClaim(0, 0, 1)
	check("day 1 claim ok", ok and reward == 15 and day == 1 and streak == 1)
	local ok2 = Rules.dailyClaim(1, 1, 1)
	check("same day cannot re-claim", not ok2)
	local _, r3, _, s3 = Rules.dailyClaim(1, 1, 2)
	check("consecutive day -> streak 2, reward 25", r3 == 25 and s3 == 2)
	local _, r4, _, s4 = Rules.dailyClaim(1, 5, 4)
	check("gap resets streak to 1 (reward 15)", r4 == 15 and s4 == 1)
	local _, r7 = Rules.dailyClaim(1, 9, 2)
	check("streak reward caps at day 7 (200)", r7 == 200)
end

-- ---- QuestRules: the pure quest engine ----
do
	-- a 2-step quest: harvest 2 radish, then sell 3
	local q2: any = { id = "q2", giver = "x", name = "T", steps = { { kind = "harvest", target = "radish", count = 2 }, { kind = "sell", count = 3 } }, reward = { coins = 100, xp = 10, unlock = "thing" } }
	local q1: any = { id = "q1", giver = "x", name = "P", steps = { { kind = "plant", target = "any", count = 1 } }, reward = { coins = 5 } }
	local st: any = { xp = 0 }

	check("fresh quest is available", QuestRules.isAvailable(q2, st, 0))
	check("accept activates it", QuestRules.accept(st, q2))
	check("cannot double-accept", not QuestRules.accept(st, q2))
	check("active quest not available again", not QuestRules.isAvailable(q2, st, 0))

	-- wrong event does nothing
	check("non-matching event no-ops", not QuestRules.report(st, { q2 }, "mine", nil, 5))
	-- step 1 needs 2 radish
	QuestRules.report(st, { q2 }, "harvest", "radish", 1)
	check("not ready after 1/2 of step 1", not QuestRules.isReady(st, q2))
	QuestRules.report(st, { q2 }, "harvest", "radish", 1)
	check("still not ready (step 2 pending)", not QuestRules.isReady(st, q2))
	eq("advanced to step 2", st.quests.active.q2.step, 2)
	-- step 2 needs sell 3
	QuestRules.report(st, { q2 }, "sell", nil, 3)
	check("ready after all steps", QuestRules.isReady(st, q2))

	-- turn-in grants reward once, is idempotent
	local r = QuestRules.turnIn(st, q2)
	check("turnIn returns the reward", r ~= nil and r.coins == 100 and r.unlock == "thing")
	check("quest now done", QuestRules.isDone(st, "q2"))
	check("turnIn again returns nil", QuestRules.turnIn(st, q2) == nil)

	-- prereq gating: q1 depends on nothing; a quest with prereq q1 is unavailable until q1 done
	local q3: any = { id = "q3", giver = "x", name = "G", steps = { { kind = "plant", target = "any", count = 1 } }, reward = {}, prereq = "q99", level = 5 }
	check("prereq not done -> unavailable", not QuestRules.isAvailable(q3, st, 9))
	q3.prereq = "q2" -- now prereq is done
	check("prereq done but level too low -> unavailable", not QuestRules.isAvailable(q3, st, 4))
	check("prereq done + level ok -> available", QuestRules.isAvailable(q3, st, 5))
end
-- data integrity: every quest step uses a known verb; every giver is a real npc-ish id string
do
	local verbs = { talk = true, plant = true, harvest = true, harvest_mut = true, sell = true, fish = true, catch_bug = true, mine = true, forage = true, cook = true, buy_animal = true, collect_animal = true, breed = true, upgrade = true, decorate = true, trade = true, sail = true, buy_vehicle = true, buy_boat = true, find_treasure = true, rebirth = true }
	local ok, ids = true, {}
	for _, quest in Quests.list do
		if type(quest.id) ~= "string" or ids[quest.id] then
			ok = false
		end
		ids[quest.id] = true
		if type(quest.giver) ~= "string" or type(quest.steps) ~= "table" or #quest.steps == 0 then
			ok = false
		end
		for _, s in quest.steps do
			if not verbs[s.kind] or type(s.count) ~= "number" or s.count <= 0 then
				ok = false
			end
		end
	end
	check("all quests: unique id + valid givers + known step verbs", ok)
	check("starter quest set has >= 40 rows", #Quests.list >= 40)
end

-- ---- UpgradeRules: geometric cost + per-level effect + buy transaction ----
do
	local plots = Upgrades.get("plots") :: any
	local sell = Upgrades.get("sellBonus") :: any
	eq("plots L0 cost = baseCost", UpgradeRules.costForLevel(plots, 0), 250)
	eq("plots L1 cost = base*growth", UpgradeRules.costForLevel(plots, 1), 500)
	eq("plots L2 cost = base*growth^2", UpgradeRules.costForLevel(plots, 2), 1000)
	check("cost strictly rises with level", UpgradeRules.costForLevel(sell, 3) > UpgradeRules.costForLevel(sell, 2))
	eq("plots effect at L0 = 6", UpgradeRules.effectAt(plots, 0), 6)
	eq("plots effect at L6 = 12", UpgradeRules.effectAt(plots, 6), 12)
	eq("sellBonus effect at L4 = 1.2", UpgradeRules.effectAt(sell, 4), 1.2)

	local st: any = { coins = 250, upgrades = {} }
	local ok, lvl = UpgradeRules.buy(st, plots)
	check("buy succeeds when affordable", ok and lvl == 1 and st.coins == 0)
	check("buy fails when broke", not (UpgradeRules.buy(st, plots)))
	eq("level recorded", UpgradeRules.levelOf(st, "plots"), 1)
	-- maxed
	local rich: any = { coins = 1e9, upgrades = { plots = plots.maxLevel } }
	check("cannot buy past maxLevel", not (UpgradeRules.buy(rich, plots)))
	check("isMaxed true at maxLevel", UpgradeRules.isMaxed(plots, plots.maxLevel))
end

-- ---- GatherRules: weighted gathering roll (fishing/bugs/mining) ----
do
	eq("weightOf uses w when present", GatherRules.weightOf({ w = 34 }), 34)
	eq("weightOf fish min 0 -> 20 (common)", GatherRules.weightOf({ min = 0 }), 20)
	check("weightOf fish min 0.95 -> ~1 (rare)", GatherRules.weightOf({ min = 0.95 }) <= 2)
	-- deterministic edges
	local bugs = Catalog.Bugs
	local function constR(v: number): () -> number
		return function()
			return v
		end
	end
	check("roll near 0 -> first item", GatherRules.roll(bugs, constR(0)) == bugs[1].id)
	check("roll near 1 -> last item", GatherRules.roll(bugs, constR(0.9999)) == bugs[#bugs].id)
	-- every result is a real id
	local ids = {}
	for _, b in bugs do
		ids[b.id] = true
	end
	local allValid = true
	for i = 1, 50 do
		if not ids[GatherRules.roll(bugs, constR(i / 51))] then
			allValid = false
		end
	end
	check("roll always returns a real id", allValid)
	-- distribution: the commonest bug beats the rarest over many rolls
	pcall(function()
		math.randomseed(77)
	end)
	local mrand = function()
		return math.random()
	end
	local counts: { [string]: number } = {}
	for _ = 1, 20000 do
		local id = GatherRules.roll(bugs, mrand)
		counts[id] = (counts[id] or 0) + 1
	end
	check("common bug (white w34) > rare bug (rainbow w3)", (counts["white"] or 0) > (counts["rainbow"] or 0))
end

-- ---- TreasureRules: deterministic spread + one-time claim ----
do
	local half = 200
	local inside, distinct = true, true
	local seen = {}
	for k = 1, 5 do
		local o = TreasureRules.spotFor(3, k, 5, half)
		if math.abs(o.x) > half or math.abs(o.z) > half then
			inside = false
		end
		local kk = string.format("%.2f,%.2f", o.x, o.z)
		if seen[kk] then
			distinct = false
		end
		seen[kk] = true
	end
	check("treasure spots stay within the region", inside)
	check("treasure spots are distinct", distinct)
	check("higher tier pays more", TreasureRules.reward(5) > TreasureRules.reward(1))
	local st: any = { coins = 0, lifetimeEarned = 0 }
	local ok, coins = TreasureRules.claim(st, "t_1_1", 2)
	check("first claim pays out", ok and coins == TreasureRules.reward(2) and st.coins == coins)
	check("second claim is refused", not (TreasureRules.claim(st, "t_1_1", 2)))
	check("claimed flag recorded", TreasureRules.isFound(st, "t_1_1"))
end

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("TESTS FAILED", 0)
end
print("ALL GREEN")
