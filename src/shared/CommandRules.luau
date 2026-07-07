--!strict
-- CommandRules: PURE parsing + help-text generation for chat commands (block 16). The server's Chatted
-- handler calls parse() then routes the verb to a validated server function -- this module never touches
-- game state, so it is fully VPS-tested. `/goto` target resolution is here too (pure string->place).

local CommandRules = {}

-- Parse a chat line. Returns { cmd, args } for a "/verb a b c" line, or nil if it isn't a command.
function CommandRules.parse(text: string): { cmd: string, args: { string } }?
	if type(text) ~= "string" or text:sub(1, 1) ~= "/" then
		return nil
	end
	local parts: { string } = {}
	for w in text:gmatch("%S+") do
		table.insert(parts, w)
	end
	if #parts == 0 then
		return nil
	end
	local cmd = parts[1]:sub(2):lower()
	table.remove(parts, 1)
	return { cmd = cmd, args = parts }
end

-- Build the /help text from the command registry.
function CommandRules.helpText(list: { any }): string
	local lines = { "📖 Bloomly Commands:" }
	for _, c in list do
		local usage = "/" .. c.name .. (c.args and (" " .. c.args) or "")
		table.insert(lines, usage .. " — " .. c.desc)
	end
	return table.concat(lines, "\n")
end

-- Resolve a /goto target string to a place. Returns ("plaza"|"harbor"|"island", islandIndex?) or nil.
function CommandRules.resolveGoto(target: string?): (string?, number?)
	if not target then
		return nil, nil
	end
	local t = target:lower()
	if t == "plaza" or t == "home" or t == "spawn" then
		return "plaza", nil
	elseif t == "harbor" or t == "harbour" or t == "dock" then
		return "harbor", nil
	end
	local n = tonumber(t)
	if n and n >= 1 and n <= 11 then
		return "island", math.floor(n)
	end
	return nil, nil
end

return CommandRules
