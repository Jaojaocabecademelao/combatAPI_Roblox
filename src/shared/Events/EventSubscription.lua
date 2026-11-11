local Subscription = {}
Subscription.__index = Subscription
function Subscription.new(bus, id)
	return setmetatable({ _bus = bus, _id = id, _connected = true }, Subscription)
end
function Subscription:Disconnect()
	if not self._connected then return false end
	self._connected = false
	local bus = self._bus
	self._bus = nil
	return bus ~= nil and bus:_Disconnect(self._id) or false
end
function Subscription:IsConnected() return self._connected and self._bus ~= nil and not self._bus.Destroyed end
function Subscription:GetId() return self._id end
return Subscription
