--!strict
-- LeaderRules: PURE daily/weekly earn tracking for the leaderboards. Counters reset when their time
-- window rolls over (day = floor(os.time()/86400), week = floor(os.time()/604800)). VPS-tested.

local LeaderRules = {}

-- Reset the daily/weekly counters if their window changed. Mutates + returns state.
function LeaderRules.applyPeriod(state: any, today: number, thisWeek: number): any
	if state.dayStamp ~= today then
		state.dailyEarned = 0
		state.dayStamp = today
	end
	if state.weekStamp ~= thisWeek then
		state.weeklyEarned = 0
		state.weekStamp = thisWeek
	end
	return state
end

-- Credit `amount` of earned coins to the daily + weekly totals (after any window reset).
function LeaderRules.addEarned(state: any, amount: number, today: number, thisWeek: number)
	LeaderRules.applyPeriod(state, today, thisWeek)
	state.dailyEarned += amount
	state.weeklyEarned += amount
end

return LeaderRules
