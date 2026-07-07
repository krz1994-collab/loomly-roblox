--!strict
-- ChallengeRules: PURE daily-challenge logic (content). The day's set is a DETERMINISTIC rotation of the
-- pool (same for everyone, no RNG needed -> no desync), so the server + tests agree. Progress lives in
-- state.challenges { day, prog, claimed } and is bumped from Quest.report by matching `kind`. No Roblox
-- globals -> VPS-tested. `day` = floor(os.time()/86400) passed in by the shell.

local ChallengeRules = {}

-- The `count` challenge templates chosen for `day`, rotating through the pool by day number.
function ChallengeRules.dailySet(day: number, pool: { any }, count: number): { any }
	local out = {}
	local n = #pool
	if n == 0 then
		return out
	end
	local start = day % n
	for i = 0, math.min(count, n) - 1 do
		table.insert(out, pool[(start + i) % n + 1])
	end
	return out
end

-- Ensure state.challenges matches `day` (reset prog+claimed at a new day). Mutates + returns it.
function ChallengeRules.ensureDay(ch: any, day: number): any
	if ch.day ~= day then
		ch.day = day
		ch.prog = {}
		ch.claimed = {}
	end
	return ch
end

-- Bump progress for every ACTIVE daily challenge whose kind matches. Call from Quest.report.
function ChallengeRules.bump(ch: any, day: number, pool: { any }, count: number, kind: string, n: number)
	ChallengeRules.ensureDay(ch, day)
	for _, c in ChallengeRules.dailySet(day, pool, count) do
		if c.kind == kind then
			ch.prog[c.id] = (ch.prog[c.id] or 0) + n
		end
	end
end

function ChallengeRules.isDone(challenge: any, ch: any): boolean
	return (ch.prog[challenge.id] or 0) >= challenge.target
end

-- Claim every done-and-unclaimed daily challenge. Mutates ch.claimed; returns (totalReward, claimedCount).
function ChallengeRules.claimAll(ch: any, day: number, pool: { any }, count: number): (number, number)
	ChallengeRules.ensureDay(ch, day)
	local reward = 0
	local claimed = 0
	for _, c in ChallengeRules.dailySet(day, pool, count) do
		if not ch.claimed[c.id] and ChallengeRules.isDone(c, ch) then
			ch.claimed[c.id] = true
			reward += c.reward
			claimed += 1
		end
	end
	return reward, claimed
end

return ChallengeRules
