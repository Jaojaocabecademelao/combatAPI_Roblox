local NetworkAdapter = require(script.Parent.NetworkAdapter)
local NetworkMessage = require(script.Parent.NetworkMessage)

local Adapter = {}
Adapter.__index = Adapter

local function defaultPeerId(player)
	return player and (player.UserId or player.Name)
end

function Adapter.new(remoteEvent, options)
	options = options or {}
	assert(type(options) == "table", "RobloxRemoteEventAdapter options must be a table")
	local role = options.Role or "Client"
	assert(role == "Client" or role == "Server", "RobloxRemoteEventAdapter Role must be Client or Server")
	assert((type(remoteEvent) == "table" or type(remoteEvent) == "userdata"),
		"RobloxRemoteEventAdapter requires a RemoteEvent-like object")
	if role == "Client" then
		assert(type(remoteEvent.FireServer) == "function",
			"Client RobloxRemoteEventAdapter requires FireServer")
	else
		assert(type(remoteEvent.FireClient) == "function",
			"Server RobloxRemoteEventAdapter requires FireClient")
	end
	local getPeerId = options.GetPeerId or defaultPeerId
	local onReceive = options.OnReceive
	local onInvalidMessage = options.OnInvalidMessage
	assert(type(getPeerId) == "function", "RobloxRemoteEventAdapter GetPeerId must be a function")
	assert(type(onReceive) == "function", "RobloxRemoteEventAdapter OnReceive must be a function")
	assert(onInvalidMessage == nil or type(onInvalidMessage) == "function",
		"RobloxRemoteEventAdapter OnInvalidMessage must be a function or nil")

	local self = setmetatable({
		RemoteEvent = remoteEvent,
		Role = role,
		GetPeerId = getPeerId,
		OnReceive = onReceive,
		OnInvalidMessage = onInvalidMessage,
		Connection = nil,
	}, Adapter)

	local callbacks = {
		Send = function(peer, message)
			if self.Role == "Server" then
				local player = options.GetPlayer and options.GetPlayer(peer.Id) or peer.Player
				if not player then return false end
				self.RemoteEvent:FireClient(player, message)
			else
				self.RemoteEvent:FireServer(message)
			end
			return true
		end,
	}
	self.Transport = NetworkAdapter.new(options.Id or "RobloxRemoteEvent", callbacks)
	return self
end

function Adapter:_reportInvalidMessage(message, detail, player)
	local peerId = player and self.GetPeerId(player) or nil
	if self.OnInvalidMessage then
		self.OnInvalidMessage(peerId, message, tostring(detail))
		return
	end
	warn(("RobloxRemoteEventAdapter rejected malformed message from peer %s: %s")
		:format(tostring(peerId), tostring(detail)))
end

function Adapter:Start()
	if self.Connection then return false, "AlreadyStarted" end
	if self.Role == "Server" then
		assert(self.RemoteEvent.OnServerEvent ~= nil, "RemoteEvent is missing OnServerEvent")
		self.Connection = self.RemoteEvent.OnServerEvent:Connect(function(player, message)
			local ok, normalized = pcall(NetworkMessage.new, message)
			if ok then
				self.OnReceive(self.GetPeerId(player), normalized, player)
			else
				self:_reportInvalidMessage(message, normalized, player)
			end
		end)
	else
		assert(self.RemoteEvent.OnClientEvent ~= nil, "RemoteEvent is missing OnClientEvent")
		self.Connection = self.RemoteEvent.OnClientEvent:Connect(function(message)
			local ok, normalized = pcall(NetworkMessage.new, message)
			if ok then
				self.OnReceive(nil, normalized)
			else
				self:_reportInvalidMessage(message, normalized)
			end
		end)
	end
	return true
end

function Adapter:Stop()
	if not self.Connection then return false end
	self.Connection:Disconnect()
	self.Connection = nil
	return true
end

function Adapter:Call(method, ...)
	return self.Transport:Call(method, ...)
end

return Adapter
