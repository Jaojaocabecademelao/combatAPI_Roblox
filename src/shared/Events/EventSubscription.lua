--!strict

local Types = require(script.Parent.Parent.CombatAPITypes)

type EventSubscriptionType = Types.EventSubscription

export type Connection = {
	Destroyed: boolean,
	_Disconnect: (self: any, id: number) -> boolean,
}

type Subscription = EventSubscriptionType & {
	_bus: Connection?,
	_id: number,
	_connected: boolean,
}

local Subscription = {}
Subscription.__index = Subscription

export type Instance = Subscription

function Subscription.new(bus: Connection, id: number): Subscription
	return setmetatable({ _bus = bus, _id = id, _connected = true }, Subscription) :: Subscription
end

function Subscription.Disconnect(self: Subscription): boolean
	if not self._connected then return false end
	self._connected = false
	local bus = self._bus
	self._bus = nil
	return bus ~= nil and bus:_Disconnect(self._id) or false
end

function Subscription.IsConnected(self: Subscription): boolean
	return self._connected and self._bus ~= nil and not self._bus.Destroyed
end

function Subscription.GetId(self: Subscription): number
	return self._id
end

return Subscription
