--!strict
-- MapRules: PURE projection from world (x,z) coordinates to normalized map coordinates (u,v in 0..1),
-- used by the minimap + full map (block 16). No Roblox globals -> VPS-tested. The client multiplies
-- (u,v) by the map frame's pixel size to place a dot.

local MapRules = {}

local function clamp01(n: number): number
	if n < 0 then
		return 0
	elseif n > 1 then
		return 1
	end
	return n
end

-- bounds = { minX, maxX, minZ, maxZ }. Returns { u, v } in 0..1 (u across X, v across Z).
function MapRules.worldToMap(x: number, z: number, bounds: any): { u: number, v: number }
	local dx = bounds.maxX - bounds.minX
	local dz = bounds.maxZ - bounds.minZ
	local u = if dx ~= 0 then (x - bounds.minX) / dx else 0.5
	local v = if dz ~= 0 then (z - bounds.minZ) / dz else 0.5
	return { u = clamp01(u), v = clamp01(v) }
end

return MapRules
