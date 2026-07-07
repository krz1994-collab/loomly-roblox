--!strict
-- Biome: the single starting biome for the slice.
--
-- SCHEMA (spec §2.4): { id, unlock, plantIds, fish, bugs, weatherEvents, mutationBias }
--   plantIds     = which crops grow here (ids into Plants)
--   mutationBias = { [mutationId] = multiplier } applied to that mutation's roll chance in
--                  this biome (e.g. winter biases "frosted" x2.0). Empty here = no bias.
--   fish/bugs/weatherEvents = collection content for later phases; empty in the slice.
--
-- Target is 5 biomes (§2.4); the slice ships ONE, fully working. Adding a biome later = adding a row.

export type Biome = {
	id: string,
	unlock: { type: string, ref: string?, v: number? },
	plantIds: { string },
	fish: { string },
	bugs: { string },
	weatherEvents: { string },
	mutationBias: { [string]: number },
}

local Meadow: Biome = {
	id = "meadow",
	unlock = { type = "start" },
	plantIds = { "radish", "sunflower", "strawberry", "pumpkin", "blueberry", "starbloom", "moonberry", "crystalrose" },
	fish = {},
	bugs = {},
	weatherEvents = {},
	mutationBias = {}, -- no bias in meadow: every mutation rolls at its base chance
}

local B = {}
B.list = { Meadow }
B.STARTER_ID = "meadow"

local byId: { [string]: Biome } = {}
for _, b in B.list do
	byId[b.id] = b
end

function B.get(biomeId: string): Biome?
	return byId[biomeId]
end

return B
