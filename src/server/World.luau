--!strict
-- World: builds the shared 3D world at runtime (Instance.new) from the pure, unit-tested
-- WorldLayout geometry. 100 personal 300x300 plots spread in a grid (grey ground between them =
-- roads/paths), a central plaza with shops, lampposts, and scattered Market NPCs. Streaming is on
-- because the map is ~3600 studs wide. Studio-verified only; kept data-driven + logs instance counts.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Bloomly.data.Config)
local WorldLayout = require(ReplicatedStorage.Bloomly.data.WorldLayout)
local Catalog = require(ReplicatedStorage.Bloomly.data.Catalog)
local Npcs = require(ReplicatedStorage.Bloomly.data.Npcs)
local Upgrades = require(ReplicatedStorage.Bloomly.data.Upgrades)

local World = {}

-- section i -> { ownerLabel, pads = { j -> { pad, prompt, cropLabel } } }
local sections: { [number]: any } = {}
local root: Folder? = nil

-- ---- colors ----
local C_ROAD = Color3.fromRGB(88, 92, 96) -- ground = roads/paths (grey); plots sit on top in green
local C_GRASS = Color3.fromRGB(104, 168, 84)
local C_FENCE = Color3.fromRGB(190, 175, 150)
local C_PLAZA = Color3.fromRGB(150, 140, 120)
local C_EMPTY = Color3.fromRGB(120, 90, 60)
local C_GROWING = Color3.fromRGB(92, 148, 74)
local C_READY = Color3.fromRGB(120, 215, 90)
local C_MARKET = Color3.fromRGB(214, 172, 60)
local C_LAMP = Color3.fromRGB(255, 236, 150)
local ZONE_COLOR: { [string]: Color3 } = {
	house = Color3.fromRGB(180, 120, 90),
	pen = Color3.fromRGB(150, 130, 100),
	utility = Color3.fromRGB(120, 120, 130),
	orchard = Color3.fromRGB(110, 150, 90),
}
local ZONE_TEXT: { [string]: string } = {
	house = "🏠 House (soon)",
	pen = "🐄 Pen (soon)",
	utility = "🏚️ Sheds (soon)",
	orchard = "🌳 Orchard (soon)",
}

local function mkPart(name: string, size: Vector3, cf: CFrame, color: Color3, parent: Instance, material: Enum.Material?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Parent = parent
	return p
end

local function mkBillboard(adornee: BasePart, w: number, h: number, offsetY: number): TextLabel
	local bb = Instance.new("BillboardGui")
	bb.Adornee = adornee
	bb.Size = UDim2.fromScale(w, h)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.MaxDistance = 220
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

local function mkPrompt(parent: BasePart, action: string, kind: string): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("kind", kind)
	prompt.Parent = parent
	return prompt
end

local function mkLamppost(x: number, z: number, parent: Instance)
	mkPart("LampPost", Vector3.new(1.2, 22, 1.2), CFrame.new(x, 11, z), Color3.fromRGB(60, 55, 50), parent)
	local head = mkPart("LampHead", Vector3.new(3, 3, 3), CFrame.new(x, 22.5, z), C_LAMP, parent, Enum.Material.Neon)
	head.Shape = Enum.PartType.Ball
end

local function mkMarket(x: number, z: number, parent: Instance, label: string)
	local m = mkPart("MarketNPC", Vector3.new(6, 10, 6), CFrame.new(x, 5, z), C_MARKET, parent)
	mkPrompt(m, "Sell all", "sell")
	mkBillboard(m, 8, 1.6, 7).Text = label
end

local ISLAND_NAMES = {
	"Sunny Beach", "Whispering Woods", "Frostpeak", "Volcano Isle", "Golden Dunes",
	"Crystal Cove", "Mushroom Grove", "Windy Cliffs", "Coral Reef", "Misty Highlands",
}
local ISLAND_COLOR = {
	Color3.fromRGB(232, 214, 150), Color3.fromRGB(70, 130, 70), Color3.fromRGB(225, 235, 245),
	Color3.fromRGB(90, 60, 55), Color3.fromRGB(224, 196, 120), Color3.fromRGB(150, 130, 200),
	Color3.fromRGB(120, 160, 90), Color3.fromRGB(140, 150, 130), Color3.fromRGB(120, 190, 180),
	Color3.fromRGB(150, 160, 170),
}

-- Build one organic (non-circular) island from overlapping rotated flat boxes.
local function buildIsland(i: number, center: { x: number, z: number }, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Island" .. i
	model.Parent = parent
	local color = ISLAND_COLOR[i] or C_GRASS
	local S = WorldLayout.ISLAND_SIZE
	mkPart("LandCore", Vector3.new(S * 0.55, 6, S * 0.55), CFrame.new(center.x, 1, center.z), color, model, Enum.Material.Grass)
	for k = 0, 11 do
		local ang = k / 12 * math.pi * 2
		local bx = center.x + math.cos(ang) * S * 0.26
		local bz = center.z + math.sin(ang) * S * 0.26
		local w = math.abs(S * (0.3 + 0.16 * math.sin(k * 1.7 + i)))
		local d = math.abs(S * (0.3 + 0.16 * math.cos(k * 1.9 + i)))
		mkPart("Land", Vector3.new(w, 6, d), CFrame.new(bx, 1, bz) * CFrame.Angles(0, ang, 0), color, model, Enum.Material.Grass)
	end
	local sign = mkPart("IslandSign", Vector3.new(3, 14, 3), CFrame.new(center.x, 7, center.z), Color3.fromRGB(120, 95, 70), model)
	mkBillboard(sign, 14, 2.4, 9).Text = "🏝️ " .. (ISLAND_NAMES[i] or ("Island " .. i))
	local back = mkPrompt(sign, "Sail back to plaza", "sailback")
	back.MaxActivationDistance = 20
end

-- Build the whole static world once.
function World.build()
	pcall(function()
		workspace.StreamingEnabled = true -- map is ~3600 studs; clients stream only nearby content
		workspace.StreamingTargetRadius = 800
	end)

	if root then
		root:Destroy()
	end
	for _, v in workspace:GetChildren() do
		if v:IsA("BasePart") and (v.Name == "Baseplate" or v:IsA("SpawnLocation")) then
			v:Destroy()
		end
	end
	root = Instance.new("Folder")
	root.Name = "BloomlyWorld"
	root.Parent = workspace
	sections = {}

	local rootF = root :: Folder
	local cols = WorldLayout.SECTION_COLS
	local rows = math.ceil(Config.PLOT_SECTIONS / cols)
	local gridW = cols * WorldLayout.SECTION_SPACING
	local gridD = rows * WorldLayout.SECTION_SPACING

	-- ground = grey road/path base under everything (green plots sit on top -> gaps look like streets)
	mkPart("Ground", Vector3.new(gridW + 600, 2, gridD + 1000), CFrame.new(0, -1, (WorldLayout.GRID_START_Z + gridD) / 2 - 200), C_ROAD, rootF)

	-- central plaza (spawn + main shops)
	mkPart("Plaza", Vector3.new(WorldLayout.PLAZA_RADIUS * 2, 1, WorldLayout.PLAZA_RADIUS * 2), CFrame.new(0, 0.5, WorldLayout.PLAZA_Z), C_PLAZA, rootF)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.CFrame = CFrame.new(0, 1.5, WorldLayout.PLAZA_Z)
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.Color = C_PLAZA
	spawn.Parent = rootF
	mkMarket(-30, WorldLayout.PLAZA_Z, rootF, "🧺 Market — sell")
	do -- placeholder shop signs (systems come in later layers)
		local seeds = mkPart("SeedShop", Vector3.new(6, 10, 6), CFrame.new(30, 5, WorldLayout.PLAZA_Z), Color3.fromRGB(90, 170, 90), rootF)
		mkBillboard(seeds, 8, 1.6, 7).Text = "🌱 Seeds (use bar below)"
		local tools = mkPart("ToolShop", Vector3.new(6, 10, 6), CFrame.new(0, 5, WorldLayout.PLAZA_Z + 40), Color3.fromRGB(120, 130, 160), rootF)
		mkBillboard(tools, 8, 1.6, 7).Text = "🛠️ Tools (soon)"
	end
	do -- garage: buy a vehicle to move faster across the big map
		for idx, veh in Catalog.Vehicles do
			local sx = (idx - (#Catalog.Vehicles + 1) / 2) * 18
			local stand = mkPart("Vehicle_" .. veh.id, Vector3.new(9, 4, 5), CFrame.new(sx, 2.5, WorldLayout.PLAZA_Z - 48), Color3.fromRGB(70, 90, 140), rootF)
			local pr = mkPrompt(stand, "Buy " .. veh.name .. " (" .. veh.cost .. "c)", "buyvehicle")
			pr:SetAttribute("vehicleId", veh.id)
			mkBillboard(stand, 6, 1.6, 4).Text = veh.emoji .. " " .. veh.name
		end
	end
	do -- upgrade kiosk: a stand per upgrade track
		for idx, track in Upgrades.list do
			local sx = (idx - (#Upgrades.list + 1) / 2) * 16
			local stand = mkPart("Upgrade_" .. track.id, Vector3.new(7, 6, 5), CFrame.new(sx, 3.5, WorldLayout.PLAZA_Z + 40), Color3.fromRGB(90, 140, 200), rootF)
			local pr = mkPrompt(stand, "Upgrade " .. track.name, "upgrade")
			pr:SetAttribute("track", track.id)
			mkBillboard(stand, 7, 1.6, 5).Text = track.emoji .. " " .. track.name
		end
	end
	do -- retention NPCs
		local rebirth = mkPart("RebirthShrine", Vector3.new(6, 10, 6), CFrame.new(-62, 5, WorldLayout.PLAZA_Z), Color3.fromRGB(180, 120, 205), rootF, Enum.Material.Neon)
		mkPrompt(rebirth, "Rebirth (+10% coins forever)", "rebirth")
		mkBillboard(rebirth, 9, 1.6, 7).Text = "🔮 Rebirth Shrine"
		local daily = mkPart("DailyGift", Vector3.new(5, 8, 5), CFrame.new(62, 4, WorldLayout.PLAZA_Z), Color3.fromRGB(220, 90, 90), rootF)
		mkPrompt(daily, "Claim daily gift", "dailygift")
		mkBillboard(daily, 8, 1.6, 6).Text = "🎁 Daily Gift"
	end
	mkLamppost(-WorldLayout.PLAZA_RADIUS, WorldLayout.PLAZA_Z, rootF)
	mkLamppost(WorldLayout.PLAZA_RADIUS, WorldLayout.PLAZA_Z, rootF)

	-- the 100 personal plots
	local half = WorldLayout.SECTION_SIZE / 2
	local padY = 1.1
	for i = 1, Config.PLOT_SECTIONS do
		local c = WorldLayout.sectionCenter(i)
		local plot = Instance.new("Model")
		plot.Name = "Plot" .. i
		plot.Parent = rootF

		-- raised green platform (=> the grey road base shows in the gaps)
		local platform = mkPart("Grass", Vector3.new(WorldLayout.SECTION_SIZE, 1, WorldLayout.SECTION_SIZE), CFrame.new(c.x, 0.5, c.z), C_GRASS, plot, Enum.Material.Grass)
		plot.PrimaryPart = platform

		-- low fence around the plot, with a GATEWAY in the front so you can walk in/out
		local fh, ft = 4, 0.6
		local gap = 44 -- width of the front gateway
		local segW = (WorldLayout.SECTION_SIZE - gap) / 2
		local segX = (gap + segW) / 2 -- centre offset of each front fence segment
		mkPart("FenceN1", Vector3.new(segW, fh, ft), CFrame.new(c.x - segX, fh / 2 + 1, c.z - half), C_FENCE, plot)
		mkPart("FenceN2", Vector3.new(segW, fh, ft), CFrame.new(c.x + segX, fh / 2 + 1, c.z - half), C_FENCE, plot)
		mkPart("GateL", Vector3.new(2, fh + 3, 2), CFrame.new(c.x - gap / 2, (fh + 3) / 2 + 1, c.z - half), Color3.fromRGB(150, 110, 70), plot)
		mkPart("GateR", Vector3.new(2, fh + 3, 2), CFrame.new(c.x + gap / 2, (fh + 3) / 2 + 1, c.z - half), Color3.fromRGB(150, 110, 70), plot)
		mkPart("FenceS", Vector3.new(WorldLayout.SECTION_SIZE, fh, ft), CFrame.new(c.x, fh / 2 + 1, c.z + half), C_FENCE, plot)
		mkPart("FenceW", Vector3.new(ft, fh, WorldLayout.SECTION_SIZE), CFrame.new(c.x - half, fh / 2 + 1, c.z), C_FENCE, plot)
		mkPart("FenceE", Vector3.new(ft, fh, WorldLayout.SECTION_SIZE), CFrame.new(c.x + half, fh / 2 + 1, c.z), C_FENCE, plot)

		-- owner sign + name at the front (entrance) edge
		local post = mkPart("OwnerPost", Vector3.new(2, 10, 2), CFrame.new(c.x, 5, c.z - half - 4), Color3.fromRGB(120, 95, 70), plot)
		local ownerLabel = mkBillboard(post, 12, 2.2, 7)
		ownerLabel.Text = "· free plot ·"
		ownerLabel.TextColor3 = Color3.fromRGB(225, 225, 225)

		-- reserved expansion zones (house / pen / utility / orchard) as labelled markers
		for _, name in WorldLayout.zoneNames() do
			local o = WorldLayout.zoneOffset(name)
			if o then
				local zp = mkPart("Zone_" .. name, Vector3.new(70, 1.2, 70), CFrame.new(c.x + o.x, 1.1, c.z + o.z), ZONE_COLOR[name] or C_GRASS, plot)
				mkBillboard(zp, 10, 1.8, 6).Text = ZONE_TEXT[name] or name
			end
		end

		-- 12 crop pads with Plant/Harvest prompts (enabled only for the owner while claimed)
		local pads: { [number]: any } = {}
		for j = 1, Config.PLOT_COUNT do
			local o = WorldLayout.plotPadOffset(j, Config.PLOT_COUNT)
			local pad = mkPart("Pad" .. j, Vector3.new(WorldLayout.PAD_SIZE, 1, WorldLayout.PAD_SIZE), CFrame.new(c.x + o.x, padY, c.z + o.z), C_EMPTY, plot)
			local prompt = mkPrompt(pad, "Plant", "plot")
			prompt.Enabled = false
			prompt:SetAttribute("section", i)
			prompt:SetAttribute("plotIndex", j)
			pads[j] = { pad = pad, prompt = prompt, cropLabel = mkBillboard(pad, 4, 2.4, 4) }
		end

		-- a lamppost at the plot's front-left corner (lines the streets)
		mkLamppost(c.x - half - 6, c.z - half - 6, plot)

		-- a scattered Market every 5th plot so selling is handy across the big map
		if i % 5 == 0 then
			mkMarket(c.x + half + 20, c.z, rootF, "🧺 Market")
		end

		sections[i] = { ownerLabel = ownerLabel, pads = pads }
	end

	-- ocean + 10 islands far out
	mkPart("Ocean", Vector3.new(WorldLayout.ISLAND_RING * 2.6, 2, WorldLayout.ISLAND_RING * 2.6), CFrame.new(0, -4, WorldLayout.MAP_CENTER_Z), Color3.fromRGB(58, 120, 190), rootF, Enum.Material.Water)
	for i = 1, WorldLayout.ISLAND_COUNT do
		buildIsland(i, WorldLayout.islandCenter(i), rootF)
	end

	-- NPCs: plaza NPCs ring the plaza; island NPCs stand on their island
	do
		local plazaNpcs = {}
		for _, npc in Npcs.list do
			if npc.island then
				local c = WorldLayout.islandCenter(npc.island)
				local body = mkPart("Npc_" .. npc.id, Vector3.new(3, 6, 3), CFrame.new(c.x, 5, c.z + 30), Color3.fromRGB(205, 180, 150), rootF)
				local pr = mkPrompt(body, "Talk", "talk")
				pr:SetAttribute("npc", npc.id)
				mkBillboard(body, 9, 1.8, 5).Text = npc.emoji .. " " .. npc.name
			else
				table.insert(plazaNpcs, npc)
			end
		end
		for idx, npc in plazaNpcs do
			local a = (idx / #plazaNpcs) * math.pi * 2
			local r = WorldLayout.PLAZA_RADIUS + 14
			local x, z = math.cos(a) * r, WorldLayout.PLAZA_Z + math.sin(a) * r
			local body = mkPart("Npc_" .. npc.id, Vector3.new(3, 6, 3), CFrame.new(x, 3, z), Color3.fromRGB(205, 180, 150), rootF)
			local pr = mkPrompt(body, "Talk", "talk")
			pr:SetAttribute("npc", npc.id)
			mkBillboard(body, 9, 1.8, 5).Text = npc.emoji .. " " .. npc.name
		end
	end

	-- harbor in the plaza: a dock + a boat per island (sail = teleport for now)
	do
		local dockZ = WorldLayout.PLAZA_Z - 70
		mkPart("Dock", Vector3.new(WorldLayout.ISLAND_COUNT * 13, 1, 40), CFrame.new(0, 0.6, dockZ), Color3.fromRGB(150, 120, 90), rootF, Enum.Material.WoodPlanks)
		for i = 1, WorldLayout.ISLAND_COUNT do
			local sx = (i - (WorldLayout.ISLAND_COUNT + 1) / 2) * 13
			local boat = mkPart("Boat" .. i, Vector3.new(9, 3, 5), CFrame.new(sx, 2, dockZ - 24), Color3.fromRGB(140, 90, 60), rootF, Enum.Material.WoodPlanks)
			local pr = mkPrompt(boat, "Sail to " .. (ISLAND_NAMES[i] or ("Island " .. i)), "sail")
			pr:SetAttribute("islandIndex", i)
		end
		mkBillboard(mkPart("HarborSign", Vector3.new(3, 12, 3), CFrame.new(0, 6, dockZ + 16), Color3.fromRGB(120, 95, 70), rootF), 14, 2, 8).Text = "⚓ Harbor — sail to the islands"
	end

	print(string.format("[Bloomly] world built: %d plots (300x300), %d pads, %d islands, %d instances", Config.PLOT_SECTIONS, Config.PLOT_SECTIONS * Config.PLOT_COUNT, WorldLayout.ISLAND_COUNT, #rootF:GetDescendants()))
end

-- Render a player's garden onto their plot (server-side => everyone sees it).
function World.renderSection(section: number, ownerName: string, view: any)
	local s = sections[section]
	if not s then
		return
	end
	s.ownerLabel.Text = "🌱 " .. ownerName .. "'s farm"
	s.ownerLabel.TextColor3 = Color3.fromRGB(180, 240, 140)
	for j = 1, Config.PLOT_COUNT do
		local pad = s.pads[j]
		local p = view.plots[j]
		if p and p.locked then
			pad.pad.Color = Color3.fromRGB(70, 70, 75)
			pad.cropLabel.Text = "🔒"
			pad.prompt.Enabled = false
		elseif not p or p.seedId == nil then
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
			pad.prompt.Enabled = false
		end
	end
end

-- Reset a plot to unclaimed when its owner leaves.
function World.clearSection(section: number)
	local s = sections[section]
	if not s then
		return
	end
	s.ownerLabel.Text = "· free plot ·"
	s.ownerLabel.TextColor3 = Color3.fromRGB(225, 225, 225)
	for j = 1, Config.PLOT_COUNT do
		local pad = s.pads[j]
		pad.pad.Color = C_EMPTY
		pad.cropLabel.Text = ""
		pad.prompt.Enabled = false
	end
end

return World
