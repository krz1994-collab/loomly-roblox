--!strict
-- PetRules: PURE pet ability math (content). The equipped pet grants a modest, capped bonus to one
-- earned dimension (coins/luck/grow). No Roblox globals -> VPS-tested. Also a weighted egg HATCH: rarer
-- pets are less likely (weight = 1 / rarity^2), deterministic given the injected rand.

local PetRules = {}

-- Multiplier for `key` from an equipped pet row (nil = no pet). 1.0 if the pet doesn't boost this key.
function PetRules.abilityMult(pet: any, key: string): number
	local ability: any = if type(pet) == "table" then pet.ability else nil
	if ability ~= nil and ability.type == key then
		return 1 + ability.value
	end
	return 1
end

-- Weighted hatch from a list of pet rows; rarer (higher rarity) => lower weight. rand()->[0,1).
function PetRules.hatch(list: { any }, rand: () -> number): string?
	local total = 0
	for _, p in list do
		total += 1 / (p.rarity * p.rarity)
	end
	if total <= 0 then
		return nil
	end
	local r = rand() * total
	local acc = 0
	for _, p in list do
		acc += 1 / (p.rarity * p.rarity)
		if r <= acc then
			return p.id
		end
	end
	return list[#list].id
end

-- The best (highest-value) owned pet id, so buying/hatching can auto-equip the strongest. `getFn` maps
-- id -> pet row.
function PetRules.bestOwned(owned: { [string]: boolean }, getFn: (string) -> any): string?
	local bestId: string? = nil
	local bestVal = -1
	for id, has in owned do
		if has then
			local p = getFn(id)
			if p and p.ability.value > bestVal then
				bestVal = p.ability.value
				bestId = id
			end
		end
	end
	return bestId
end

return PetRules
