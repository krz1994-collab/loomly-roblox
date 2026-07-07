--!strict
-- UpgradeRules: PURE math for the universal upgrade system (no Roblox globals; track injected).
-- The "geometric ramp, never a wall" cost curve + the per-level effect + the buy transaction.
-- Player levels live in state.upgrades = { [trackId] = level }.

export type Track = { id: string, name: string, emoji: string, maxLevel: number, baseCost: number, growth: number, base: number, perLevel: number }

local UpgradeRules = {}

function UpgradeRules.levelOf(state: any, trackId: string): number
	return (state.upgrades and state.upgrades[trackId]) or 0
end

-- Cost to buy the NEXT level (i.e. go from `level` to `level+1`). Geometric.
function UpgradeRules.costForLevel(track: Track, level: number): number
	return math.floor(track.baseCost * track.growth ^ level)
end

-- Effect value at a given level (linear on top of base). e.g. sellBonus base 1.0 + 0.05/level.
function UpgradeRules.effectAt(track: Track, level: number): number
	return track.base + level * track.perLevel
end

function UpgradeRules.isMaxed(track: Track, level: number): boolean
	return level >= track.maxLevel
end

-- Buy the next level of `track` if affordable + not maxed. Debits coins, bumps the level.
-- Returns (ok, newLevel). Pure (mutates the passed state table only).
function UpgradeRules.buy(state: any, track: Track): (boolean, number)
	if not state.upgrades then
		state.upgrades = {}
	end
	local level = state.upgrades[track.id] or 0
	if level >= track.maxLevel then
		return false, level
	end
	local cost = UpgradeRules.costForLevel(track, level)
	if (state.coins or 0) < cost then
		return false, level
	end
	state.coins -= cost
	state.upgrades[track.id] = level + 1
	return true, level + 1
end

return UpgradeRules
