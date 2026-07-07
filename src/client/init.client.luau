--!strict
-- BloomlyClient: the HUD for the 3D world. It does NOT block the screen or drive gameplay logic --
-- you walk your avatar to your farm and press the ProximityPrompt (E) on a pad to plant/harvest, and
-- on the Market to sell. All of that is server-authoritative. This client only:
--   1. renders a small HUD (coins / level / xp / codex / inventory) from StateUpdate, and
--   2. lets you PICK which seed the next Plant prompt uses (fires SelectSeed).
-- It holds no authoritative state.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Bloomly.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "BloomlyHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

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
hint.Text = "Find your 🌱 farm below · press E on a plot to plant / harvest · sell at 🧺 Market"
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

-- ---- bottom seed bar ----
local seedBar = Instance.new("Frame")
seedBar.Size = UDim2.new(0, 640, 0, 60)
seedBar.Position = UDim2.new(0.5, -320, 1, -74)
seedBar.BackgroundTransparency = 1
seedBar.Parent = gui
local barLayout = Instance.new("UIListLayout")
barLayout.FillDirection = Enum.FillDirection.Horizontal
barLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
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

local function render(view: any)
	stats.Text = string.format("🪙 %d    Lv %d (%d xp)    📖 %d    🌾 %d", view.coins, view.level, view.xp, view.codexCount, view.harvests)

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

local ok, view = pcall(function()
	return Remotes.GetState:InvokeServer()
end)
if ok and view then
	render(view)
end
