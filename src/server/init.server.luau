--!strict
-- BloomlyServer: the authoritative game server for the vertical slice.
--
-- Reads as: on join we load the player's state; the client asks for it via GetState; the client
-- sends Plant/Harvest/SellAll intents which we VALIDATE and apply through Farm; we push the
-- resulting truth back with StateUpdate on a 1s cadence so timers stay live.
--
-- Every OnServerEvent/OnServerInvoke handler below is a trust boundary. The header comment on each
-- one lists exactly what the server checks before it will act. The client is assumed hostile.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Bloomly.Remotes)
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local PlayerData = require(script.PlayerData)
local Farm = require(script.Farm)

-- In the slice every player owns exactly Config.PLOT_COUNT plots. This is also the "owned plot
-- count" the plant-unlock rules key off. When a plot shop exists, this becomes per-player.
local function ownedPlotsFor(_player: Player): number
	return Config.PLOT_COUNT
end

-- Send a player their authoritative view. The ONLY way state reaches a client.
local function pushState(player: Player)
	local state = PlayerData.get(player)
	if state then
		Remotes.StateUpdate:FireClient(player, Farm.buildView(state, ownedPlotsFor(player)))
	end
end

-- ---- lifecycle ------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	PlayerData.load(player) -- creates/loads authoritative state (DataStore seam lives in load())
	pushState(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- Cover players who joined before this script ran.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	PlayerData.unload(player) -- saves (seam) + frees memory
end)

-- ---- GetState (RemoteFunction, client -> server) --------------------------------
-- VALIDATES: nothing to validate -- it's a read of the caller's OWN state only. A player can only
-- ever ask for their own view (we key off `player`, never a client-supplied id).
Remotes.GetState.OnServerInvoke = function(player: Player)
	local state = PlayerData.get(player) or PlayerData.load(player)
	return Farm.buildView(state, ownedPlotsFor(player))
end

-- ---- Plant (RemoteEvent, client -> server) --------------------------------------
-- VALIDATES: arg types; that the plot index is in range; that the plot is EMPTY (not overwriting a
-- growing crop); that the seed id is real; that the seed is UNLOCKED for this player. All in
-- Farm.plant. The client's seed menu is a convenience -- the server re-checks the unlock itself.
Remotes.Plant.OnServerEvent:Connect(function(player: Player, seedId: any, plotIndex: any)
	if type(seedId) ~= "string" or type(plotIndex) ~= "number" then
		return -- reject malformed intents outright
	end
	local state = PlayerData.get(player)
	if not state then
		return
	end
	local ok = Farm.plant(state, seedId, plotIndex, ownedPlotsFor(player))
	if ok then
		pushState(player) -- reflect the new truth; if invalid we simply don't change anything
	end
end)

-- ---- Harvest (RemoteEvent, client -> server) ------------------------------------
-- VALIDATES: arg type; plot index in range; the plot actually has a crop; the crop is READY per
-- the SERVER grow clock (a client cannot claim readiness early). The mutation is rolled here,
-- server-side, in Farm.harvest -- the outcome is never client-supplied.
Remotes.Harvest.OnServerEvent:Connect(function(player: Player, plotIndex: any)
	if type(plotIndex) ~= "number" then
		return
	end
	local state = PlayerData.get(player)
	if not state then
		return
	end
	local ok = Farm.harvest(state, plotIndex)
	if ok then
		pushState(player)
	end
end)

-- ---- SellAll (RemoteEvent, client -> server) ------------------------------------
-- VALIDATES: nothing from the client is trusted -- it carries no args. The server prices the
-- player's OWN inventory at the NPC floor (baseValue x mutation.mult) and credits coins. The
-- client cannot set the price or the amount.
Remotes.SellAll.OnServerEvent:Connect(function(player: Player)
	local state = PlayerData.get(player)
	if not state then
		return
	end
	local ok = Farm.sellAll(state)
	if ok then
		pushState(player)
	end
end)

-- ---- state push loop ------------------------------------------------------------
-- Keeps each client's "growing / ready" readout and countdown current. Simplest correct approach:
-- push every player's view every STATE_PUSH_SECONDS. A production build would push on-change and
-- let the client predict the countdown locally; this is deliberately obvious instead of optimal.
task.spawn(function()
	while true do
		task.wait(Config.STATE_PUSH_SECONDS)
		for _, player in Players:GetPlayers() do
			pushState(player)
		end
	end
end)

-- ---- save cadence ---------------------------------------------------------------
-- Persist every online player every SAVE_CADENCE_SECONDS. NEVER save per-action: at 50 players
-- per-action writes would blow the DataStore request budget. Cadence + on-leave + on-shutdown is
-- the spec §5.2 discipline. Each save is a lock-guarded UpdateAsync with retries (in PlayerData).
task.spawn(function()
	while true do
		task.wait(Config.SAVE_CADENCE_SECONDS)
		for _, player in Players:GetPlayers() do
			task.spawn(PlayerData.save, player) -- spawn so one slow write doesn't stall the others
		end
	end
end)

-- ---- shutdown -------------------------------------------------------------------
-- Flush every player's save (and release their lock) before the server dies. save() blocks on its
-- retry writer, so BindToClose holds the server open until writes finish (Roblox allows ~30s).
game:BindToClose(function()
	for _, player in Players:GetPlayers() do
		task.spawn(PlayerData.save, player, true) -- release lock so a rejoin on a new server isn't blocked
	end
	task.wait(3) -- give the spawned writes a moment to complete before the process exits
end)

print("[Bloomly] server ready -- persistence online, " .. Config.PLOT_COUNT .. " plots/player, cap " .. Config.MAX_PLAYERS)
