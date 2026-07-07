--!strict
-- House: the player's HOUSE (block 10). An upgradeable building (Tent -> Castle) that generates
-- passive RENT coins over time (collect at the door, capped so you must come back) and holds DECOR you
-- buy + place for a cozy look (and a small rent bonus). Tier 0 = starter tent. Pure math lives in
-- HouseRules; this is the data.

export type Tier = { name: string, emoji: string, rentPerMin: number, rentCap: number, upgradeCost: number } -- upgradeCost = coins to REACH this tier

export type Decor = { id: string, name: string, emoji: string, cost: number, rentBonusPerMin: number, unlockTier: number }

local H = {}

-- Index by tier number 0..MAX. TIERS[0] = the free starter. upgradeCost = cost to reach that tier.
local TIERS: { [number]: Tier } = {
	[0] = { name = "Tent", emoji = "⛺", rentPerMin = 1, rentCap = 60, upgradeCost = 0 },
	[1] = { name = "Cabin", emoji = "🛖", rentPerMin = 3, rentCap = 180, upgradeCost = 1000 },
	[2] = { name = "Cottage", emoji = "🏡", rentPerMin = 7, rentCap = 420, upgradeCost = 3500 },
	[3] = { name = "House", emoji = "🏠", rentPerMin = 15, rentCap = 900, upgradeCost = 9000 },
	[4] = { name = "Villa", emoji = "🏘️", rentPerMin = 30, rentCap = 1800, upgradeCost = 22000 },
	[5] = { name = "Mansion", emoji = "🏰", rentPerMin = 60, rentCap = 3600, upgradeCost = 50000 },
	[6] = { name = "Castle", emoji = "🏯", rentPerMin = 120, rentCap = 7200, upgradeCost = 120000 },
}
H.MAX = 6

local DECOR: { Decor } = {
	{ id = "rug", name = "Cozy Rug", emoji = "🟫", cost = 400, rentBonusPerMin = 1, unlockTier = 0 },
	{ id = "lamp", name = "Lamp", emoji = "🪔", cost = 700, rentBonusPerMin = 2, unlockTier = 1 },
	{ id = "plant", name = "House Plant", emoji = "🪴", cost = 1000, rentBonusPerMin = 3, unlockTier = 1 },
	{ id = "painting", name = "Painting", emoji = "🖼️", cost = 2500, rentBonusPerMin = 5, unlockTier = 2 },
	{ id = "fireplace", name = "Fireplace", emoji = "🔥", cost = 5000, rentBonusPerMin = 9, unlockTier = 3 },
	{ id = "piano", name = "Grand Piano", emoji = "🎹", cost = 12000, rentBonusPerMin = 18, unlockTier = 4 },
	{ id = "chandelier", name = "Chandelier", emoji = "💎", cost = 30000, rentBonusPerMin = 40, unlockTier = 5 },
}

function H.tierData(tier: number): Tier?
	return TIERS[tier]
end
function H.upgradeCost(tier: number): number?
	local next = TIERS[tier + 1]
	return if next then next.upgradeCost else nil
end
H.decorList = DECOR
local decorById: { [string]: Decor } = {}
for _, d in DECOR do
	decorById[d.id] = d
end
function H.getDecor(id: string): Decor?
	return decorById[id]
end
return H
