local Result = {}
Result.__index = Result
Result.Type = table.freeze({ Success = "Success", InvalidMessage = "InvalidMessage", InvalidChannel = "InvalidChannel", InvalidPeer = "InvalidPeer", InvalidSequence = "InvalidSequence", InvalidFrame = "InvalidFrame", NotConnected = "NotConnected", AlreadyConnected = "AlreadyConnected", AlreadyRegistered = "AlreadyRegistered", UnknownPeer = "UnknownPeer", AdapterRejected = "AdapterRejected", SendFailed = "SendFailed", ReceiveFailed = "ReceiveFailed", AckFailed = "AckFailed", SnapshotFailed = "SnapshotFailed", InvalidPayload = "InvalidPayload", Duplicate = "Duplicate", OutOfOrder = "OutOfOrder" })
function Result.new(data) return setmetatable(data, Result) end
return Result
