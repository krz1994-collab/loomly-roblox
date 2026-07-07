--!strict
-- Trees: fruit-tree species (pure data) for the ORCHARD (block 7). You buy a tree into an orchard
-- slot; it then produces `fruitId` fruit every `cycleSec` seconds up to `cap`, which you PICK (banks
-- "fruit|<fruitId>" into inventory, sold at the Market like any gathered item). The Greenhouse upgrade
-- shortens every tree's cycle. Higher-tier trees cost more + ripen slower but pay far more per fruit.
--   Item key in inventory/sell = "fruit|<fruitId>".

export type Tree = {
	id: string,
	name: string,
	emoji: string,
	fruitId: string,
	fruitEmoji: string,
	fruitSell: number,
	cycleSec: number, -- seconds per 1 fruit (before Greenhouse speed-up)
	cap: number, -- max fruit that can accrue before you must pick (come-back cap)
	cost: number, -- coins to plant this tree in a slot
	unlockLevel: number, -- player level required to buy
}

local Trees: { Tree } = {
	{ id = "apple", name = "Apple Tree", emoji = "🍎", fruitId = "apple", fruitEmoji = "🍎", fruitSell = 18, cycleSec = 90, cap = 8, cost = 300, unlockLevel = 1 },
	{ id = "orange", name = "Orange Tree", emoji = "🍊", fruitId = "orange", fruitEmoji = "🍊", fruitSell = 26, cycleSec = 120, cap = 8, cost = 600, unlockLevel = 4 },
	{ id = "cherry", name = "Cherry Tree", emoji = "🍒", fruitId = "cherry", fruitEmoji = "🍒", fruitSell = 40, cycleSec = 150, cap = 6, cost = 1100, unlockLevel = 7 },
	{ id = "peach", name = "Peach Tree", emoji = "🍑", fruitId = "peach", fruitEmoji = "🍑", fruitSell = 60, cycleSec = 200, cap = 6, cost = 2000, unlockLevel = 10 },
	{ id = "pear", name = "Pear Tree", emoji = "🍐", fruitId = "pear", fruitEmoji = "🍐", fruitSell = 85, cycleSec = 240, cap = 6, cost = 3200, unlockLevel = 13 },
	{ id = "plum", name = "Plum Tree", emoji = "🫐", fruitId = "plum", fruitEmoji = "🫐", fruitSell = 120, cycleSec = 300, cap = 5, cost = 5000, unlockLevel = 16 },
	{ id = "mango", name = "Mango Tree", emoji = "🥭", fruitId = "mango", fruitEmoji = "🥭", fruitSell = 175, cycleSec = 360, cap = 5, cost = 8000, unlockLevel = 20 },
	{ id = "goldapple", name = "Golden Apple Tree", emoji = "🌟", fruitId = "goldapple", fruitEmoji = "🌟", fruitSell = 320, cycleSec = 480, cap = 4, cost = 16000, unlockLevel = 26 },
}

local T = {}
T.list = Trees
-- Fruit rows (id/emoji/sell) so the Market can price a "fruit|<id>" inventory key.
local Fruits: { { id: string, emoji: string, sell: number } } = {}
local byId: { [string]: Tree } = {}
for _, t in Trees do
	byId[t.id] = t
	table.insert(Fruits, { id = t.fruitId, emoji = t.fruitEmoji, sell = t.fruitSell })
end
T.Fruits = Fruits
function T.get(id: string): Tree?
	return byId[id]
end
return T
