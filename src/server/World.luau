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
local Monsters = require(ReplicatedStorage.Bloomly.data.Monsters)
local City = require(ReplicatedStorage.Bloomly.data.City)
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

-- A little blocky CHARACTER (a "ludek": legs, torso, arms, head) instead of a plain block, so NPCs
-- look like people. Anchored; wanderers are moved with Model:PivotTo. Feet sit at y=0 (ground top).
local NPC_SKIN = { Color3.fromRGB(255, 220, 180), Color3.fromRGB(232, 190, 150), Color3.fromRGB(200, 150, 110), Color3.fromRGB(160, 112, 80) }
local NPC_SHIRT = { Color3.fromRGB(80, 140, 220), Color3.fromRGB(220, 90, 90), Color3.fromRGB(90, 190, 120), Color3.fromRGB(235, 190, 70), Color3.fromRGB(160, 120, 220), Color3.fromRGB(90, 190, 200) }
local function mkCharacter(id: string, x: number, z: number, seed: number): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "Npc_" .. id
	model.Parent = root -- FIX: was `rootF` (a local inside World.build) => a nil global => NPCs never appeared
	local skin = NPC_SKIN[(seed % #NPC_SKIN) + 1]
	local shirt = NPC_SHIRT[(seed % #NPC_SHIRT) + 1]
	local function part(nm: string, size: Vector3, ox: number, oy: number, color: Color3): Part
		return mkPart(nm, size, CFrame.new(x + ox, oy, z), color, model)
	end
	part("LegL", Vector3.new(1.4, 5, 1.4), -1, 2.5, Color3.fromRGB(55, 65, 85))
	part("LegR", Vector3.new(1.4, 5, 1.4), 1, 2.5, Color3.fromRGB(55, 65, 85))
	local torso = part("Torso", Vector3.new(4, 5, 2), 0, 7.5, shirt)
	part("ArmL", Vector3.new(1.4, 5, 1.4), -2.7, 7.5, skin)
	part("ArmR", Vector3.new(1.4, 5, 1.4), 2.7, 7.5, skin)
	local head = part("Head", Vector3.new(2.4, 2.4, 2.4), 0, 11.2, skin)
	head.Material = Enum.Material.SmoothPlastic
	-- a little FACE on the head front (-z) so the "ludek" reads as a person: two eyes + hair + a smile
	mkPart("HairN" .. id, Vector3.new(2.7, 0.9, 2.7), CFrame.new(x, 12.5, z), Color3.fromRGB(60, 45, 35), model)
	mkPart("EyeLN" .. id, Vector3.new(0.5, 0.5, 0.3), CFrame.new(x - 0.55, 11.5, z - 1.25), Color3.fromRGB(35, 30, 30), model)
	mkPart("EyeRN" .. id, Vector3.new(0.5, 0.5, 0.3), CFrame.new(x + 0.55, 11.5, z - 1.25), Color3.fromRGB(35, 30, 30), model)
	mkPart("MouthN" .. id, Vector3.new(1.1, 0.3, 0.3), CFrame.new(x, 10.7, z - 1.25), Color3.fromRGB(150, 80, 70), model)
	model.PrimaryPart = torso
	return model, torso
end

-- A monster: a coloured body with eyes, an hp billboard, and an "attack" prompt. hp lives on a model
-- attribute; the combat handler in init.server reads/writes it + respawns. Returns the model.
local function mkMonster(mdef: any, x: number, z: number, idx: number): Model
	local model = Instance.new("Model")
	model.Name = "Mon_" .. mdef.id .. "_" .. idx
	model.Parent = root -- FIX: was `rootF` (nil global) => monsters never appeared
	local col = Color3.fromRGB(mdef.color[1], mdef.color[2], mdef.color[3])
	local body = mkPart("MonBody", Vector3.new(6, 7, 5), CFrame.new(x, 4, z), col, model, Enum.Material.SmoothPlastic)
	local eyeL = mkPart("EyeL", Vector3.new(1.1, 1.1, 1.1), CFrame.new(x - 1.3, 6, z - 2.4), Color3.fromRGB(255, 255, 255), model, Enum.Material.Neon)
	eyeL.Shape = Enum.PartType.Ball
	local eyeR = mkPart("EyeR", Vector3.new(1.1, 1.1, 1.1), CFrame.new(x + 1.3, 6, z - 2.4), Color3.fromRGB(255, 255, 255), model, Enum.Material.Neon)
	eyeR.Shape = Enum.PartType.Ball
	model.PrimaryPart = body
	model:SetAttribute("monsterId", mdef.id)
	model:SetAttribute("hp", mdef.hp)
	model:SetAttribute("maxHp", mdef.hp)
	local pr = mkPrompt(body, "Attack " .. mdef.name, "attack")
	pr.HoldDuration = 0
	pr.MaxActivationDistance = 12
	local lbl = mkBillboard(body, 10, 2, 6)
	lbl.Name = "MonHp"
	lbl.Text = mdef.emoji .. " " .. mdef.name .. "\n❤️ " .. mdef.hp .. "/" .. mdef.hp
	return model
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

-- A proper CITY BUILDING that faces the town centre: walls + roof + door + windows + a big rooftop sign,
-- with a "ludek" shopkeeper standing out front. Rotated (lookAt) so the door/greeter face the plaza.
local function mkBuilding(x: number, z: number, w: number, d: number, h: number, color: Color3, emoji: string, name: string, seed: number, parent: Instance)
	local model = Instance.new("Model")
	model.Name = "Bld_" .. (name:gsub("%s", ""))
	model.Parent = parent
	local bcf = CFrame.lookAt(Vector3.new(x, 0, z), Vector3.new(0, 0, 0))
	local function place(lx: number, ly: number, lz: number): CFrame
		return bcf * CFrame.new(lx, ly, lz)
	end
	local base = mkPart("Wall", Vector3.new(w, h, d), place(0, h / 2, 0), color, model)
	mkPart("Roof", Vector3.new(w + 4, 2.5, d + 4), place(0, h + 1.2, 0), Color3.fromRGB(96, 74, 60), model, Enum.Material.Slate)
	mkPart("Door", Vector3.new(7, 9, 1), place(0, 4.5, -d / 2 - 0.6), Color3.fromRGB(78, 54, 40), model, Enum.Material.WoodPlanks)
	mkPart("Win1", Vector3.new(5, 5, 1), place(-w / 4, h * 0.62, -d / 2 - 0.6), Color3.fromRGB(150, 205, 235), model, Enum.Material.Glass)
	mkPart("Win2", Vector3.new(5, 5, 1), place(w / 4, h * 0.62, -d / 2 - 0.6), Color3.fromRGB(150, 205, 235), model, Enum.Material.Glass)
	mkBillboard(base, 16, 2.6, h / 2 + 4).Text = emoji .. " " .. name
	-- greeter NPC out front (faces the plaza too). Feet at ground; front is toward the centre.
	local front = place(0, 0, -d / 2 - 7)
	local gm, gt = mkCharacter("shop_" .. seed, front.X, front.Z, seed)
	mkBillboard(gt, 12, 2, 8).Text = emoji .. " " .. name
	local pr = mkPrompt(gt, "Talk", "talk") -- every civic shopkeeper is talkable (generic city dialogue)
	pr:SetAttribute("npc", "city:" .. emoji .. ":" .. name)
	return model
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
	local R = WorldLayout.MAINLAND_RADIUS -- grass island radius (covers every plot ring + a margin)

	-- MAINLAND = one round, ORGANIC grass island centred on (0,0). Its COASTLINE follows a wavy radius per
	-- angle (not a straight ruler edge): we lay a grid of flat tiles but only place a tile where it sits
	-- inside the wavy shore radius, and tiles near the shore are SAND (a beach ring). Tiling also keeps
	-- every part < 2048 studs (the old giant part was invalid -> the void). Terrain water (below) fills the
	-- sea around the island, so where the grass/sand stops you step straight into real, swimmable water.
	local function shoreR(ang: number): number
		return R + math.sin(ang * 3) * 260 + math.sin(ang * 5 + 1.3) * 150 + math.cos(ang * 2 + 0.6) * 100
	end
	do
		local tile = 300
		local span = R + 450
		local n = math.ceil((span * 2) / tile)
		local GRASS = {
			{ Color3.fromRGB(96, 158, 74), Enum.Material.Grass },
			{ Color3.fromRGB(110, 170, 86), Enum.Material.Grass },
			{ Color3.fromRGB(122, 178, 94), Enum.Material.LeafyGrass },
		}
		for ix = 0, n - 1 do
			for iz = 0, n - 1 do
				local cx = -span + ix * tile + tile / 2
				local cz = -span + iz * tile + tile / 2
				local dist = math.sqrt(cx * cx + cz * cz)
				local edge = shoreR(math.atan2(cz, cx))
				if dist <= edge then
					if dist >= edge - 300 then -- shoreline band => sandy beach that wraps the whole island
						mkPart("Beach_" .. ix .. "_" .. iz, Vector3.new(tile + 2, 2, tile + 2), CFrame.new(cx, -1, cz), Color3.fromRGB(228, 210, 152), rootF, Enum.Material.Sand)
					else
						local g = GRASS[((ix + iz) % #GRASS) + 1]
						mkPart("Ground_" .. ix .. "_" .. iz, Vector3.new(tile + 2, 2, tile + 2), CFrame.new(cx, -1, cz), g[1], rootF, g[2])
					end
				end
			end
		end
	end

	-- ROADS: grey paths so the town reads as a town. A ring road just outside the plaza + radial spokes
	-- out to the coast (drivable by bike/car; they sit just under the plot platforms so they show only in
	-- the gaps). Kept < 2048 studs each.
	do
		local roadCol = Color3.fromRGB(96, 100, 104)
		for k = 0, 11 do -- 12 radial spokes fanning out from the centre (len kept < 2048 = valid part)
			local a = k / 12 * math.pi * 2
			local len = 1900
			local mid = 240 + len / 2
			mkPart("Spoke" .. k, Vector3.new(len, 0.4, 26), CFrame.new(math.cos(a) * mid, 0.08, math.sin(a) * mid) * CFrame.Angles(0, -a, 0), roadCol, rootF, Enum.Material.Concrete)
		end
		for ring = 0, 4 do -- concentric ring roads between the plot rings
			local rr = WorldLayout.RING0 - 180 + ring * WorldLayout.SECTION_SPACING
			local segs = math.max(24, math.floor((2 * math.pi * rr) / 90))
			for s = 0, segs - 1 do
				local a = s / segs * math.pi * 2
				local seg = (2 * math.pi * rr) / segs + 4
				mkPart("Ring" .. ring .. "_" .. s, Vector3.new(seg, 0.4, 20), CFrame.new(math.cos(a) * rr, 0.06, math.sin(a) * rr) * CFrame.Angles(0, -a + math.pi / 2, 0), roadCol, rootF, Enum.Material.Concrete)
			end
		end
	end

	-- scattered rocks/boulders in the COASTAL BELT (just inside the shore, past the outermost plot ring)
	-- so they dress the shoreline without blocking a plot or a road.
	do
		local rockCol = { Color3.fromRGB(120, 120, 126), Color3.fromRGB(100, 100, 106), Color3.fromRGB(138, 132, 120) }
		for k = 1, 70 do
			local a = (k / 70) * math.pi * 2 + (k % 3) * 0.3
			local r = shoreR(a) - 120 - (k % 5) * 40
			local rx, rz = math.cos(a) * r, math.sin(a) * r
			local sz = 3 + (k % 6) * 1.4
			mkPart("Rock" .. k, Vector3.new(sz, sz * 0.75, sz * (0.8 + (k % 3) * 0.15)), CFrame.new(rx, sz * 0.3, rz) * CFrame.Angles((k % 4) * 0.3, (k % 7) * 0.5, 0), rockCol[(k % 3) + 1], rootF, Enum.Material.Rock)
		end
	end

	-- FORESTS + MOUNTAINS in the coastal belt so the island feels real, not an empty field. Trees ring the
	-- shore (inside the beach); a few big rounded mountains sit right at the coast as landmarks.
	do
		-- a belt of trees (trunk + leafy canopy) hugging the shoreline
		for k = 1, 120 do
			local a = (k / 120) * math.pi * 2 + (k % 5) * 0.22
			local r = shoreR(a) - 190 - (k % 7) * 45
			local tx, tz = math.cos(a) * r, math.sin(a) * r
			local h = 14 + (k % 5) * 4
			mkPart("Trunk" .. k, Vector3.new(3, h, 3), CFrame.new(tx, h / 2, tz), Color3.fromRGB(105, 75, 50), rootF, Enum.Material.Wood)
			local leaf = mkPart("Leaves" .. k, Vector3.new(14, 14, 14), CFrame.new(tx, h + 4, tz), Color3.fromRGB(60 + (k % 3) * 20, 140 + (k % 4) * 15, 60), rootF, Enum.Material.Grass)
			leaf.Shape = Enum.PartType.Ball
		end
		-- a ring of rounded mountains right at the coast (big stone hills w/ snow caps)
		for k = 1, 14 do
			local a = (k / 14) * math.pi * 2 + 0.2
			local r = shoreR(a) - 40
			local mx, mz = math.cos(a) * r, math.sin(a) * r
			local mh = 120 + (k % 4) * 40
			local m = mkPart("Mountain" .. k, Vector3.new(mh * 0.9, mh, mh * 0.9), CFrame.new(mx, mh / 2 - 10, mz), Color3.fromRGB(110, 108, 112), rootF, Enum.Material.Rock)
			m.Shape = Enum.PartType.Ball -- rounded peak (cheap, reads as a hill/mountain)
			mkPart("Snow" .. k, Vector3.new(mh * 0.4, mh * 0.3, mh * 0.4), CFrame.new(mx, mh - 10, mz), Color3.fromRGB(240, 245, 250), rootF, Enum.Material.Sand)
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
		local seeds = mkPart("SeedShop", Vector3.new(8, 11, 8), CFrame.new(30, 5.5, WorldLayout.PLAZA_Z), Color3.fromRGB(90, 170, 90), rootF)
		mkPrompt(seeds, "Buy seeds", "seedshop") -- opens the Seed Shop buy panel (buy seeds into stock)
		mkBillboard(seeds, 10, 1.8, 7).Text = "🌱 Seed Shop — press E to buy"
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

	-- ===== THE CITY: a ring of civic buildings around the town centre so the middle of the island is a
	-- real town (hospital, car dealer, bike shop, bank, school, cafe, cinema, police...), each with a
	-- shopkeeper "ludek" out front. They sit between the plaza and the first ring of farms.
	do
		for k, b in City.buildings do
			local c = City.centerOf(k) -- shared with the map, so markers never drift from the buildings
			local w = 26 + (k % 3) * 6
			local h = 20 + (k % 4) * 6
			local col = Color3.fromRGB(b.color[1], b.color[2], b.color[3])
			mkBuilding(c.x, c.z, w, 22, h, col, b.emoji, b.name, 700 + k, rootF)
		end
		-- park + fishing spots + street benches so the town uses its space and has "random city things"
		local benchCol = Color3.fromRGB(120, 90, 60)
		for k = 1, 10 do
			local a = k / 10 * math.pi * 2 + 0.5
			local r = 300 + (k % 4) * 30
			mkPart("Bench" .. k, Vector3.new(8, 2, 2.4), CFrame.new(math.cos(a) * r, 1, math.sin(a) * r) * CFrame.Angles(0, -a, 0), benchCol, rootF, Enum.Material.WoodPlanks)
		end
		-- three town fishing spots (ponds) tucked into the coastal belt gaps
		for k = 1, 3 do
			local a = k / 3 * math.pi * 2 + 1.1
			local r = 2360
			mkGather("TownPond" .. k, math.cos(a) * r, math.sin(a) * r, Vector3.new(26, 2, 26), Color3.fromRGB(70, 130, 200), Enum.Material.Water, "Fish", "fish", "fish", "🎣 Fishing Spot", rootF)
		end

		-- PARKS + GREENERY (Adam: "parki, lasy" w srodku): tree clusters + flower beds woven through the
		-- town (in the gaps between the civic buildings) so the centre has green parks, not just concrete.
		local function mkTree(tx: number, tz: number, tag: string)
			local h = 12 + (math.abs(tx + tz) % 6)
			mkPart("PkTrunk" .. tag, Vector3.new(2.6, h, 2.6), CFrame.new(tx, h / 2, tz), Color3.fromRGB(105, 75, 50), rootF, Enum.Material.Wood)
			local leaf = mkPart("PkLeaf" .. tag, Vector3.new(12, 12, 12), CFrame.new(tx, h + 3, tz), Color3.fromRGB(70, 150, 70), rootF, Enum.Material.Grass)
			leaf.Shape = Enum.PartType.Ball
		end
		local FLOWER = { Color3.fromRGB(240, 120, 150), Color3.fromRGB(250, 210, 90), Color3.fromRGB(180, 130, 230), Color3.fromRGB(240, 150, 90) }
		local nB = #City.buildings
		for g = 1, nB do -- one little park in each gap between two neighbouring buildings
			local a = (g - 0.5) / nB * math.pi * 2 + 0.2
			local r = 460
			local px, pz = math.cos(a) * r, math.sin(a) * r
			-- a small grassy park pad + a cluster of trees + a ring of flowers
			mkPart("ParkPad" .. g, Vector3.new(34, 0.6, 34), CFrame.new(px, 0.35, pz), Color3.fromRGB(96, 170, 84), rootF, Enum.Material.Grass)
			for c = 0, 2 do
				local ca = a + (c - 1) * 0.16
				mkTree(math.cos(ca) * (r + (c - 1) * 8), math.sin(ca) * (r + (c - 1) * 8), g .. "_" .. c)
			end
			for f = 0, 5 do
				local fa = f / 6 * math.pi * 2
				local fl = mkPart("PkFlower" .. g .. "_" .. f, Vector3.new(1, 2.4, 1), CFrame.new(px + math.cos(fa) * 13, 1.4, pz + math.sin(fa) * 13), FLOWER[(f % 4) + 1], rootF, Enum.Material.Neon)
				fl.Shape = Enum.PartType.Ball
			end
		end
		-- a couple of bigger tree groves ("lasy") in the wider gaps out between the farm rings
		for g = 1, 8 do
			local a = g / 8 * math.pi * 2 + 0.9
			local r = 900 + (g % 3) * 360 -- lands in a road gap between plot rings
			local gx, gz = math.cos(a) * r, math.sin(a) * r
			for c = 1, 5 do
				local ca = a + (c - 3) * 0.06
				local cr = r + (c - 3) * 10
				mkTree(math.cos(ca) * cr, math.sin(ca) * cr, "grove" .. g .. "_" .. c)
			end
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

		-- RADIAL: rotate the whole plot so its GATEWAY + crop field face the central plaza (the plot's local
		-- -z / "front" points at 0,0), and the house/pen sit at the back. Every part is placed via plotCF so
		-- the fences, pads, crops + gate all turn together. `place(lx,ly,lz)` = local offset -> world CFrame.
		local plotCF = CFrame.lookAt(Vector3.new(c.x, 0, c.z), Vector3.new(0, 0, 0))
		local function place(lx: number, ly: number, lz: number): CFrame
			return plotCF * CFrame.new(lx, ly, lz)
		end

		-- raised green platform (=> the grey road base shows in the gaps)
		local platform = mkPart("Grass", Vector3.new(WorldLayout.SECTION_SIZE, 1, WorldLayout.SECTION_SIZE), place(0, 0.5, 0), C_GRASS, plot, Enum.Material.Grass)
		plot.PrimaryPart = platform

		-- low fence around the plot, with a wide GATEWAY (arch) in the front (facing the plaza)
		local fh, ft = 4, 0.6
		local gap = 60 -- width of the front gateway
		local segW = (WorldLayout.SECTION_SIZE - gap) / 2
		local segX = (gap + segW) / 2 -- centre offset of each front fence segment
		mkPart("FenceN1", Vector3.new(segW, fh, ft), place(-segX, fh / 2 + 1, -half), C_FENCE, plot)
		mkPart("FenceN2", Vector3.new(segW, fh, ft), place(segX, fh / 2 + 1, -half), C_FENCE, plot)
		local gpH = 12 -- tall gate posts + a top beam so the gateway reads as an obvious opening
		mkPart("GateL", Vector3.new(2.5, gpH, 2.5), place(-gap / 2, gpH / 2 + 1, -half), Color3.fromRGB(150, 110, 70), plot)
		mkPart("GateR", Vector3.new(2.5, gpH, 2.5), place(gap / 2, gpH / 2 + 1, -half), Color3.fromRGB(150, 110, 70), plot)
		mkPart("GateTop", Vector3.new(gap + 6, 2.5, 2.5), place(0, gpH + 1, -half), Color3.fromRGB(150, 110, 70), plot)
		mkBillboard(mkPart("GateSign", Vector3.new(0.5, 0.5, 0.5), place(0, gpH + 4, -half), C_FENCE, plot), 10, 1.6, 0).Text = "🚪 Gate (walk through here)"
		mkPart("FenceS", Vector3.new(WorldLayout.SECTION_SIZE, fh, ft), place(0, fh / 2 + 1, half), C_FENCE, plot)
		mkPart("FenceW", Vector3.new(ft, fh, WorldLayout.SECTION_SIZE), place(-half, fh / 2 + 1, 0), C_FENCE, plot)
		mkPart("FenceE", Vector3.new(ft, fh, WorldLayout.SECTION_SIZE), place(half, fh / 2 + 1, 0), C_FENCE, plot)

		-- owner sign + name at the front (entrance) edge, facing the plaza
		local post = mkPart("OwnerPost", Vector3.new(2, 10, 2), place(0, 5, -half - 4), Color3.fromRGB(120, 95, 70), plot)
		local ownerLabel = mkBillboard(post, 12, 2.2, 7)
		ownerLabel.Text = "· free plot ·"
		ownerLabel.TextColor3 = Color3.fromRGB(225, 225, 225)

		-- reserved expansion zones (house / pen / utility / orchard) as labelled markers
		for _, name in WorldLayout.zoneNames() do
			local o = WorldLayout.zoneOffset(name)
			if o then
				local zp = mkPart("Zone_" .. name, Vector3.new(70, 1.2, 70), place(o.x, 1.1, o.z), ZONE_COLOR[name] or C_GRASS, plot)
				mkBillboard(zp, 10, 1.8, 6).Text = ZONE_TEXT[name] or name
			end
		end

		-- 12 crop pads with Plant/Harvest prompts (enabled only for the owner while claimed)
		local pads: { [number]: any } = {}
		for j = 1, Config.PLOT_COUNT do
			local o = WorldLayout.plotPadOffset(j, Config.PLOT_COUNT)
			local pad = mkPart("Pad" .. j, Vector3.new(WorldLayout.PAD_SIZE, 1, WorldLayout.PAD_SIZE), place(o.x, padY, o.z), C_EMPTY, plot)
			local prompt = mkPrompt(pad, "Plant", "plot")
			prompt.Enabled = false
			prompt:SetAttribute("section", i)
			prompt:SetAttribute("plotIndex", j)
			-- a real crop object that GROWS: a stalk that scales from sprout to full, hidden when empty,
			-- with a soft glow that turns on when the crop is ready to harvest.
			local crop = mkPart("Crop" .. j, Vector3.new(2, 2, 2), place(o.x, padY + 1, o.z), C_GROWING, plot, Enum.Material.Grass)
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
		local lp = place(-half - 6, 0, -half - 6)
		mkLamppost(lp.X, lp.Z, plot)

		-- a scattered Market every 5th plot so selling is handy across the big map
		if i % 5 == 0 then
			local mp = place(half + 20, 0, 0)
			mkMarket(mp.X, mp.Z, rootF, "🧺 Market")
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

	-- OCEAN = real Roblox TERRAIN WATER (not a flat blue part you walk on). Terrain water lets the avatar
	-- actually SWIM, and it has no 2048-stud part limit. Its surface sits just below the beach (top ~ -1.5)
	-- so where the sand ends you step down into swimmable sea. We fill it in 2000-stud blocks out past the
	-- island ring, and SKIP blocks fully under the mainland (that water would be hidden by grass anyway).
	-- NOTE: this is the one thing I cannot performance-test from outside Studio -- if it ever hurts your
	-- framerate, tell me and I will shrink the fill area or its depth (it's this single block).
	do
		local terrain = workspace.Terrain
		pcall(function()
			terrain:Clear()
		end)
		local wtop = -1.5
		local depth = 7
		local wy = wtop - depth / 2
		local tile = 2000
		local reach = WorldLayout.ISLAND_RING + 700
		local n = math.ceil((reach * 2) / tile)
		for ix = 0, n - 1 do
			for iz = 0, n - 1 do
				local ox = -reach + ix * tile + tile / 2
				local oz = -reach + iz * tile + tile / 2
				if math.sqrt(ox * ox + oz * oz) > WorldLayout.MAINLAND_RADIUS - 800 then
					terrain:FillBlock(CFrame.new(ox, wy, oz), Vector3.new(tile, depth, tile), Enum.Material.Water)
				end
			end
		end
	end
	-- a few ships sailing the sea between the mainland and the islands. They move SLOWLY (a real sail, not
	-- rockets) and gently bob + roll on the water surface so it looks natural.
	do
		local ships = {}
		for k = 1, 5 do
			local hull = mkPart("Ship" .. k, Vector3.new(18, 8, 40), CFrame.new(0, 1, 0), Color3.fromRGB(120, 85, 55), rootF, Enum.Material.WoodPlanks)
			local sail = mkPart("Sail" .. k, Vector3.new(2, 26, 22), CFrame.new(0, 18, 0), Color3.fromRGB(235, 235, 240), hull, Enum.Material.Fabric)
			-- spd is radians per 0.1s tick: ~0.0012 rad/tick => ~0.012 rad/s => ~40 studs/s at r~3000. Gentle.
			table.insert(ships, { hull = hull, sail = sail, r = 2850 + k * 130, a = k * 1.25, spd = 0.0011 + k * 0.00018 })
		end
		task.spawn(function()
			while true do
				task.wait(0.1)
				local t = os.clock()
				for i, s in ships do
					s.a += s.spd
					local x = math.cos(s.a) * s.r
					local z = math.sin(s.a) * s.r
					local bob = math.sin(t * 0.7 + i) * 1.2 -- rise/fall on the swell
					local roll = math.sin(t * 0.9 + i * 1.3) * 0.05 -- slight side-to-side lean
					s.hull.CFrame = CFrame.new(x, 1 + bob, z) * CFrame.Angles(0, -s.a + math.pi / 2, 0) * CFrame.Angles(0, 0, roll)
					s.sail.CFrame = s.hull.CFrame * CFrame.new(0, 16, 0)
				end
			end
		end)
	end

	-- SKY LIFE: balloons + planes + a flock of birds, all circling over the map so lots is happening.
	-- Built from several parts each (balloons are balls, planes have wings+tail) so they read properly,
	-- not as flat squares.
	do
		local cz = WorldLayout.MAP_CENTER_Z
		local sky: { any } = {}
		local balloonCol = { Color3.fromRGB(230, 80, 80), Color3.fromRGB(80, 160, 230), Color3.fromRGB(240, 200, 70), Color3.fromRGB(120, 210, 120), Color3.fromRGB(230, 130, 220) }
		for k = 1, 5 do
			local balloon = mkPart("Balloon" .. k, Vector3.new(30, 36, 30), CFrame.new(0, 300, 0), balloonCol[k], rootF, Enum.Material.SmoothPlastic)
			balloon.Shape = Enum.PartType.Ball
			local basket = mkPart("Basket" .. k, Vector3.new(9, 8, 9), CFrame.new(0, 260, 0), Color3.fromRGB(120, 85, 55), rootF, Enum.Material.WoodPlanks)
			table.insert(sky, { root = balloon, b = basket, kind = "balloon", a = k * 1.3, r = 1400 + k * 260, base = 250 + k * 18, spd = 0.008 + k * 0.0015 })
		end
		for k = 1, 3 do
			local body = mkPart("Plane" .. k, Vector3.new(6, 5, 34), CFrame.new(0, 340, 0), Color3.fromRGB(225, 225, 235), rootF, Enum.Material.Metal)
			local wing = mkPart("Wing" .. k, Vector3.new(46, 1.6, 9), CFrame.new(0, 340, 0), Color3.fromRGB(200, 200, 212), rootF, Enum.Material.Metal)
			local tail = mkPart("Tail" .. k, Vector3.new(1.6, 10, 6), CFrame.new(0, 344, 0), Color3.fromRGB(210, 70, 70), rootF, Enum.Material.Metal)
			table.insert(sky, { root = body, w = wing, tl = tail, kind = "plane", a = k * 2.1, r = 2100 + k * 220, base = 330 + k * 16, spd = 0.02 + k * 0.003 })
		end
		for k = 1, 12 do
			local bird = mkPart("Bird" .. k, Vector3.new(2.4, 1, 3), CFrame.new(0, 150, 0), Color3.fromRGB(40, 40, 46), rootF, Enum.Material.SmoothPlastic)
			local wings = mkPart("BW" .. k, Vector3.new(7, 0.4, 2.2), CFrame.new(0, 150, 0), Color3.fromRGB(45, 45, 52), rootF, Enum.Material.SmoothPlastic)
			table.insert(sky, { root = bird, w = wings, kind = "bird", a = (k / 12) * math.pi * 2, r = 800 + (k % 3) * 60, base = 150, spd = 0.03, off = k * 0.5 })
		end
		task.spawn(function()
			while true do
				task.wait(0.08)
				local t = os.clock()
				for _, o in sky do
					o.a += o.spd
					local x = math.cos(o.a) * o.r
					local z = cz + math.sin(o.a) * o.r
					local y = o.base + math.sin(t * 0.6 + (o.off or 0)) * 6
					local cf = CFrame.new(x, y, z) * CFrame.Angles(0, -o.a + math.pi / 2, 0)
					o.root.CFrame = cf
					if o.b then
						o.b.CFrame = cf * CFrame.new(0, -22, 0) -- balloon basket hangs below
					end
					if o.w then
						o.w.CFrame = cf -- wings centred on the body
					end
					if o.tl then
						o.tl.CFrame = cf * CFrame.new(0, 4, -15) -- plane tail
					end
				end
			end
		end)
	end

	-- SEA LIFE: fish circling near the shore that occasionally leap out of the water, + a ring of foam
	-- "waves" that bob at the shoreline so the sea feels alive.
	do
		local WATER_TOP = -1.5
		local fishCol = { Color3.fromRGB(120, 165, 205), Color3.fromRGB(230, 150, 90), Color3.fromRGB(200, 210, 120), Color3.fromRGB(180, 130, 210) }
		local fish = {}
		for k = 1, 22 do
			local f = mkPart("Fish" .. k, Vector3.new(2, 1.2, 4.2), CFrame.new(0, WATER_TOP - 1, 0), fishCol[(k % 4) + 1], rootF, Enum.Material.SmoothPlastic)
			table.insert(fish, { part = f, a = (k / 22) * math.pi * 2, off = 120 + (k % 5) * 90, spd = 0.008 + (k % 3) * 0.003, jp = k * 0.35 })
		end
		-- foam "wave" crests hugging the ORGANIC shoreline (follow shoreR per angle, at the water surface)
		local foam = {}
		for k = 1, 60 do
			local a = (k / 60) * math.pi * 2
			local r = shoreR(a) + 8
			local fm = mkPart("Foam" .. k, Vector3.new(90, 1, 22), CFrame.new(math.cos(a) * r, WATER_TOP, math.sin(a) * r) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(225, 240, 250), rootF, Enum.Material.Foil)
			fm.Transparency = 0.35
			table.insert(foam, { part = fm, base = WATER_TOP, off = k * 0.4 })
		end
		task.spawn(function()
			while true do
				task.wait(0.08)
				local t = os.clock()
				for _, fo in fish do
					fo.a += fo.spd
					local r = shoreR(fo.a) + fo.off -- swim just offshore, following the wavy coast
					local x = math.cos(fo.a) * r
					local z = math.sin(fo.a) * r
					local phase = (t * 0.5 + fo.jp * 6) % 6.5
					local y, tilt = WATER_TOP - 1, 0
					if phase < 1.1 then -- a leap out of the water
						y = WATER_TOP - 1 + math.sin(phase / 1.1 * math.pi) * 7
						tilt = math.cos(phase / 1.1 * math.pi) * 0.7
					end
					fo.part.CFrame = CFrame.new(x, y, z) * CFrame.Angles(tilt, -fo.a + math.pi / 2, 0)
				end
				for _, fm in foam do
					fm.part.Position = Vector3.new(fm.part.Position.X, fm.base + math.sin(t * 1.2 + fm.off) * 0.6, fm.part.Position.Z)
				end
			end
		end)
	end
	for i = 1, WorldLayout.ISLAND_COUNT do
		buildIsland(i, WorldLayout.islandCenter(i), rootF)
	end

	-- MONSTERS: spawn a few of each creature on its island (combat, RPG block 3).
	for _, mdef in Monsters.list do
		local c = WorldLayout.islandCenter(mdef.island)
		for k = 1, 3 do
			local a = (k / 3) * math.pi * 2 + mdef.island
			local r = WorldLayout.ISLAND_SIZE * 0.28
			mkMonster(mdef, c.x + math.cos(a) * r, c.z + math.sin(a) * r, k)
		end
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

	-- NPCs are little people (ludki) SCATTERED across the whole map; island NPCs stand on their island;
	-- wanderers actually walk around their spot.
	do
		local wanderers = {}
		local seed = 0
		for _, npc in Npcs.list do
			seed += 1
			local x, z
			if npc.island then
				local c = WorldLayout.islandCenter(npc.island)
				x, z = c.x, c.z + 30
			elseif npc.id == "willow" or npc.id == "pip" then
				-- keep the starter NPCs (quest-giver Willow + seed shop Pip) right by the central plaza
				x, z = (npc.id == "pip" and 24 or -24), WorldLayout.PLAZA_Z + 30
			else
				-- golden-angle scatter across the whole island (centred on 0,0) so shopkeepers + wanderers
				-- are spread map-wide, standing on the ring roads between the farms, not clumped in one spot.
				-- r is clamped to just inside the wavy shore so an NPC never ends up hovering over the sea.
				local a = seed * 2.39996
				local r = math.min(300 + (seed % 10) * 220, shoreR(a) - 240)
				x, z = math.cos(a) * r, math.sin(a) * r
			end
			local model, torso = mkCharacter(npc.id, x, z, seed)
			local pr = mkPrompt(torso, "Talk", "talk")
			pr:SetAttribute("npc", npc.id)
			mkBillboard(torso, 11, 2, 8).Text = npc.emoji .. " " .. npc.name
			if npc.behavior == "W" and not npc.island then
				table.insert(wanderers, { model = model, hx = x, hz = z, p = seed * 0.7, last = Vector3.new(x, 0, z) })
			end
		end
		-- wander loop: the "W" NPCs stroll around the town on smooth organic paths (layered sines => no
		-- jerky orbits), FACE the way they're walking, and bob up/down a little so they look like they walk.
		task.spawn(function()
			while true do
				task.wait(0.12)
				local t = os.clock()
				for i, w in wanderers do
					local wx = w.hx + math.sin(t * 0.12 + w.p) * 40 + math.sin(t * 0.05 + w.p * 2) * 26
					local wz = w.hz + math.cos(t * 0.10 + w.p * 1.3) * 40 + math.sin(t * 0.07 + w.p) * 22
					local dir = Vector3.new(wx - w.last.X, 0, wz - w.last.Z)
					local yaw = (dir.Magnitude > 0.02) and math.atan2(dir.X, dir.Z) or 0
					local bob = math.abs(math.sin(t * 6 + i)) * 0.6 -- little walking bounce
					w.model:PivotTo(CFrame.new(wx, 7.5 + bob, wz) * CFrame.Angles(0, yaw, 0))
					w.last = Vector3.new(wx, 0, wz)
				end
			end
		end)
	end

	-- harbor at the SOUTH COAST (at the real sea now): a dock reaching over the water + a boat per island
	-- (sail = teleport for now). A radial road spoke runs from the central plaza out to it.
	do
		-- south waterline (the +wave at due south puts the coast ~MAINLAND_RADIUS+140); the dock BRIDGES from
		-- land out over the sea so you walk from the beach onto the pier and the boats sit on real water.
		local shoreZ = -(WorldLayout.MAINLAND_RADIUS + 140)
		mkPart("Dock", Vector3.new(WorldLayout.ISLAND_COUNT * 13, 1, 340), CFrame.new(0, 0.6, shoreZ), Color3.fromRGB(150, 120, 90), rootF, Enum.Material.WoodPlanks)
		for i = 1, WorldLayout.ISLAND_COUNT do
			local sx = (i - (WorldLayout.ISLAND_COUNT + 1) / 2) * 13
			local boat = mkPart("Boat" .. i, Vector3.new(9, 3, 5), CFrame.new(sx, 1.5, shoreZ - 150), Color3.fromRGB(140, 90, 60), rootF, Enum.Material.WoodPlanks)
			local pr = mkPrompt(boat, "Sail to " .. (ISLAND_NAMES[i] or ("Island " .. i)), "sail")
			pr:SetAttribute("islandIndex", i)
		end
		mkBillboard(mkPart("HarborSign", Vector3.new(3, 12, 3), CFrame.new(0, 6, shoreZ + 150), Color3.fromRGB(120, 95, 70), rootF), 14, 2, 8).Text = "⚓ Harbor — sail to the islands"
		-- Boat shop: buy your first boat here (gates all sailing). Captain Bay stands beside it.
		local boatShop = mkPart("BoatShop", Vector3.new(7, 8, 6), CFrame.new((WorldLayout.ISLAND_COUNT + 3) * 7, 4, shoreZ + 150), Color3.fromRGB(120, 80, 55), rootF, Enum.Material.WoodPlanks)
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
