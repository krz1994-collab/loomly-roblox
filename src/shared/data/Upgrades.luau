--!strict
-- Upgrades: buyable upgrade TRACKS (pure data). Each track has a geometric cost ramp (easy start,
-- never a wall) and a per-level effect. The pure UpgradeRules module computes cost + effect; the
-- shell (a plaza kiosk + the `upgrade` prompt) buys them and re-applies the effect.
--   effectAt(level) = base + level * perLevel   (see UpgradeRules)

export type Track = {
	id: string,
	name: string,
	emoji: string,
	maxLevel: number,
	baseCost: number,
	growth: number, -- cost = floor(baseCost * growth^level)
	base: number, -- effect at level 0
	perLevel: number, -- effect added per level
}

local Upgrades: { Track } = {
	{ id = "plots", name = "Farm Plots", emoji = "🌱", maxLevel = 6, baseCost = 250, growth = 2.0, base = 6, perLevel = 1 }, -- 6 -> 12 plots
	{ id = "sellBonus", name = "Market Deal", emoji = "💰", maxLevel = 10, baseCost = 500, growth = 1.6, base = 1.0, perLevel = 0.05 }, -- +5% sell / level
	{ id = "growSpeed", name = "Fast Growth", emoji = "⚡", maxLevel = 10, baseCost = 400, growth = 1.6, base = 1.0, perLevel = 0.08 }, -- crops grow +8% faster / level
	{ id = "walkSpeed", name = "Swift Boots", emoji = "👟", maxLevel = 8, baseCost = 300, growth = 1.7, base = 1.0, perLevel = 0.06 }, -- +6% walk / level
	{ id = "luck", name = "Lucky Charm", emoji = "🍀", maxLevel = 8, baseCost = 1000, growth = 1.8, base = 1.0, perLevel = 0.15 }, -- +15% mutation odds / level
	{ id = "greenhouse", name = "Greenhouse", emoji = "🏡", maxLevel = 8, baseCost = 800, growth = 1.7, base = 1.0, perLevel = 0.12 }, -- fruit trees ripen +12% faster / level
}

local U = {}
U.list = Upgrades
local byId: { [string]: Track } = {}
for _, t in Upgrades do
	byId[t.id] = t
end
function U.get(id: string): Track?
	return byId[id]
end
return U
