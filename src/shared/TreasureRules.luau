--!strict
-- TreasureRules: PURE placement + reward math for hidden treasures. Spots are deterministic (same
-- server layout every build) but spread out; each treasure is claimed once per player
-- (state.treasuresFound[id] = true). No Roblox globals -> VPS-testable.

local TreasureRules = {}

-- Local offset {x,z} of treasure `k` (1..count) within a region of half-size `half`, seeded by
-- `seed` (e.g. island index) so different regions get different arrangements. Deterministic + spread.
function TreasureRules.spotFor(seed: number, k: number, count: number, half: number): { x: number, z: number }
	local a = (k / count) * math.pi * 2 + seed * 0.7
	local h = ((k * 37 + seed * 101) % 100) / 100 -- pseudo-random 0..1, deterministic
	local r = half * (0.35 + 0.55 * h)
	return { x = math.cos(a) * r, z = math.sin(a) * r }
end

-- Coin reward for a treasure of a given tier (island index / depth). Bigger tiers pay more.
function TreasureRules.reward(tier: number): number
	return 50 + tier * 45
end

-- Has the player already claimed this treasure id?
function TreasureRules.isFound(state: any, id: string): boolean
	return state.treasuresFound ~= nil and state.treasuresFound[id] == true
end

-- Claim a treasure. Returns (ok, coins). ok=false if already claimed.
function TreasureRules.claim(state: any, id: string, tier: number): (boolean, number)
	if not state.treasuresFound then
		state.treasuresFound = {}
	end
	if state.treasuresFound[id] then
		return false, 0
	end
	state.treasuresFound[id] = true
	local coins = TreasureRules.reward(tier)
	state.coins += coins
	state.lifetimeEarned += coins
	return true, coins
end

return TreasureRules
