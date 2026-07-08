--!strict
-- Monsters: the creatures you fight on the islands (Tibia-flavoured combat, RPG block 3). Each has hp,
-- an xp + coin reward, and a chance to drop a loot item (a "loot|<id>" inventory item, sellable at the
-- Market like any gathered good). Combat is press-E-to-hit for now (kid-safe, no physics tuning); a real
-- weapon tool can layer on later. `island` = which island it spawns on.

export type Monster = {
	id: string,
	name: string,
	emoji: string,
	hp: number,
	xp: number,
	coins: number,
	island: number,
	color: { number },
	loot: { id: string, emoji: string, sell: number, chance: number }?,
}

local M = {}

local Monsters: { Monster } = {
	{ id = "slime", name = "Green Slime", emoji = "🟢", hp = 40, xp = 15, coins = 20, island = 1, color = { 90, 200, 110 }, loot = { id = "slimegel", emoji = "🫧", sell = 30, chance = 0.6 } },
	{ id = "wolf", name = "Dire Wolf", emoji = "🐺", hp = 80, xp = 30, coins = 40, island = 2, color = { 110, 110, 120 }, loot = { id = "wolfpelt", emoji = "🟫", sell = 60, chance = 0.5 } },
	{ id = "yeti", name = "Frost Yeti", emoji = "🧊", hp = 220, xp = 110, coins = 160, island = 3, color = { 200, 225, 240 }, loot = { id = "frostcore", emoji = "❄️", sell = 220, chance = 0.4 } },
	{ id = "skeleton", name = "Skeleton", emoji = "💀", hp = 120, xp = 55, coins = 75, island = 4, color = { 225, 225, 210 }, loot = { id = "bone", emoji = "🦴", sell = 90, chance = 0.55 } },
	{ id = "dragon", name = "Baby Dragon", emoji = "🐉", hp = 500, xp = 300, coins = 500, island = 4, color = { 200, 70, 60 }, loot = { id = "dragonscale", emoji = "🔥", sell = 800, chance = 0.35 } },
	{ id = "scorpion", name = "Desert Scorpion", emoji = "🦂", hp = 100, xp = 45, coins = 60, island = 5, color = { 210, 170, 90 }, loot = { id = "venom", emoji = "🟣", sell = 110, chance = 0.5 } },
	{ id = "troll", name = "Cave Troll", emoji = "👹", hp = 260, xp = 130, coins = 200, island = 6, color = { 120, 150, 110 }, loot = { id = "trollhide", emoji = "🟩", sell = 260, chance = 0.4 } },
	{ id = "spore", name = "Spore Beast", emoji = "🍄", hp = 140, xp = 60, coins = 85, island = 7, color = { 180, 120, 190 }, loot = { id = "spore", emoji = "💮", sell = 120, chance = 0.5 } },
	{ id = "harpy", name = "Cliff Harpy", emoji = "🦅", hp = 160, xp = 70, coins = 100, island = 8, color = { 150, 160, 180 }, loot = { id = "feather", emoji = "🪶", sell = 140, chance = 0.5 } },
	{ id = "crab", name = "Giant Crab", emoji = "🦀", hp = 130, xp = 55, coins = 80, island = 9, color = { 220, 120, 90 }, loot = { id = "pearl", emoji = "🦪", sell = 200, chance = 0.4 } },
	{ id = "wraith", name = "Mist Wraith", emoji = "👻", hp = 300, xp = 150, coins = 240, island = 10, color = { 190, 200, 220 }, loot = { id = "ectoplasm", emoji = "🌫️", sell = 320, chance = 0.4 } },
	{ id = "fae", name = "Wild Fae", emoji = "🧚", hp = 380, xp = 220, coins = 360, island = 11, color = { 210, 140, 240 }, loot = { id = "faedust", emoji = "✨", sell = 500, chance = 0.5 } },
}

M.list = Monsters
local byId: { [string]: Monster } = {}
for _, m in Monsters do
	byId[m.id] = m
end
function M.get(id: string): Monster?
	return byId[id]
end

-- Loot rows (id/emoji/sell) so the Market can price a "loot|<id>" inventory item.
M.Loot = {}
for _, m in Monsters do
	if m.loot then
		table.insert(M.Loot, { id = m.loot.id, emoji = m.loot.emoji, sell = m.loot.sell })
	end
end

return M
