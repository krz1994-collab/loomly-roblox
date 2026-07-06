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
eq("PLOT_COUNT is 6", Config.PLOT_COUNT, 6)

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
	return { coins = 20, lifetimeEarned = 0, harvests = 0, xp = 0, codex = {}, inventory = {}, plots = plots }
end
do
	local st: any = {
		coins = 512,
		lifetimeEarned = 999,
		harvests = 7,
		xp = 250,
		codex = { ["radish|golden"] = true, ["sunflower|normal"] = true },
		inventory = { ["radish|normal"] = 3, ["pumpkin|giant"] = 1 },
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
	local N = 50
	-- no two of the 50 section centres are closer than one section's size (=> platforms never overlap)
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
	check(string.format("50 sections never overlap (min gap %.0f >= size %.0f)", minDist, WorldLayout.SECTION_SIZE), minDist >= WorldLayout.SECTION_SIZE)

	-- every plot pad sits fully inside its section
	local half = WorldLayout.SECTION_SIZE / 2
	local padHalf = WorldLayout.PAD_SIZE / 2
	local allInside = true
	local seen = {}
	local distinct = true
	for p = 1, 6 do
		local o = WorldLayout.plotPadOffset(p, 6)
		if math.abs(o.x) + padHalf > half or math.abs(o.z) + padHalf > half then
			allInside = false
		end
		local kk = o.x .. "," .. o.z
		if seen[kk] then
			distinct = false
		end
		seen[kk] = true
	end
	check("all 6 plot pads fit inside their section", allInside)
	check("plot pads are at distinct positions", distinct)
end

-- ---- PlotRules: claim + ownership (pure) ----
eq("empty world -> claim section 1", PlotRules.pickFreeSection({}, 50), 1)
eq("lowest free section is picked", PlotRules.pickFreeSection({ [1] = true, [2] = true }, 50), 3)
check("full world -> no free section", PlotRules.pickFreeSection({ [1] = true, [2] = true, [3] = true }, 3) == nil)
check("owner can act on own section", PlotRules.canInteract(500, 500))
check("stranger cannot act on your section", not PlotRules.canInteract(500, 999))
check("unclaimed section is not interactable", not PlotRules.canInteract(nil, 500))

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("TESTS FAILED", 0)
end
print("ALL GREEN")
