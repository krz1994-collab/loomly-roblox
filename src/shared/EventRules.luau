--!strict
-- EventRules: PURE event picker. Weighted choice among events that aren't on cooldown and match the
-- time of day (night-only events only at night). Deterministic given `rand`. VPS-testable.

local EventRules = {}

-- events: list of Event; rand: ()->[0,1); now: epoch seconds; isNight: bool; cooldownUntil: {[id]=epoch}
-- Returns the picked event, or nil if none is currently eligible.
function EventRules.pickEvent(events: { any }, rand: () -> number, now: number, isNight: boolean, cooldownUntil: { [string]: number }): any
	local eligible = {}
	local total = 0
	for _, e in events do
		local onCd = cooldownUntil[e.id] ~= nil and cooldownUntil[e.id] > now
		local nightOk = (not e.night) or isNight
		if not onCd and nightOk then
			table.insert(eligible, e)
			total += e.weight
		end
	end
	if #eligible == 0 then
		return nil
	end
	local r = rand() * total
	local acc = 0
	for _, e in eligible do
		acc += e.weight
		if r <= acc then
			return e
		end
	end
	return eligible[#eligible]
end

return EventRules
