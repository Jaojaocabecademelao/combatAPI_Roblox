local Peer = {}
Peer.__index = Peer
Peer.Role = table.freeze({ Client = "Client", Server = "Server", Peer = "Peer" })
Peer.State = table.freeze({ Disconnected = "Disconnected", Connecting = "Connecting", Connected = "Connected", Disconnecting = "Disconnecting" })
function Peer.new(id, role)
	assert(type(id) == "string" or type(id) == "number", "NetworkPeer id is required")
	return setmetatable({ Id = id, Role = role or Peer.Role.Peer, State = Peer.State.Disconnected }, Peer)
end
return Peer
