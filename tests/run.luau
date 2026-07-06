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

print(string.format("\n%d passed, %d failed", passed, failed))
if failed > 0 then
	error("TESTS FAILED", 0)
end
print("ALL GREEN")
