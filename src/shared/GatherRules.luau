--!strict
-- GatherRules: PURE weighted roll for gathering activities (fishing / bug-catching / mining /
-- foraging). Each list is a Catalog table (Fish/Bugs/Ores/Shells/...). A row's rarity comes from its
-- `w` (weight; higher = commoner) or, for fish, from `min` (accuracy needed; higher = rarer).
-- Server-authoritative: the shell rolls with a real Random; tests inject a deterministic rand.

local GatherRules = {}

-- Relative weight of a row (commoner = bigger). Fish use `min`; everything else uses `w`.
function GatherRules.weightOf(row: any): number
	if type(row.w) == "number" then
		return row.w
	end
	if type(row.min) == "number" then
		return math.max(1, (1 - row.min) * 20) -- min 0 -> 20 (common), min 0.95 -> ~1 (rare)
	end
	return 10
end

-- Roll one row's id from `list` by weight. `rand` returns [0,1). `luck` (>=1) mildly boosts rares by
-- shrinking common weights. Deterministic given `rand`.
function GatherRules.roll(list: { any }, rand: () -> number, luck: number?): string
	local L = luck or 1
	local total = 0
	local w = {}
	for i, row in list do
		local base = GatherRules.weightOf(row)
		-- luck compresses common weights toward rarer ones (mild; capped)
		local adj = base / (1 + (L - 1) * math.clamp(1 - base / 25, 0, 1))
		w[i] = adj
		total += adj
	end
	local r = rand() * total
	local acc = 0
	for i, row in list do
		acc += w[i]
		if r <= acc then
			return row.id
		end
	end
	return list[#list].id
end

return GatherRules
