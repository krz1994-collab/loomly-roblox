--!strict
-- ProduceRules: the PURE time-accrual core shared by every "produces X every N seconds, up to a cap"
-- system -- orchard trees, pen animals, beehives, house rent. Deterministic + VPS-tested once here,
-- reused everywhere. Clock is os.time() epoch seconds (survives saves + accrues while offline, which
-- is the retention win). The CAP is what makes players come back: an idle producer stops filling once
-- it hits `cap`, so leaving it for a week doesn't dump a week of loot.

local ProduceRules = {}

-- How many whole units have accrued since `lastAt`, capped at `cap`. cycleSec must be > 0.
function ProduceRules.readyCount(lastAt: number, now: number, cycleSec: number, cap: number): number
	if cycleSec <= 0 then
		return 0
	end
	local raw = math.floor((now - lastAt) / cycleSec)
	if raw <= 0 then
		return 0
	end
	return math.min(cap, raw)
end

-- Collect the accrued units. Returns (count, newLastAt). Carries PARTIAL progress under the cap (so a
-- half-grown fruit isn't lost); DISCARDS overflow above the cap (enforcing the come-back cap). Pure:
-- the caller writes newLastAt back into the slot + banks `count` into inventory.
function ProduceRules.collect(lastAt: number, now: number, cycleSec: number, cap: number): (number, number)
	if cycleSec <= 0 then
		return 0, lastAt
	end
	local raw = math.floor((now - lastAt) / cycleSec)
	if raw <= 0 then
		return 0, lastAt
	end
	local n = math.min(cap, raw)
	local newLast: number
	if raw > cap then
		newLast = now -- was over the cap: overflow is discarded, clock resets to now
	else
		newLast = lastAt + n * cycleSec -- under the cap: keep the sub-cycle remainder growing
	end
	return n, newLast
end

return ProduceRules
