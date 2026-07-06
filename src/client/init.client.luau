--!strict
-- BloomlyClient: the whole client for the slice. It does exactly two things:
--   1. RENDER the authoritative state the server sends (StateUpdate / GetState).
--   2. SEND intents when the player taps (Plant / Harvest / SellAll).
--
-- It holds NO authoritative state. It never decides a mutation, a price, a coin balance, or
-- whether a crop is ready -- it only shows what the server said and asks the server to act.
-- If you deleted this file and sent the same remotes from the command bar, the game would behave
-- identically: the client is a window, not a source of truth.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Bloomly.Remotes)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ---- static UI shell ------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "BloomlyUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = playerGui

local root = Instance.new("Frame")
root.Size = UDim2.fromScale(1, 1)
root.BackgroundColor3 = Color3.fromRGB(24, 30, 22)
root.BorderSizePixel = 0
root.Parent = gui

local pad = Instance.new("UIPadding")
pad.PaddingTop = UDim.new(0, 16)
pad.PaddingLeft = UDim.new(0, 16)
pad.PaddingRight = UDim.new(0, 16)
pad.Parent = root

local col = Instance.new("UIListLayout")
col.FillDirection = Enum.FillDirection.Vertical
col.Padding = UDim.new(0, 10)
col.SortOrder = Enum.SortOrder.LayoutOrder
col.Parent = root

local function label(text: string, order: number, height: number, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, height)
	l.BackgroundTransparency = 1
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextColor3 = Color3.fromRGB(235, 240, 225)
	l.Font = Enum.Font.GothamMedium
	l.TextSize = size
	l.Text = text
	l.LayoutOrder = order
	l.Parent = root
	return l
end

local function rowFrame(order: number, height: number): Frame
	local f = Instance.new("Frame")
	f.Size = UDim2.new(1, 0, 0, height)
	f.BackgroundTransparency = 1
	f.LayoutOrder = order
	f.Parent = root
	local h = Instance.new("UIListLayout")
	h.FillDirection = Enum.FillDirection.Horizontal
	h.Padding = UDim.new(0, 8)
	h.SortOrder = Enum.SortOrder.LayoutOrder
	h.Parent = f
	return f
end

local header = label("Bloomly - connecting...", 1, 26, 22)
label("Seeds (tap to select, then tap an empty plot):", 2, 18, 14)
local seedsRow = rowFrame(3, 64)
label("Plots (tap empty = plant selected seed, tap READY = harvest):", 4, 18, 14)
local plotsRow = rowFrame(5, 72)
local sellButton = Instance.new("TextButton")
sellButton.Size = UDim2.new(0, 220, 0, 40)
sellButton.LayoutOrder = 6
sellButton.BackgroundColor3 = Color3.fromRGB(210, 170, 60)
sellButton.TextColor3 = Color3.fromRGB(30, 25, 10)
sellButton.Font = Enum.Font.GothamBold
sellButton.TextSize = 16
sellButton.Text = "Sell all -> coins"
sellButton.Parent = root
local invTitle = label("Inventory:", 7, 18, 14)
local invBox = label("(empty)", 8, 120, 15)
invBox.TextYAlignment = Enum.TextYAlignment.Top

-- ---- dynamic state --------------------------------------------------------------
local selectedSeedId: string? = nil
local seedButtons: { [string]: TextButton } = {}
local plotButtons: { [number]: TextButton } = {}
local latestView: any = nil
local builtSeeds = false
local builtPlots = false

local COL_NORMAL = Color3.fromRGB(70, 110, 60)
local COL_SELECTED = Color3.fromRGB(120, 190, 90)
local COL_LOCKED = Color3.fromRGB(70, 70, 70)
local COL_POOR = Color3.fromRGB(95, 72, 60)
local COL_EMPTY = Color3.fromRGB(60, 70, 55)
local COL_GROWING = Color3.fromRGB(90, 100, 70)
local COL_READY = Color3.fromRGB(120, 190, 90)

-- Build the seed buttons once (the crop list is fixed; only unlocked-ness changes).
-- `view` is the dynamic snapshot from the server; typed `any` because it crosses the remote boundary.
local function buildSeeds(view: any)
	for _, s in view.seeds do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 96, 1, 0)
		btn.BackgroundColor3 = COL_NORMAL
		btn.TextColor3 = Color3.fromRGB(245, 245, 240)
		btn.Font = Enum.Font.GothamMedium
		btn.TextSize = 13
		btn.Text = s.emoji .. " " .. s.id
		btn.Parent = seedsRow
		seedButtons[s.id] = btn
		-- INTENT: selecting a seed is purely local UI; nothing is sent until you tap a plot.
		btn.Activated:Connect(function()
			local latest = latestView
			if latest then
				for _, ss in latest.seeds do
					if ss.id == s.id and not ss.unlocked then
						return -- can't select a locked seed (server would reject it anyway)
					end
				end
			end
			selectedSeedId = s.id
		end)
	end
end

-- Build the plot buttons once (count comes from the first view).
local function buildPlots(view: any)
	for _, p in view.plots do
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 110, 1, 0)
		btn.BackgroundColor3 = COL_EMPTY
		btn.TextColor3 = Color3.fromRGB(245, 245, 240)
		btn.Font = Enum.Font.GothamMedium
		btn.TextSize = 13
		btn.Text = "Plot " .. p.index
		btn.Parent = plotsRow
		plotButtons[p.index] = btn
		local index = p.index
		btn.Activated:Connect(function()
			local latest = latestView
			if not latest then
				return
			end
			local plot = latest.plots[index]
			if plot and plot.ready then
				-- INTENT: ask the server to harvest. The server re-checks readiness and rolls the mutation.
				Remotes.Harvest:FireServer(index)
			elseif plot and not plot.seedId and selectedSeedId then
				-- INTENT: ask the server to plant. The server re-checks the plot is empty and the seed is unlocked.
				Remotes.Plant:FireServer(selectedSeedId, index)
			end
			-- If the plot is mid-grow, or nothing is selected, we send nothing.
		end)
	end
end

local function render(view: any)
	latestView = view
	header.Text = string.format(
		"Bloomly   coins: %d   Lv %d (%d xp)   codex: %d   harvests: %d",
		view.coins, view.level, view.xp, view.codexCount, view.harvests
	)

	if not builtSeeds then
		buildSeeds(view)
		builtSeeds = true
	end
	if not builtPlots then
		buildPlots(view)
		builtPlots = true
	end

	for _, s in view.seeds do
		local btn = seedButtons[s.id]
		if btn then
			if not s.unlocked then
				btn.BackgroundColor3 = COL_LOCKED
				btn.Text = s.emoji .. " " .. s.id .. "\nLOCKED"
			elseif not s.affordable then
				btn.BackgroundColor3 = COL_POOR -- unlocked but you can't afford the seed cost
				btn.Text = s.emoji .. " " .. s.id .. "\nneed " .. s.cost .. "c"
			else
				btn.BackgroundColor3 = if selectedSeedId == s.id then COL_SELECTED else COL_NORMAL
				btn.Text = s.emoji .. " " .. s.id .. "\nbuy " .. s.cost .. "c · " .. s.growSeconds .. "s"
			end
		end
	end

	for _, p in view.plots do
		local btn = plotButtons[p.index]
		if btn then
			if not p.seedId then
				btn.BackgroundColor3 = COL_EMPTY
				btn.Text = "Plot " .. p.index .. "\n(empty)"
			elseif p.ready then
				btn.BackgroundColor3 = COL_READY
				btn.Text = p.emoji .. "  READY\ntap to harvest"
			else
				btn.BackgroundColor3 = COL_GROWING
				btn.Text = p.emoji .. "  growing\n" .. p.secondsLeft .. "s left"
			end
		end
	end

	if #view.inventory == 0 then
		invTitle.Text = "Inventory:"
		invBox.Text = "(empty - harvest something)"
	else
		local total = 0
		local lines = {}
		for _, item in view.inventory do
			local mut = if item.mutationId == "normal" then "" else " [" .. item.mutationId .. "]"
			table.insert(lines, string.format("%s %s%s  x%d   @%dc = %dc",
				item.emoji, item.plantId, mut, item.qty, item.unitValue, item.unitValue * item.qty))
			total += item.unitValue * item.qty
		end
		invTitle.Text = "Inventory (sell value: " .. total .. "c):"
		invBox.Text = table.concat(lines, "\n")
	end
end

-- INTENT: sell everything. No args -- the server prices your own inventory at the NPC floor.
sellButton.Activated:Connect(function()
	Remotes.SellAll:FireServer()
end)

-- Keep rendering whatever truth the server pushes (join push + 1s cadence).
Remotes.StateUpdate.OnClientEvent:Connect(render)

-- Initial fetch so we don't wait up to a second for the first push. Wrapped because the server
-- handler is assigned at server startup; the StateUpdate cadence covers us if this ever races.
local ok, view = pcall(function()
	return Remotes.GetState:InvokeServer()
end)
if ok and view then
	render(view)
end
