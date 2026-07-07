--!strict
-- TutorialRules: PURE onboarding logic (block 2). Decides whether a tutorial should fire (first time
-- only) against the player's `tutorialsSeen` set. No Roblox globals -> VPS-tested. The server shell
-- calls shouldTrigger before sending Bloomy's line, then records it seen.

local TutorialRules = {}

-- Fire this tutorial? Only if the player hasn't seen it yet.
function TutorialRules.shouldTrigger(id: string, seen: { [string]: boolean }): boolean
	return seen[id] ~= true
end

-- Record a tutorial as seen (mutates the set). Returns true if it was newly marked.
function TutorialRules.markSeen(id: string, seen: { [string]: boolean }): boolean
	if seen[id] == true then
		return false
	end
	seen[id] = true
	return true
end

-- Are all activities covered by tutorial rows? (used by the coverage test + safety at load).
function TutorialRules.coverageOk(activities: { string }, byIdList: { any }): boolean
	local have: { [string]: boolean } = {}
	for _, t in byIdList do
		have[t.id] = true
	end
	for _, a in activities do
		if not have[a] then
			return false
		end
	end
	return true
end

return TutorialRules
