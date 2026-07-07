--!strict
-- Bees: the BEEHIVE (block 9). A single upgradeable hive that produces honey over time. Level 0 = no
-- hive yet (build it for the level-1 cost); each level makes honey faster + raises the cap. Honey is a
-- "honey|honey" inventory item (sold at the Market, and an ingredient in cooking recipes). A live hive
-- also gives a small server-side mutation nudge (pollination) applied in Farm.harvest.
--   Item key in inventory/sell = "honey|honey".

export type Level = { produceSec: number, cap: number, upgradeCost: number } -- upgradeCost = coins to REACH this level

local B = {}

B.HONEY = { id = "honey", emoji = "🍯", sell = 55 }
B.MAX = 5

-- Index 1..MAX. LEVELS[n] describes a hive AT level n (n>=1). upgradeCost = cost to go from n-1 to n
-- (so buying the first hive costs LEVELS[1].upgradeCost).
local LEVELS: { Level } = {
	{ produceSec = 120, cap = 6, upgradeCost = 1500 },
	{ produceSec = 100, cap = 8, upgradeCost = 4000 },
	{ produceSec = 80, cap = 10, upgradeCost = 9000 },
	{ produceSec = 60, cap = 12, upgradeCost = 18000 },
	{ produceSec = 45, cap = 15, upgradeCost = 35000 },
}

-- Hive stats at a given level (nil for level 0 = no hive built).
function B.dataAt(level: number): Level?
	return LEVELS[level]
end

-- Cost to go from `level` to `level+1` (build first hive when level==0). nil if already maxed.
function B.upgradeCost(level: number): number?
	local next = LEVELS[level + 1]
	return if next then next.upgradeCost else nil
end

-- Pollination mutation nudge from a live hive: +4% mutation odds per level (capped, no P2W -- earned).
function B.pollinationMult(level: number): number
	return 1 + 0.04 * math.min(level, B.MAX)
end

return B
