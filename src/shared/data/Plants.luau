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
	{ id = "starbloom",  biome = "meadow", emoji = "🌟", cost = 500, growMs = 720000, sell = 1400, tier = 6, unlock = { type = "plot", n = 6 } },
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
function P.isUnlocked(plant: Plant, state: { lifetimeEarned: number }, ownedPlots: number): boolean
	local u = plant.unlock
	if u.type == "start" then
		return true
	elseif u.type == "earned" then
		return state.lifetimeEarned >= (u.v or 0)
	elseif u.type == "plot" then
		return ownedPlots >= (u.n or 0)
	end
	-- "codex" and any future type: not supported in the slice -> locked. Add the rule when the
	-- feature it gates (codex/collection) exists. Returning false is the safe default.
	return false
end

return P
