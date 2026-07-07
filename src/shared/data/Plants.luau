--!strict
-- Plants: the meadow biome's crop table for the vertical slice (6 of the web game's 8).
--
-- SCHEMA (spec §2.1): { id, biome, emoji, cost, growMs, sell, tier, unlock }
--   cost    = seed price (coin sink; not charged in this slice yet -- see Farm.plant TODO)
--   growMs  = grow time in MILLISECONDS (ported field name; server converts to seconds)
--   sell    = base NPC sell price = the "baseValue" in the spec's pricing math (§3.3)
--   tier    = 1..6 difficulty/value tier (metadata; the geometric sell ramp)
--   unlock  = { type = "start"|"earned"|"plot"|"codex", v=?, n=? }
--
-- VALUES PORTED VERBATIM from web economy.js PLANTS (the balance is the reuse; the code is not).
-- Adding more crops later = adding rows here. No logic changes.

export type Unlock = { type: string, v: number?, n: number?, ref: string? }
export type Plant = {
	id: string,
	biome: string,
	emoji: string,
	cost: number,
	growMs: number,
	sell: number,
	tier: number,
	unlock: Unlock,
}

local Plants: { Plant } = {
	{ id = "radish",     biome = "meadow", emoji = "🥕", cost = 5,   growMs = 20000,  sell = 9,    tier = 1, unlock = { type = "start" } },
	{ id = "sunflower",  biome = "meadow", emoji = "🌻", cost = 12,  growMs = 45000,  sell = 25,   tier = 2, unlock = { type = "start" } },
	{ id = "strawberry", biome = "meadow", emoji = "🍓", cost = 30,  growMs = 90000,  sell = 70,   tier = 3, unlock = { type = "earned", v = 100 } },
	{ id = "pumpkin",    biome = "meadow", emoji = "🎃", cost = 80,  growMs = 180000, sell = 200,  tier = 4, unlock = { type = "plot", n = 4 } },
	{ id = "blueberry",  biome = "meadow", emoji = "🫐", cost = 200, growMs = 360000, sell = 520,  tier = 5, unlock = { type = "earned", v = 1000 } },
	{ id = "starbloom",  biome = "meadow", emoji = "🌟", cost = 500,  growMs = 720000,   sell = 1400, tier = 6, unlock = { type = "plot", n = 6 } },
	{ id = "moonberry",  biome = "meadow", emoji = "🌙", cost = 1200, growMs = 1500000,  sell = 3600, tier = 7, unlock = { type = "earned", v = 10000 } },
	{ id = "crystalrose",biome = "meadow", emoji = "💎", cost = 3000, growMs = 2700000,  sell = 9500, tier = 8, unlock = { type = "codex", n = 5 } },
	-- ── Enchanted Forest crops (block 15): magic crops, unlocked LATE, biased toward top mutations ──
	{ id = "wispberry",  biome = "enchanted", emoji = "🔮", cost = 6000,  growMs = 1800000,  sell = 16000, tier = 9,  unlock = { type = "earned", v = 50000 } },
	{ id = "fairybloom", biome = "enchanted", emoji = "🧚", cost = 12000, growMs = 2400000,  sell = 34000, tier = 10, unlock = { type = "earned", v = 120000 } },
	{ id = "moonpetal",  biome = "enchanted", emoji = "🌸", cost = 24000, growMs = 3000000,  sell = 70000, tier = 11, unlock = { type = "earned", v = 300000 } },
	{ id = "dreamroot",  biome = "enchanted", emoji = "💠", cost = 48000, growMs = 3600000,  sell = 150000, tier = 12, unlock = { type = "codex", n = 12 } },
	{ id = "glimmergrass",biome = "enchanted",emoji = "✨", cost = 90000, growMs = 4200000,  sell = 320000, tier = 13, unlock = { type = "earned", v = 1000000 } },
	-- ── Per-island biome crops (content): each line unlocks when you complete that island's quest
	--    (reward sets the "islandN" flag). Sail there, do the NPC's quest, then plant them at home. ──
	-- island 1 Sunny Beach
	{ id = "beachmelon", biome = "beach", emoji = "🍈", cost = 48, growMs = 60000, sell = 120, tier = 3, unlock = { type = "unlock", ref = "island1" } },
	{ id = "coconut", biome = "beach", emoji = "🥥", cost = 72, growMs = 90000, sell = 180, tier = 3, unlock = { type = "unlock", ref = "island1" } },
	{ id = "seaoat", biome = "beach", emoji = "🌾", cost = 104, growMs = 120000, sell = 260, tier = 3, unlock = { type = "unlock", ref = "island1" } },
	-- island 2 Whispering Woods
	{ id = "wildberry", biome = "woods", emoji = "🫐", cost = 80, growMs = 90000, sell = 200, tier = 4, unlock = { type = "unlock", ref = "island2" } },
	{ id = "mossbloom", biome = "woods", emoji = "🌼", cost = 120, growMs = 120000, sell = 300, tier = 4, unlock = { type = "unlock", ref = "island2" } },
	{ id = "acorn", biome = "woods", emoji = "🌰", cost = 168, growMs = 160000, sell = 420, tier = 4, unlock = { type = "unlock", ref = "island2" } },
	-- island 3 Frostpeak (slow, high value)
	{ id = "frostberry", biome = "ice", emoji = "❄️", cost = 140, growMs = 150000, sell = 350, tier = 5, unlock = { type = "unlock", ref = "island3" } },
	{ id = "snowpea", biome = "ice", emoji = "🟢", cost = 200, growMs = 200000, sell = 500, tier = 5, unlock = { type = "unlock", ref = "island3" } },
	{ id = "iceblossom", biome = "ice", emoji = "🌨️", cost = 280, growMs = 260000, sell = 700, tier = 5, unlock = { type = "unlock", ref = "island3" } },
	-- island 4 Volcano Isle
	{ id = "emberberry", biome = "volcano", emoji = "🔥", cost = 220, growMs = 180000, sell = 550, tier = 6, unlock = { type = "unlock", ref = "island4" } },
	{ id = "lavaroot", biome = "volcano", emoji = "🌶️", cost = 320, growMs = 240000, sell = 800, tier = 6, unlock = { type = "unlock", ref = "island4" } },
	{ id = "magmapepper", biome = "volcano", emoji = "🫑", cost = 440, growMs = 320000, sell = 1100, tier = 6, unlock = { type = "unlock", ref = "island4" } },
	-- island 5 Golden Dunes
	{ id = "cactusfruit", biome = "desert", emoji = "🌵", cost = 340, growMs = 220000, sell = 850, tier = 7, unlock = { type = "unlock", ref = "island5" } },
	{ id = "goldenwheat", biome = "desert", emoji = "🌾", cost = 480, growMs = 300000, sell = 1200, tier = 7, unlock = { type = "unlock", ref = "island5" } },
	{ id = "sandmelon", biome = "desert", emoji = "🍈", cost = 640, growMs = 400000, sell = 1600, tier = 7, unlock = { type = "unlock", ref = "island5" } },
	-- island 6 Crystal Cove
	{ id = "crystalmoss", biome = "cave", emoji = "💠", cost = 520, growMs = 260000, sell = 1300, tier = 8, unlock = { type = "unlock", ref = "island6" } },
	{ id = "glowvine", biome = "cave", emoji = "💚", cost = 720, growMs = 340000, sell = 1800, tier = 8, unlock = { type = "unlock", ref = "island6" } },
	{ id = "voidberry", biome = "cave", emoji = "🟣", cost = 1000, growMs = 440000, sell = 2500, tier = 8, unlock = { type = "unlock", ref = "island6" } },
	-- island 7 Mushroom Grove
	{ id = "glowcap", biome = "grove", emoji = "🍄", cost = 800, growMs = 300000, sell = 2000, tier = 9, unlock = { type = "unlock", ref = "island7" } },
	{ id = "nightbloom", biome = "grove", emoji = "🌸", cost = 1120, growMs = 400000, sell = 2800, tier = 9, unlock = { type = "unlock", ref = "island7" } },
	{ id = "sporefern", biome = "grove", emoji = "🌿", cost = 1520, growMs = 520000, sell = 3800, tier = 9, unlock = { type = "unlock", ref = "island7" } },
	-- island 8 Windy Cliffs
	{ id = "cloudberry", biome = "mountain", emoji = "☁️", cost = 1280, growMs = 360000, sell = 3200, tier = 10, unlock = { type = "unlock", ref = "island8" } },
	{ id = "peakflower", biome = "mountain", emoji = "🌺", cost = 1800, growMs = 480000, sell = 4500, tier = 10, unlock = { type = "unlock", ref = "island8" } },
	{ id = "windgrass", biome = "mountain", emoji = "🍃", cost = 2400, growMs = 620000, sell = 6000, tier = 10, unlock = { type = "unlock", ref = "island8" } },
	-- island 9 Coral Reef
	{ id = "kelp", biome = "reef", emoji = "🌿", cost = 2000, growMs = 420000, sell = 5000, tier = 11, unlock = { type = "unlock", ref = "island9" } },
	{ id = "pearlrice", biome = "reef", emoji = "🍚", cost = 2800, growMs = 560000, sell = 7000, tier = 11, unlock = { type = "unlock", ref = "island9" } },
	{ id = "coralbloom", biome = "reef", emoji = "🪸", cost = 3800, growMs = 720000, sell = 9500, tier = 11, unlock = { type = "unlock", ref = "island9" } },
	-- island 10 Misty Highlands
	{ id = "mistherb", biome = "highland", emoji = "🌿", cost = 3200, growMs = 480000, sell = 8000, tier = 12, unlock = { type = "unlock", ref = "island10" } },
	{ id = "relicroot", biome = "highland", emoji = "🥀", cost = 4400, growMs = 640000, sell = 11000, tier = 12, unlock = { type = "unlock", ref = "island10" } },
	{ id = "dewlily", biome = "highland", emoji = "🌷", cost = 6000, growMs = 840000, sell = 15000, tier = 12, unlock = { type = "unlock", ref = "island10" } },
}

local P = {}
P.list = Plants

local byId: { [string]: Plant } = {}
for _, p in Plants do
	byId[p.id] = p
end

function P.get(plantId: string): Plant?
	return byId[plantId]
end

-- Is this crop plantable for a given player right now?
-- Called on the SERVER before honoring a plant() intent (never trust the client's seed pick),
-- and used to build the "unlocked seeds" list the client renders.
--   state       = the player's authoritative data (needs .lifetimeEarned)
--   ownedPlots  = how many plots the player owns (slice: Config.PLOT_COUNT)
function P.isUnlocked(plant: Plant, state: { lifetimeEarned: number, codex: { [string]: boolean }?, unlocks: { [string]: boolean }? }, ownedPlots: number): boolean
	local u = plant.unlock
	if u.type == "start" then
		return true
	elseif u.type == "earned" then
		return state.lifetimeEarned >= (u.v or 0)
	elseif u.type == "plot" then
		return ownedPlots >= (u.n or 0)
	elseif u.type == "unlock" then
		-- gated behind an island (or feature) unlock flag set by a quest reward, e.g. "island4".
		return state.unlocks ~= nil and state.unlocks[u.ref or ""] == true
	elseif u.type == "codex" then
		-- unlocked once you've DISCOVERED `n` distinct plant species (any mutation counts once).
		local species: { [string]: boolean } = {}
		if state.codex then
			for key in state.codex do
				species[(string.gsub(key, "|.*$", ""))] = true
			end
		end
		local count = 0
		for _ in species do
			count += 1
		end
		return count >= (u.n or 0)
	end
	return false
end

return P
