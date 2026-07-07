--!strict
-- Animals: farm animals (pure data) for the PEN (block 8). Buy an animal into a pen slot; it produces
-- `productId` every `produceSec` up to `cap`, which you COLLECT ("product|<productId>" -> inventory,
-- sold at the Market). Two same-species adult animals can BREED (see AnimalRules) into a rarer baby.
--   Item key in inventory/sell = "product|<productId>".

export type Animal = {
	id: string,
	name: string,
	emoji: string,
	productId: string,
	productEmoji: string,
	productSell: number,
	produceSec: number,
	cap: number,
	cost: number,
	unlockLevel: number,
	tier: number, -- 1 common .. used by breeding to pick a rarer offspring
}

local Animals: { Animal } = {
	{ id = "chicken", name = "Chicken", emoji = "🐔", productId = "egg", productEmoji = "🥚", productSell = 15, produceSec = 80, cap = 10, cost = 250, unlockLevel = 1, tier = 1 },
	{ id = "cow", name = "Cow", emoji = "🐄", productId = "milk", productEmoji = "🥛", productSell = 30, produceSec = 140, cap = 8, cost = 700, unlockLevel = 4, tier = 1 },
	{ id = "sheep", name = "Sheep", emoji = "🐑", productId = "wool", productEmoji = "🧶", productSell = 45, produceSec = 180, cap = 8, cost = 1300, unlockLevel = 7, tier = 2 },
	{ id = "pig", name = "Pig", emoji = "🐖", productId = "truffle", productEmoji = "🍄", productSell = 70, produceSec = 220, cap = 6, cost = 2400, unlockLevel = 10, tier = 2 },
	{ id = "goat", name = "Goat", emoji = "🐐", productId = "cheese", productEmoji = "🧀", productSell = 100, produceSec = 260, cap = 6, cost = 4000, unlockLevel = 13, tier = 3 },
	{ id = "duck", name = "Duck", emoji = "🦆", productId = "downfeather", productEmoji = "🪶", productSell = 140, produceSec = 300, cap = 6, cost = 6500, unlockLevel = 16, tier = 3 },
	{ id = "bee", name = "Honey Bee", emoji = "🐝", productId = "royaljelly", productEmoji = "🍯", productSell = 210, produceSec = 340, cap = 5, cost = 10000, unlockLevel = 20, tier = 4 },
	{ id = "unicorn", name = "Unicorn", emoji = "🦄", productId = "stardust", productEmoji = "✨", productSell = 400, produceSec = 480, cap = 4, cost = 22000, unlockLevel = 27, tier = 5 },
}

local A = {}
A.list = Animals
local Products: { { id: string, emoji: string, sell: number } } = {}
local byId: { [string]: Animal } = {}
local byTier: { [number]: { Animal } } = {}
for _, a in Animals do
	byId[a.id] = a
	table.insert(Products, { id = a.productId, emoji = a.productEmoji, sell = a.productSell })
	byTier[a.tier] = byTier[a.tier] or {}
	table.insert(byTier[a.tier], a)
end
A.Products = Products
function A.get(id: string): Animal?
	return byId[id]
end
-- Lowest-tier animal at or above `tier` (used by breeding to award a rarer baby). Falls back to the
-- highest tier that exists.
function A.firstOfTier(tier: number): Animal?
	local best: Animal? = nil
	for _, a in Animals do
		if a.tier >= tier then
			if best == nil or a.tier < best.tier then
				best = a
			end
		end
	end
	return best
end
return A
