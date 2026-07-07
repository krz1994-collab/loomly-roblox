--!strict
-- Pets: adoptable companions (content). Each has a passive ABILITY that boosts one earned dimension
-- (coins / luck / grow) while equipped -- NEVER pay-to-win: pets are bought with in-game coins or
-- hatched from earned eggs, and the bonuses are modest + capped. `rarity` weights egg hatching (higher
-- = rarer = less likely). Costs mirror Catalog.Pets.

export type Pet = {
	id: string,
	name: string,
	emoji: string,
	cost: number,
	rarity: number, -- 1 common .. 6 legendary (also the hatch-weight tier)
	ability: { type: string, value: number }, -- type in {coins,luck,grow}; value = +fraction while equipped
}

local Pets: { Pet } = {
	{ id = "chick", name = "Chick", emoji = "🐤", cost = 600, rarity = 1, ability = { type = "coins", value = 0.03 } },
	{ id = "cat", name = "Cat", emoji = "🐱", cost = 2500, rarity = 2, ability = { type = "luck", value = 0.08 } },
	{ id = "dog", name = "Dog", emoji = "🐶", cost = 2500, rarity = 2, ability = { type = "coins", value = 0.06 } },
	{ id = "bunny", name = "Bunny", emoji = "🐰", cost = 6000, rarity = 3, ability = { type = "grow", value = 0.05 } },
	{ id = "parrot", name = "Parrot", emoji = "🦜", cost = 12000, rarity = 3, ability = { type = "luck", value = 0.15 } },
	{ id = "turtle", name = "Turtle", emoji = "🐢", cost = 18000, rarity = 4, ability = { type = "coins", value = 0.12 } },
	{ id = "fox", name = "Fox", emoji = "🦊", cost = 30000, rarity = 4, ability = { type = "luck", value = 0.20 } },
	{ id = "dragon", name = "Dragon", emoji = "🐲", cost = 40000, rarity = 5, ability = { type = "grow", value = 0.15 } },
	{ id = "unicorn", name = "Unicorn", emoji = "🦄", cost = 120000, rarity = 6, ability = { type = "luck", value = 0.35 } },
}

local M = {}
M.list = Pets
local byId: { [string]: Pet } = {}
for _, p in Pets do
	byId[p.id] = p
end
function M.get(id: string): Pet?
	return byId[id]
end
return M
