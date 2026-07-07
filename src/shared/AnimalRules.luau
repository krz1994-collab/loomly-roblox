--!strict
-- AnimalRules: PURE breeding math (block 8). Two animals of the SAME species (checked in the shell)
-- can breed into a baby. The baby's tier is the parents' tier, with a 25% chance to jump one tier
-- rarer -- so breeding is a slow path to rarer animals without pay-to-win. `rand` is injected (tests
-- pass a fake); the shell passes the server RNG.

local AnimalRules = {}

AnimalRules.RARE_UP_CHANCE = 0.25

-- The offspring tier for parents of tiers t1,t2. rand()->[0,1).
function AnimalRules.offspringTier(t1: number, t2: number, rand: () -> number): number
	local base = math.max(t1, t2)
	if rand() < AnimalRules.RARE_UP_CHANCE then
		return base + 1
	end
	return base
end

return AnimalRules
