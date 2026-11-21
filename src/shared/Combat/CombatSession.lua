local Serializer = require(script.Parent.Parent.Simulation.StateSerializer)

local Session = {}
Session.__index = Session
Session.Version = 1
Session.State = table.freeze({
	Waiting = "Waiting",
	Predicting = "Predicting",
	Confirmed = "Confirmed",
	Reconciliating = "Reconciliating",
	RollingBack = "RollingBack",
})

local validPeerId = function(value)
	return (type(value) == "string" and value ~= "")
		or (type(value) == "number" and value == value
			and value >= 0 and value < math.huge and value % 1 == 0)
end

local validFrame = function(value)
	return type(value) == "number" and value == value
		and value >= 0 and value < math.huge and value % 1 == 0
end

function Session.new(world, options)
	assert(world and type(world.GetRollbackResolver) == "function",
		"CombatSession.new requires a World")
	options = options or {}
	assert(type(options) == "table", "CombatSession.new expects an options table")
	local predictionHorizon = options.PredictionHorizon or 8
	assert(validFrame(predictionHorizon) and predictionHorizon >= 1,
		"CombatSession PredictionHorizon must be a positive integer")
	return setmetatable({
		World = world,
		PredictionHorizon = predictionHorizon,
		ConfirmedFrame = options.ConfirmedFrame or 0,
		State = Session.State.Waiting,
		Peers = {},
		Inputs = {},
		LastAcceptedSequence = {},
		Divergences = {},
		Events = {},
	}, Session)
end

function Session:RegisterPeer(peerId)
	assert(validPeerId(peerId), "CombatSession peer ID is invalid")
	assert(self.Peers[peerId] == nil, "CombatSession peer already registered")
	self.Peers[peerId] = { PeerId = peerId, Connected = true }
	self.LastAcceptedSequence[peerId] = nil
	return true
end

function Session:DisconnectPeer(peerId)
	if not validPeerId(peerId) or not self.Peers[peerId] then return false end
	self.Peers[peerId].Connected = false
	for key, input in pairs(self.Inputs) do
		if input.PeerId == peerId then self.Inputs[key] = nil end
	end
	return true
end

function Session:IsPeerConnected(peerId)
	local peer = self.Peers[peerId]
	return peer ~= nil and peer.Connected == true
end

function Session:ProposeInput(peerId, entityId, frame, sequence, input)
	if not self:IsPeerConnected(peerId) then return nil, "PeerDisconnected" end
	assert(validFrame(frame), "CombatSession input frame is invalid")
	assert(sequence == nil or (validFrame(sequence)),
		"CombatSession input sequence is invalid")
	assert(validPeerId(entityId), "CombatSession entity ID is invalid")
	if sequence ~= nil then
		local previous = self.LastAcceptedSequence[peerId]
		if previous ~= nil then
			if sequence == previous then return nil, "DuplicateInput" end
			if sequence < previous then return nil, "OutOfOrderInput" end
		end
	end
	local key = tostring(peerId) .. ":" .. tostring(entityId) .. ":" .. tostring(frame)
	if self.Inputs[key] then return nil, "DuplicateInput" end
	local lead = frame - self.ConfirmedFrame
	if lead > self.PredictionHorizon then return nil, "FutureInputBeyondPredictionHorizon" end
	if frame < self.ConfirmedFrame then return nil, "LateInputAlreadyConfirmed" end
	local cloned = Serializer.CloneSerializable(input or {})
	self.Inputs[key] = Serializer.Freeze({
		PeerId = peerId,
		EntityId = entityId,
		Frame = frame,
		Sequence = sequence,
		Input = cloned,
		Status = "Proposed",
	})
	self.State = frame > self.ConfirmedFrame
		and Session.State.Predicting or Session.State.Waiting
	return Serializer.CloneSerializable(cloned)
end

function Session:AcceptInput(peerId, entityId, frame)
	local key = tostring(peerId) .. ":" .. tostring(entityId) .. ":" .. tostring(frame)
	local input = self.Inputs[key]
	if not input then return false, "InputNotFound" end
	local accepted = {}
	for name, value in pairs(input) do accepted[name] = value end
	accepted.Status = "Accepted"
	self.Inputs[key] = table.freeze(accepted)
	if input.Sequence ~= nil then
		self.LastAcceptedSequence[peerId] = input.Sequence
	end
	table.insert(self.Events, table.freeze({
		Type = "InputAccepted",
		PeerId = peerId,
		EntityId = entityId,
		Frame = frame,
		Sequence = input.Sequence,
	}))
	return true
end

function Session:RejectInput(peerId, entityId, frame, reason)
	local key = tostring(peerId) .. ":" .. tostring(entityId) .. ":" .. tostring(frame)
	if not self.Inputs[key] then return false, "InputNotFound" end
	self.Inputs[key] = nil
	table.insert(self.Events, table.freeze({
		Type = "InputRejected",
		PeerId = peerId,
		EntityId = entityId,
		Frame = frame,
		Reason = reason or "Rejected",
	}))
	return true
end

function Session:ConfirmFrame(frame)
	assert(validFrame(frame), "CombatSession confirmed frame is invalid")
	if frame < self.ConfirmedFrame then return false, "ConfirmedFrameMovedBackward" end
	self.ConfirmedFrame = frame
	for key, input in pairs(self.Inputs) do
		if input.Frame <= frame then self.Inputs[key] = nil end
	end
	self.State = Session.State.Confirmed
	table.insert(self.Events, table.freeze({
		Type = "FrameConfirmed",
		Frame = frame,
	}))
	return true
end

function Session:Reconcile(frame, hasDivergence, details)
	assert(validFrame(frame), "CombatSession reconcile frame is invalid")
	self.State = hasDivergence
		and Session.State.Reconciliating or Session.State.Confirmed
	if hasDivergence then
		local copy = Serializer.CloneSerializable(details or {})
		table.insert(self.Divergences, table.freeze({
			Frame = frame,
			Details = Serializer.Freeze(copy),
		}))
		while #self.Divergences > 128 do table.remove(self.Divergences, 1) end
	end
	return hasDivergence
end

function Session:RequestRollback(frame, reason)
	assert(validFrame(frame), "CombatSession rollback frame is invalid")
	local rollback = self.World:GetRollbackResolver()
	if not rollback then return nil, "RollbackResolverUnavailable" end
	local restored = frame <= self.ConfirmedFrame
		and frame or self.ConfirmedFrame
	self.State = Session.State.RollingBack
	local result = rollback:RequestRollback(
		self.World,
		restored,
		frame,
		reason or "AuthoritativeCorrection",
		"World"
	)
	return result
end

function Session:GetStatus()
	local accepted = {}
	for _, input in pairs(self.Inputs) do
		table.insert(accepted, Serializer.CloneSerializable(input))
	end
	table.sort(accepted, function(left, right)
		if left.Frame ~= right.Frame then return left.Frame < right.Frame end
		return tostring(left.PeerId) < tostring(right.PeerId)
	end)
	return table.freeze({
		Version = Session.Version,
		State = self.State,
		ConfirmedFrame = self.ConfirmedFrame,
		PredictionHorizon = self.PredictionHorizon,
		PendingInputs = table.freeze(accepted),
		Divergences = table.freeze(Serializer.CloneSerializable(self.Divergences)),
	})
end

function Session:Capture()
	return Serializer.Freeze({
		Version = Session.Version,
		ConfirmedFrame = self.ConfirmedFrame,
		PredictionHorizon = self.PredictionHorizon,
		State = self.State,
		Peers = Serializer.CloneSerializable(self.Peers),
		Inputs = Serializer.CloneSerializable(self.Inputs),
		LastAcceptedSequence = Serializer.CloneSerializable(self.LastAcceptedSequence),
		Divergences = Serializer.CloneSerializable(self.Divergences),
		Events = Serializer.CloneSerializable(self.Events),
	})
end

function Session:Restore(snapshot)
	assert(type(snapshot) == "table" and snapshot.Version == Session.Version,
		"Unsupported CombatSession snapshot")
	self.ConfirmedFrame = snapshot.ConfirmedFrame
	self.PredictionHorizon = snapshot.PredictionHorizon
	self.State = snapshot.State
	self.Peers = Serializer.CloneSerializable(snapshot.Peers)
	self.Inputs = Serializer.CloneSerializable(snapshot.Inputs)
	self.LastAcceptedSequence = Serializer.CloneSerializable(snapshot.LastAcceptedSequence)
	self.Divergences = Serializer.CloneSerializable(snapshot.Divergences)
	self.Events = Serializer.CloneSerializable(snapshot.Events)
	return self
end

return Session
