--!strict
-- AchievementRules: PURE achievement checks (block 14). Given a `stats` map (harvests, lifetimeEarned,
-- level, codexCount, rebirths, treasures, museumCount) and the set already earned, return the ones
-- newly crossed. No Roblox globals -> VPS-tested. The server builds `stats` from PlayerState.

local AchievementRules = {}

function AchievementRules.isEarned(ach: any, stats: { [string]: number }): boolean
	return (stats[ach.stat] or 0) >= ach.threshold
end

-- Achievements whose threshold is met but which aren't in `already`. Returns the achievement rows.
function AchievementRules.newlyEarned(list: { any }, stats: { [string]: number }, already: { [string]: boolean }): { any }
	local out = {}
	for _, a in list do
		if not already[a.id] and AchievementRules.isEarned(a, stats) then
			table.insert(out, a)
		end
	end
	return out
end

return AchievementRules
