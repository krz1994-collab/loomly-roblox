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
local ProximityPromptService = game:GetService("ProximityPromptService")

local Remotes = require(ReplicatedStorage.Bloomly.Remotes)
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local PlotRules = require(ReplicatedStorage.Bloomly.PlotRules)
local PlayerData = require(script.PlayerData)
local Farm = require(script.Farm)
local PlotClaim = require(script.PlotClaim)
local World = require(script.World)

-- Build the shared 3D world once, before anyone arrives.
World.build()

-- The seed each player wants the next Plant prompt to use (transient preference; never saved).
local selectedSeed: { [number]: string } = {}

-- Every player owns Config.PLOT_COUNT plots. This becomes per-player when the plot shop lands (L4).
local function ownedPlotsFor(_player: Player): number
	return Config.PLOT_COUNT
end

-- Send a player their authoritative view AND render their garden into the 3D world so EVERYONE sees
-- it. The view is the single source of truth; the 3D crops are just another renderer of it.
local function pushState(player: Player)
	local state = PlayerData.get(player)
	if not state then
		return
	end
	local view: any = Farm.buildView(state, ownedPlotsFor(player))
	local section = PlotClaim.sectionOf(player.UserId)
	view.section = section -- so the client knows which section is its own
	view.selectedSeed = selectedSeed[player.UserId]
	Remotes.StateUpdate:FireClient(player, view)
	if section then
		World.renderSection(section, player.Name, view)
	end
end

-- ---- lifecycle ------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	PlayerData.load(player) -- loads authoritative state (DataStore in load())
	PlotClaim.claim(player) -- assign a free farm section for this session
	selectedSeed[player.UserId] = "radish" -- sensible default so the first Plant prompt just works
	pushState(player) -- renders the section's crops + fills the client HUD
end

Players.PlayerAdded:Connect(onPlayerAdded)
-- Cover players who joined before this script ran.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	local section = PlotClaim.release(player) -- free the section for reuse
	if section then
		World.clearSection(section) -- reset it to "free" in the world
	end
	selectedSeed[player.UserId] = nil
	PlayerData.unload(player) -- final save + release lock + free memory
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

-- ---- SelectSeed (RemoteEvent, client -> server) ---------------------------------
-- VALIDATES: seedId is a string. Only records a preference; the actual plant re-validates the seed
-- (exists + unlocked + affordable) server-side.
Remotes.SelectSeed.OnServerEvent:Connect(function(player: Player, seedId: any)
	if type(seedId) == "string" then
		selectedSeed[player.UserId] = seedId
		pushState(player) -- so the HUD highlights the chosen seed
	end
end)

-- ---- ProximityPrompt interactions (the 3D world's intents) ----------------------
-- Walking up to a plot pad or the market and pressing the prompt fires this ON THE SERVER with the
-- triggering player. We read the prompt's attributes, re-check the actor OWNS the targeted section,
-- then run the same server-authoritative Farm logic. The client never decides the outcome; this is
-- the 3D equivalent of the old button intents.
ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, player: Player)
	local state = PlayerData.get(player)
	if not state then
		return
	end
	local kind = prompt:GetAttribute("kind")

	if kind == "sell" then
		if Farm.sellAll(state) then
			pushState(player)
		end
	elseif kind == "plot" then
		local section = prompt:GetAttribute("section")
		local plotIndex = prompt:GetAttribute("plotIndex")
		if type(section) ~= "number" or type(plotIndex) ~= "number" then
			return
		end
		-- OWNERSHIP GUARD: you can only work the section you own. (Also, crops are addressed by YOUR
		-- own plot index, so you fundamentally cannot touch another player's crops.)
		if not PlotRules.canInteract(PlotClaim.ownerOfSection(section), player.UserId) then
			return
		end
		local plot = state.plots[plotIndex]
		local changed = false
		if plot and plot.seedId == nil then
			changed = Farm.plant(state, selectedSeed[player.UserId] or "radish", plotIndex, ownedPlotsFor(player))
		elseif plot and plot.seedId ~= nil then
			changed = Farm.harvest(state, plotIndex)
		end
		if changed then
			pushState(player)
		end
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
