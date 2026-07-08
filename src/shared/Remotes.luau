--!strict
-- Remotes: the ONLY channel between client and server. Requiring this module returns a table
-- of remote references. The server creates the instances; the client waits for them.
--
-- THE AUTHORITY BOUNDARY LIVES HERE. Everything a client can ask the server to do is one of
-- these remotes. There is no other way for the client to change game state. Each client->server
-- remote is validated on the server (see BloomlyServer). Read this list top to bottom to see the
-- entire surface a cheater could poke at:
--
--   Client -> Server (intents; server validates then acts):
--     Plant     (RemoteEvent)    : "I want to plant seedId in plotIndex"
--     Harvest   (RemoteEvent)    : "I want to harvest plotIndex"
--     SellAll   (RemoteEvent)    : "I want to sell my whole inventory to the NPC"
--     GetState  (RemoteFunction) : "Send me my current state" (called once on join)
--
--   Server -> Client (truth; client just renders it):
--     StateUpdate (RemoteEvent)  : "Here is your authoritative farm state"

local RunService = game:GetService("RunService")

local Bloomly = script.Parent -- the ReplicatedStorage.Bloomly folder

-- SelectSeed (client->server): "the seed I want the next Plant prompt to plant". Purely a preference;
-- the actual planting is a server-side ProximityPrompt handler (see BloomlyServer).
-- Notify (server->client): a short dialogue/toast line (quest accepted/completed, etc.).
-- Trade remotes (block 14b): direct player-to-player trade, both online, same server.
--   TradeAction (client->server): { do="request"/"respond"/"offer"/"unoffer"/"confirm"/"cancel", ... }
--   TradeUpdate (server->client): the live trade window state (partner, both offers, confirms) or nil
local EVENT_NAMES = { "Plant", "Harvest", "SellAll", "StateUpdate", "SelectSeed", "Notify", "TradeAction", "TradeUpdate" }
local FUNCTION_NAMES = { "GetState", "GetCodex" }

-- The server (and only the server) creates the folder + instances. It is safe to run this on
-- require because the server requires Remotes during startup, before any client can call in.
if RunService:IsServer() then
	local folder = Bloomly:FindFirstChild("Remotes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = Bloomly
	end
	for _, name in EVENT_NAMES do
		if not folder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
	end
	for _, name in FUNCTION_NAMES do
		if not folder:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
	end
end

-- Both sides resolve the same references. WaitForChild covers the client joining before the
-- server has finished replicating the instances.
local folder = Bloomly:WaitForChild("Remotes")

local Remotes = {
	Plant = folder:WaitForChild("Plant") :: RemoteEvent,
	Harvest = folder:WaitForChild("Harvest") :: RemoteEvent,
	SellAll = folder:WaitForChild("SellAll") :: RemoteEvent,
	StateUpdate = folder:WaitForChild("StateUpdate") :: RemoteEvent,
	SelectSeed = folder:WaitForChild("SelectSeed") :: RemoteEvent,
	Notify = folder:WaitForChild("Notify") :: RemoteEvent,
	TradeAction = folder:WaitForChild("TradeAction") :: RemoteEvent,
	TradeUpdate = folder:WaitForChild("TradeUpdate") :: RemoteEvent,
	GetState = folder:WaitForChild("GetState") :: RemoteFunction,
	GetCodex = folder:WaitForChild("GetCodex") :: RemoteFunction,
}

return Remotes
