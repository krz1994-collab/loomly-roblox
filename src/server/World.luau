--!strict
-- World: builds the shared 3D world at runtime with Instance.new (I can't place parts by hand in
-- Studio from the VPS, so the world is generated from code + the pure WorldLayout geometry).
-- Also renders each claimed section's crops so ALL players see each other's farms (server-side =
-- replicated = flexing works). Every interactable carries attributes the server reads on trigger.
--
-- This whole module is Studio-verified only. It is kept data-driven (positions come from the pure,
-- unit-tested WorldLayout) and logs instance counts so a blind build is easy to sanity-check.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local WorldLayout = require(ReplicatedStorage.Bloomly.data.WorldLayout)

local World = {}

-- section i -> { platform, ownerLabel, pads = { j -> { pad, prompt, cropLabel } } }
local sections: { [number]: any } = {}
local root: Folder? = nil

-- ---- colors ----
local C_GROUND = Color3.fromRGB(96, 148, 74)
local C_HUB = Color3.fromRGB(150, 140, 120)
local C_GRASS = Color3.fromRGB(110, 165, 88)
local C_EMPTY = Color3.fromRGB(120, 90, 60) -- tilled soil
local C_GROWING = Color3.fromRGB(90, 140, 70)
local C_READY = Color3.fromRGB(120, 215, 90)
local C_MARKET = Color3.fromRGB(210, 170, 60)

local function mkPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

-- A floating text label over a part (owner name, crop emoji + status).
local function mkBillboard(adornee: BasePart, size: UDim2, studsOffsetY: number): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Adornee = adornee
	bb.Size = size
	bb.StudsOffset = Vector3.new(0, studsOffsetY, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 90
	bb.Parent = adornee
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = bb
	return label
end

-- Build the whole static world once. Safe to call a second time (rebuilds cleanly).
function World.build()
	if root then
		root:Destroy()
	end
	-- remove the default Baseplate-template ground + spawn so our world is the only one
	for _, v in workspace:GetChildren() do
		if v:IsA("BasePart") and (v.Name == "Baseplate" or v:IsA("SpawnLocation")) then
			v:Destroy()
		end
	end
	root = Instance.new("Folder")
	root.Name = "BloomlyWorld"
	root.Parent = workspace
	sections = {}

	-- ground big enough to cover the hub + the whole section grid
	local gridDepth = math.ceil(Config.PLOT_SECTIONS / WorldLayout.SECTION_COLS) * WorldLayout.SECTION_SPACING
	mkPart("Ground", Vector3.new(700, 2, gridDepth + 240), CFrame.new(0, -1, (WorldLayout.GRID_START_Z + gridDepth) / 2), C_GROUND, root)

	-- hub platform (a simple flat square) + a spawn point (avatars appear in the hub, not on a plot)
	mkPart("Hub", Vector3.new(WorldLayout.HUB_RADIUS * 2, 1, WorldLayout.HUB_RADIUS * 2), CFrame.new(0, 0.5, 0), C_HUB, root)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.CFrame = CFrame.new(0, 1.5, 0)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C_HUB
	spawn.Parent = root

	-- Market NPC (a coloured pillar) with a "Sell all" prompt in the hub
	local market = mkPart("MarketNPC", Vector3.new(4, 8, 4), CFrame.new(0, 4, -WorldLayout.HUB_RADIUS + 6), C_MARKET, root)
	local sellPrompt = Instance.new("ProximityPrompt")
	sellPrompt.ActionText = "Sell all"
	sellPrompt.ObjectText = "Market"
	sellPrompt.HoldDuration = 0
	sellPrompt.MaxActivationDistance = 12
	sellPrompt:SetAttribute("kind", "sell")
	sellPrompt.Parent = market
	local mLabel = mkBillboard(market, UDim2.fromScale(6, 1.4), 6)
	mLabel.Text = "🧺 Market — sell here"

	-- the N farm sections
	local padY = 1.0
	for i = 1, Config.PLOT_SECTIONS do
		local c = WorldLayout.sectionCenter(i)
		local secModel = Instance.new("Model")
		secModel.Name = "Section" .. i
		secModel.Parent = root

		local platform = mkPart("Grass", Vector3.new(WorldLayout.SECTION_SIZE, 1, WorldLayout.SECTION_SIZE), CFrame.new(c.x, 0.5, c.z), C_GRASS, secModel)
		secModel.PrimaryPart = platform
		local ownerLabel = mkBillboard(platform, UDim2.fromScale(8, 1.6), WorldLayout.SECTION_SIZE / 2 + 4)
		ownerLabel.Text = "· free ·"
		ownerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)

		local pads: { [number]: any } = {}
		for j = 1, Config.PLOT_COUNT do
			local o = WorldLayout.plotPadOffset(j, Config.PLOT_COUNT)
			local pad = mkPart("Pad" .. j, Vector3.new(WorldLayout.PAD_SIZE, 1, WorldLayout.PAD_SIZE), CFrame.new(c.x + o.x, padY, c.z + o.z), C_EMPTY, secModel)
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Plant"
			prompt.ObjectText = ""
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 10
			prompt.Enabled = false -- enabled only for the section's owner while claimed (set in render)
			prompt:SetAttribute("kind", "plot")
			prompt:SetAttribute("section", i)
			prompt:SetAttribute("plotIndex", j)
			prompt.Parent = pad
			local cropLabel = mkBillboard(pad, UDim2.fromScale(3, 2), 3)
			pads[j] = { pad = pad, prompt = prompt, cropLabel = cropLabel }
		end

		sections[i] = { platform = platform, ownerLabel = ownerLabel, pads = pads }
	end

	local instanceCount = #root:GetDescendants()
	print("[Bloomly] world built: " .. Config.PLOT_SECTIONS .. " sections, " .. (Config.PLOT_SECTIONS * Config.PLOT_COUNT) .. " pads, " .. instanceCount .. " instances")
end

-- Render a player's garden onto their claimed section (called by the server so everyone sees it).
-- `view` is Farm.buildView output (view.plots[j] = {seedId, emoji, ready, secondsLeft}).
function World.renderSection(section: number, ownerName: string, view: any)
	local s = sections[section]
	if not s then
		return
	end
	s.ownerLabel.Text = "🌱 " .. ownerName
	s.ownerLabel.TextColor3 = Color3.fromRGB(180, 240, 140)
	for j = 1, Config.PLOT_COUNT do
		local pad = s.pads[j]
		local p = view.plots[j]
		if not p or p.seedId == nil then
			pad.pad.Color = C_EMPTY
			pad.cropLabel.Text = ""
			pad.prompt.ActionText = "Plant"
			pad.prompt.Enabled = true
		elseif p.ready then
			pad.pad.Color = C_READY
			pad.cropLabel.Text = p.emoji .. "\n✅ READY"
			pad.prompt.ActionText = "Harvest"
			pad.prompt.Enabled = true
		else
			pad.pad.Color = C_GROWING
			pad.cropLabel.Text = p.emoji .. "\n🌱 " .. p.secondsLeft .. "s"
			pad.prompt.Enabled = false -- nothing to do while growing
		end
	end
end

-- Reset a section to unclaimed when its owner leaves.
function World.clearSection(section: number)
	local s = sections[section]
	if not s then
		return
	end
	s.ownerLabel.Text = "· free ·"
	s.ownerLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	for j = 1, Config.PLOT_COUNT do
		local pad = s.pads[j]
		pad.pad.Color = C_EMPTY
		pad.cropLabel.Text = ""
		pad.prompt.Enabled = false
	end
end

return World
