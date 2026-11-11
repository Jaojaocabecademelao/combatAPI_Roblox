local Component = require(script.Parent.Parent.Core.Component)
local NetworkComponent = setmetatable({}, Component)
NetworkComponent.__index = NetworkComponent
function NetworkComponent.new(peerId)
	local self = setmetatable(Component.new(), NetworkComponent)
	self.EntityId, self.PeerId, self.NetworkId = nil, peerId, nil
	self.LastReceivedFrame, self.LastSentFrame, self.LastAcknowledgedFrame = nil, nil, nil
	self.LastReceivedSequence, self.LastSentSequence = nil, nil
	self.ConnectionState = "Disconnected"
	return self
end
function NetworkComponent:Attach(entity) self.Entity, self.EntityId = entity, entity.Id; return self end
function NetworkComponent:Detach() self.Entity, self.EntityId = nil, nil end
return NetworkComponent
