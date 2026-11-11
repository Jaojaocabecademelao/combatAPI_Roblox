local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Adapter = require(Shared.Combat.RobloxRemoteEventAdapter)
local NetworkPeer = require(Shared.Combat.NetworkPeer)
local NetworkMessage = require(Shared.Combat.NetworkMessage)
local NetworkChannel = require(Shared.Combat.NetworkChannel)

local assertions = 0
local function check(value, message)
	assert(value, message or ("Remote adapter assertion " .. tostring(assertions + 1) .. " failed"))
	assertions += 1
end

local function signal()
	local connected
	return {
		Connect = function(_, callback)
			connected = callback
			return {
				Disconnect = function()
					connected = nil
				end,
			}
		end,
		Fire = function(_, ...)
			if connected then connected(...) end
		end,
	}
end

local clientSent
local clientRemote = {
	FireServer = function(_, message) clientSent = message end,
	OnClientEvent = signal(),
}
local clientReceived
local clientInvalid
local clientAdapter = Adapter.new(clientRemote, {
	Role = "Client",
	OnReceive = function(_, message) clientReceived = message end,
	OnInvalidMessage = function(peerId, rawMessage, detail)
		clientInvalid = { PeerId = peerId, Message = rawMessage, Detail = detail }
	end,
})
local message = NetworkMessage.new({
	Type = NetworkMessage.Type.Input,
	Channel = NetworkChannel.Input,
	SimulationFrame = 1,
	Payload = {},
})
check(clientAdapter:Call("Send", NetworkPeer.new("server", NetworkPeer.Role.Server), message),
	"Client transport sends through FireServer")
check(clientSent == message, "Client transport preserves the message")
check(clientAdapter:Start(), "Client transport starts")
clientRemote.OnClientEvent:Fire(message)
check(clientReceived ~= nil
	and clientReceived ~= message
	and clientReceived.Type == message.Type
	and clientReceived.Channel == message.Channel
	and clientReceived.SimulationFrame == message.SimulationFrame,
	"Client transport validates and reconstructs messages through OnClientEvent")
local malformedClientMessage = {
	Version = NetworkMessage.Version + 1,
	Type = NetworkMessage.Type.Input,
	Channel = NetworkChannel.Input,
	SimulationFrame = 1,
}
clientRemote.OnClientEvent:Fire(malformedClientMessage)
check(clientInvalid and clientInvalid.PeerId == nil
	and clientInvalid.Message == malformedClientMessage
	and string.find(clientInvalid.Detail, "unsupported", 1, true),
	"Malformed client messages are reported instead of silently discarded")
check(clientAdapter:Stop(), "Client transport stops")

local serverSent
local serverRemote = {
	FireClient = function(_, player, payload)
		serverSent = { Player = player, Message = payload }
	end,
	OnServerEvent = signal(),
}
local player = { UserId = 42 }
local serverReceived, serverInvalid
local serverAdapter = Adapter.new(serverRemote, {
	Role = "Server",
	GetPlayer = function(peerId)
		return peerId == 42 and player or nil
	end,
	GetPeerId = function(value) return value.UserId end,
	OnReceive = function() serverReceived = true end,
	OnInvalidMessage = function(peerId, rawMessage, detail)
		serverInvalid = { PeerId = peerId, Message = rawMessage, Detail = detail }
	end,
})
check(serverAdapter:Call("Send", NetworkPeer.new(42, NetworkPeer.Role.Client), message),
	"Server transport sends through FireClient")
check(serverSent.Player == player and serverSent.Message == message,
	"Server transport resolves the peer player")
check(serverAdapter:Start(), "Server transport starts")
local malformedServerMessage = {
	Version = NetworkMessage.Version + 1,
	Type = NetworkMessage.Type.Input,
	Channel = NetworkChannel.Input,
	SimulationFrame = 1,
}
serverRemote.OnServerEvent:Fire(player, malformedServerMessage)
check(serverInvalid and serverInvalid.PeerId == player.UserId
	and serverInvalid.Message == malformedServerMessage
	and string.find(serverInvalid.Detail, "unsupported", 1, true)
	and not serverReceived,
	"Server reports malformed payloads with the transport-derived peer ID")
check(not pcall(function()
		Adapter.new({ FireServer = function() end }, { Role = "Server", OnReceive = function() end })
	end), "Server transport does not require FireServer")
check(not pcall(function()
		Adapter.new({ FireClient = function() end }, { Role = "Client", OnReceive = function() end })
	end), "Client transport does not require FireClient")
check(serverAdapter:Stop(), "Server transport stops")

print(("CombatRobloxRemoteEventAdapterTest: PASS (%d assertions)"):format(assertions))
