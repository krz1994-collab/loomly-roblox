--!strict
-- TradeRules: the PURE, safety-critical core of player-to-player trading (block 14). The ONE property
-- that must hold is CONSERVATION: no trade operation may create or destroy items. Everything is modelled
-- as moving counts between plain inventory maps (a player's inventory <-> their trade offer escrow), so
-- it is fully VPS-tested. Design: ESCROW-AT-OFFER (items leave inventory the moment they're offered),
-- REFUND on cancel/disconnect, atomic SETTLE only when both sides confirm. The server shell owns the
-- session state machine + double-confirm; this module guarantees the arithmetic can't dupe or vanish.

local TradeRules = {}

-- Move `qty` of `key` from `inv` into `escrow` (offering it). Returns true on success; false if the
-- player doesn't actually hold that many (never trust the client's requested qty).
function TradeRules.escrow(inv: { [string]: number }, escrow: { [string]: number }, key: string, qty: number): boolean
	if qty <= 0 then
		return false
	end
	local have = inv[key] or 0
	if have < qty then
		return false
	end
	local left = have - qty
	if left > 0 then
		inv[key] = left
	else
		inv[key] = nil
	end
	escrow[key] = (escrow[key] or 0) + qty
	return true
end

-- Return everything in `escrow` back to `inv` (cancel / disconnect / any offer change). Clears escrow.
function TradeRules.refund(inv: { [string]: number }, escrow: { [string]: number })
	for key, qty in escrow do
		if qty > 0 then
			inv[key] = (inv[key] or 0) + qty
		end
	end
	table.clear(escrow)
end

-- Atomic settle: A's escrow goes to B's inventory, B's escrow goes to A's inventory. Clears both
-- escrows. Called ONLY after both players have confirmed and nothing changed since. Conserves totals.
function TradeRules.settle(invA: { [string]: number }, escrowA: { [string]: number }, invB: { [string]: number }, escrowB: { [string]: number })
	for key, qty in escrowA do
		if qty > 0 then
			invB[key] = (invB[key] or 0) + qty
		end
	end
	for key, qty in escrowB do
		if qty > 0 then
			invA[key] = (invA[key] or 0) + qty
		end
	end
	table.clear(escrowA)
	table.clear(escrowB)
end

-- Sum of all counts in a map (for conservation checks / display).
function TradeRules.total(map: { [string]: number }): number
	local n = 0
	for _, qty in map do
		n += qty
	end
	return n
end

return TradeRules
