--!strict
-- SailRules: PURE gating for the harbor (block 13). You must BUY a boat once (Captain Bay's harbor_01
-- quest), then each island opens at a required player level -- so there is always a next island just
-- ahead. Level gates mirror the island-unlock quest levels in data/Quests.luau. VPS-tested.

local SailRules = {}

-- Minimum player level to sail to island i (1-based). Island 11 = the Enchanted Forest (block 15).
SailRules.ISLAND_MIN_LEVEL = { 5, 7, 10, 13, 15, 17, 19, 22, 25, 30, 35 }
SailRules.BOAT_COST = 250

-- Can this player sail to islandIndex right now? Returns (ok, reason).
function SailRules.canSailTo(islandIndex: number, state: any, level: number): (boolean, string)
	if not (state.unlocks and state.unlocks.boat) then
		return false, "Buy a boat at the ⚓ Harbor first!"
	end
	local need = SailRules.ISLAND_MIN_LEVEL[islandIndex] or 1
	if level < need then
		return false, "🔒 Reach level " .. need .. " to sail to this island!"
	end
	return true, "ok"
end

-- Can this player buy their first boat? Returns (ok, reason).
function SailRules.canBuyBoat(state: any): (boolean, string)
	if state.unlocks and state.unlocks.boat then
		return false, "You already own a boat!"
	end
	if state.coins < SailRules.BOAT_COST then
		return false, "Need " .. SailRules.BOAT_COST .. " coins for a boat."
	end
	return true, "ok"
end

return SailRules
