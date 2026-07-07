--!strict
-- HouseRules: PURE math for house passive RENT (block 10). Rent accrues at rentPerMin (tier base +
-- placed decor bonuses), capped so a player must return to collect. Clock is os.time() epoch seconds.
-- On collect the shell sets house.lastRent = now (sub-minute remainder is negligible: <=1 coin).

local HouseRules = {}

-- Total rent/min = tier base + sum of placed decor bonuses (bonus * count). decorList is House.decorList.
function HouseRules.rentPerMin(tierRentPerMin: number, decorMap: { [string]: number }, decorList: { any }): number
	local r = tierRentPerMin
	for _, d in decorList do
		local n = decorMap[d.id]
		if n and n > 0 then
			r += d.rentBonusPerMin * n
		end
	end
	return r
end

-- Coins owed since lastRent, capped at `cap`. Does not mutate.
function HouseRules.rentDue(lastRent: number, now: number, rentPerMin: number, cap: number): number
	local sec = now - lastRent
	if sec <= 0 or rentPerMin <= 0 then
		return 0
	end
	return math.min(cap, math.floor(sec * rentPerMin / 60))
end

return HouseRules
