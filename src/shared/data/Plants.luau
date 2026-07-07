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

export type Unlock = { type: string, v: number?, n: number? }
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
function P.isUnlocked(plant: Plant, state: { lifetimeEarned: number, codex: { [string]: boolean }? }, ownedPlots: number): boolean
	local u = plant.unlock
	if u.type == "start" then
		return true
	elseif u.type == "earned" then
		return state.lifetimeEarned >= (u.v or 0)
	elseif u.type == "plot" then
		return ownedPlots >= (u.n or 0)
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
