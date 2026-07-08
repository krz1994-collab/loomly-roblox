--!strict
-- Leaderboard: three ranking boards -- ALL-TIME (lifetimeEarned), THIS WEEK, TODAY. Keeps a per-server
-- cache of every player seen this session and ranks them. Good enough to be live + competitive now.
--
-- GLOBAL UPGRADE (later, once the place is published): mirror `update` into three OrderedDataStores
-- (all-time / weekly-<weekStamp> / daily-<dayStamp>) and read the real cross-server top via
-- GetSortedAsync. The interface below (update / top / championId) stays identical.

local Leaderboard = {}

-- userId -> { name, daily, weekly, all }
local cache: { [number]: { name: string, daily: number, weekly: number, all: number } } = {}

function Leaderboard.update(userId: number, name: string, daily: number, weekly: number, all: number)
	cache[userId] = { name = name, daily = daily, weekly = weekly, all = all }
end

-- metric in {"daily","weekly","all"} -> sorted top-n array of { userId, name, value }
function Leaderboard.top(metric: string, n: number): { any }
	local arr = {}
	for uid, e in cache do
		table.insert(arr, { userId = uid, name = e.name, value = (e :: any)[metric] or 0 })
	end
	table.sort(arr, function(a, b)
		return a.value > b.value
	end)
	local out = {}
	for i = 1, math.min(n, #arr) do
		out[i] = arr[i]
	end
	return out
end

function Leaderboard.championId(metric: string): number?
	local t = Leaderboard.top(metric, 1)
	return t[1] and t[1].userId or nil
end

return Leaderboard
