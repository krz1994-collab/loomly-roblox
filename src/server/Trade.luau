--!strict
-- Trade: the SERVER state machine for direct player-to-player trading (block 14b). Both players must be
-- online in the same server. Flow: request -> respond(accept) -> each offers items (ESCROWED out of
-- inventory immediately) -> any change resets BOTH confirms -> when both confirm, atomic SETTLE. All the
-- item arithmetic goes through TradeRules (VPS-tested, conservation-proven) so a trade can never dupe or
-- vanish items. On disconnect we refund the escrow BEFORE the leaving player's save runs.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Remotes = require(ReplicatedStorage.Bloomly.Remotes)
local TradeRules = require(ReplicatedStorage.Bloomly.TradeRules)
local PlayerData = require(script.Parent.PlayerData)

local Trade = {}

-- userId -> session. Both partners reference the SAME session table.
type Session = {
	a: number,
	b: number,
	offerA: { [string]: number },
	offerB: { [string]: number },
	confirmA: boolean,
	confirmB: boolean,
}
local sessions: { [number]: Session } = {}
local invites: { [number]: number } = {} -- targetUserId -> requesterUserId (a pending trade request)

local pushStateFn: (Player) -> () = function() end
function Trade.setup(pushState: (Player) -> ())
	pushStateFn = pushState
end

local function notify(player: Player?, msg: string)
	if player then
		Remotes.Notify:FireClient(player, msg)
	end
end

local function invOf(userId: number): { [string]: number }?
	local p = Players:GetPlayerByUserId(userId)
	local state = if p then PlayerData.get(p) else nil
	return if state then state.inventory else nil
end

local function toList(map: { [string]: number }): { { key: string, qty: number } }
	local out = {}
	for key, qty in map do
		if qty > 0 then
			table.insert(out, { key = key, qty = qty })
		end
	end
	return out
end

-- Push the live window to both partners (each sees themselves as "you").
local function sendUpdate(s: Session)
	local pa = Players:GetPlayerByUserId(s.a)
	local pb = Players:GetPlayerByUserId(s.b)
	if pa then
		Remotes.TradeUpdate:FireClient(pa, {
			partner = if pb then pb.Name else "?",
			yourOffer = toList(s.offerA),
			theirOffer = toList(s.offerB),
			youConfirmed = s.confirmA,
			theyConfirmed = s.confirmB,
		})
	end
	if pb then
		Remotes.TradeUpdate:FireClient(pb, {
			partner = if pa then pa.Name else "?",
			yourOffer = toList(s.offerB),
			theirOffer = toList(s.offerA),
			youConfirmed = s.confirmB,
			theyConfirmed = s.confirmA,
		})
	end
end

local function closeWindows(s: Session)
	local pa = Players:GetPlayerByUserId(s.a)
	local pb = Players:GetPlayerByUserId(s.b)
	if pa then
		Remotes.TradeUpdate:FireClient(pa, nil)
	end
	if pb then
		Remotes.TradeUpdate:FireClient(pb, nil)
	end
end

-- Refund both escrows to their owners + drop the session. `reason` is toasted to whoever's left.
local function endSession(s: Session, reason: string)
	local invA = invOf(s.a)
	local invB = invOf(s.b)
	if invA then
		TradeRules.refund(invA, s.offerA)
	end
	if invB then
		TradeRules.refund(invB, s.offerB)
	end
	sessions[s.a] = nil
	sessions[s.b] = nil
	closeWindows(s)
	local pa = Players:GetPlayerByUserId(s.a)
	local pb = Players:GetPlayerByUserId(s.b)
	notify(pa, reason)
	notify(pb, reason)
	if pa then
		pushStateFn(pa)
	end
	if pb then
		pushStateFn(pb)
	end
end

-- ---- client-driven actions ----

function Trade.request(from: Player, targetUserId: number)
	if sessions[from.UserId] then
		notify(from, "Finish your current trade first!")
		return
	end
	local target = Players:GetPlayerByUserId(targetUserId)
	if not target or target == from then
		notify(from, "Can't trade with that player.")
		return
	end
	if sessions[target.UserId] then
		notify(from, target.Name .. " is already trading.")
		return
	end
	invites[target.UserId] = from.UserId
	notify(target, "🤝 " .. from.Name .. " wants to trade! Open the Trade menu to accept.")
	notify(from, "Trade request sent to " .. target.Name .. ".")
end

function Trade.respond(player: Player, accept: boolean)
	local requesterId = invites[player.UserId]
	if not requesterId then
		return
	end
	invites[player.UserId] = nil
	local requester = Players:GetPlayerByUserId(requesterId)
	if not accept or not requester then
		notify(requester, player.Name .. " declined the trade.")
		return
	end
	if sessions[player.UserId] or sessions[requesterId] then
		notify(player, "One of you is already trading.")
		return
	end
	local s: Session = { a = requesterId, b = player.UserId, offerA = {}, offerB = {}, confirmA = false, confirmB = false }
	sessions[requesterId] = s
	sessions[player.UserId] = s
	sendUpdate(s)
end

local function myEscrow(s: Session, userId: number): ({ [string]: number }, boolean)
	if userId == s.a then
		return s.offerA, true
	end
	return s.offerB, false
end

function Trade.offer(player: Player, key: string, qty: number)
	local s = sessions[player.UserId]
	if not s then
		return
	end
	local inv = invOf(player.UserId)
	if not inv then
		return
	end
	local escrow = select(1, myEscrow(s, player.UserId))
	if TradeRules.escrow(inv, escrow, key, qty) then
		s.confirmA = false -- ANY change to the deal resets both confirmations (anti-scam)
		s.confirmB = false
		sendUpdate(s)
		pushStateFn(player) -- their inventory shrank
	end
end

function Trade.unoffer(player: Player, key: string)
	local s = sessions[player.UserId]
	if not s then
		return
	end
	local inv = invOf(player.UserId)
	if not inv then
		return
	end
	local escrow = select(1, myEscrow(s, player.UserId))
	local held = escrow[key]
	if held and held > 0 then
		inv[key] = (inv[key] or 0) + held
		escrow[key] = nil
		s.confirmA = false
		s.confirmB = false
		sendUpdate(s)
		pushStateFn(player)
	end
end

function Trade.confirm(player: Player)
	local s = sessions[player.UserId]
	if not s then
		return
	end
	if player.UserId == s.a then
		s.confirmA = true
	else
		s.confirmB = true
	end
	if s.confirmA and s.confirmB then
		-- both locked in: settle atomically through the conservation-proven core
		local invA = invOf(s.a)
		local invB = invOf(s.b)
		if invA and invB then
			TradeRules.settle(invA, s.offerA, invB, s.offerB)
			sessions[s.a] = nil
			sessions[s.b] = nil
			closeWindows(s)
			local pa = Players:GetPlayerByUserId(s.a)
			local pb = Players:GetPlayerByUserId(s.b)
			notify(pa, "✅ Trade complete!")
			notify(pb, "✅ Trade complete!")
			if pa then
				pushStateFn(pa)
			end
			if pb then
				pushStateFn(pb)
			end
		else
			endSession(s, "Trade cancelled (a player left).")
		end
	else
		sendUpdate(s)
	end
end

function Trade.cancel(player: Player)
	local s = sessions[player.UserId]
	if s then
		endSession(s, "❌ Trade cancelled.")
	end
end

-- Called from PlayerRemoving BEFORE the save: refund escrow so nothing is lost/duped on disconnect.
function Trade.onLeave(player: Player)
	invites[player.UserId] = nil
	for uid, reqId in invites do
		if reqId == player.UserId then
			invites[uid] = nil
		end
	end
	local s = sessions[player.UserId]
	if s then
		endSession(s, "Trade cancelled (a player left).")
	end
end

return Trade
