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
local Rules = require(ReplicatedStorage.Bloomly.Rules)
local WorldLayout = require(ReplicatedStorage.Bloomly.data.WorldLayout)
local Catalog = require(ReplicatedStorage.Bloomly.data.Catalog)
local UpgradeRules = require(ReplicatedStorage.Bloomly.UpgradeRules)
local Upgrades = require(ReplicatedStorage.Bloomly.data.Upgrades)
local GatherRules = require(ReplicatedStorage.Bloomly.GatherRules)
local TreasureRules = require(ReplicatedStorage.Bloomly.TreasureRules)
local EventRules = require(ReplicatedStorage.Bloomly.EventRules)
local EventsData = require(ReplicatedStorage.Bloomly.data.Events)

local gatherRng = Random.new()
local function gatherRand(): number
	return gatherRng:NextNumber()
end
local GATHER_CAT: { [string]: { any } } = { fish = Catalog.Fish, bug = Catalog.Bugs, ore = Catalog.Ores, shell = Catalog.Shells }
local PlayerData = require(script.PlayerData)
local Farm = require(script.Farm)
local PlotClaim = require(script.PlotClaim)
local World = require(script.World)
local Quest = require(script.Quest)
local Events = require(script.Events)
local Homestead = require(script.Homestead)

-- Build the shared 3D world once, before anyone arrives.
World.build()

-- The seed each player wants the next Plant prompt to use (transient preference; never saved).
local selectedSeed: { [number]: string } = {}

-- Owned plots = BASE_PLOTS + the "plots" upgrade level, capped at the built pad count (PLOT_COUNT).
local function ownedPlotsFor(player: Player): number
	local state = PlayerData.get(player)
	local lvl = (state and state.upgrades and state.upgrades.plots) or 0
	return math.min(Config.PLOT_COUNT, Config.BASE_PLOTS + lvl)
end

-- Competitive leaderboard: Coins + Level show on the player list (rywalizacja between players).
local function setupLeaderstats(player: Player, state: any)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Value = math.floor(state.coins)
	coins.Parent = ls
	local lvl = Instance.new("IntValue")
	lvl.Name = "Level"
	lvl.Value = Rules.levelForXp(state.xp)
	lvl.Parent = ls
	ls.Parent = player
end

local function updateLeaderstats(player: Player, state: any)
	local ls = player:FindFirstChild("leaderstats")
	if not ls then
		return
	end
	local coins = ls:FindFirstChild("Coins")
	local lvl = ls:FindFirstChild("Level")
	if coins then
		(coins :: IntValue).Value = math.floor(state.coins)
	end
	if lvl then
		(lvl :: IntValue).Value = Rules.levelForXp(state.xp)
	end
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
	view.quests = Quest.activeView(state) -- active quests + progress for the tracker
	view.event = Events.view(os.time()) -- active server-wide event (nil if none) -> client banner
	Remotes.StateUpdate:FireClient(player, view)
	updateLeaderstats(player, state)
	if section then
		World.renderSection(section, player.Name, view)
	end
end

-- Put the player physically ON their claimed plot: with 100 plots they shouldn't have to search for
-- theirs, and the Plant/Harvest prompts only work on your own plot -- so we land you right on it.
local function teleportToYard(player: Player)
	local section = PlotClaim.sectionOf(player.UserId)
	local char = player.Character
	if not section or not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local c = WorldLayout.sectionCenter(section)
	local target = Vector3.new(c.x, 6, c.z - WorldLayout.SECTION_SIZE / 2 + 24) -- just inside the entrance
	pcall(function()
		player:RequestStreamAroundAsync(target) -- stream the plot in before we land there (map is huge)
	end)
	;(hrp :: BasePart).CFrame = CFrame.new(target)
end

local BASE_WALKSPEED = 16
local function vehicleById(id: string?): any
	if not id then
		return nil
	end
	for _, v in Catalog.Vehicles do
		if v.id == id then
			return v
		end
	end
	return nil
end

-- Apply the owned vehicle's speed boost to the character (huge map => vehicles matter).
local function applyVehicleSpeed(player: Player)
	local state = PlayerData.get(player)
	local char = player.Character
	if not state or not char then
		return
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local veh = vehicleById(state.vehicle)
	local walkUp = UpgradeRules.effectAt(Upgrades.get("walkSpeed") :: any, (state.upgrades and state.upgrades.walkSpeed) or 0)
	hum.WalkSpeed = BASE_WALKSPEED * (veh and veh.speed or 1) * walkUp
end

-- Generic teleport (used by harbor sailing). Streams the destination in first (huge map).
local function teleportPlayerTo(player: Player, x: number, z: number)
	local char = player.Character
	if not char then
		return
	end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return
	end
	local target = Vector3.new(x, 10, z)
	pcall(function()
		player:RequestStreamAroundAsync(target)
	end)
	;(hrp :: BasePart).CFrame = CFrame.new(target)
end

-- ---- lifecycle ------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local state = PlayerData.load(player) -- loads authoritative state (DataStore in load())
	PlotClaim.claim(player) -- assign a free 300x300 plot for this session
	setupLeaderstats(player, state) -- Coins + Level on the player list
	selectedSeed[player.UserId] = "radish" -- sensible default so the first Plant prompt just works
	pushState(player) -- renders the plot's crops + fills the client HUD
	player.CharacterAdded:Connect(function()
		task.wait(0.4) -- let the character finish loading before we move it
		teleportToYard(player)
		applyVehicleSpeed(player)
	end)
	if player.Character then
		teleportToYard(player)
		applyVehicleSpeed(player)
	end
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

	if kind == "talk" then
		local npcId = prompt:GetAttribute("npc")
		if type(npcId) == "string" then
			local res = Quest.talkTo(player, npcId)
			if res.action == "accept" then
				Remotes.Notify:FireClient(player, "📜 New quest: " .. res.questName)
			elseif res.action == "complete" then
				Remotes.Notify:FireClient(player, "✅ Quest complete: " .. res.questName .. "!")
			end
			pushState(player)
		end
	elseif kind == "sell" then
		local sold = 0
		for _, qn in state.inventory do
			sold += qn
		end
		if Farm.sellAll(state) then
			Quest.report(player, "sell", nil, sold)
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
		if plotIndex > ownedPlotsFor(player) then
			Remotes.Notify:FireClient(player, "🔒 Buy the 🌱 Farm Plots upgrade (at the plaza) to unlock this pad!")
			return
		end
		local plot = state.plots[plotIndex]
		local changed = false
		if plot and plot.seedId == nil then
			local seed = selectedSeed[player.UserId] or "radish"
			changed = Farm.plant(state, seed, plotIndex, ownedPlotsFor(player))
			if changed then
				Quest.report(player, "plant", seed, 1)
			end
		elseif plot and plot.seedId ~= nil then
			local seed = plot.seedId
			local hok, _, mut = Farm.harvest(state, plotIndex)
			changed = hok
			if hok then
				Quest.report(player, "harvest", seed, 1)
				if mut and mut ~= "normal" then
					Quest.report(player, "harvest_mut", nil, 1)
				end
			end
		end
		if changed then
			pushState(player)
		end
	elseif kind == "buyvehicle" then
		-- VALIDATES: vehicle exists, not already owned, and you can afford it. Server debits + applies.
		local vid = prompt:GetAttribute("vehicleId")
		local veh = if type(vid) == "string" then vehicleById(vid) else nil
		if veh and state.vehicle ~= vid and state.coins >= veh.cost then
			state.coins -= veh.cost
			state.vehicle = vid
			applyVehicleSpeed(player)
			Quest.report(player, "buy_vehicle", vid, 1)
			pushState(player)
		end
	elseif kind == "sail" then
		local idx = prompt:GetAttribute("islandIndex")
		if type(idx) == "number" then
			local c = WorldLayout.islandCenter(idx)
			teleportPlayerTo(player, c.x, c.z)
			Quest.report(player, "sail", tostring(idx), 1)
			pushState(player)
		end
	elseif kind == "sailback" then
		teleportPlayerTo(player, 0, WorldLayout.PLAZA_Z)
	elseif kind == "rebirth" then
		-- VALIDATES: you have enough lifetime-earned for your next (scaling) rebirth. Resets wallet,
		-- grants a permanent +10% coin multiplier; keeps everything else.
		local cost = Rules.rebirthCost(state.rebirths or 0)
		if state.lifetimeEarned >= cost then
			state.rebirths = (state.rebirths or 0) + 1
			state.coins = Config.START_COINS
			Quest.report(player, "rebirth", nil, 1)
			pushState(player)
		end
	elseif kind == "dailygift" then
		local today = math.floor(os.time() / 86400)
		local d = state.daily or { day = 0, streak = 0 }
		local ok, reward, day, streak = Rules.dailyClaim(d.day, d.streak, today)
		if ok then
			state.daily = { day = day, streak = streak }
			state.coins += reward
			state.lifetimeEarned += reward
			Remotes.Notify:FireClient(player, "🎁 Daily gift: +" .. reward .. "c! (streak " .. streak .. ")")
			pushState(player)
		end
	elseif kind == "fish" or kind == "catch_bug" or kind == "mine" or kind == "forage" then
		-- Gathering: server rolls a weighted catch (GatherRules), adds it to inventory, reports quest.
		local cat = prompt:GetAttribute("list")
		if type(cat) == "string" then
			local luck = UpgradeRules.effectAt(Upgrades.get("luck") :: any, (state.upgrades and state.upgrades.luck) or 0)
					* Events.mult(os.time(), "luck") -- active "luck" event (Gold Rush / Butterfly Migration etc.)
			local id: string? = nil
			if cat == "mushroom" then
				id = Catalog.Mushroom.id
			elseif GATHER_CAT[cat] then
				id = GatherRules.roll(GATHER_CAT[cat], gatherRand, luck)
			end
			if id then
				local invKey = cat .. "|" .. id
				state.inventory[invKey] = (state.inventory[invKey] or 0) + 1
				state.harvests += 1
				Quest.report(player, kind, id, 1)
				Remotes.Notify:FireClient(player, "✨ Got a " .. id .. "!")
				pushState(player)
			end
		end
	elseif kind == "treasure" then
		local tid = prompt:GetAttribute("tid")
		local tier = prompt:GetAttribute("tier")
		if type(tid) == "string" and type(tier) == "number" then
			local ok, coins = TreasureRules.claim(state, tid, tier)
			if ok then
				Quest.report(player, "find_treasure", nil, 1)
				Remotes.Notify:FireClient(player, "💰 Treasure! +" .. coins .. " coins!")
				pushState(player)
			else
				Remotes.Notify:FireClient(player, "You already found this treasure. Look for others! 🗺️")
			end
		end
	elseif kind == "upgrade" then
		-- VALIDATES: track exists, not maxed, affordable. Server debits + bumps the level (UpgradeRules).
		local trackId = prompt:GetAttribute("track")
		local track = if type(trackId) == "string" then Upgrades.get(trackId) else nil
		if track then
			local ok = UpgradeRules.buy(state, track)
			if ok then
				if trackId == "walkSpeed" then
					applyVehicleSpeed(player)
				end
				Quest.report(player, "upgrade", trackId :: string, 1)
				Remotes.Notify:FireClient(player, "⬆️ Upgraded " .. track.name .. " to Lv " .. (state.upgrades[trackId] or 0) .. "!")
				pushState(player)
			end
		end
	elseif kind == "homestead" then
		-- Blocks 7-10: one dispatch for the orchard / pen / kitchen / hive / house stations. The prompt
		-- carries an "act" attribute; Homestead enforces cost/unlock/timers on the caller's own state.
		local act = prompt:GetAttribute("act")
		local nowT = os.time()
		local msg: string? = nil
		local changed = false
		if act == "orchard_plant" then
			local ok, m = Homestead.plantTree(state, nowT); changed = ok; msg = m
		elseif act == "orchard_pick" then
			local n, m = Homestead.pickFruit(state, nowT); changed = n > 0; msg = m
			if n > 0 then Quest.report(player, "harvest", "fruit", n) end
		elseif act == "pen_buy" then
			local ok, m = Homestead.buyAnimal(state, nowT); changed = ok; msg = m
		elseif act == "pen_collect" then
			local n, m = Homestead.collectProducts(state, nowT); changed = n > 0; msg = m
			if n > 0 then Quest.report(player, "collect_animal", nil, n) end
		elseif act == "pen_breed" then
			local ok, m = Homestead.breed(state, gatherRand, nowT); changed = ok; msg = m
		elseif act == "cook_start" then
			local ok, m = Homestead.cook(state, nowT); changed = ok; msg = m
		elseif act == "cook_collect" then
			local ok, m = Homestead.collectDish(state, nowT); changed = ok; msg = m
			if ok then Quest.report(player, "cook", nil, 1) end
		elseif act == "hive_up" then
			local ok, m = Homestead.upgradeHive(state, nowT); changed = ok; msg = m
			if ok then Quest.report(player, "upgrade", "hive", 1) end
		elseif act == "hive_collect" then
			local n, m = Homestead.collectHoney(state, nowT); changed = n > 0; msg = m
		elseif act == "house_up" then
			local ok, m = Homestead.upgradeHouse(state, nowT); changed = ok; msg = m
			if ok then Quest.report(player, "upgrade", "house", 1) end
		elseif act == "house_rent" then
			local n, m = Homestead.collectRent(state, nowT); changed = n > 0; msg = m
		elseif act == "house_decor" then
			local ok, m = Homestead.buyDecor(state); changed = ok; msg = m
			if ok then Quest.report(player, "decorate", nil, 1) end
		end
		if msg then
			Remotes.Notify:FireClient(player, msg)
		end
		if changed then
			pushState(player)
		end
	end
end)

-- ---- day / night cycle (ambient, server-authoritative) --------------------------
-- A shared ~20-minute day so dusk/night is the SAME for everyone (night-only events + future
-- nocturnal bugs/stars rely on this). ClockTime advances 24h over DAY_LENGTH real seconds.
local Lighting = game:GetService("Lighting")
local DAY_LENGTH = 1200 -- seconds of real time per in-game day
local function isNightNow(): boolean
	local h = Lighting.ClockTime
	return h < 6 or h >= 18
end
task.spawn(function()
	Lighting.ClockTime = 8 -- start mid-morning
	while true do
		task.wait(2)
		Lighting.ClockTime = (Lighting.ClockTime + (24 / DAY_LENGTH) * 2) % 24
	end
end)

-- ---- EventDirector: the 50 EPIC events -----------------------------------------
-- Every EVENT_INTERVAL seconds we pick a weighted event (respecting per-event cooldowns + night
-- gating) via the pure EventRules, START it (Events holds its multipliers), and ANNOUNCE it to the
-- whole server. Farm + gathering read Events.mult(...) so the effect is REAL immediately. When it
-- expires we announce the end. The director waits until at least one player is online.
local EVENT_INTERVAL = 240 -- ~4 min between events (frequent enough to see while play-testing)
local eventRng = Random.new()
local function eventRand(): number
	return eventRng:NextNumber()
end
local function announceAll(msg: string)
	for _, player in Players:GetPlayers() do
		Remotes.Notify:FireClient(player, msg)
	end
end
task.spawn(function()
	local cooldownUntil: { [string]: number } = {}
	task.wait(45) -- let the first joiner settle in before the first event
	while true do
		if #Players:GetPlayers() > 0 then
			local nowT = os.time()
			local picked = EventRules.pickEvent(EventsData.list, eventRand, nowT, isNightNow(), cooldownUntil)
			if picked then
				Events.start(picked, nowT, picked.dur)
				cooldownUntil[picked.id] = nowT + picked.cd
				announceAll(picked.emoji .. " EVENT: " .. picked.name .. " -- " .. picked.desc)
				for _, player in Players:GetPlayers() do
					pushState(player) -- flash the banner immediately
				end
				task.wait(picked.dur)
				announceAll(picked.emoji .. " " .. picked.name .. " has ended. Thanks for playing!")
				for _, player in Players:GetPlayers() do
					pushState(player) -- clear the banner
				end
			end
		end
		task.wait(EVENT_INTERVAL)
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
