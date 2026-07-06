--!strict
-- PlotRules: PURE rules for the shared-world plot-claim system (no Roblox globals, VPS-testable).
-- In the shared world every player claims one numbered farm SECTION for their session; their
-- persisted `state.plots` renders onto it. Sections are session-only (never saved) -- only the
-- garden data is saved, so you can land on a different section each visit and see the same garden.

local PlotRules = {}

-- Lowest free section id in 1..sectionCount, or nil if all taken. `claimed` maps section -> anything
-- truthy for taken sections. Deterministic (lowest-first) so it's trivially testable.
function PlotRules.pickFreeSection(claimed: { [number]: any }, sectionCount: number): number?
	for i = 1, sectionCount do
		if claimed[i] == nil then
			return i
		end
	end
	return nil
end

-- The ownership guard used on every farm interaction: a player may only act on the section they own.
-- ownerUserId is who owns the section the interaction targets; actorUserId is who is acting.
function PlotRules.canInteract(ownerUserId: number?, actorUserId: number): boolean
	return ownerUserId ~= nil and ownerUserId == actorUserId
end

return PlotRules
