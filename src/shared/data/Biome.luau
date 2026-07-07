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

-- Enchanted Forest (block 15, island 11): magic crops that lean hard toward the top mutation tiers.
-- mutationBias multiplies each listed mutation's roll chance when a crop of this biome is harvested
-- (applied in Farm.harvest). Everything here is earned play, never pay-to-win.
local Enchanted: Biome = {
	id = "enchanted",
	unlock = { type = "quest", ref = "isle_enchanted" },
	plantIds = { "wispberry", "fairybloom", "moonpetal", "dreamroot", "glimmergrass" },
	fish = {},
	bugs = {},
	weatherEvents = { "fairy_mischief", "firefly_fest", "enchanted_bloom" },
	mutationBias = { bloomly = 3, mythic = 3, celestial = 2.5, rainbow = 2 },
}

local B = {}
B.list = { Meadow, Enchanted }
B.STARTER_ID = "meadow"

local byId: { [string]: Biome } = {}
for _, b in B.list do
	byId[b.id] = b
end

function B.get(biomeId: string): Biome?
	return byId[biomeId]
end

return B
