--!strict
-- City: the shared definition of the civic buildings that ring the town centre. BOTH the world builder
-- (World.luau, which places the buildings) and the map (MapData/MapRules, which marks them) read from
-- THIS one source, so the map can never drift from where the buildings actually stand.

local City = {}

export type Building = { emoji: string, name: string, color: { number } }

City.buildings = {
	{ emoji = "🏥", name = "Hospital", color = { 238, 242, 246 } },
	{ emoji = "🚗", name = "Car Dealership", color = { 120, 140, 190 } },
	{ emoji = "🚲", name = "Bike Shop", color = { 118, 192, 160 } },
	{ emoji = "🏦", name = "Bank", color = { 204, 192, 138 } },
	{ emoji = "🏫", name = "School", color = { 212, 162, 120 } },
	{ emoji = "☕", name = "Cafe", color = { 182, 132, 100 } },
	{ emoji = "🥐", name = "Bakery", color = { 232, 202, 150 } },
	{ emoji = "🛒", name = "Grocery", color = { 150, 202, 150 } },
	{ emoji = "🎬", name = "Cinema", color = { 92, 92, 132 } },
	{ emoji = "🚓", name = "Police Station", color = { 88, 112, 172 } },
	{ emoji = "🚒", name = "Fire Station", color = { 202, 92, 80 } },
	{ emoji = "📚", name = "Library", color = { 162, 142, 192 } },
	{ emoji = "💪", name = "Gym", color = { 122, 122, 142 } },
	{ emoji = "👕", name = "Clothing Store", color = { 212, 150, 192 } },
	{ emoji = "🏨", name = "Hotel", color = { 182, 172, 202 } },
	{ emoji = "🏛️", name = "Town Hall", color = { 222, 216, 200 } },
} :: { Building }

-- Where civic building `k` (1-based) stands: a ring around the town centre (0,0), between the plaza and
-- the first ring of farms. Kept identical in World.luau's placement loop.
function City.centerOf(k: number): { x: number, z: number }
	local n = #City.buildings
	local a = (k - 1) / n * math.pi * 2 + 0.2
	local r = 430 + (k % 3) * 45
	return { x = math.cos(a) * r, z = math.sin(a) * r }
end

return City
