--!strict
-- Recipes: cooking recipes (pure data) for the KITCHEN (block 9). A recipe consumes `needs`
-- (inventory keys -> qty), cooks for `cookSec`, then yields a "dish|<id>" item worth `sell` + `xp`.
-- Dishes sell at the Market like anything else (later: temporary buffs). Ingredients reference real
-- inventory keys already in the game: crops "carrot|normal", fruit "fruit|apple", products
-- "product|egg"/"product|milk", gathered "fish|carp", honey "honey|honey".
--   Item key in inventory/sell = "dish|<id>".

export type Recipe = {
	id: string,
	name: string,
	emoji: string,
	needs: { [string]: number },
	cookSec: number,
	sell: number,
	xp: number,
	unlockLevel: number,
}

local Recipes: { Recipe } = {
	{ id = "salad", name = "Garden Salad", emoji = "🥗", needs = { ["carrot|normal"] = 1, ["radish|normal"] = 1 }, cookSec = 30, sell = 60, xp = 8, unlockLevel = 2 },
	{ id = "pie", name = "Apple Pie", emoji = "🥧", needs = { ["fruit|apple"] = 2, ["product|egg"] = 1 }, cookSec = 60, sell = 130, xp = 16, unlockLevel = 5 },
	{ id = "omelette", name = "Farm Omelette", emoji = "🍳", needs = { ["product|egg"] = 2, ["product|milk"] = 1 }, cookSec = 45, sell = 110, xp = 14, unlockLevel = 5 },
	{ id = "soup", name = "Pumpkin Soup", emoji = "🍲", needs = { ["pumpkin|normal"] = 1, ["product|milk"] = 1 }, cookSec = 70, sell = 160, xp = 18, unlockLevel = 8 },
	{ id = "sushi", name = "Reef Sushi", emoji = "🍣", needs = { ["fish|carp"] = 2, ["carrot|normal"] = 1 }, cookSec = 90, sell = 220, xp = 24, unlockLevel = 11 },
	{ id = "cheese_board", name = "Cheese Board", emoji = "🧀", needs = { ["product|cheese"] = 2, ["fruit|pear"] = 1 }, cookSec = 110, sell = 320, xp = 32, unlockLevel = 14 },
	{ id = "honey_cake", name = "Honey Cake", emoji = "🍰", needs = { ["honey|honey"] = 2, ["product|egg"] = 2, ["fruit|peach"] = 1 }, cookSec = 140, sell = 460, xp = 44, unlockLevel = 17 },
	{ id = "feast", name = "Grand Feast", emoji = "🍱", needs = { ["dish|pie"] = 1, ["dish|sushi"] = 1, ["product|truffle"] = 1 }, cookSec = 200, sell = 900, xp = 80, unlockLevel = 22 },
}

local R = {}
R.list = Recipes
local byId: { [string]: Recipe } = {}
for _, r in Recipes do
	byId[r.id] = r
end
function R.get(id: string): Recipe?
	return byId[id]
end
return R
