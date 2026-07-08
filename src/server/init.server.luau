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
local MarketplaceService = game:GetService("MarketplaceService")

local Remotes = require(ReplicatedStorage.Bloomly.Remotes)
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local PlotRules = require(ReplicatedStorage.Bloomly.PlotRules)
local Rules = require(ReplicatedStorage.Bloomly.Rules)
local WorldLayout = require(ReplicatedStorage.Bloomly.data.WorldLayout)
local Catalog = require(ReplicatedStorage.Bloomly.data.Catalog)
local Plants = require(ReplicatedStorage.Bloomly.data.Plants)
local Monsters = require(ReplicatedStorage.Bloomly.data.Monsters)
local UpgradeRules = require(ReplicatedStorage.Bloomly.UpgradeRules)
local Upgrades = require(ReplicatedStorage.Bloomly.data.Upgrades)
local GatherRules = require(ReplicatedStorage.Bloomly.GatherRules)
local TreasureRules = require(ReplicatedStorage.Bloomly.TreasureRules)
local EventRules = require(ReplicatedStorage.Bloomly.EventRules)
local EventsData = require(ReplicatedStorage.Bloomly.data.Events)
local SailRules = require(ReplicatedStorage.Bloomly.SailRules)
local AchievementRules = require(ReplicatedStorage.Bloomly.AchievementRules)
local Achievements = require(ReplicatedStorage.Bloomly.data.Achievements)
local CommandRules = require(ReplicatedStorage.Bloomly.CommandRules)
local Commands = require(ReplicatedStorage.Bloomly.data.Commands)
local Premium = require(ReplicatedStorage.Bloomly.data.Premium)
local TutorialRules = require(ReplicatedStorage.Bloomly.TutorialRules)
local Tutorials = require(ReplicatedStorage.Bloomly.data.Tutorials)
local Pets = require(ReplicatedStorage.Bloomly.data.Pets)
local PetRules = require(ReplicatedStorage.Bloomly.PetRules)
local ChallengeRules = require(ReplicatedStorage.Bloomly.ChallengeRules)
local Challenges = require(ReplicatedStorage.Bloomly.data.Challenges)

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
local Trade = require(script.Trade)
local Leaderboard = require(script.Leaderboard)

-- Build the shared 3D world once, before anyone arrives.
World.build()

-- The seed each player wants the next Plant prompt to use (transient preference; never saved).
local selectedSeed: { [number]: string } = {}

-- Playtime rewards (retention): escalating coins for time spent online this session.
local PLAYTIME = { { 2, 100 }, { 5, 200 }, { 10, 350 }, { 15, 500 }, { 20, 750 }, { 30, 1200 }, { 45, 2000 }, { 60, 3500 } }
local sessionStart: { [number]: number } = {} -- userId -> os.time() at join
local ptClaimed: { [number]: number } = {} -- userId -> highest playtime milestone claimed this session

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

local function countKeys(map: { [string]: any }): number
	local n = 0
	for _ in map do
		n += 1
	end
	return n
end

-- Award any newly-earned achievements: mark them, pay the reward, toast the player. Pure decision in
-- AchievementRules; this shell builds the stats + applies the effect.
local function checkAchievements(player: Player, state: any)
	local stats = {
		harvests = state.harvests,
		lifetimeEarned = state.lifetimeEarned,
		level = Rules.levelForXp(state.xp),
		codexCount = countKeys(state.codex),
		rebirths = state.rebirths or 0,
		treasures = countKeys(state.treasuresFound),
		museumCount = countKeys(state.museum),
	}
	local newly = AchievementRules.newlyEarned(Achievements.list, stats, state.achievements)
	for _, a in newly do
		state.achievements[a.id] = true
		state.coins += a.reward
		state.lifetimeEarned += a.reward
		Remotes.Notify:FireClient(player, "🏅 Achievement: " .. a.emoji .. " " .. a.name .. "! (+" .. a.reward .. "c)")
	end
end

-- Bloomy the mascot: the FIRST time a player meets an activity, send its coaching line (once). Pure
-- decision in TutorialRules; recorded in state.tutorialsSeen (persisted).
local function tut(player: Player, state: any, id: string)
	if TutorialRules.shouldTrigger(id, state.tutorialsSeen) then
		TutorialRules.markSeen(id, state.tutorialsSeen)
		local t = Tutorials.get(id)
		if t then
			Remotes.Notify:FireClient(player, t.emoji .. " " .. t.mascotLine)
		end
	end
end

-- Which tutorial a prompt kind / homestead act teaches (first-time coaching).
local PROMPT_TUT: { [string]: string } = {
	talk = "quests", sell = "sell", plot = "plant", sail = "sail", buyboat = "sail",
	rebirth = "rebirth", dailygift = "daily", fish = "fish", catch_bug = "catch_bug",
	mine = "mine", forage = "forage", treasure = "treasure", museum = "museum", upgrade = "upgrade",
	adoptpet = "pets", hatchegg = "pets", challenges = "challenges",
}
local HOME_TUT: { [string]: string } = {
	orchard_plant = "orchard", orchard_pick = "orchard", pen_buy = "animals", pen_collect = "animals",
	pen_breed = "breed", cook_start = "cook", cook_collect = "cook", hive_up = "bees", hive_collect = "bees",
	house_up = "house", house_rent = "house", house_decor = "decorate",
}

-- Send a player their authoritative view AND render their garden into the 3D world so EVERYONE sees
-- it. The view is the single source of truth; the 3D crops are just another renderer of it.
local function pushState(player: Player)
	local state = PlayerData.get(player)
	if not state then
		return
	end
	checkAchievements(player, state) -- award milestones before snapshotting (reflects reward in this push)
	Leaderboard.update(player.UserId, player.Name, state.dailyEarned or 0, state.weeklyEarned or 0, state.lifetimeEarned or 0)
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

-- ---- chat commands (block 16) ---------------------------------------------------
-- Parse via the pure CommandRules, then route each verb to the SAME validated server functions the
-- ProximityPrompts use. Unknown -> a friendly nudge to /help.
local function handleCommand(player: Player, text: string)
	local parsed = CommandRules.parse(text)
	if not parsed then
		return
	end
	local state = PlayerData.get(player)
	if not state then
		return
	end
	local cmd = parsed.cmd
	if cmd == "help" or cmd == "commands" then
		Remotes.Notify:FireClient(player, CommandRules.helpText(Commands.list))
	elseif cmd == "home" or cmd == "stuck" then
		teleportToYard(player)
		Remotes.Notify:FireClient(player, "🏠 Warped back to your farm!")
	elseif cmd == "goto" then
		local place, idx = CommandRules.resolveGoto(parsed.args[1])
		if place == "plaza" then
			teleportPlayerTo(player, 0, WorldLayout.PLAZA_Z)
		elseif place == "harbor" then
			teleportPlayerTo(player, 0, WorldLayout.PLAZA_Z - 70)
		elseif place == "island" and idx then
			local ok, reason = SailRules.canSailTo(idx, state, Rules.levelForXp(state.xp))
			if ok then
				local c = WorldLayout.islandCenter(idx)
				teleportPlayerTo(player, c.x, c.z)
				Quest.report(player, "sail", tostring(idx), 1)
			else
				Remotes.Notify:FireClient(player, reason)
			end
		else
			Remotes.Notify:FireClient(player, "Try /goto plaza, /goto harbor, or /goto <1-11>")
		end
	elseif cmd == "sell" then
		local sold = 0
		for _, qn in state.inventory do
			sold += qn
		end
		if Farm.sellAll(state) then
			Quest.report(player, "sell", nil, sold)
			pushState(player)
		else
			Remotes.Notify:FireClient(player, "Nothing to sell right now!")
		end
	elseif cmd == "daily" then
		Remotes.Notify:FireClient(player, "🎁 Claim at the Daily Gift stand in the plaza. Current streak: " .. ((state.daily and state.daily.streak) or 0))
	elseif cmd == "quests" then
		local qs = Quest.activeView(state)
		if qs and #qs > 0 then
			local lines = { "📜 Active quests:" }
			for _, q in qs do
				table.insert(lines, "• " .. q.name .. " (" .. q.prog .. "/" .. q.need .. ")")
			end
			Remotes.Notify:FireClient(player, table.concat(lines, "\n"))
		else
			Remotes.Notify:FireClient(player, "No active quests — talk to 🌳 Elder Willow in the plaza!")
		end
	elseif cmd == "trade" then
		local name = parsed.args[1]
		if not name then
			Remotes.Notify:FireClient(player, "Use /trade <player name>.")
		else
			local target: Player? = nil
			for _, p in Players:GetPlayers() do
				if p ~= player and p.Name:lower() == name:lower() then
					target = p
				end
			end
			if target then
				Trade.request(player, target.UserId)
			else
				Remotes.Notify:FireClient(player, "Couldn't find a player named '" .. name .. "' here.")
			end
		end
	elseif cmd == "rebirth" then
		local cost = Rules.rebirthCost(state.rebirths or 0)
		Remotes.Notify:FireClient(player, "🔮 Rebirth resets your coins for a permanent +10% coin boost. Next costs " .. cost .. " lifetime coins. Use the Rebirth Shrine in the plaza.")
	elseif cmd == "map" then
		Remotes.Notify:FireClient(player, "🗺️ Press the Map button (top-right) to see the whole world!")
	elseif cmd == "shop" then
		Remotes.Notify:FireClient(player, "🛒 Seeds, Tools, Pets, Vehicles and Upgrades are in the plaza; Boats are at the Harbor.")
	elseif cmd == "tutorial" or cmd == "guide" then
		Remotes.Notify:FireClient(player, "👋 Walk up to any station and press E — the prompt tells you what it does!")
	else
		Remotes.Notify:FireClient(player, "Unknown command '" .. cmd .. "'. Type /help! 😊")
	end
end

-- ---- monetization (block C): Robux products/gamepasses -> perks (strictly no P2W) --------------
-- Perks are stored as unlocks["perk_<id>"]. Real product/gamepass ids live in data/Premium.luau
-- (robuxId); until you fill them (create them on create.roblox.com), nothing here can be purchased.
local premiumByRobux: { [number]: any } = {}
for _, p in Premium.list do
	if p.robuxId ~= 0 then
		premiumByRobux[p.robuxId] = p
	end
end

local function grantPerk(player: Player, product: any): boolean
	local state = PlayerData.get(player)
	if not state then
		return false
	end
	state.unlocks["perk_" .. product.id] = true
	Remotes.Notify:FireClient(player, "✨ Unlocked: " .. product.name .. "!")
	pushState(player)
	return true
end

-- consumable dev-products
MarketplaceService.ProcessReceipt = function(receipt)
	local product = premiumByRobux[receipt.ProductId]
	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if product and player and grantPerk(player, product) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet -- try again later (don't lose the Robux)
end

-- gamepasses: grant on purchase, and on join if already owned
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, purchased: boolean)
	if purchased and premiumByRobux[passId] then
		grantPerk(player, premiumByRobux[passId])
	end
end)

local function grantOwnedGamepasses(player: Player)
	for _, p in Premium.list do
		if p.kind == "gamepass" and p.robuxId ~= 0 then
			local ok, owns = pcall(function()
				return MarketplaceService:UserOwnsGamePassAsync(player.UserId, p.robuxId)
			end)
			if ok and owns then
				local state = PlayerData.get(player)
				if state then
					state.unlocks["perk_" .. p.id] = true
				end
			end
		end
	end
end

-- ---- lifecycle ------------------------------------------------------------------
local function onPlayerAdded(player: Player)
	local state = PlayerData.load(player) -- loads authoritative state (DataStore in load())
	task.spawn(grantOwnedGamepasses, player) -- restore any gamepass perks they already own
	PlotClaim.claim(player) -- assign a free 300x300 plot for this session
	setupLeaderstats(player, state) -- Coins + Level on the player list
	selectedSeed[player.UserId] = "radish" -- sensible default so the first Plant prompt just works
	sessionStart[player.UserId] = os.time() -- start the playtime-reward clock
	ptClaimed[player.UserId] = 0
	pushState(player) -- renders the plot's crops + fills the client HUD
	task.delay(3, function()
		if PlayerData.get(player) then
			tut(player, state, "welcome") -- Bloomy greets brand-new players
		end
	end)
	player.CharacterAdded:Connect(function()
		task.wait(0.4) -- let the character finish loading before we move it
		teleportToYard(player)
		applyVehicleSpeed(player)
	end)
	player.Chatted:Connect(function(msg)
		handleCommand(player, msg) -- chat commands (/help, /goto, /trade, ...)
	end)
	if player.Character then
		teleportToYard(player)
		applyVehicleSpeed(player)
	end
end

Trade.setup(pushState) -- let the trade module refresh a player's HUD after escrow/settle

Players.PlayerAdded:Connect(onPlayerAdded)
-- Cover players who joined before this script ran.
for _, player in Players:GetPlayers() do
	task.spawn(onPlayerAdded, player)
end

Players.PlayerRemoving:Connect(function(player)
	Trade.onLeave(player) -- refund any open trade escrow BEFORE the save runs (no dupe/loss on disconnect)
	local section = PlotClaim.release(player) -- free the section for reuse
	if section then
		World.clearSection(section) -- reset it to "free" in the world
	end
	selectedSeed[player.UserId] = nil
	sessionStart[player.UserId] = nil
	ptClaimed[player.UserId] = nil
	PlayerData.unload(player) -- final save + release lock + free memory
end)

-- ---- GetState (RemoteFunction, client -> server) --------------------------------
-- VALIDATES: nothing to validate -- it's a read of the caller's OWN state only. A player can only
-- ever ask for their own view (we key off `player`, never a client-supplied id).
Remotes.GetState.OnServerInvoke = function(player: Player)
	local state = PlayerData.get(player) or PlayerData.load(player)
	return Farm.buildView(state, ownedPlotsFor(player))
end

-- ---- GetCodex (RemoteFunction) : the player's discovered "plantId|mutationId" set, for the pokedex.
Remotes.GetCodex.OnServerInvoke = function(player: Player)
	local state = PlayerData.get(player)
	return state and state.codex or {}
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

-- ---- TradeAction (RemoteEvent, client -> server) --------------------------------
-- VALIDATES: the sub-action + arg types; Trade re-checks session membership + escrow holdings on the
-- server. The client can only ask; every item move goes through the conservation-proven TradeRules.
Remotes.TradeAction.OnServerEvent:Connect(function(player: Player, msg: any)
	if type(msg) ~= "table" or type(msg.do_) ~= "string" then
		return
	end
	local act = msg.do_
	if act == "request" and type(msg.target) == "number" then
		Trade.request(player, msg.target)
	elseif act == "respond" then
		Trade.respond(player, msg.accept == true)
	elseif act == "offer" and type(msg.key) == "string" and type(msg.qty) == "number" then
		Trade.offer(player, msg.key, math.floor(msg.qty))
	elseif act == "unoffer" and type(msg.key) == "string" then
		Trade.unoffer(player, msg.key)
	elseif act == "confirm" then
		Trade.confirm(player)
	elseif act == "cancel" then
		Trade.cancel(player)
	end
end)

-- ---- BuySeed (RemoteEvent, client -> server) ------------------------------------
-- VALIDATES: types; seed exists + is UNLOCKED for this player; qty in 1..SEED_BUY_LIMIT; affordable.
-- Charges qty*cost and adds the seeds to stock. Planting later spends the stock (see Farm.plant).
local SEED_BUY_LIMIT = 25
Remotes.BuySeed.OnServerEvent:Connect(function(player: Player, seedId: any, qty: any)
	if type(seedId) ~= "string" or type(qty) ~= "number" then
		return
	end
	local state = PlayerData.get(player)
	if not state then
		return
	end
	qty = math.clamp(math.floor(qty), 1, SEED_BUY_LIMIT)
	local plant = Plants.get(seedId)
	if not plant or not Plants.isUnlocked(plant, state, ownedPlotsFor(player)) then
		return
	end
	local cost = plant.cost * qty
	if state.coins < cost then
		Remotes.Notify:FireClient(player, "Not enough coins for " .. qty .. " " .. seedId .. " seeds.")
		return
	end
	state.coins -= cost
	state.seeds[seedId] = (state.seeds[seedId] or 0) + qty
	Remotes.Notify:FireClient(player, "🌱 Bought " .. qty .. " " .. seedId .. " seeds! (-" .. cost .. "c)")
	pushState(player)
end)

-- ---- combat helpers (RPG block 3) ----
local function setMonsterVisible(model: Model, visible: boolean)
	for _, p in model:GetDescendants() do
		if p:IsA("BasePart") then
			(p :: BasePart).Transparency = visible and 0 or 1
		elseif p:IsA("ProximityPrompt") then
			(p :: ProximityPrompt).Enabled = visible
		elseif p:IsA("BillboardGui") then
			(p :: BillboardGui).Enabled = visible
		end
	end
end
local function respawnMonster(model: Model, mdef: any)
	model:SetAttribute("hp", mdef.hp)
	local label = model:FindFirstChild("MonHp", true)
	if label and label:IsA("TextLabel") then
		label.Text = mdef.emoji .. " " .. mdef.name .. "\n❤️ " .. mdef.hp .. "/" .. mdef.hp
	end
	setMonsterVisible(model, true)
end

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

	-- First-time coaching: fire the matching tutorial before we run the action.
	do
		local tutId = PROMPT_TUT[kind]
		if kind == "homestead" then
			local act = prompt:GetAttribute("act")
			tutId = if type(act) == "string" then HOME_TUT[act] else nil
		end
		if tutId then
			tut(player, state, tutId)
		end
	end

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
	elseif kind == "buyboat" then
		-- Buy the first boat (Captain Bay's harbor_01 step). Unlocks the harbor + advances buy_boat quests.
		local ok, reason = SailRules.canBuyBoat(state)
		if ok then
			state.coins -= SailRules.BOAT_COST
			state.unlocks.boat = true
			Quest.report(player, "buy_boat", nil, 1)
			Remotes.Notify:FireClient(player, "⛵ You bought a boat! Sail to the islands from the Harbor.")
			pushState(player)
		else
			Remotes.Notify:FireClient(player, reason)
		end
	elseif kind == "sail" then
		local idx = prompt:GetAttribute("islandIndex")
		if type(idx) == "number" then
			-- GATE: must own a boat AND be high enough level for THIS island (SailRules, VPS-tested).
			local ok, reason = SailRules.canSailTo(idx, state, Rules.levelForXp(state.xp))
			if not ok then
				Remotes.Notify:FireClient(player, reason)
				return
			end
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
					* Farm.petMult(state, "luck") -- equipped luck pet
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
	elseif kind == "attack" then
		-- COMBAT: press E to hit the monster. Shared hp (co-op), server-authoritative. On death: xp +
		-- coins + a chance at loot, report kill/loot quests, then the monster respawns after a delay.
		local model = prompt.Parent and prompt.Parent.Parent
		if not (model and model:IsA("Model")) then
			return
		end
		local monId = model:GetAttribute("monsterId")
		local hp = model:GetAttribute("hp")
		local maxHp = model:GetAttribute("maxHp")
		if type(monId) ~= "string" or type(hp) ~= "number" or hp <= 0 then
			return
		end
		local mdef = Monsters.get(monId)
		if not mdef then
			return
		end
		local dmg = 20 + Rules.levelForXp(state.xp) * 2 -- you hit harder as you level
		hp = math.max(0, hp - dmg)
		model:SetAttribute("hp", hp)
		local label = model:FindFirstChild("MonHp", true)
		if hp > 0 then
			if label and label:IsA("TextLabel") then
				label.Text = mdef.emoji .. " " .. mdef.name .. "\n❤️ " .. hp .. "/" .. tostring(maxHp)
			end
		else
			state.xp += mdef.xp
			state.coins += mdef.coins
			state.lifetimeEarned += mdef.coins
			Quest.report(player, "kill", monId, 1)
			local msg = "⚔️ Defeated " .. mdef.name .. "! +" .. mdef.xp .. " xp +" .. mdef.coins .. "c"
			if mdef.loot and math.random() < mdef.loot.chance then
				local key = "loot|" .. mdef.loot.id
				state.inventory[key] = (state.inventory[key] or 0) + 1
				msg = msg .. "  + " .. mdef.loot.emoji .. " " .. mdef.loot.id .. "!"
				Quest.report(player, "loot", mdef.loot.id, 1)
			end
			Remotes.Notify:FireClient(player, msg)
			setMonsterVisible(model, false)
			local m = model
			task.delay(25, function()
				if m and m.Parent then
					respawnMonster(m, mdef)
				end
			end)
			pushState(player)
		end
	elseif kind == "premium" then
		-- Show the (cosmetic/convenience-only) Robux catalogue. Real purchase prompts wire in once the
		-- MarketplaceService product IDs are configured; for now this lists what's coming (zero P2W).
		local lines = { "✨ Premium (all cosmetic / convenience -- NEVER pay-to-win):" }
		for _, p in Premium.list do
			table.insert(lines, p.emoji .. " " .. p.name .. " -- " .. p.price .. " R$")
		end
		Remotes.Notify:FireClient(player, table.concat(lines, "\n"))
	elseif kind == "challenges" then
		-- Claim any finished daily challenges, then show today's board with live progress.
		local today = math.floor(os.time() / 86400)
		local reward, claimed = ChallengeRules.claimAll(state.challenges, today, Challenges.list, Challenges.DAILY_COUNT)
		if reward > 0 then
			state.coins += reward
			state.lifetimeEarned += reward
		end
		local lines = { "🎯 Daily Challenges:" }
		for _, c in ChallengeRules.dailySet(today, Challenges.list, Challenges.DAILY_COUNT) do
			local p = math.min(state.challenges.prog[c.id] or 0, c.target)
			local mark = if state.challenges.claimed[c.id] then "✅" elseif p >= c.target then "🎁" else "•"
			table.insert(lines, mark .. " " .. c.desc .. " (" .. p .. "/" .. c.target .. ") +" .. c.reward .. "c")
		end
		if claimed > 0 then
			table.insert(lines, 1, "Claimed " .. claimed .. " for +" .. reward .. "c!")
		end
		Remotes.Notify:FireClient(player, table.concat(lines, "\n"))
		if reward > 0 then
			pushState(player)
		end
	elseif kind == "adoptpet" then
		-- Buy the best pet you can afford + don't own yet; auto-equip the strongest owned.
		local best: any = nil
		for _, p in Pets.list do
			if not state.pets.owned[p.id] and state.coins >= p.cost then
				if best == nil or p.cost > best.cost then
					best = p
				end
			end
		end
		if best then
			state.coins -= best.cost
			state.pets.owned[best.id] = true
			state.pets.equipped = PetRules.bestOwned(state.pets.owned, Pets.get)
			Quest.report(player, "buy_pet", best.id, 1)
			Remotes.Notify:FireClient(player, best.emoji .. " Adopted a " .. best.name .. "! (" .. best.ability.type .. " +" .. math.floor(best.ability.value * 100) .. "%)")
			pushState(player)
		else
			Remotes.Notify:FireClient(player, "Can't afford a new pet yet (or you own them all)!")
		end
	elseif kind == "hatchegg" then
		-- Buy a mystery egg -> weighted hatch (rarer pets less likely). Auto-equips the strongest owned.
		local EGG_COST = 2000
		if state.coins < EGG_COST then
			Remotes.Notify:FireClient(player, "A mystery egg costs " .. EGG_COST .. " coins!")
		else
			local id = PetRules.hatch(Pets.list, gatherRand)
			local pet = if id then Pets.get(id) else nil
			if pet then
				state.coins -= EGG_COST
				local dup = state.pets.owned[pet.id] == true
				state.pets.owned[pet.id] = true
				state.pets.equipped = PetRules.bestOwned(state.pets.owned, Pets.get)
				Quest.report(player, "buy_pet", pet.id, 1)
				Remotes.Notify:FireClient(player, "🥚➡️ " .. pet.emoji .. " You hatched a " .. pet.name .. (dup and " (duplicate)" or "!") .. "")
				pushState(player)
			end
		end
	elseif kind == "museum" then
		-- Donate ONE of every inventory item type not yet in the museum; pay a flat reward each + a
		-- collection badge. Encourages keeping one of everything rather than selling it all.
		local REWARD = 60
		local donated = 0
		for key, qty in state.inventory do
			if qty >= 1 and not state.museum[key] then
				state.museum[key] = true
				local left = qty - 1
				if left > 0 then
					state.inventory[key] = left
				else
					state.inventory[key] = nil
				end
				state.coins += REWARD
				state.lifetimeEarned += REWARD
				donated += 1
			end
		end
		if donated > 0 then
			Quest.report(player, "donate", nil, donated)
			Remotes.Notify:FireClient(player, "🏛️ Donated " .. donated .. " new item(s)! (+" .. (donated * REWARD) .. "c)")
			pushState(player)
		else
			Remotes.Notify:FireClient(player, "Nothing new to donate -- gather rarer items!")
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

-- ---- fall safety net (kid-safe: no falling into the void) ----------------------
-- With StreamingEnabled a player can occasionally clip past the world edge, and kids love jumping
-- fences. If anyone drops below the world, warp them straight back onto their own farm.
task.spawn(function()
	while true do
		task.wait(0.4)
		for _, player in Players:GetPlayers() do
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp and (hrp :: BasePart).Position.Y < -20 then
				teleportToYard(player)
				Remotes.Notify:FireClient(player, "🪂 Whoops! Warped you back to your farm.")
			end
		end
	end
end)

-- ---- playtime rewards (retention): escalating coins for staying online -----------
task.spawn(function()
	while true do
		task.wait(20)
		for _, player in Players:GetPlayers() do
			local start = sessionStart[player.UserId]
			local state = PlayerData.get(player)
			if start and state then
				local mins = (os.time() - start) / 60
				local claimed = ptClaimed[player.UserId] or 0
				for i = claimed + 1, #PLAYTIME do
					if mins >= PLAYTIME[i][1] then
						local r = PLAYTIME[i][2]
						state.coins += r
						state.lifetimeEarned += r
						ptClaimed[player.UserId] = i
						Remotes.Notify:FireClient(player, "⏱️ Playtime reward (" .. PLAYTIME[i][1] .. " min online): +" .. r .. "c!")
						pushState(player)
					else
						break
					end
				end
			end
		end
	end
end)

-- ---- leaderboards: 3 boards (all-time / week / today) + champion rewards ---------
do
	local function makeBoard(x: number, titleText: string): TextLabel
		local part = Instance.new("Part")
		part.Size = Vector3.new(2, 26, 18)
		part.Anchored = true
		part.Color = Color3.fromRGB(38, 42, 54)
		part.Material = Enum.Material.SmoothPlastic
		part.Position = Vector3.new(x, 13, WorldLayout.PLAZA_Z - 46)
		part.Parent = workspace
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromScale(16, 14)
		bb.StudsOffset = Vector3.new(0, 1, 0)
		bb.MaxDistance = 260
		bb.Adornee = part
		bb.Parent = part
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.fromScale(1, 1)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextColor3 = Color3.fromRGB(240, 242, 255)
		lbl.TextStrokeTransparency = 0.5
		lbl.TextSize = 16
		lbl.TextYAlignment = Enum.TextYAlignment.Top
		lbl.Text = titleText
		lbl.Parent = bb
		return lbl
	end
	local boards = {
		{ metric = "all", title = "🏆 ALL-TIME TOP", label = makeBoard(-48, "🏆 ALL-TIME TOP") },
		{ metric = "weekly", title = "📅 THIS WEEK", label = makeBoard(0, "📅 THIS WEEK") },
		{ metric = "daily", title = "☀️ TODAY", label = makeBoard(48, "☀️ TODAY") },
	}
	task.spawn(function()
		while true do
			for _, b in boards do
				local top = Leaderboard.top(b.metric, 10)
				local lines = { b.title, "" }
				for i, e in top do
					table.insert(lines, i .. ". " .. e.name .. "  " .. e.value .. "c")
				end
				if #top == 0 then
					table.insert(lines, "(be the first!)")
				end
				b.label.Text = table.concat(lines, "\n")
			end
			task.wait(15)
		end
	end)
	-- champion bonus: the current #1 of the daily + weekly boards gets a periodic coin reward (a reason
	-- to fight for the top spot). Modest so it doesn't runaway-snowball.
	task.spawn(function()
		while true do
			task.wait(300)
			local function reward(metric: string, amount: number, emoji: string, label: string)
				local id = Leaderboard.championId(metric)
				local p = if id then Players:GetPlayerByUserId(id) else nil
				local st = if p then PlayerData.get(p) else nil
				if p and st then
					st.coins += amount
					st.lifetimeEarned += amount
					Remotes.Notify:FireClient(p, emoji .. " You're #1 " .. label .. "! Champion bonus +" .. amount .. "c")
					pushState(p)
				end
			end
			reward("daily", 250, "☀️", "today")
			reward("weekly", 500, "📅", "this week")
		end
	end)
end

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
