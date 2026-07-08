--!strict
-- BloomlyClient: the HUD for the 3D world. It does NOT block the screen or drive gameplay logic --
-- you walk your avatar to your farm and press the ProximityPrompt (E) on a pad to plant/harvest, and
-- on the Market to sell. All of that is server-authoritative. This client only:
--   1. renders a small HUD (coins / level / xp / codex / inventory) from StateUpdate, and
--   2. lets you PICK which seed the next Plant prompt uses (fires SelectSeed).
-- It holds no authoritative state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = require(ReplicatedStorage.Bloomly.Remotes)
local MapData = require(ReplicatedStorage.Bloomly.data.MapData)
local MapRules = require(ReplicatedStorage.Bloomly.MapRules)
local WorldLayout = require(ReplicatedStorage.Bloomly.data.WorldLayout)
local Tutorials = require(ReplicatedStorage.Bloomly.data.Tutorials)
local Sounds = require(ReplicatedStorage.Bloomly.data.Sounds)
local Plants = require(ReplicatedStorage.Bloomly.data.Plants)

-- ---- sound: one cached Sound per key, played on demand. Empty ids are silent (safe). ----
local SoundService = game:GetService("SoundService")
local soundCache: { [string]: Sound } = {}
local function playSound(key: string)
	local def = Sounds.map[key]
	if not def or def.id == "" then
		return
	end
	local s = soundCache[key]
	if not s then
		s = Instance.new("Sound")
		s.SoundId = def.id
		s.Volume = def.volume
		s.Looped = def.looped or false
		s.Parent = SoundService
		soundCache[key] = s
	end
	if def.looped then
		if not s.IsPlaying then
			s:Play()
		end
	else
		s:Play()
	end
end
playSound("music") -- background loop if an id is configured

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BloomlyHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

-- ---- loading screen (polish) : covers the screen until the first authoritative state arrives ----
local loading = Instance.new("Frame")
loading.Size = UDim2.fromScale(1, 1)
loading.BackgroundColor3 = Color3.fromRGB(24, 40, 26)
loading.BorderSizePixel = 0
loading.ZIndex = 50
loading.Parent = gui
local loadingText = Instance.new("TextLabel")
loadingText.Size = UDim2.new(1, 0, 0, 80)
loadingText.Position = UDim2.new(0, 0, 0.5, -40)
loadingText.BackgroundTransparency = 1
loadingText.TextColor3 = Color3.fromRGB(240, 255, 230)
loadingText.Font = Enum.Font.GothamBold
loadingText.TextSize = 40
loadingText.Text = "🌱 Bloomly"
loadingText.ZIndex = 51
loadingText.Parent = loading
local loadingSub = Instance.new("TextLabel")
loadingSub.Size = UDim2.new(1, 0, 0, 30)
loadingSub.Position = UDim2.new(0, 0, 0.5, 20)
loadingSub.BackgroundTransparency = 1
loadingSub.TextColor3 = Color3.fromRGB(190, 220, 190)
loadingSub.Font = Enum.Font.Gotham
loadingSub.TextSize = 16
loadingSub.Text = "Growing your world..."
loadingSub.ZIndex = 51
loadingSub.Parent = loading
local loadingDone = false
local function hideLoading()
	if loadingDone then
		return
	end
	loadingDone = true
	task.spawn(function()
		for i = 0, 10 do
			loading.BackgroundTransparency = i / 10
			loadingText.TextTransparency = i / 10
			loadingSub.TextTransparency = i / 10
			task.wait(0.04)
		end
		loading.Visible = false
	end)
end

-- ---- top-left stats panel ----
local hud = Instance.new("Frame")
hud.Size = UDim2.new(0, 360, 0, 74)
hud.Position = UDim2.new(0, 12, 0, 12)
hud.BackgroundColor3 = Color3.fromRGB(24, 30, 22)
hud.BackgroundTransparency = 0.25
hud.BorderSizePixel = 0
hud.Parent = gui
local hudCorner = Instance.new("UICorner")
hudCorner.CornerRadius = UDim.new(0, 8)
hudCorner.Parent = hud

local stats = Instance.new("TextLabel")
stats.Size = UDim2.new(1, -12, 0, 26)
stats.Position = UDim2.new(0, 8, 0, 4)
stats.BackgroundTransparency = 1
stats.TextXAlignment = Enum.TextXAlignment.Left
stats.TextColor3 = Color3.fromRGB(240, 245, 230)
stats.Font = Enum.Font.GothamBold
stats.TextSize = 16
stats.Text = "Bloomly — connecting..."
stats.Parent = hud

local invLabel = Instance.new("TextLabel")
invLabel.Size = UDim2.new(1, -110, 0, 24)
invLabel.Position = UDim2.new(0, 8, 0, 40)
invLabel.BackgroundTransparency = 1
invLabel.TextXAlignment = Enum.TextXAlignment.Left
invLabel.TextColor3 = Color3.fromRGB(210, 220, 200)
invLabel.Font = Enum.Font.Gotham
invLabel.TextSize = 14
invLabel.Text = "🎒 empty"
invLabel.Parent = hud

local sellBtn = Instance.new("TextButton")
sellBtn.Size = UDim2.new(0, 92, 0, 26)
sellBtn.Position = UDim2.new(1, -100, 0, 40)
sellBtn.BackgroundColor3 = Color3.fromRGB(210, 170, 60)
sellBtn.TextColor3 = Color3.fromRGB(30, 25, 10)
sellBtn.Font = Enum.Font.GothamBold
sellBtn.TextSize = 13
sellBtn.Text = "Sell all"
sellBtn.Parent = hud
local sbCorner = Instance.new("UICorner")
sbCorner.CornerRadius = UDim.new(0, 6)
sbCorner.Parent = sellBtn
sellBtn.Activated:Connect(function()
	Remotes.SellAll:FireServer()
end)

-- ---- hint ----
local hint = Instance.new("TextLabel")
hint.Size = UDim2.new(0, 560, 0, 22)
hint.Position = UDim2.new(0.5, -280, 0, 12)
hint.BackgroundTransparency = 1
hint.TextColor3 = Color3.fromRGB(255, 255, 255)
hint.TextStrokeTransparency = 0.5
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 15
hint.Text = "Find your 🌱 farm · press E on a plot to plant/harvest · sell at 🧺 Market · hold Shift to sprint"
hint.Parent = gui

-- ---- event banner (top-center, under the hint) ----
-- Shows the ACTIVE server-wide event (from §D's 50 EPIC events) with a live countdown. Hidden when
-- no event is running. Pulses so a kid can't miss that something big is happening.
local eventBanner = Instance.new("TextLabel")
eventBanner.Size = UDim2.new(0, 620, 0, 40)
eventBanner.Position = UDim2.new(0.5, -310, 0, 40)
eventBanner.BackgroundColor3 = Color3.fromRGB(80, 30, 90)
eventBanner.BackgroundTransparency = 1
eventBanner.BorderSizePixel = 0
eventBanner.TextColor3 = Color3.fromRGB(255, 240, 170)
eventBanner.TextStrokeTransparency = 1
eventBanner.Font = Enum.Font.GothamBold
eventBanner.TextSize = 18
eventBanner.Text = ""
eventBanner.Visible = false
eventBanner.Parent = gui
local ebCorner = Instance.new("UICorner")
ebCorner.CornerRadius = UDim.new(0, 8)
ebCorner.Parent = eventBanner

local currentEvent: any = nil -- last event snapshot from the server {name,emoji,desc,timeLeft}
-- Local countdown ticker so the banner timer ticks smoothly between state pushes.
task.spawn(function()
	while true do
		task.wait(1)
		if currentEvent and currentEvent.timeLeft and currentEvent.timeLeft > 0 then
			currentEvent.timeLeft -= 1
			local mins = math.floor(currentEvent.timeLeft / 60)
			local secs = currentEvent.timeLeft % 60
			eventBanner.Text = string.format("%s  %s  ·  %d:%02d left", currentEvent.emoji, currentEvent.name, mins, secs)
		end
	end
end)

-- ---- quest tracker (top-right) ----
local questPanel = Instance.new("TextLabel")
questPanel.Size = UDim2.new(0, 300, 0, 150)
questPanel.Position = UDim2.new(1, -312, 0, 44)
questPanel.BackgroundColor3 = Color3.fromRGB(24, 30, 22)
questPanel.BackgroundTransparency = 0.3
questPanel.BorderSizePixel = 0
questPanel.TextXAlignment = Enum.TextXAlignment.Left
questPanel.TextYAlignment = Enum.TextYAlignment.Top
questPanel.TextColor3 = Color3.fromRGB(235, 240, 225)
questPanel.Font = Enum.Font.GothamMedium
questPanel.TextSize = 13
questPanel.Text = "📜 Quests: talk to 🌳 Elder Willow to start!"
questPanel.Parent = gui
local qpCorner = Instance.new("UICorner")
qpCorner.CornerRadius = UDim.new(0, 8)
qpCorner.Parent = questPanel
local qpPad = Instance.new("UIPadding")
qpPad.PaddingLeft = UDim.new(0, 8)
qpPad.PaddingTop = UDim.new(0, 6)
qpPad.Parent = questPanel

-- ---- notify toast (bottom-center, fades) ----
local toast = Instance.new("TextLabel")
toast.Size = UDim2.new(0, 520, 0, 34)
toast.Position = UDim2.new(0.5, -260, 1, -120)
toast.BackgroundColor3 = Color3.fromRGB(40, 60, 30)
toast.BackgroundTransparency = 1
toast.TextColor3 = Color3.fromRGB(255, 255, 255)
toast.TextStrokeTransparency = 1
toast.Font = Enum.Font.GothamBold
toast.TextSize = 18
toast.Text = ""
toast.Parent = gui
local toastCorner = Instance.new("UICorner")
toastCorner.CornerRadius = UDim.new(0, 8)
toastCorner.Parent = toast
local toastToken = 0
Remotes.Notify.OnClientEvent:Connect(function(msg: string)
	-- contextual sound cue (silent until you configure the ids in data/Sounds.luau)
	if string.find(msg, "EVENT") then
		playSound("event")
	elseif string.find(msg, "Treasure") or string.find(msg, "treasure") then
		playSound("treasure")
	elseif string.find(msg, "Achievement") then
		playSound("reward")
	end
	toast.Text = msg
	toast.BackgroundTransparency = 0.2
	toast.TextStrokeTransparency = 0.3
	toastToken += 1
	local myToken = toastToken
	task.delay(3.5, function()
		if myToken == toastToken then
			toast.BackgroundTransparency = 1
			toast.TextStrokeTransparency = 1
			toast.Text = ""
		end
	end)
end)

-- ---- bottom seed bar (horizontal scroll: the crop roster is large now) ----
local seedBar = Instance.new("ScrollingFrame")
seedBar.Size = UDim2.new(0, 900, 0, 66)
seedBar.Position = UDim2.new(0.5, -450, 1, -80)
seedBar.BackgroundTransparency = 1
seedBar.BorderSizePixel = 0
seedBar.ScrollingDirection = Enum.ScrollingDirection.X
seedBar.ScrollBarThickness = 6
seedBar.CanvasSize = UDim2.new(0, 0, 0, 0)
seedBar.AutomaticCanvasSize = Enum.AutomaticSize.X
seedBar.Parent = gui
local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
barLayout.VerticalAlignment = Enum.VerticalAlignment.Center
barLayout.Padding = UDim.new(0, 6)
barLayout.SortOrder = Enum.SortOrder.LayoutOrder
barLayout.Parent = seedBar

local COL_NORMAL = Color3.fromRGB(70, 110, 60)
local COL_SELECTED = Color3.fromRGB(120, 190, 90)
local COL_LOCKED = Color3.fromRGB(70, 70, 70)
local COL_POOR = Color3.fromRGB(95, 72, 60)

local seedButtons: { [string]: TextButton } = {}
local builtSeeds = false

local function buildSeeds(view: any)
	for _, s in view.seeds do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 96, 1, 0)
		btn.BackgroundColor3 = COL_NORMAL
		btn.TextColor3 = Color3.fromRGB(245, 245, 240)
		btn.Font = Enum.Font.GothamMedium
		btn.TextSize = 12
		btn.Text = s.emoji .. " " .. s.id
		btn.Parent = seedBar
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = btn
		seedButtons[s.id] = btn
		btn.Activated:Connect(function()
			-- picking a seed is just a request; server records it + re-checks on plant
			Remotes.SelectSeed:FireServer(s.id)
		end)
	end
end

local lastInventory: { any } = {} -- most recent inventory snapshot (for the trade offer picker)
local lastSection: number? = nil -- the player's own plot section (for the "your farm" map dot)

-- ---- juice: floating popups + level-up flash ----
local function floatPopup(text: string, color: Color3)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 240, 0, 40)
	lbl.Position = UDim2.new(0.5, -120, 0.62, 0)
	lbl.BackgroundTransparency = 1
	lbl.TextColor3 = color
	lbl.TextStrokeTransparency = 0.35
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 26
	lbl.Text = text
	lbl.ZIndex = 30
	lbl.Parent = gui
	task.spawn(function()
		for i = 0, 22 do
			lbl.Position = UDim2.new(0.5, -120, 0.62 - i * 0.013, 0)
			lbl.TextTransparency = i / 22
			lbl.TextStrokeTransparency = 0.35 + i * 0.03
			task.wait(0.03)
		end
		lbl:Destroy()
	end)
end

local function levelUpFlash(n: number)
	local f = Instance.new("TextLabel")
	f.Size = UDim2.new(0, 520, 0, 70)
	f.Position = UDim2.new(0.5, -260, 0.35, 0)
	f.BackgroundTransparency = 1
	f.TextColor3 = Color3.fromRGB(255, 225, 90)
	f.TextStrokeTransparency = 0.3
	f.Font = Enum.Font.GothamBlack
	f.TextSize = 46
	f.Text = "⭐ LEVEL UP!  Lv " .. n
	f.ZIndex = 31
	f.Parent = gui
	task.spawn(function()
		for i = 0, 34 do
			f.TextSize = 46 + math.sin(i / 34 * math.pi) * 10
			f.TextTransparency = math.max(0, (i - 20) / 14)
			f.TextStrokeTransparency = 0.3 + math.max(0, (i - 20) / 14)
			task.wait(0.04)
		end
		f:Destroy()
	end)
end

local prev = { coins = nil :: number?, xp = nil :: number?, level = nil :: number? }

local function render(view: any)
	stats.Text = string.format("🪙 %d    Lv %d (%d xp)    📖 %d    🌾 %d%s", view.coins, view.level, view.xp, view.codexCount, view.harvests, (view.pet and view.pet ~= "" and ("    " .. view.pet)) or "")

	hideLoading() -- first authoritative state arrived -> reveal the world
	lastInventory = view.inventory or {}
	lastSection = view.section or lastSection

	-- juice: pop floating rewards + a level-up flash when the numbers jump up
	if prev.coins ~= nil then
		local dc = view.coins - (prev.coins :: number)
		if dc > 0 then
			floatPopup("+" .. dc .. " 🪙", Color3.fromRGB(255, 220, 90))
			playSound("reward")
		end
		local dx = view.xp - (prev.xp :: number)
		if dx > 0 then
			floatPopup("+" .. dx .. " xp", Color3.fromRGB(150, 220, 255))
		end
		if view.level > (prev.level :: number) then
			levelUpFlash(view.level)
			if Sounds.map.levelup.id ~= "" then
				playSound("levelup")
			else
				playSound("reward")
			end
		end
	end
	prev.coins, prev.xp, prev.level = view.coins, view.xp, view.level
	local count, worth = 0, 0
	for _, item in view.inventory do
		count += item.qty
		worth += item.unitValue * item.qty
	end
	invLabel.Text = if count == 0 then "🎒 empty" else string.format("🎒 %d items · worth %dc", count, worth)

	if not builtSeeds then
		buildSeeds(view)
		builtSeeds = true
	end
	for _, s in view.seeds do
		local btn = seedButtons[s.id]
		if btn then
			if not s.unlocked then
				btn.BackgroundColor3 = COL_LOCKED
				btn.Text = s.emoji .. " " .. s.id .. "\nLOCKED"
			elseif not s.affordable then
				btn.BackgroundColor3 = COL_POOR
				btn.Text = s.emoji .. " " .. s.id .. "\nneed " .. s.cost .. "c"
			else
				btn.BackgroundColor3 = if view.selectedSeed == s.id then COL_SELECTED else COL_NORMAL
				btn.Text = s.emoji .. " " .. s.id .. "\nbuy " .. s.cost .. "c"
			end
		end
	end

	-- event banner
	if view.event then
		currentEvent = view.event
		eventBanner.Visible = true
		eventBanner.BackgroundTransparency = 0.15
		eventBanner.TextStrokeTransparency = 0.4
		local mins = math.floor((view.event.timeLeft or 0) / 60)
		local secs = (view.event.timeLeft or 0) % 60
		eventBanner.Text = string.format("%s  %s  ·  %d:%02d left", view.event.emoji, view.event.name, mins, secs)
	else
		currentEvent = nil
		eventBanner.Visible = false
	end

	-- quest tracker
	if view.quests and #view.quests > 0 then
		local lines = { "📜 Quests:" }
		for _, q in view.quests do
			if q.ready then
				table.insert(lines, "✅ " .. q.name .. " — turn in!")
			else
				table.insert(lines, "• " .. q.name .. "  (" .. q.prog .. "/" .. q.need .. ", step " .. q.step .. "/" .. q.steps .. ")")
			end
		end
		questPanel.Text = table.concat(lines, "\n")
	else
		questPanel.Text = "📜 Quests: talk to 🌳 Elder Willow to start!"
	end
end

Remotes.StateUpdate.OnClientEvent:Connect(render)

-- ================= TRADE UI (block 14b) =================
-- A "Trade" button opens a player picker (request a trade / accept an incoming one). Once a session is
-- live, TradeUpdate drives a two-column window: your offer, their offer, both confirm states, and a row
-- of your inventory to offer from. All moves are server-authoritative (TradeRules).
local function mkBtn(parent: Instance, text: string, w: number, color: Color3): TextButton
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, w, 0, 30)
	b.BackgroundColor3 = color
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.Text = text
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	return b
end

local tradeBtn = mkBtn(gui, "🤝 Trade", 92, Color3.fromRGB(90, 130, 200))
tradeBtn.Position = UDim2.new(1, -104, 0, 200)

-- ---- player picker ----
local picker = Instance.new("Frame")
picker.Size = UDim2.new(0, 260, 0, 300)
picker.Position = UDim2.new(0.5, -130, 0.5, -150)
picker.BackgroundColor3 = Color3.fromRGB(28, 34, 44)
picker.BorderSizePixel = 0
picker.Visible = false
picker.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = picker
end
local pickerTitle = Instance.new("TextLabel")
pickerTitle.Size = UDim2.new(1, 0, 0, 30)
pickerTitle.BackgroundTransparency = 1
pickerTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
pickerTitle.Font = Enum.Font.GothamBold
pickerTitle.TextSize = 15
pickerTitle.Text = "🤝 Trade with..."
pickerTitle.Parent = picker
local pickerList = Instance.new("ScrollingFrame")
pickerList.Size = UDim2.new(1, -16, 1, -80)
pickerList.Position = UDim2.new(0, 8, 0, 34)
pickerList.BackgroundTransparency = 1
pickerList.BorderSizePixel = 0
pickerList.ScrollBarThickness = 5
pickerList.Parent = picker
local pll = Instance.new("UIListLayout"); pll.Padding = UDim.new(0, 4); pll.Parent = pickerList
local acceptBtn = mkBtn(picker, "✅ Accept incoming request", 240, Color3.fromRGB(80, 160, 90))
acceptBtn.Position = UDim2.new(0, 10, 1, -74)
acceptBtn.Size = UDim2.new(1, -20, 0, 28)
local closePicker = mkBtn(picker, "Close", 240, Color3.fromRGB(120, 90, 90))
closePicker.Position = UDim2.new(0, 10, 1, -40)
closePicker.Size = UDim2.new(1, -20, 0, 28)
closePicker.Activated:Connect(function() picker.Visible = false end)
acceptBtn.Activated:Connect(function()
	Remotes.TradeAction:FireServer({ do_ = "respond", accept = true })
	picker.Visible = false
end)
local function refreshPicker()
	for _, ch in pickerList:GetChildren() do
		if ch:IsA("TextButton") then ch:Destroy() end
	end
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local b = mkBtn(pickerList, other.Name, 230, Color3.fromRGB(70, 100, 150))
			b.Size = UDim2.new(1, -6, 0, 28)
			local uid = other.UserId
			b.Activated:Connect(function()
				Remotes.TradeAction:FireServer({ do_ = "request", target = uid })
				picker.Visible = false
			end)
		end
	end
end
tradeBtn.Activated:Connect(function()
	refreshPicker()
	picker.Visible = not picker.Visible
end)

-- ---- live trade window ----
local tradeWin = Instance.new("Frame")
tradeWin.Size = UDim2.new(0, 480, 0, 340)
tradeWin.Position = UDim2.new(0.5, -240, 0.5, -170)
tradeWin.BackgroundColor3 = Color3.fromRGB(26, 32, 40)
tradeWin.BorderSizePixel = 0
tradeWin.Visible = false
tradeWin.Parent = gui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = tradeWin
end
local twTitle = Instance.new("TextLabel")
twTitle.Size = UDim2.new(1, 0, 0, 28)
twTitle.BackgroundTransparency = 1
twTitle.TextColor3 = Color3.fromRGB(240, 245, 255)
twTitle.Font = Enum.Font.GothamBold
twTitle.TextSize = 15
twTitle.Text = "Trade"
twTitle.Parent = tradeWin
local yourOffer = Instance.new("TextLabel")
yourOffer.Size = UDim2.new(0.5, -12, 0, 120)
yourOffer.Position = UDim2.new(0, 8, 0, 32)
yourOffer.BackgroundColor3 = Color3.fromRGB(34, 44, 38)
yourOffer.TextColor3 = Color3.fromRGB(220, 235, 220)
yourOffer.Font = Enum.Font.Gotham
yourOffer.TextSize = 13
yourOffer.TextXAlignment = Enum.TextXAlignment.Left
yourOffer.TextYAlignment = Enum.TextYAlignment.Top
yourOffer.Text = ""
yourOffer.Parent = tradeWin
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = yourOffer local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,6); p.PaddingTop=UDim.new(0,4); p.Parent=yourOffer end
local theirOffer = Instance.new("TextLabel")
theirOffer.Size = UDim2.new(0.5, -12, 0, 120)
theirOffer.Position = UDim2.new(0.5, 4, 0, 32)
theirOffer.BackgroundColor3 = Color3.fromRGB(44, 38, 34)
theirOffer.TextColor3 = Color3.fromRGB(235, 220, 220)
theirOffer.Font = Enum.Font.Gotham
theirOffer.TextSize = 13
theirOffer.TextXAlignment = Enum.TextXAlignment.Left
theirOffer.TextYAlignment = Enum.TextYAlignment.Top
theirOffer.Text = ""
theirOffer.Parent = tradeWin
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = theirOffer local p=Instance.new("UIPadding"); p.PaddingLeft=UDim.new(0,6); p.PaddingTop=UDim.new(0,4); p.Parent=theirOffer end
local confirmLbl = Instance.new("TextLabel")
confirmLbl.Size = UDim2.new(1, -16, 0, 20)
confirmLbl.Position = UDim2.new(0, 8, 0, 156)
confirmLbl.BackgroundTransparency = 1
confirmLbl.TextColor3 = Color3.fromRGB(255, 240, 170)
confirmLbl.Font = Enum.Font.GothamBold
confirmLbl.TextSize = 13
confirmLbl.Text = ""
confirmLbl.Parent = tradeWin
-- inventory row to offer from
local invRow = Instance.new("ScrollingFrame")
invRow.Size = UDim2.new(1, -16, 0, 84)
invRow.Position = UDim2.new(0, 8, 0, 180)
invRow.BackgroundColor3 = Color3.fromRGB(20, 24, 30)
invRow.BorderSizePixel = 0
invRow.ScrollBarThickness = 5
invRow.Parent = tradeWin
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0,6); c.Parent = invRow end
local irl = Instance.new("UIGridLayout"); irl.CellSize = UDim2.new(0, 110, 0, 24); irl.CellPadding = UDim2.new(0, 4, 0, 4); irl.Parent = invRow
local twConfirm = mkBtn(tradeWin, "✅ Confirm", 150, Color3.fromRGB(80, 160, 90))
twConfirm.Position = UDim2.new(0, 8, 1, -40)
local twCancel = mkBtn(tradeWin, "❌ Cancel", 150, Color3.fromRGB(170, 80, 80))
twCancel.Position = UDim2.new(1, -158, 1, -40)
twConfirm.Activated:Connect(function() Remotes.TradeAction:FireServer({ do_ = "confirm" }) end)
twCancel.Activated:Connect(function() Remotes.TradeAction:FireServer({ do_ = "cancel" }) end)

local function offerText(list: { any }): string
	if not list or #list == 0 then
		return "(nothing)"
	end
	local lines = {}
	for _, it in list do
		table.insert(lines, "• " .. it.key .. " x" .. it.qty)
	end
	return table.concat(lines, "\n")
end

local function rebuildInvRow()
	for _, ch in invRow:GetChildren() do
		if ch:IsA("TextButton") then ch:Destroy() end
	end
	for _, item in lastInventory do
		-- buildView inventory rows are {plantId,mutationId,qty,...}; reconstruct the server inventory key
		local invKey = (item.mutationId and item.mutationId ~= "") and (item.plantId .. "|" .. item.mutationId) or item.plantId
		local b = mkBtn(invRow, (item.emoji or "") .. " +1", 110, Color3.fromRGB(70, 110, 150))
		b.Activated:Connect(function()
			Remotes.TradeAction:FireServer({ do_ = "offer", key = invKey, qty = 1 })
		end)
	end
end

Remotes.TradeUpdate.OnClientEvent:Connect(function(data: any)
	if not data then
		tradeWin.Visible = false
		return
	end
	tradeWin.Visible = true
	picker.Visible = false
	twTitle.Text = "🤝 Trading with " .. tostring(data.partner)
	yourOffer.Text = "YOUR OFFER:\n" .. offerText(data.yourOffer)
	theirOffer.Text = (tostring(data.partner) .. "'S OFFER:\n") .. offerText(data.theirOffer)
	confirmLbl.Text = "You: " .. (data.youConfirmed and "✅" or "⬜") .. "   Them: " .. (data.theyConfirmed and "✅" or "⬜") .. "   (offering resets confirms)"
	rebuildInvRow()
end)

-- ================= MAP + MINIMAP (block 16) =================
-- A corner minimap projects the real world (MapData landmarks) through MapRules; a "you" dot tracks
-- your character live. The Map button opens a bigger full-map with island labels + your farm.
local DOT = {
	plaza = Color3.fromRGB(120, 200, 120),
	harbor = Color3.fromRGB(120, 160, 220),
	island = Color3.fromRGB(230, 200, 120),
	you = Color3.fromRGB(255, 90, 90),
	farm = Color3.fromRGB(120, 255, 160),
}
local landmarks = MapData.landmarks()

-- Build a map panel (frame) of pixel size `sz`; returns the frame + a function to place a live "you" dot.
local function buildMap(sz: number, withLabels: boolean): (Frame, Frame, Frame)
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(0, sz, 0, sz)
	frame.BackgroundColor3 = Color3.fromRGB(30, 46, 60)
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 8); c.Parent = frame
	-- ocean ring hint
	for _, lm in landmarks do
		local p = MapRules.worldToMap(lm.x, lm.z, MapData.BOUNDS)
		local dot = Instance.new("Frame")
		local isIsle = lm.kind == "island"
		dot.Size = UDim2.new(0, isIsle and 8 or 10, 0, isIsle and 8 or 10)
		dot.Position = UDim2.new(p.u, -4, p.v, -4)
		dot.BackgroundColor3 = DOT[lm.kind] or Color3.fromRGB(200, 200, 200)
		dot.BorderSizePixel = 0
		local dc = Instance.new("UICorner"); dc.CornerRadius = UDim.new(1, 0); dc.Parent = dot
		dot.Parent = frame
		if withLabels then
			local lbl = Instance.new("TextLabel")
			lbl.Size = UDim2.new(0, 90, 0, 14)
			lbl.Position = UDim2.new(p.u, 6, p.v, -7)
			lbl.BackgroundTransparency = 1
			lbl.TextColor3 = Color3.fromRGB(235, 240, 230)
			lbl.Font = Enum.Font.Gotham
			lbl.TextSize = 11
			lbl.TextXAlignment = Enum.TextXAlignment.Left
			lbl.Text = (lm.kind == "island") and ((lm.island == 11) and "Enchanted Forest" or lm.name) or lm.name
			lbl.Parent = frame
		end
	end
	-- your-farm dot (position updated when we learn our section)
	local farmDot = Instance.new("Frame")
	farmDot.Size = UDim2.new(0, 9, 0, 9)
	farmDot.BackgroundColor3 = DOT.farm
	farmDot.BorderSizePixel = 0
	farmDot.Visible = false
	local fc = Instance.new("UICorner"); fc.CornerRadius = UDim.new(1, 0); fc.Parent = farmDot
	farmDot.Parent = frame
	-- you dot
	local youDot = Instance.new("Frame")
	youDot.Size = UDim2.new(0, 9, 0, 9)
	youDot.BackgroundColor3 = DOT.you
	youDot.BorderSizePixel = 0
	local yc = Instance.new("UICorner"); yc.CornerRadius = UDim.new(1, 0); yc.Parent = youDot
	youDot.Parent = frame
	return frame, youDot, farmDot
end

local miniMap, miniYou, miniFarm = buildMap(150, false)
miniMap.Position = UDim2.new(0, 12, 1, -162)
miniMap.Parent = gui

local fullMap, fullYou, fullFarm = buildMap(420, true)
fullMap.Position = UDim2.new(0.5, -210, 0.5, -210)
fullMap.Visible = false
fullMap.Parent = gui
local mapTitle = Instance.new("TextLabel")
mapTitle.Size = UDim2.new(1, 0, 0, 22)
mapTitle.Position = UDim2.new(0, 0, 0, -24)
mapTitle.BackgroundTransparency = 1
mapTitle.TextColor3 = Color3.fromRGB(240, 245, 230)
mapTitle.Font = Enum.Font.GothamBold
mapTitle.TextSize = 16
mapTitle.Text = "🗺️ Bloomly World Map"
mapTitle.Parent = fullMap

local mapBtn = mkBtn(gui, "🗺️ Map", 80, Color3.fromRGB(90, 140, 90))
mapBtn.Position = UDim2.new(1, -104, 0, 236)
mapBtn.Activated:Connect(function()
	fullMap.Visible = not fullMap.Visible
end)

-- place the "your farm" dots once we know our section
local function updateFarmDots()
	if not lastSection then
		return
	end
	local c = WorldLayout.sectionCenter(lastSection)
	local p = MapRules.worldToMap(c.x, c.z, MapData.BOUNDS)
	for _, d in { miniFarm, fullFarm } do
		d.Position = UDim2.new(p.u, -4, p.v, -4)
		d.Visible = true
	end
end

-- live "you" dot every frame from the character root
RunService.Heartbeat:Connect(function()
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local p = MapRules.worldToMap((hrp :: BasePart).Position.X, (hrp :: BasePart).Position.Z, MapData.BOUNDS)
		miniYou.Position = UDim2.new(p.u, -4, p.v, -4)
		fullYou.Position = UDim2.new(p.u, -4, p.v, -4)
	end
	updateFarmDots()
end)

-- ================= HELP / GUIDE (block 2) =================
-- A "?" button opens a scrollable guide built from the Tutorials data -- every mechanic explained so a
-- kid can always look up "how do I collect this?".
local helpBtn = mkBtn(gui, "❓ Help", 80, Color3.fromRGB(200, 160, 70))
helpBtn.Position = UDim2.new(1, -104, 0, 272)

local helpPanel = Instance.new("Frame")
helpPanel.Size = UDim2.new(0, 420, 0, 420)
helpPanel.Position = UDim2.new(0.5, -210, 0.5, -210)
helpPanel.BackgroundColor3 = Color3.fromRGB(28, 36, 30)
helpPanel.BorderSizePixel = 0
helpPanel.Visible = false
helpPanel.ZIndex = 20
helpPanel.Parent = gui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = helpPanel end
local helpTitle = Instance.new("TextLabel")
helpTitle.Size = UDim2.new(1, 0, 0, 30)
helpTitle.BackgroundTransparency = 1
helpTitle.TextColor3 = Color3.fromRGB(240, 245, 230)
helpTitle.Font = Enum.Font.GothamBold
helpTitle.TextSize = 17
helpTitle.Text = "📖 How to Play Bloomly"
helpTitle.ZIndex = 21
helpTitle.Parent = helpPanel
local helpScroll = Instance.new("ScrollingFrame")
helpScroll.Size = UDim2.new(1, -16, 1, -76)
helpScroll.Position = UDim2.new(0, 8, 0, 34)
helpScroll.BackgroundTransparency = 1
helpScroll.BorderSizePixel = 0
helpScroll.ScrollBarThickness = 6
helpScroll.CanvasSize = UDim2.new(0, 0, 0, #Tutorials.list * 58)
helpScroll.ZIndex = 21
helpScroll.Parent = helpPanel
local hsl = Instance.new("UIListLayout"); hsl.Padding = UDim.new(0, 4); hsl.Parent = helpScroll
for _, t in Tutorials.list do
	local row = Instance.new("TextLabel")
	row.Size = UDim2.new(1, -6, 0, 54)
	row.BackgroundColor3 = Color3.fromRGB(38, 48, 40)
	row.TextColor3 = Color3.fromRGB(225, 235, 220)
	row.Font = Enum.Font.Gotham
	row.TextSize = 13
	row.TextXAlignment = Enum.TextXAlignment.Left
	row.TextYAlignment = Enum.TextYAlignment.Top
	row.TextWrapped = true
	row.Text = t.emoji .. " " .. t.title .. "\n" .. t.hint
	row.ZIndex = 22
	row.Parent = helpScroll
	do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = row local p = Instance.new("UIPadding"); p.PaddingLeft = UDim.new(0, 8); p.PaddingTop = UDim.new(0, 4); p.Parent = row end
end
local helpClose = mkBtn(helpPanel, "Close", 200, Color3.fromRGB(120, 90, 90))
helpClose.Position = UDim2.new(0.5, -100, 1, -36)
helpClose.Size = UDim2.new(0, 200, 0, 30)
helpClose.ZIndex = 22
helpClose.Activated:Connect(function() helpPanel.Visible = false end)
helpBtn.Activated:Connect(function() helpPanel.Visible = not helpPanel.Visible end)

-- ================= INVENTORY (block A) =================
local bagBtn = mkBtn(gui, "🎒 Bag", 80, Color3.fromRGB(150, 120, 70))
bagBtn.Position = UDim2.new(1, -104, 0, 164)

local bagPanel = Instance.new("Frame")
bagPanel.Size = UDim2.new(0, 380, 0, 440)
bagPanel.Position = UDim2.new(0.5, -190, 0.5, -220)
bagPanel.BackgroundColor3 = Color3.fromRGB(34, 30, 24)
bagPanel.BorderSizePixel = 0
bagPanel.Visible = false
bagPanel.ZIndex = 20
bagPanel.Parent = gui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = bagPanel end
local bagTitle = Instance.new("TextLabel")
bagTitle.Size = UDim2.new(1, 0, 0, 30)
bagTitle.BackgroundTransparency = 1
bagTitle.TextColor3 = Color3.fromRGB(245, 235, 210)
bagTitle.Font = Enum.Font.GothamBold
bagTitle.TextSize = 16
bagTitle.Text = "🎒 Inventory"
bagTitle.ZIndex = 21
bagTitle.Parent = bagPanel
local bagScroll = Instance.new("ScrollingFrame")
bagScroll.Size = UDim2.new(1, -16, 1, -76)
bagScroll.Position = UDim2.new(0, 8, 0, 34)
bagScroll.BackgroundTransparency = 1
bagScroll.BorderSizePixel = 0
bagScroll.ScrollBarThickness = 6
bagScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
bagScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
bagScroll.ZIndex = 21
bagScroll.Parent = bagPanel
local bsl = Instance.new("UIListLayout"); bsl.Padding = UDim.new(0, 3); bsl.Parent = bagScroll
local bagClose = mkBtn(bagPanel, "Close", 200, Color3.fromRGB(120, 90, 70))
bagClose.Position = UDim2.new(0.5, -100, 1, -36)
bagClose.Size = UDim2.new(0, 200, 0, 30)
bagClose.ZIndex = 22
bagClose.Activated:Connect(function() bagPanel.Visible = false end)

-- rarity color for mutations, so rare stacks pop (flex + trade value)
local RARITY = {
	bloomly = Color3.fromRGB(255, 120, 220), mythic = Color3.fromRGB(255, 150, 80),
	celestial = Color3.fromRGB(160, 200, 255), rainbow = Color3.fromRGB(150, 255, 170),
	frosted = Color3.fromRGB(150, 220, 255), golden = Color3.fromRGB(255, 220, 90),
	giant = Color3.fromRGB(200, 180, 140), wet = Color3.fromRGB(160, 200, 230),
}

local function refreshBag()
	for _, ch in bagScroll:GetChildren() do
		if ch:IsA("TextLabel") then ch:Destroy() end
	end
	local items = {}
	for _, it in lastInventory do
		table.insert(items, it)
	end
	table.sort(items, function(a, b) return (a.unitValue * a.qty) > (b.unitValue * b.qty) end)
	local total = 0
	if #items == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, -6, 0, 30)
		empty.BackgroundTransparency = 1
		empty.TextColor3 = Color3.fromRGB(180, 180, 170)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 14
		empty.Text = "Empty. Plant, fish, mine and forage to fill it up!"
		empty.ZIndex = 22
		empty.Parent = bagScroll
	end
	for _, it in items do
		local mut = it.mutationId
		local name = (mut ~= nil and mut ~= "" and mut ~= "normal") and (mut .. " " .. it.plantId) or it.plantId
		local row = Instance.new("TextLabel")
		row.Size = UDim2.new(1, -6, 0, 26)
		row.BackgroundColor3 = Color3.fromRGB(46, 40, 32)
		row.TextColor3 = RARITY[mut] or Color3.fromRGB(230, 225, 210)
		row.Font = Enum.Font.GothamMedium
		row.TextSize = 14
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.Text = string.format("  %s  %s  x%d    (%dc each)", it.emoji or "", name, it.qty, it.unitValue)
		row.ZIndex = 22
		row.Parent = bagScroll
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 5); c.Parent = row
		total += it.unitValue * it.qty
	end
	bagTitle.Text = string.format("🎒 Inventory  ·  worth %dc", total)
end

bagBtn.Activated:Connect(function()
	bagPanel.Visible = not bagPanel.Visible
	if bagPanel.Visible then refreshBag() end
end)

-- ================= CODEX / POKEDEX (block B) =================
local codexBtn = mkBtn(gui, "📖 Codex", 84, Color3.fromRGB(90, 120, 160))
codexBtn.Position = UDim2.new(1, -104, 0, 308)

local codexPanel = Instance.new("Frame")
codexPanel.Size = UDim2.new(0, 460, 0, 460)
codexPanel.Position = UDim2.new(0.5, -230, 0.5, -230)
codexPanel.BackgroundColor3 = Color3.fromRGB(26, 32, 44)
codexPanel.BorderSizePixel = 0
codexPanel.Visible = false
codexPanel.ZIndex = 20
codexPanel.Parent = gui
do local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = codexPanel end
local codexTitle = Instance.new("TextLabel")
codexTitle.Size = UDim2.new(1, 0, 0, 30)
codexTitle.BackgroundTransparency = 1
codexTitle.TextColor3 = Color3.fromRGB(235, 240, 255)
codexTitle.Font = Enum.Font.GothamBold
codexTitle.TextSize = 16
codexTitle.Text = "📖 Codex"
codexTitle.ZIndex = 21
codexTitle.Parent = codexPanel
local codexScroll = Instance.new("ScrollingFrame")
codexScroll.Size = UDim2.new(1, -16, 1, -76)
codexScroll.Position = UDim2.new(0, 8, 0, 34)
codexScroll.BackgroundTransparency = 1
codexScroll.BorderSizePixel = 0
codexScroll.ScrollBarThickness = 6
codexScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
codexScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
codexScroll.ZIndex = 21
codexScroll.Parent = codexPanel
local cgl = Instance.new("UIGridLayout"); cgl.CellSize = UDim2.new(0, 100, 0, 60); cgl.CellPadding = UDim2.new(0, 6, 0, 6); cgl.Parent = codexScroll
local codexClose = mkBtn(codexPanel, "Close", 200, Color3.fromRGB(90, 90, 120))
codexClose.Position = UDim2.new(0.5, -100, 1, -36)
codexClose.Size = UDim2.new(0, 200, 0, 30)
codexClose.ZIndex = 22
codexClose.Activated:Connect(function() codexPanel.Visible = false end)

local RARE_MUTS = { golden = true, frosted = true, rainbow = true, celestial = true, mythic = true, bloomly = true, giant = true, wet = true }

local function refreshCodex()
	for _, ch in codexScroll:GetChildren() do
		if ch:IsA("TextLabel") then ch:Destroy() end
	end
	local ok2, codex = pcall(function() return Remotes.GetCodex:InvokeServer() end)
	if not ok2 or type(codex) ~= "table" then codex = {} end
	local species: { [string]: boolean } = {}
	local rares = 0
	for key in codex do
		local sp = string.match(key, "^(.-)|")
		if sp then species[sp] = true end
		local mut = string.match(key, "|(.+)$")
		if mut and RARE_MUTS[mut] then rares += 1 end
	end
	local total = #Plants.list
	local found = 0
	for _, pl in Plants.list do
		local disc = species[pl.id] == true
		if disc then found += 1 end
		local cell = Instance.new("TextLabel")
		cell.BackgroundColor3 = disc and Color3.fromRGB(50, 80, 60) or Color3.fromRGB(40, 44, 54)
		cell.TextColor3 = disc and Color3.fromRGB(220, 245, 220) or Color3.fromRGB(120, 122, 130)
		cell.Font = Enum.Font.GothamMedium
		cell.TextSize = 13
		cell.Text = disc and (pl.emoji .. "\n" .. pl.id) or "❓\n???"
		cell.ZIndex = 22
		cell.Parent = codexScroll
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 6); c.Parent = cell
	end
	codexTitle.Text = string.format("📖 Codex  %d/%d crops (%d%%)  ·  %d rare finds", found, total, math.floor(found / math.max(1, total) * 100), rares)
end

codexBtn.Activated:Connect(function()
	codexPanel.Visible = not codexPanel.Visible
	if codexPanel.Visible then refreshCodex() end
end)

local ok, view = pcall(function()
	return Remotes.GetState:InvokeServer()
end)
if ok and view then
	render(view)
end

-- ================= SPRINT (hold Shift) =================
local UIS = game:GetService("UserInputService")
local SPRINT_MULT = 1.7
local sprinting = false
local baseWS = 16
local function humanoid(): Humanoid?
	local c = player.Character
	return c and c:FindFirstChildOfClass("Humanoid")
end
UIS.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		local hum = humanoid()
		if hum and not sprinting then
			sprinting = true
			baseWS = hum.WalkSpeed -- remember the current speed (vehicle/upgrade already applied by server)
			hum.WalkSpeed = baseWS * SPRINT_MULT
		end
	end
end)
UIS.InputEnded:Connect(function(input: InputObject)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		local hum = humanoid()
		if hum and sprinting then
			sprinting = false
			hum.WalkSpeed = baseWS
		end
	end
end)
player.CharacterAdded:Connect(function()
	sprinting = false -- reset on respawn
end)

-- ================= AMBIENT LIFE (polish) =================
-- All local to this client (cheap, no server load): soft clouds drifting across the sky, butterflies
-- that flit around wherever you are, and the occasional shooting star at night.
local Lighting = game:GetService("Lighting")

local function decoPart(size: Vector3, color: Color3, material: Enum.Material, transparency: number): Part
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = material
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Parent = workspace
	return p
end

local clouds = {}
for _ = 1, 8 do
	local c = decoPart(Vector3.new(math.random(120, 220), 8, math.random(80, 140)), Color3.fromRGB(245, 248, 255), Enum.Material.SmoothPlastic, 0.35)
	c.Position = Vector3.new(math.random(-3000, 3000), math.random(190, 270), math.random(-400, 4000))
	table.insert(clouds, { part = c, speed = math.random(5, 14) })
end

local flyers = {}
for _ = 1, 6 do
	local b = decoPart(Vector3.new(1.4, 0.4, 1.4), Color3.fromHSV(math.random(), 0.6, 1), Enum.Material.Neon, 0.1)
	table.insert(flyers, { part = b, phase = math.random() * 6.28, r = math.random(8, 22), h = math.random(3, 9), spd = 0.5 + math.random() })
end

RunService.Heartbeat:Connect(function(dt)
	for _, cl in clouds do
		local p = cl.part.Position
		local nx = p.X + cl.speed * dt
		if nx > 3300 then
			nx = -3300
		end
		cl.part.Position = Vector3.new(nx, p.Y, p.Z)
	end
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp then
		local base = (hrp :: BasePart).Position
		local t = os.clock()
		for _, f in flyers do
			local a = t * f.spd + f.phase
			f.part.Position = base + Vector3.new(math.cos(a) * f.r, f.h + math.sin(a * 2) * 2, math.sin(a) * f.r)
		end
	end
end)

-- shooting stars at night
task.spawn(function()
	while true do
		task.wait(math.random(5, 12))
		local h = Lighting.ClockTime
		if h < 6 or h > 19 then
			local char = player.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			local base = if hrp then (hrp :: BasePart).Position else Vector3.new(0, 0, 1000)
			local start = base + Vector3.new(math.random(-400, 400), 260, math.random(-200, 600))
			local dir = Vector3.new(math.random(-300, 300), -90, math.random(-200, 200))
			local star = decoPart(Vector3.new(3, 3, 3), Color3.fromRGB(255, 255, 220), Enum.Material.Neon, 0)
			star.Shape = Enum.PartType.Ball
			task.spawn(function()
				for i = 0, 30 do
					star.Position = start + dir * (i / 30)
					star.Transparency = i / 30
					task.wait(0.03)
				end
				star:Destroy()
			end)
		end
	end
end)
