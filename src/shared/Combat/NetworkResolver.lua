local NetworkComponent = require(script.Parent.NetworkComponent)
local NetworkProfile = require(script.Parent.NetworkProfile)
local NetworkAdapter = require(script.Parent.NetworkAdapter)
local NetworkPeer = require(script.Parent.NetworkPeer)
local NetworkMessage = require(script.Parent.NetworkMessage)
local NetworkSnapshot = require(script.Parent.NetworkSnapshot)
local NetworkResult = require(script.Parent.NetworkResult)
local NetworkEvent = require(script.Parent.NetworkEvent)
local NetworkChannel = require(script.Parent.NetworkChannel)
local Sequence = require(script.Parent.NetworkSequence)

local Resolver = {}
Resolver.__index = Resolver
local validTypes = {}
for _, value in pairs(NetworkMessage.Type) do validTypes[value] = true end
local validChannels = {}
for _, value in pairs(NetworkChannel) do validChannels[value] = true end
local function validFrame(frame) return type(frame) == "number" and frame >= 0 and frame < math.huge and frame % 1 == 0 end
local channelForType = {
	[NetworkMessage.Type.Input] = NetworkChannel.Input,
	[NetworkMessage.Type.Snapshot] = NetworkChannel.Snapshot,
	[NetworkMessage.Type.Acknowledgement] = NetworkChannel.Sync,
	[NetworkMessage.Type.Synchronization] = NetworkChannel.Sync,
	[NetworkMessage.Type.Command] = NetworkChannel.Simulation,
	[NetworkMessage.Type.Event] = NetworkChannel.Events,
}

function Resolver.new(world, options)
	options = options or {}
	local self = setmetatable({ World = world, Profile = options.Profile or NetworkProfile.new(), Profiles = {}, Adapters = {}, Peers = {}, Components = {}, LastSequences = {}, Events = {}, Results = {}, Incoming = {}, Outgoing = {}, CurrentFrame = 0, Metrics = { Sent = 0, Received = 0, Rejected = 0, Duplicates = 0, OutOfOrder = 0 } }, Resolver)
	self:RegisterProfile(self.Profile)
	for id, adapter in pairs(options.Adapters or {}) do self:RegisterAdapter(id, adapter) end
	return self
end
function Resolver:_result(kind, data)
	data = data or {}; data.Type, data.Accepted = kind, kind == NetworkResult.Type.Success
	local result = NetworkResult.new(data); table.insert(self.Results, result); return result
end
function Resolver:_emit(kind, data)
	data.Type = kind
	local event = NetworkEvent.new(data); table.insert(self.Events, event); return event
end
function Resolver:RegisterProfile(profile)
	if getmetatable(profile) ~= NetworkProfile then return false end
	self.Profiles[profile.Channel] = profile; return true
end
function Resolver:GetProfile(channel) return self.Profiles[channel] end
function Resolver:RegisterAdapter(id, adapter)
	if type(id) ~= "string" or type(adapter) ~= "table" or type(adapter.Call) ~= "function" then return false end
	self.Adapters[id] = adapter; return true
end
function Resolver:GetAdapterDefinition(id) return self.Adapters[id] end
function Resolver:RegisterPeer(peer)
	if getmetatable(peer) ~= NetworkPeer then return self:_result(NetworkResult.Type.InvalidPeer) end
	if self.Peers[peer.Id] then return self:_result(NetworkResult.Type.AlreadyRegistered, { PeerId = peer.Id }) end
	self.Peers[peer.Id] = peer
	return self:_result(NetworkResult.Type.Success, { PeerId = peer.Id })
end
function Resolver:GetPeer(peerId) return self.Peers[peerId] end
function Resolver:UnregisterPeer(peerId)
	if not self.Peers[peerId] then return self:_result(NetworkResult.Type.UnknownPeer, { PeerId = peerId }) end
	self.Peers[peerId] = nil; self.LastSequences[peerId] = nil
	return self:_result(NetworkResult.Type.Success, { PeerId = peerId })
end
function Resolver:Connect(peerId, options)
	local peer = self.Peers[peerId]
	if not peer then return self:_result(NetworkResult.Type.UnknownPeer, { PeerId = peerId }) end
	if peer.State == NetworkPeer.State.Connected then return self:_result(NetworkResult.Type.AlreadyConnected, { PeerId = peerId }) end
	peer.State = NetworkPeer.State.Connecting
	local adapter = options and (options.Adapter or self.Adapters[options.AdapterId]) or self.Adapters.Mock
	if adapter and not adapter:Call("Register", peer) then peer.State = NetworkPeer.State.Disconnected; return self:_result(NetworkResult.Type.AdapterRejected, { PeerId = peerId }) end
	peer.State = NetworkPeer.State.Connected
	self:_emit(NetworkEvent.Type.Connected, { PeerId = peerId }); return self:_result(NetworkResult.Type.Success, { PeerId = peerId })
end
function Resolver:Disconnect(peerId, options)
	local peer = self.Peers[peerId]
	if not peer then return self:_result(NetworkResult.Type.UnknownPeer, { PeerId = peerId }) end
	peer.State = NetworkPeer.State.Disconnecting
	local adapter = options and (options.Adapter or self.Adapters[options.AdapterId]) or self.Adapters.Mock
	if adapter then adapter:Call("Unregister", peer) end
	peer.State = NetworkPeer.State.Disconnected
	self:_emit(NetworkEvent.Type.Disconnected, { PeerId = peerId }); return self:_result(NetworkResult.Type.Success, { PeerId = peerId })
end
function Resolver:_validate(message, peerId)
	if getmetatable(message) ~= NetworkMessage then return NetworkResult.Type.InvalidMessage end
	if message.Version ~= NetworkMessage.Version then return NetworkResult.Type.InvalidMessage end
	if not validChannels[message.Channel] or not validTypes[message.Type]
		or channelForType[message.Type] ~= message.Channel then return NetworkResult.Type.InvalidChannel end
	if peerId ~= nil and not self.Peers[peerId] then return NetworkResult.Type.UnknownPeer end
	if not validFrame(message.SimulationFrame) then return NetworkResult.Type.InvalidFrame end
	if message.Sequence ~= nil and (type(message.Sequence) ~= "number" or message.Sequence < 0 or message.Sequence % 1 ~= 0) then return NetworkResult.Type.InvalidSequence end
	return nil
end
function Resolver:_sequenceDecision(message, peerId)
	if message.Sequence == nil then return nil end
	self.LastSequences[peerId] = self.LastSequences[peerId] or {}
	local previous = self.LastSequences[peerId][message.Channel]
	if previous == nil then self.LastSequences[peerId][message.Channel] = message.Sequence; return nil end
	local sequence = Sequence.new(previous)
	if sequence:Compare(message.Sequence) >= 0 then return message.Sequence == previous and NetworkResult.Type.Duplicate or NetworkResult.Type.OutOfOrder end
	self.LastSequences[peerId][message.Channel] = message.Sequence
	return nil
end
function Resolver:Send(peerId, message, options)
	local peer = self.Peers[peerId]
	if not peer then return self:_result(NetworkResult.Type.UnknownPeer) end
	if peer.State ~= NetworkPeer.State.Connected then return self:_result(NetworkResult.Type.NotConnected, { PeerId = peerId }) end
	local failure = self:_validate(message, peerId)
	if failure then return self:_result(failure, { PeerId = peerId }) end
	local adapter = options and (options.Adapter or self.Adapters[options.AdapterId]) or self.Adapters.Mock
	if not adapter then return self:_result(NetworkResult.Type.InvalidPeer, { PeerId = peerId }) end
	if not adapter:Call("Send", peer, message) then return self:_result(NetworkResult.Type.SendFailed, { PeerId = peerId }) end
	self.Outgoing[peerId] = self.Outgoing[peerId] or {}; table.insert(self.Outgoing[peerId], message)
	self.Metrics.Sent += 1
	self:_emit(NetworkEvent.Type.MessageSent, { PeerId = peerId, Channel = message.Channel, Sequence = message.Sequence, SimulationFrame = message.SimulationFrame, MessageType = message.Type })
	return self:_result(NetworkResult.Type.Success, { PeerId = peerId, Message = message })
end
function Resolver:Broadcast(message, options)
	local count = 0
	local peerIds = {}
	for peerId in pairs(self.Peers) do table.insert(peerIds, peerId) end
	table.sort(peerIds)
	for _, peerId in ipairs(peerIds) do
		local peer = self.Peers[peerId]
		if peer.State == NetworkPeer.State.Connected then
			local result = self:Send(peerId, message, options)
			if result.Accepted then count += 1 end
		end
	end
	return self:_result(count > 0 and NetworkResult.Type.Success or NetworkResult.Type.NotConnected, { Count = count, Message = message })
end
function Resolver:Receive(peerId, message)
	local peer = self.Peers[peerId]
	if not peer then return self:_result(NetworkResult.Type.UnknownPeer, { PeerId = peerId }) end
	local failure = self:_validate(message, peerId) or self:_sequenceDecision(message, peerId)
	if failure then
		self.Metrics.Rejected += 1
		if failure == NetworkResult.Type.Duplicate then self.Metrics.Duplicates += 1 end
		if failure == NetworkResult.Type.OutOfOrder then self.Metrics.OutOfOrder += 1 end
		self:_emit(NetworkEvent.Type.SequenceRejected, { PeerId = peerId, Sequence = message.Sequence, Channel = message.Channel, MessageType = message.Type, Result = failure })
		return self:_result(failure, { PeerId = peerId })
	end
	self.Incoming[peerId] = self.Incoming[peerId] or {}; table.insert(self.Incoming[peerId], message)
	self.Metrics.Received += 1
	self:_emit(NetworkEvent.Type.MessageReceived, { PeerId = peerId, Sequence = message.Sequence, SimulationFrame = message.SimulationFrame, Channel = message.Channel, MessageType = message.Type })
	local eventType = message.Type == NetworkMessage.Type.Input and NetworkEvent.Type.InputReceived or message.Type == NetworkMessage.Type.Snapshot and NetworkEvent.Type.SnapshotReceived or message.Type == NetworkMessage.Type.Synchronization and NetworkEvent.Type.SynchronizationReceived
	if eventType then self:_emit(eventType, { PeerId = peerId, Sequence = message.Sequence, SimulationFrame = message.SimulationFrame, Channel = message.Channel, MessageType = message.Type }) end
	return self:_result(NetworkResult.Type.Success, { PeerId = peerId, Message = message })
end
function Resolver:Acknowledge(peerId, sequence, frame)
	if not self.Peers[peerId] then return self:_result(NetworkResult.Type.UnknownPeer) end
	if type(sequence) ~= "number" or not validFrame(frame) then return self:_result(NetworkResult.Type.AckFailed, { PeerId = peerId }) end
	self:_emit(NetworkEvent.Type.Acknowledged, { PeerId = peerId, Sequence = sequence, SimulationFrame = frame })
	return self:_result(NetworkResult.Type.Success, { PeerId = peerId, Sequence = sequence, SimulationFrame = frame })
end
function Resolver:CreateSnapshot(data) return NetworkSnapshot.new(data) end
function Resolver:GetIncoming(peerId) return self.Incoming[peerId] or {} end
function Resolver:GetOutgoing(peerId) return self.Outgoing[peerId] or {} end
function Resolver:GetLastReceivedSequence(peerId, channel) return self.LastSequences[peerId] and self.LastSequences[peerId][channel] end
function Resolver:GetConnectionState(peerId) local peer = self.Peers[peerId]; return peer and peer.State end
function Resolver:GetEvents() return table.clone(self.Events) end
function Resolver:GetResults() return table.clone(self.Results) end
function Resolver:GetMetrics()
	return {
		Sent = self.Metrics.Sent,
		Received = self.Metrics.Received,
		Rejected = self.Metrics.Rejected,
		Duplicates = self.Metrics.Duplicates,
		OutOfOrder = self.Metrics.OutOfOrder,
	}
end
function Resolver:Clear() self.Events, self.Results = {}, {}; return self end
return Resolver
