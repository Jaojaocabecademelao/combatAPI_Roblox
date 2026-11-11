local Adapter = {}
Adapter.__index = Adapter
function Adapter.new(adapterId, callbacks)
	assert(type(adapterId) == "string" and adapterId ~= "", "NetworkAdapter id is required")
	callbacks = callbacks or {}
	return setmetatable({ Id = adapterId, Send = callbacks.Send, Broadcast = callbacks.Broadcast, Receive = callbacks.Receive, Register = callbacks.Register, Unregister = callbacks.Unregister, IsConnected = callbacks.IsConnected, GetPeer = callbacks.GetPeer }, Adapter)
end
function Adapter:Validate(message) return type(message) == "table" and type(message.Type) == "string" end
function Adapter:Call(method, ...) if self[method] then return self[method](...) ~= false end; return true end
return Adapter
