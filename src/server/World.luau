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
local TreasureRules = require(ReplicatedStorage.Bloomly.TreasureRules)

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

-- A little sparkle emitter for juice (ready crops, treasure chests). Uses the engine's default
-- particle texture so no external asset is needed.
local function mkSparkle(parent: BasePart, color: Color3, rate: number): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(color)
	pe.Size = NumberSequence.new(0.7)
	pe.Transparency = NumberSequence.new(0.2)
	pe.Lifetime = NumberRange.new(0.5, 1.0)
	pe.Rate = rate
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 0.7
	pe.Rotation = NumberRange.new(0, 360)
	pe.Parent = parent
	return pe
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

-- A gathering node (fishing pond / mine rock / forage bush / bug patch).
local function mkGather(name: string, x: number, z: number, size: Vector3, color: Color3, mat: Enum.Material, action: string, kind: string, list: string, label: string, parent: Instance)
	local node = mkPart(name, size, CFrame.new(x, size.Y / 2, z), color, parent, mat)
	local pr = mkPrompt(node, action, kind)
	pr:SetAttribute("list", list)
	pr.HoldDuration = 0.4
	mkBillboard(node, 6, 1.4, size.Y + 2).Text = label
end

local ISLAND_NAMES = {
	"Sunny Beach", "Whispering Woods", "Frostpeak", "Volcano Isle", "Golden Dunes",
	"Crystal Cove", "Mushroom Grove", "Windy Cliffs", "Coral Reef", "Misty Highlands",
	"Enchanted Forest",
}
local ISLAND_COLOR = {
	Color3.fromRGB(232, 214, 150), Color3.fromRGB(70, 130, 70), Color3.fromRGB(225, 235, 245),
	Color3.fromRGB(90, 60, 55), Color3.fromRGB(224, 196, 120), Color3.fromRGB(150, 130, 200),
	Color3.fromRGB(120, 160, 90), Color3.fromRGB(140, 150, 130), Color3.fromRGB(120, 190, 180),
	Color3.fromRGB(150, 160, 170), Color3.fromRGB(150, 90, 210),
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
	-- Enchanted Forest (block 15): bioluminescent giant mushroom-trees, floating rocks + will-o-wisps.
	if i == 11 then
		for k = 0, 7 do
			local ang = k / 8 * math.pi * 2
			local tx = center.x + math.cos(ang) * S * 0.18
			local tz = center.z + math.sin(ang) * S * 0.18
			mkPart("Stalk", Vector3.new(4, 40, 4), CFrame.new(tx, 20, tz), Color3.fromRGB(180, 160, 210), model, Enum.Material.SmoothPlastic)
			local capColor = (k % 2 == 0) and Color3.fromRGB(200, 120, 240) or Color3.fromRGB(120, 220, 220)
			local cap = mkPart("Cap", Vector3.new(24, 10, 24), CFrame.new(tx, 42, tz), capColor, model, Enum.Material.Neon)
			cap.Shape = Enum.PartType.Ball
			local wisp = mkPart("Wisp", Vector3.new(2, 2, 2), CFrame.new(tx, 30 + k, tz + 6), Color3.fromRGB(180, 255, 230), model, Enum.Material.Neon)
			wisp.Shape = Enum.PartType.Ball
			local pl = Instance.new("PointLight")
			pl.Color = capColor
			pl.Range = 30
			pl.Brightness = 3
			pl.Parent = cap
		end
		-- Ancient Treant guardian at the centre
		mkPart("Treant", Vector3.new(14, 60, 14), CFrame.new(center.x, 30, center.z), Color3.fromRGB(90, 130, 90), model, Enum.Material.Wood)
	end

	local sign = mkPart("IslandSign", Vector3.new(3, 14, 3), CFrame.new(center.x, 7, center.z), Color3.fromRGB(120, 95, 70), model)
	mkBillboard(sign, 14, 2.4, 9).Text = (i == 11 and "🌟 " or "🏝️ ") .. (ISLAND_NAMES[i] or ("Island " .. i))
	local back = mkPrompt(sign, "Sail back to plaza", "sailback")
	back.MaxActivationDistance = 20
end

-- Build the whole static world once.
function World.build()
	pcall(function()
		workspace.StreamingEnabled = true -- map is ~3600 studs; clients stream only nearby content
		workspace.StreamingTargetRadius = 1200 -- stream a bit more so the plot + path around it are loaded
		-- Do NOT force PauseOutsideLoadedArea: on this big map it can freeze the character when it lands
		-- on a far plot before content streams (feels like "can't get onto my plot"). We instead let
		-- movement flow freely and catch any rare void fall with the safety net in init.server.
		workspace.StreamingIntegrityMode = Enum.StreamingIntegrityMode.Disabled
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

	-- ground = a GRID OF TILES under the whole mainland (plaza + all 100 plots + the roads between).
	-- IMPORTANT: a single Roblox part cannot exceed 2048 studs on an axis, so one giant ground part is
	-- invalid and leaves a void. We tile it with ~1700-stud parts so there is solid ground everywhere and
	-- you can walk the entire map on foot without ever falling into the abyss.
	do
		local tile = 1700
		local x0, x1 = -2800, 2800
		local z0, z1 = -500, WorldLayout.GRID_START_Z + gridD + 500
		local nx = math.ceil((x1 - x0) / tile)
		local nz = math.ceil((z1 - z0) / tile)
		for ix = 0, nx - 1 do
			for iz = 0, nz - 1 do
				local cx = x0 + ix * tile + tile / 2
				local cz = z0 + iz * tile + tile / 2
				mkPart("GroundTile_" .. ix .. "_" .. iz, Vector3.new(tile, 2, tile), CFrame.new(cx, -1, cz), C_ROAD, rootF, Enum.Material.Ground)
			end
		end
	end

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
		-- Challenge Board: 3 rotating daily challenges; press to view progress + claim rewards (content).
		local board = mkPart("ChallengeBoard", Vector3.new(7, 8, 2), CFrame.new(78, 4, WorldLayout.PLAZA_Z), Color3.fromRGB(90, 120, 170), rootF)
		mkPrompt(board, "Daily challenges", "challenges")
		mkBillboard(board, 9, 1.7, 6).Text = "🎯 Daily Challenges"
		-- Museum: donate one of every item for badges + rewards (block 14).
		local museum = mkPart("Museum", Vector3.new(14, 14, 10), CFrame.new(-95, 7, WorldLayout.PLAZA_Z + 30), Color3.fromRGB(210, 200, 175), rootF, Enum.Material.Marble)
		mkPrompt(museum, "Donate to museum", "museum")
		mkBillboard(museum, 14, 2, 9).Text = "🏛️ Museum — donate 1 of each"
		-- Premium Boutique: cosmetic/convenience Robux catalogue (block 16, zero pay-to-win).
		local boutique = mkPart("PremiumShop", Vector3.new(8, 11, 7), CFrame.new(95, 5.5, WorldLayout.PLAZA_Z + 30), Color3.fromRGB(230, 180, 220), rootF, Enum.Material.Neon)
		mkPrompt(boutique, "Browse Premium", "premium")
		mkBillboard(boutique, 10, 1.8, 7).Text = "✨ Premium — cosmetics only"
		-- Bloomy the mascot: greets new players; press the ❓ Help button anytime (block 2).
		local bloomy = mkPart("Bloomy", Vector3.new(4, 6, 4), CFrame.new(10, 4, WorldLayout.PLAZA_Z - 10), Color3.fromRGB(120, 220, 120), rootF, Enum.Material.Neon)
		bloomy.Shape = Enum.PartType.Ball
		mkBillboard(bloomy, 8, 1.6, 5).Text = "🌱 Bloomy — press ❓ Help!"
		-- Pet Shop + Egg Hatchery: adopt pets (passive coin/luck/grow boosts, earned not P2W) (content).
		local petshop = mkPart("PetShop", Vector3.new(7, 9, 6), CFrame.new(-30, 4.5, WorldLayout.PLAZA_Z - 44), Color3.fromRGB(240, 180, 120), rootF)
		mkPrompt(petshop, "Adopt a pet", "adoptpet")
		mkBillboard(petshop, 9, 1.7, 6).Text = "🐾 Pet Shop"
		local hatchery = mkPart("Hatchery", Vector3.new(6, 8, 6), CFrame.new(-14, 4, WorldLayout.PLAZA_Z - 44), Color3.fromRGB(250, 230, 180), rootF)
		mkPrompt(hatchery, "Hatch a mystery egg (2000c)", "hatchegg")
		mkBillboard(hatchery, 9, 1.7, 6).Text = "🥚 Egg Hatchery"
	end

	-- Homestead village (blocks 7-10): a row of stations behind the plaza. Each is a labelled hut with
	-- a small pad per action (own ProximityPrompt so kids see one clear key each). All act on the
	-- caller's OWN persistent orchard/pen/kitchen/hive/house (like the shared Market/upgrade kiosk).
	do
		local HOME_Z = WorldLayout.PLAZA_Z + 90
		local stations = {
			{ name = "Orchard", emoji = "🌳", color = Color3.fromRGB(80, 150, 70), acts = { { t = "Plant tree", a = "orchard_plant" }, { t = "Pick fruit", a = "orchard_pick" } } },
			{ name = "Animal Pen", emoji = "🐄", color = Color3.fromRGB(190, 160, 110), acts = { { t = "Buy animal", a = "pen_buy" }, { t = "Collect", a = "pen_collect" }, { t = "Breed", a = "pen_breed" } } },
			{ name = "Kitchen", emoji = "🍳", color = Color3.fromRGB(205, 120, 90), acts = { { t = "Cook dish", a = "cook_start" }, { t = "Collect dish", a = "cook_collect" } } },
			{ name = "Beehive", emoji = "🐝", color = Color3.fromRGB(230, 200, 80), acts = { { t = "Build/upgrade", a = "hive_up" }, { t = "Collect honey", a = "hive_collect" } } },
			{ name = "House", emoji = "🏠", color = Color3.fromRGB(170, 120, 90), acts = { { t = "Upgrade house", a = "house_up" }, { t = "Collect rent", a = "house_rent" }, { t = "Buy decor", a = "house_decor" } } },
		}
		for n, st in stations do
			local hx = -180 + (n - 1) * 90
			local hut = mkPart("Home_" .. st.name, Vector3.new(10, 12, 10), CFrame.new(hx, 6, HOME_Z), st.color, rootF)
			mkBillboard(hut, 12, 2, 8).Text = st.emoji .. " " .. st.name
			for j, act in st.acts do
				local px = hx + (j - (#st.acts + 1) / 2) * 7
				local pad = mkPart("HomeAct_" .. act.a, Vector3.new(5, 1.4, 5), CFrame.new(px, 0.7, HOME_Z - 12), st.color, rootF)
				local pr = mkPrompt(pad, act.t, "homestead")
				pr:SetAttribute("act", act.a)
				mkBillboard(pad, 5, 1.2, 3).Text = act.t
			end
		end
	end

	mkLamppost(-WorldLayout.PLAZA_RADIUS, WorldLayout.PLAZA_Z, rootF)
	mkLamppost(WorldLayout.PLAZA_RADIUS, WorldLayout.PLAZA_Z, rootF)

	-- plaza centrepiece: a little fountain with a water spray, + rings of flowers for life
	do
		local fx = -14
		local base = mkPart("Fountain", Vector3.new(16, 2, 16), CFrame.new(fx, 1, WorldLayout.PLAZA_Z + 60), Color3.fromRGB(160, 170, 185), rootF, Enum.Material.Marble)
		base.Shape = Enum.PartType.Cylinder
		base.Orientation = Vector3.new(0, 0, 90)
		local spout = mkPart("FountainSpout", Vector3.new(3, 8, 3), CFrame.new(fx, 5, WorldLayout.PLAZA_Z + 60), Color3.fromRGB(120, 190, 230), rootF, Enum.Material.Neon)
		local water = mkSparkle(spout, Color3.fromRGB(150, 210, 255), 30)
		water.Speed = NumberRange.new(6, 10)
		water.Lifetime = NumberRange.new(0.8, 1.4)
		water.SpreadAngle = Vector2.new(35, 35)
		local FLOWER = { Color3.fromRGB(240, 120, 150), Color3.fromRGB(250, 210, 90), Color3.fromRGB(180, 130, 230), Color3.fromRGB(240, 150, 90) }
		for k = 0, 17 do
			local a = k / 18 * math.pi * 2
			local r = WorldLayout.PLAZA_RADIUS - 8
			local fl = mkPart("Flower", Vector3.new(1.2, 3, 1.2), CFrame.new(math.cos(a) * r, 1.5, WorldLayout.PLAZA_Z + math.sin(a) * r), FLOWER[(k % 4) + 1], rootF, Enum.Material.Neon)
			fl.Shape = Enum.PartType.Ball
		end
	end

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

		-- low fence around the plot, with a wide GATEWAY (arch) in the front so you can walk in/out
		local fh, ft = 4, 0.6
		local gap = 60 -- width of the front gateway
		local segW = (WorldLayout.SECTION_SIZE - gap) / 2
		local segX = (gap + segW) / 2 -- centre offset of each front fence segment
		mkPart("FenceN1", Vector3.new(segW, fh, ft), CFrame.new(c.x - segX, fh / 2 + 1, c.z - half), C_FENCE, plot)
		mkPart("FenceN2", Vector3.new(segW, fh, ft), CFrame.new(c.x + segX, fh / 2 + 1, c.z - half), C_FENCE, plot)
		local gpH = 12 -- tall gate posts + a top beam so the gateway reads as an obvious opening
		mkPart("GateL", Vector3.new(2.5, gpH, 2.5), CFrame.new(c.x - gap / 2, gpH / 2 + 1, c.z - half), Color3.fromRGB(150, 110, 70), plot)
		mkPart("GateR", Vector3.new(2.5, gpH, 2.5), CFrame.new(c.x + gap / 2, gpH / 2 + 1, c.z - half), Color3.fromRGB(150, 110, 70), plot)
		mkPart("GateTop", Vector3.new(gap + 6, 2.5, 2.5), CFrame.new(c.x, gpH + 1, c.z - half), Color3.fromRGB(150, 110, 70), plot)
		mkBillboard(mkPart("GateSign", Vector3.new(0.5, 0.5, 0.5), CFrame.new(c.x, gpH + 4, c.z - half), C_FENCE, plot), 10, 1.6, 0).Text = "🚪 Gate (walk through here)"
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
			-- a real crop object that GROWS: a stalk that scales from sprout to full, hidden when empty,
			-- with a soft glow that turns on when the crop is ready to harvest.
			local crop = mkPart("Crop" .. j, Vector3.new(2, 2, 2), CFrame.new(c.x + o.x, padY + 1, c.z + o.z), C_GROWING, plot, Enum.Material.Grass)
			crop.Transparency = 1
			local glow = Instance.new("PointLight")
			glow.Color = Color3.fromRGB(140, 255, 150)
			glow.Range = 12
			glow.Brightness = 0
			glow.Parent = crop
			local sparkle = mkSparkle(crop, Color3.fromRGB(255, 245, 170), 14)
			sparkle.Enabled = false -- only sparkles when ready to harvest
			pads[j] = { pad = pad, prompt = prompt, cropLabel = mkBillboard(pad, 4, 2.4, 4), crop = crop, glow = glow, sparkle = sparkle, cropY = padY }
		end

		-- a lamppost at the plot's front-left corner (lines the streets)
		mkLamppost(c.x - half - 6, c.z - half - 6, plot)

		-- a scattered Market every 5th plot so selling is handy across the big map
		if i % 5 == 0 then
			mkMarket(c.x + half + 20, c.z, rootF, "🧺 Market")
		end

		sections[i] = { ownerLabel = ownerLabel, pads = pads }
	end

	-- gathering grove near the plaza (fish / mine / forage / bugs — for the tutorial + early quests)
	do
		local gz = WorldLayout.PLAZA_Z - 110
		mkGather("Pond", -45, gz, Vector3.new(22, 2, 22), Color3.fromRGB(70, 130, 200), Enum.Material.Water, "Fish", "fish", "fish", "🎣 Fishing Pond", rootF)
		mkGather("Rocks", -5, gz, Vector3.new(8, 8, 8), Color3.fromRGB(120, 120, 125), Enum.Material.Rock, "Mine", "mine", "ore", "⛏️ Rocks", rootF)
		mkGather("Bush", 30, gz, Vector3.new(7, 5, 7), Color3.fromRGB(80, 150, 70), Enum.Material.Grass, "Forage", "forage", "mushroom", "🍄 Forage Bush", rootF)
		mkGather("Flowers", 60, gz, Vector3.new(8, 2, 8), Color3.fromRGB(220, 150, 200), Enum.Material.Grass, "Catch bug", "catch_bug", "bug", "🦋 Bug Patch", rootF)
	end

	-- ocean + 11 islands far out (10 biomes + the Enchanted Forest)
	mkPart("Ocean", Vector3.new(WorldLayout.ISLAND_RING * 2.6, 2, WorldLayout.ISLAND_RING * 2.6), CFrame.new(0, -4, WorldLayout.MAP_CENTER_Z), Color3.fromRGB(58, 120, 190), rootF, Enum.Material.Water)
	for i = 1, WorldLayout.ISLAND_COUNT do
		buildIsland(i, WorldLayout.islandCenter(i), rootF)
	end
	-- island-specific gathering nodes
	local islandGather = {
		{ 4, "Mine", "mine", "ore", "⛏️ Lava Rocks" }, { 3, "Mine", "mine", "ore", "❄️ Ice Crystals" },
		{ 6, "Mine", "mine", "ore", "💎 Gem Vein" }, { 1, "Fish", "fish", "fish", "🎣 Beach Waters" },
		{ 9, "Fish", "fish", "fish", "🐠 Reef Waters" }, { 2, "Catch bug", "catch_bug", "bug", "🦋 Forest Bugs" },
		{ 7, "Forage", "forage", "mushroom", "🍄 Glow Caps" },
		{ 11, "Catch fairy", "catch_bug", "bug", "🧚 Fairy Ring" }, { 11, "Fish", "fish", "fish", "💫 Glowing Pool" },
	}
	for gi, g in islandGather do
		local c = WorldLayout.islandCenter(g[1] :: number)
		-- stagger x by loop index so two nodes on the same island (e.g. the Enchanted Forest) don't overlap
		mkGather("IsleGather" .. tostring(gi), c.x - 45 + (gi % 2) * 90, c.z + (gi % 3) * 22, Vector3.new(9, 5, 9), Color3.fromRGB(140, 130, 120), Enum.Material.Rock, g[2] :: string, g[3] :: string, g[4] :: string, g[5] :: string, rootF)
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
		-- Boat shop: buy your first boat here (gates all sailing). Captain Bay stands beside it.
		local boatShop = mkPart("BoatShop", Vector3.new(7, 8, 6), CFrame.new((WorldLayout.ISLAND_COUNT + 3) * 7, 4, dockZ), Color3.fromRGB(120, 80, 55), rootF, Enum.Material.WoodPlanks)
		mkPrompt(boatShop, "Buy a Boat (250c)", "buyboat")
		mkBillboard(boatShop, 10, 1.8, 6).Text = "⛵ Boat Shop — buy your first boat!"
	end

	-- hidden treasures: 5 per island (tier = island index) + 5 around the plaza
	do
		local perRegion = 5
		local function spawnTreasures(seed: number, cx: number, cz: number, half: number, tier: number)
			for k = 1, perRegion do
				local o = TreasureRules.spotFor(seed, k, perRegion, half)
				local chest = mkPart("Treasure_" .. seed .. "_" .. k, Vector3.new(4, 3, 4), CFrame.new(cx + o.x, 1.5, cz + o.z), Color3.fromRGB(230, 200, 90), rootF, Enum.Material.Neon)
				local pr = mkPrompt(chest, "Dig treasure", "treasure")
				pr:SetAttribute("tid", "t_" .. seed .. "_" .. k)
				pr:SetAttribute("tier", tier)
				pr.MaxActivationDistance = 8
				mkSparkle(chest, Color3.fromRGB(255, 235, 120), 10) -- glittering so you can spot it
				mkBillboard(chest, 4, 1.4, 3).Text = "💰"
			end
		end
		spawnTreasures(0, 0, WorldLayout.PLAZA_Z, WorldLayout.PLAZA_RADIUS + 30, 1)
		for i = 1, WorldLayout.ISLAND_COUNT do
			local c = WorldLayout.islandCenter(i)
			spawnTreasures(i, c.x, c.z, WorldLayout.ISLAND_SIZE / 2 * 0.75, i + 1)
		end
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
		-- helper: shape the 3D crop for a growth fraction (0..1); `readyGlow` lights it up when ripe
		local function showCrop(frac: number, color: Color3, readyGlow: boolean)
			if not pad.crop then
				return
			end
			local h = 1 + frac * 5
			local w = 1.4 + frac * 1.6
			local cp = pad.crop.Position
			pad.crop.Size = Vector3.new(w, h, w)
			pad.crop.CFrame = CFrame.new(cp.X, pad.cropY + 0.5 + h / 2, cp.Z)
			pad.crop.Color = color
			pad.crop.Transparency = 0
			if pad.glow then
				pad.glow.Brightness = readyGlow and 2.2 or 0
			end
			if pad.sparkle then
				pad.sparkle.Enabled = readyGlow
			end
		end
		local function hideCrop()
			if pad.crop then
				pad.crop.Transparency = 1
			end
			if pad.glow then
				pad.glow.Brightness = 0
			end
			if pad.sparkle then
				pad.sparkle.Enabled = false
			end
		end

		if p and p.locked then
			pad.pad.Color = Color3.fromRGB(70, 70, 75)
			pad.cropLabel.Text = "🔒"
			pad.prompt.Enabled = false
			hideCrop()
		elseif not p or p.seedId == nil then
			pad.pad.Color = C_EMPTY
			pad.cropLabel.Text = ""
			pad.prompt.ActionText = "Plant"
			pad.prompt.Enabled = true
			hideCrop()
		elseif p.ready then
			pad.pad.Color = C_READY
			pad.cropLabel.Text = p.emoji .. "\n✅ READY"
			pad.prompt.ActionText = "Harvest"
			pad.prompt.Enabled = true
			showCrop(1, Color3.fromRGB(130, 235, 115), true) -- full grown + glowing
		else
			pad.pad.Color = C_GROWING
			pad.cropLabel.Text = p.emoji .. "\n🌱 " .. p.secondsLeft .. "s"
			pad.prompt.Enabled = false
			showCrop(p.grownFrac or 0, Color3.fromRGB(95, 175, 85), false) -- scales as it grows
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
		if pad.crop then
			pad.crop.Transparency = 1
		end
		if pad.glow then
			pad.glow.Brightness = 0
		end
		if pad.sparkle then
			pad.sparkle.Enabled = false
		end
	end
end

return World
