--!strict
-- Events: server shell holding the CURRENT active event + exposing its global multipliers so Farm
-- (and gathering) can apply them. The EventDirector loop in init.server picks + starts events.

local Events = {}

local current: any = nil -- { id, name, emoji, desc, effect, endsAt }

function Events.start(event: any, now: number, dur: number)
	current = { id = event.id, name = event.name, emoji = event.emoji, desc = event.desc, effect = event.effect, endsAt = now + dur }
end

-- The active event, or nil (auto-clears when expired).
function Events.active(now: number): any
	if current and now < current.endsAt then
		return current
	end
	current = nil
	return nil
end

-- The current multiplier for an effect key (coins/mutation/grow/luck), or 1 if no matching event.
function Events.mult(now: number, key: string): number
	local c = Events.active(now)
	if c and c.effect[key] then
		return c.effect[key]
	end
	return 1
end

-- A compact snapshot for the client banner.
function Events.view(now: number): any
	local c = Events.active(now)
	if not c then
		return nil
	end
	return { name = c.name, emoji = c.emoji, desc = c.desc, timeLeft = math.max(0, math.ceil(c.endsAt - now)) }
end

return Events
