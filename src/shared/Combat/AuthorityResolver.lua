local Component = require(script.Parent.AuthorityComponent)
local Profile = require(script.Parent.AuthorityProfile)
local State = require(script.Parent.AuthorityState)
local Policy = require(script.Parent.AuthorityPolicy)
local Result = require(script.Parent.AuthorityResult)
local Event = require(script.Parent.AuthorityEvent)
local Request = require(script.Parent.AuthorityRequest)
local Snapshot = require(script.Parent.AuthoritySnapshot)
local Validation = require(script.Parent.AuthorityValidation)
local NetworkPeer = require(script.Parent.NetworkPeer)
local NetworkMessage = require(script.Parent.NetworkMessage)
local NetworkSnapshot = require(script.Parent.NetworkSnapshot)
local NetworkChannel = require(script.Parent.NetworkChannel)
local NetworkSequence = require(script.Parent.NetworkSequence)
local InputComponent = require(script.Parent.InputComponent)
local RollbackRequest = require(script.Parent.RollbackRequest)

local Resolver = {}
Resolver.__index = Resolver

local function normalizeProfile(profile, fallback)
	if profile == nil then return fallback end
	if getmetatable(profile) == Profile then return profile end
	if type(profile) ~= "table" then return nil end
	local ok, normalized = pcall(Profile.new, profile)
	return ok and normalized or nil
end

local function idOrder(a, b)
	if type(a) ~= type(b) then return type(a) < type(b) end
	if type(a) == "number" or type(a) == "string" then return a < b end
	return tostring(a) < tostring(b)
end

local function validPeerId(value)
	if type(value) == "string" then return value ~= "" and #value <= 128 end
	return type(value) == "number" and value == value and value >= 0
		and value < math.huge and value % 1 == 0
end

local function parseFailureResult(failure)
	if failure == "InvalidFrame" then return Result.Type.InvalidFrame end
	if failure == "InvalidSequence" then return Result.Type.InvalidSequence end
	if failure == "InvalidEntity" then return Result.Type.InvalidEntity end
	if failure == "InvalidInput" then return Result.Type.InvalidInput end
	return Result.Type.ValidationFailed
end

function Resolver.new(world, profile)
	local normalized = normalizeProfile(profile, Profile.new())
	assert(normalized, "AuthorityResolver profile is invalid")
	local component = Component.new(normalized)
	return setmetatable({
		World = world,
		Profile = normalized,
		Component = component,
		Peers = {},
		Owners = {},
		LastSequences = {},
		InputCounts = {},
		Events = {},
		Results = {},
		Processing = false,
		SnapshotSequence = 0,
	}, Resolver)
end

function Resolver:_result(kind, data)
	data = data or {}
	data.Type = kind
	local result = Result.new(data)
	table.insert(self.Results, result)
	return result
end

function Resolver:_emit(kind, data)
	data = data or {}
	data.Type = kind
	local event = Event.new(data)
	table.insert(self.Events, event)
	return event
end

function Resolver:_frame()
	local simulation = self.World:GetSimulation()
	if not simulation then return nil end
	local frame = simulation:GetGameTime():GetFrame()
	if frame ~= self.World.CurrentFrame then return nil end
	return frame
end

function Resolver:_entity(entityOrId)
	local entity
	if type(entityOrId) == "table" then
		entity = entityOrId
	else
		if not validPeerId(entityOrId) then return nil end
		entity = self.World:GetEntity(entityOrId)
	end
	if not entity or not validPeerId(entity.Id) or entity.Destroyed
		or self.World:GetEntity(entity.Id) ~= entity then return nil end
	return entity
end

function Resolver:_reject(kind, detail, data)
	data = data or {}
	data.Detail = detail
	if self.Profile.InputPolicy ~= Policy.Ignore then
		self.Component.RejectedInputFrames[#self.Component.RejectedInputFrames + 1] = {
			Frame = data.SimulationFrame,
			PeerId = data.PeerId,
			EntityId = data.EntityId,
			Reason = kind,
		}
		while #self.Component.RejectedInputFrames > 128 do
			table.remove(self.Component.RejectedInputFrames, 1)
		end
		self:_emit(Event.Type.InputRejected, data)
		if self.Profile.RejectInvalidInputs and (kind == Result.Type.InvalidInput
			or kind == Result.Type.InvalidFrame or kind == Result.Type.InvalidSequence
			or kind == Result.Type.ValidationFailed) then
			self:_emit(Event.Type.InputInvalid, data)
		end
	end
	if data.PeerId ~= nil and self.Profile.InputPolicy == Policy.Disconnect then
		local network = self.World:GetNetworkResolver()
		if network and network:GetPeer(data.PeerId) then network:Disconnect(data.PeerId) end
	end

	return self:_result(kind, data)
end

function Resolver:_discardPeerInputs(peerId, entityId)
	for pendingEntityId, frames in pairs(self.Component.PendingInputFrames) do
		if entityId == nil or pendingEntityId == entityId then
			for frame, request in pairs(frames) do
				if request.PeerId == peerId then frames[frame] = nil end
			end
			if next(frames) == nil then self.Component.PendingInputFrames[pendingEntityId] = nil end
		end
	end
end

function Resolver:Enable(profile)
	if self.Processing then return self:_result(Result.Type.AlreadyProcessing) end
	local normalized = normalizeProfile(profile, self.Profile)
	if not normalized then return self:_result(Result.Type.ValidationFailed, { Detail = "Invalid authority profile" }) end
	if not normalized.Enabled then return self:_result(Result.Type.Disabled) end
	self.Component.AuthorityState = State.Initializing
	local frame = self:_frame()
	if frame == nil then
		self.Component.AuthorityState = State.Error
		self:_emit(Event.Type.Error, { Detail = "Simulation is missing or its frame is inconsistent" })
		return self:_result(Result.Type.SimulationUnavailable)
	end
	self.Profile = normalized
	self.Component.Profile = normalized
	self.Component.Enabled = true
	self.Component.CurrentAuthoritativeFrame = frame
	self.Component.AuthorityState = State.Active
	self:_emit(Event.Type.Started, { SimulationFrame = frame })
	return self:_result(Result.Type.Success, { SimulationFrame = frame })
end

function Resolver:Disable()
	if self.Processing then return self:_result(Result.Type.AlreadyProcessing) end
	if not self.Component.Enabled then return self:_result(Result.Type.Disabled) end
	self.Component.Enabled = false
	self.Component.AuthorityState = State.Inactive
	self.Component.PendingInputFrames = {}
	self:_emit(Event.Type.Stopped, { SimulationFrame = self.Component.CurrentAuthoritativeFrame })
	return self:_result(Result.Type.Success)
end

function Resolver:IsEnabled()
	return self.Component.Enabled == true and self.Component.AuthorityState ~= State.Error
end

function Resolver:RegisterPeer(peer)
	if getmetatable(peer) ~= NetworkPeer or not validPeerId(peer.Id) then
		return self:_result(Result.Type.InvalidPeer)
	end
	local network = self.World:GetNetworkResolver()
	if not network or network:GetPeer(peer.Id) ~= peer then
		return self:_result(Result.Type.InvalidPeer, { PeerId = peer.Id, Detail = "Peer is not registered with NetworkResolver" })
	end
	if self.Peers[peer.Id] then return self:_result(Result.Type.InvalidPeer, { PeerId = peer.Id, Detail = "Peer already registered" }) end
	self.Peers[peer.Id] = peer
	return self:_result(Result.Type.Success, { PeerId = peer.Id })
end

function Resolver:UnregisterPeer(peerId)
	if not validPeerId(peerId) then return self:_result(Result.Type.InvalidPeer, { PeerId = peerId }) end
	if not self.Peers[peerId] then return self:_result(Result.Type.UnknownPeer, { PeerId = peerId }) end
	self:_discardPeerInputs(peerId)
	self.Peers[peerId] = nil
	self.LastSequences[peerId] = nil
	self.InputCounts[peerId] = nil
	for entityId, owner in pairs(self.Owners) do
		if owner == peerId then self.Owners[entityId] = nil end
	end
	return self:_result(Result.Type.Success, { PeerId = peerId })
end

function Resolver:GetOwnedEntities(peerId)
	local result = {}
	for entityId, owner in pairs(self.Owners) do
		if owner == peerId then
			local entity = self.World:GetEntity(entityId)
			if entity then table.insert(result, entity) end
		end
	end
	table.sort(result, function(a, b) return tostring(a.Id) < tostring(b.Id) end)
	return result
end

function Resolver:BindEntity(peerId, entityOrId)
	if self.Processing then return self:_result(Result.Type.AlreadyProcessing) end
	if not validPeerId(peerId) then return self:_result(Result.Type.InvalidPeer, { PeerId = peerId }) end
	if not self.Peers[peerId] or self.World:GetNetworkResolver():GetPeer(peerId) ~= self.Peers[peerId] then
		return self:_result(Result.Type.UnknownPeer, { PeerId = peerId })
	end
	local entity = self:_entity(entityOrId)
	if not entity or not entity:GetComponent(InputComponent) then
		return self:_result(Result.Type.InvalidEntity, { PeerId = peerId })
	end
	local owner = self.Owners[entity.Id]
	if owner ~= nil and owner ~= peerId then
		return self:_result(Result.Type.OwnershipConflict, { PeerId = peerId, EntityId = entity.Id, OwnerPeerId = owner })
	end
	self.Owners[entity.Id] = peerId
	return self:_result(Result.Type.Success, { PeerId = peerId, EntityId = entity.Id })
end

function Resolver:UnbindEntity(peerId, entityOrId)
	if self.Processing then return self:_result(Result.Type.AlreadyProcessing) end
	if not validPeerId(peerId) then return self:_result(Result.Type.InvalidPeer, { PeerId = peerId }) end
	local entity = self:_entity(entityOrId)
	if not entity then return self:_result(Result.Type.InvalidEntity) end
	if self.Owners[entity.Id] ~= peerId then
		return self:_result(Result.Type.UnauthorizedEntity, { PeerId = peerId, EntityId = entity.Id })
	end
	self:_discardPeerInputs(peerId, entity.Id)
	self.Owners[entity.Id] = nil
	return self:_result(Result.Type.Success, { PeerId = peerId, EntityId = entity.Id })
end

function Resolver:_parse(value, peerId)
	local input, failure = Validation.Parse(value, self.Profile, self.World:GetInputResolver().Profile, peerId)
	if not input then return nil, failure end
	if type(value) == "table" and getmetatable(value) == NetworkMessage
		and value.Sender ~= nil and value.Sender ~= peerId then
		return nil, "Sender does not match transport peer"
	end
	return input
end

function Resolver:_validateParsed(peerId, input)
	local frame = self:_frame()
	if frame == nil then return Result.Type.SimulationUnavailable, "Simulation frame is unavailable" end
	local entity = self:_entity(input.EntityId)
	if not entity or not entity:GetComponent(InputComponent) then
		return Result.Type.InvalidEntity, "Entity is missing or has no InputComponent"
	end
	if peerId ~= nil then
		local network = self.World:GetNetworkResolver()
		if not self.Peers[peerId] or not network or network:GetPeer(peerId) ~= self.Peers[peerId] then
			return Result.Type.UnknownPeer, "Peer is not registered with NetworkResolver"
		end
		if self.Peers[peerId].State ~= NetworkPeer.State.Connected then
			return Result.Type.InvalidPeer, "Peer is not connected"
		end
		if self.Owners[entity.Id] ~= peerId then return Result.Type.UnauthorizedEntity, "Peer does not own entity" end
		local last = self.LastSequences[peerId]
		if last ~= nil then
			local sequence = NetworkSequence.new(last)
			local comparison = sequence:Compare(input.NetworkSequence)
			if comparison == 0 then return Result.Type.DuplicateInput, "Network sequence was already used" end
			if comparison > 0 then return Result.Type.OutOfOrderInput, "Network sequence is older than the accepted sequence" end
		end
	end
	local current = self.Component.CurrentAuthoritativeFrame
	if input.SimulationFrame <= current then
		local delay = current - input.SimulationFrame
		local maximum = math.min(self.Profile.MaxPastFrames, self.Profile.MaxInputDelayFrames)
		if delay > maximum and self.Profile.PastInputPolicy == Policy.PastInput.Rollback then
			return Result.Type.RecoveryRequired,
				"Input is outside the rollback window; request a fresh authoritative snapshot", entity
		end
		if delay > maximum or self.Profile.PastInputPolicy == Policy.PastInput.Reject then
			return Result.Type.PastInput, "Past simulation frame is not accepted", entity
		end
		-- The existing RollbackResolver accepts this only when its complete snapshot and
		-- input-history contracts can support an authoritative restore and replay.
		return Result.Type.RollbackUnsupported,
			"Existing RollbackResolver cannot safely replay this authority input", entity
	end
	local lead = input.SimulationFrame - current
	if lead > math.min(self.Profile.MaxFutureFrames, self.Profile.MaxInputLeadFrames) then
		return Result.Type.FutureInput, "Simulation frame exceeds the configured future-input limit"
	end
	if peerId ~= nil then
		local peerCounts = self.InputCounts[peerId]
		local count = peerCounts and peerCounts[input.SimulationFrame] or 0
		if count >= self.Profile.MaxInputsPerFrame then
			return Result.Type.InputRateExceeded, "Peer exceeded the frame input limit"
		end
	end
	local frames = self.Component.PendingInputFrames[input.EntityId]
	if frames and frames[input.SimulationFrame] then
		return Result.Type.DuplicateInput, "Entity already has an input for this simulation frame"
	end
	return nil, nil, entity
end

function Resolver:ValidateInput(peerId, value)
	if not self:IsEnabled() then return self:_result(Result.Type.Disabled) end
	if not validPeerId(peerId) then return self:_result(Result.Type.InvalidPeer, { PeerId = peerId }) end
	local input, parseFailure = self:_parse(value, peerId)
	if not input then return self:_reject(parseFailureResult(parseFailure), parseFailure, { PeerId = peerId }) end
	local failure, detail, entity = self:_validateParsed(peerId, input)
	if failure then
		return self:_reject(failure, detail, {
			PeerId = peerId, EntityId = input.EntityId, SimulationFrame = input.SimulationFrame,
		})
	end
	self:_emit(Event.Type.InputValidated, {
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence,
	})
	return self:_result(Result.Type.Success, {
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Input = input,
	})
end

function Resolver:_queueLateRollback(peerId, input, entity)
	self.Component.AuthorityState = State.Simulating
	local rollback = self.World:GetRollbackResolver()
	local current = self.Component.CurrentAuthoritativeFrame
	local restoreFrame = input.SimulationFrame - 1
	if not rollback or restoreFrame < 0 then
		self.Component.AuthorityState = State.Active
		return self:_reject(Result.Type.RollbackUnsupported,
			"Rollback requires a confirmed snapshot before the late input frame", {
				PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
			})
	end
	local canRollback, rollbackFailure = rollback:CanRollback(
		self.World, restoreFrame, current)
	if not canRollback then
		self.Component.AuthorityState = State.Active
		return self:_reject(Result.Type.RollbackUnsupported,
			("Rollback cannot accept this input: %s"):format(tostring(rollbackFailure)), {
				PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
			})
	end
	local prepared, tokenOrDetail = rollback:PrepareInputFrame(
		self.World, input.SimulationFrame, entity.Id, input.Inputs)
	if not prepared then
		self.Component.AuthorityState = State.Active
		return self:_reject(Result.Type.RollbackUnsupported,
			("Rollback input preparation failed: %s"):format(tostring(tokenOrDetail)), {
				PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
			})
	end
	self.Processing = true
	local replay = rollback:ExecuteRollback(
		self.World, restoreFrame, current, RollbackRequest.Reason.LateInput)
	self.Processing = false
	if not replay.Accepted then
		rollback:RestorePreparedInput(tokenOrDetail)
		self.Component.AuthorityState = State.Active
		return self:_reject(Result.Type.RollbackUnsupported,
			("Rollback replay failed: %s"):format(tostring(replay.Type)), {
				PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
			})
	end

	local request = Request.new({
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Input = input,
	})
	self.Component.AcceptedInputFrames[#self.Component.AcceptedInputFrames + 1] = {
		EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Replayed = true,
	}
	while #self.Component.AcceptedInputFrames > 256 do
		table.remove(self.Component.AcceptedInputFrames, 1)
	end
	if peerId ~= nil then
		self.LastSequences[peerId] = input.NetworkSequence
		local peerCounts = self.InputCounts[peerId] or {}
		self.InputCounts[peerId] = peerCounts
		peerCounts[input.SimulationFrame] = (peerCounts[input.SimulationFrame] or 0) + 1
	end
	self.Component.AuthorityState = State.Active
	self:_emit(Event.Type.InputAccepted, {
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Replayed = true,
	})
	return self:_result(Result.Type.Success, {
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Request = request, Replayed = true,
	})
end

function Resolver:_queue(peerId, value)
	if not self:IsEnabled() then return self:_result(Result.Type.Disabled) end
	if self.Processing then return self:_result(Result.Type.AlreadyProcessing) end
	self.Component.AuthorityState = State.Validating
	local input, parseFailure = self:_parse(value, peerId)
	if not input then
		self.Component.AuthorityState = State.Active
		return self:_reject(parseFailureResult(parseFailure), parseFailure, { PeerId = peerId })
	end
	local failure, detail, entity = self:_validateParsed(peerId, input)
	if failure then
		self.Component.AuthorityState = State.Active
		local recovery = nil
		if failure == Result.Type.RecoveryRequired then
			recovery = {
				Required = true,
				CurrentFrame = self.Component.CurrentAuthoritativeFrame,
				RequestedFrame = input.SimulationFrame,
				Reason = detail,
			}
		end
		if failure == Result.Type.RollbackUnsupported
			and self.Profile.PastInputPolicy == Policy.PastInput.Rollback then
			return self:_queueLateRollback(peerId, input, entity)
		end
		return self:_reject(failure, detail, {
			PeerId = peerId, EntityId = input.EntityId, SimulationFrame = input.SimulationFrame,
			Recovery = recovery,
		})
	end
	local request = Request.new({
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Input = input,
	})
	local entityFrames = self.Component.PendingInputFrames[entity.Id]
	if not entityFrames then entityFrames = {}; self.Component.PendingInputFrames[entity.Id] = entityFrames end
	entityFrames[input.SimulationFrame] = request
	self.Component.AcceptedInputFrames[#self.Component.AcceptedInputFrames + 1] = {
		EntityId = entity.Id, SimulationFrame = input.SimulationFrame, NetworkSequence = input.NetworkSequence,
	}
	while #self.Component.AcceptedInputFrames > 256 do table.remove(self.Component.AcceptedInputFrames, 1) end
	if peerId ~= nil then
		self.LastSequences[peerId] = input.NetworkSequence
		local peerCounts = self.InputCounts[peerId] or {}
		self.InputCounts[peerId] = peerCounts
		peerCounts[input.SimulationFrame] = (peerCounts[input.SimulationFrame] or 0) + 1
	end
	self.Component.AuthorityState = State.Active
	self:_emit(Event.Type.InputAccepted, {
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence,
	})
	return self:_result(Result.Type.Success, {
		PeerId = peerId, EntityId = entity.Id, SimulationFrame = input.SimulationFrame,
		NetworkSequence = input.NetworkSequence, Request = request,
	})
end

function Resolver:SubmitInput(peerId, value)
	if not validPeerId(peerId) then
		return self:_result(Result.Type.InvalidPeer, { PeerId = peerId, Detail = "Use SubmitServerInput for server-owned input" })
	end
	return self:_queue(peerId, value)
end

-- peerId must be derived from the trusted server transport callback, never from the payload.
function Resolver:ReceiveNetworkInput(peerId, message)
	local network = self.World:GetNetworkResolver()
	if not network then
		return nil, self:_result(Result.Type.SimulationUnavailable, {
			PeerId = peerId, Detail = "NetworkResolver is unavailable",
		})
	end
	if getmetatable(message) ~= NetworkMessage or message.Type ~= NetworkMessage.Type.Input
		or message.Channel ~= NetworkChannel.Input then
		return nil, self:_reject(Result.Type.InvalidInput,
			"Expected a versioned Input message on the Input channel", { PeerId = peerId })
	end
	local transportResult = network:Receive(peerId, message)
	if not transportResult.Accepted then return transportResult, nil end
	return transportResult, self:SubmitInput(peerId, message)
end

function Resolver:SubmitServerInput(entityOrId, value)
	local entity = self:_entity(entityOrId)
	if not entity or not entity:GetComponent(InputComponent) then return self:_result(Result.Type.InvalidEntity) end
	if type(value) ~= "table" or getmetatable(value) ~= nil then
		return self:_reject(Result.Type.ValidationFailed, "Malformed server input", { EntityId = entity.Id })
	end
	local copy = {}
	for key, entry in pairs(value) do copy[key] = entry end
	if copy.EntityId ~= nil and copy.EntityId ~= entity.Id then
		return self:_reject(Result.Type.UnauthorizedEntity, "Server input entity mismatch", { EntityId = entity.Id })
	end
	copy.EntityId = entity.Id
	copy.NetworkSequence = nil
	return self:_queue(nil, copy)
end

function Resolver:_stepFrame(frame)
	for entityId in pairs(self.Component.PendingInputFrames) do
		if not self:_entity(entityId) then
			self.Component.PendingInputFrames[entityId] = nil
		end
	end
	local inputResolver = self.World:GetInputResolver()
	local entities = self.World:GetEntities()
	table.sort(entities, function(a, b) return idOrder(a.Id, b.Id) end)
	for _, entity in ipairs(entities) do
		if entity:GetComponent(InputComponent) then
			local _, failure = inputResolver:AdvanceFrame(entity, frame, "Authority")
			if failure then return false, failure end
		end
	end
	for _, entity in ipairs(entities) do
		local requests = self.Component.PendingInputFrames[entity.Id]
		local request = requests and requests[frame]
		if request then
			local inputIds = {}
			for inputId in pairs(request.Input.Inputs) do table.insert(inputIds, inputId) end
			table.sort(inputIds)
			for _, inputId in ipairs(inputIds) do
				local state = request.Input.Inputs[inputId]
				local _, failure = inputResolver:SetInput(entity, inputId, state, frame, {
					Source = request.PeerId == nil and "AuthorityServer" or "AuthorityPeer",
				})
				if failure then return false, failure end
			end
			requests[frame] = nil
			if next(requests) == nil then self.Component.PendingInputFrames[entity.Id] = nil end
			self.Component.LastProcessedInputFrame = math.max(
				self.Component.LastProcessedInputFrame or frame, frame)
		end
	end
	local simulation = self.World:GetSimulation()
	local ok, failure = pcall(simulation.Step, simulation)
	if not ok then return false, tostring(failure) end
	if simulation:GetGameTime():GetFrame() ~= frame or self.World.CurrentFrame ~= frame then
		return false, "Simulation and World frame did not advance together"
	end
	self.Component.CurrentAuthoritativeFrame = frame
	for _, peerCounts in pairs(self.InputCounts) do
		for inputFrame in pairs(peerCounts) do
			if inputFrame <= frame then peerCounts[inputFrame] = nil end
		end
	end
	self:_emit(Event.Type.SimulationAdvanced, { SimulationFrame = frame })
	return true
end

function Resolver:Advance(frame)
	if not self:IsEnabled() then return self:_result(Result.Type.Disabled) end
	if self.Processing then return self:_result(Result.Type.AlreadyProcessing) end
	if not Validation.IsValidFrame(frame) or frame <= self.Component.CurrentAuthoritativeFrame
		or frame - self.Component.CurrentAuthoritativeFrame > self.Profile.MaxFramesPerAdvance then
		return self:_result(Result.Type.InvalidAdvance, {
			SimulationFrame = frame, CurrentAuthoritativeFrame = self.Component.CurrentAuthoritativeFrame,
		})
	end
	local current = self:_frame()
	if current ~= self.Component.CurrentAuthoritativeFrame then
		self.Component.AuthorityState = State.Error
		self.Component.Enabled = false
		self:_emit(Event.Type.Error, { Detail = "Authority and Simulation frame cursors diverged" })
		return self:_result(Result.Type.SimulationUnavailable)
	end
	self.Processing = true
	for nextFrame = current + 1, frame do
		self.Component.AuthorityState = State.Simulating
		local callOk, ok, detail = pcall(self._stepFrame, self, nextFrame)
		if not callOk then
			detail = tostring(ok)
			ok = false
		end
		if not ok then
			self.Component.AuthorityState = State.Error
			self.Component.Enabled = false
			self.Processing = false
			self:_emit(Event.Type.Error, { SimulationFrame = nextFrame, Detail = detail })
			return self:_result(Result.Type.SimulationFailed, { SimulationFrame = nextFrame, Detail = detail })
		end
	end
	self.Processing = false
	self.Component.AuthorityState = State.Active
	local snapshotResult
	if self.Profile.PublishSnapshots
		and self.Component.CurrentAuthoritativeFrame % self.Profile.SnapshotInterval == 0 then
		local ok, snapshot, snapshotFailure = pcall(self.CreateSnapshot, self)
		if ok and snapshot ~= nil then
			snapshotResult = self:PublishSnapshot(snapshot)
		else
			local detail = tostring(ok and snapshotFailure or snapshot)
			snapshotResult = self:_result(Result.Type.SnapshotFailed, { Detail = detail })
			self:_emit(Event.Type.Error, { Detail = detail })
		end
	end
	return self:_result(Result.Type.Success, {
		SimulationFrame = self.Component.CurrentAuthoritativeFrame,
		SnapshotResult = snapshotResult,
	})
end

function Resolver:GetAuthoritativeFrame()
	return self.Component.CurrentAuthoritativeFrame
end

function Resolver:CreateSnapshot()
	local frame = self:_frame()
	if frame == nil or frame ~= self.Component.CurrentAuthoritativeFrame then
		return nil, "Simulation frame is unavailable or non-authoritative"
	end
	local entities = {}
	for _, entity in ipairs(self.World:GetEntities()) do
		table.insert(entities, entity)
	end
	table.sort(entities, function(a, b) return idOrder(a.Id, b.Id) end)
	local publicEntities = {}
	local predictionFrames = {}
	local complete = self.Profile.SnapshotFilter ~= nil
	for _, entity in ipairs(entities) do
		local projection = { State = entity.State, Components = {} }
		if self.Profile.SnapshotFilter then
			local ok, filtered = pcall(self.Profile.SnapshotFilter, entity, frame)
			if not ok then return nil, "SnapshotFilter failed: " .. tostring(filtered) end
			if type(filtered) ~= "table" or getmetatable(filtered) ~= nil then
				return nil, "SnapshotFilter must return a plain data table"
			end
			projection = filtered
			complete = complete and filtered.Complete == true
		end
		local inputComponent = entity:GetComponent(InputComponent)
		local inputFrame = inputComponent and inputComponent.InputBuffer:Get(frame)
		local authoritativeInputs = {}
		if inputFrame then
			for inputId, state in pairs(inputFrame.Inputs) do authoritativeInputs[inputId] = state end
		end
		predictionFrames[entity.Id] = { Frame = frame, Inputs = authoritativeInputs }
		table.insert(publicEntities, {
			Id = entity.Id,
			State = entity.State,
			Components = projection.Components or {},
		})
	end
	local simulation = self.World:GetSimulation()
	self.SnapshotSequence = (self.SnapshotSequence + 1) % 4294967296
	local ok, snapshot = pcall(Snapshot.new, {
		SimulationFrame = frame,
		Entities = publicEntities,
		Components = { Prediction = predictionFrames },
		RNGState = simulation:GetRNG():GetState(),
		NetworkSequence = self.SnapshotSequence,
		Complete = complete,
	})
	if not ok then return nil, tostring(snapshot) end
	self:_emit(Event.Type.SnapshotCreated, {
		SimulationFrame = frame, NetworkSequence = self.SnapshotSequence,
	})
	return snapshot
end

function Resolver:PublishSnapshot(snapshot)
	if getmetatable(snapshot) ~= Snapshot then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "Expected AuthoritySnapshot" })
	end
	local cloned, safeSnapshot = pcall(Snapshot.new, {
		SimulationFrame = snapshot.SimulationFrame,
		Entities = snapshot.Entities,
		Components = snapshot.Components,
		RNGState = snapshot.RNGState,
		NetworkSequence = snapshot.NetworkSequence,
		Complete = snapshot.Complete,
	})
	if not cloned then
		return self:_result(Result.Type.SnapshotFailed, { Detail = tostring(safeSnapshot) })
	end
	snapshot = safeSnapshot
	if type(snapshot.NetworkSequence) ~= "number" or snapshot.NetworkSequence ~= snapshot.NetworkSequence
		or snapshot.NetworkSequence < 0 or snapshot.NetworkSequence > 4294967295
		or snapshot.NetworkSequence % 1 ~= 0 or snapshot.NetworkSequence ~= self.SnapshotSequence then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot network sequence is invalid" })
	end
	if snapshot.SimulationFrame ~= self.Component.CurrentAuthoritativeFrame
		or not Validation.IsValidFrame(snapshot.SimulationFrame) then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot frame is not the current authoritative frame" })
	end
	if not snapshot.Complete then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "A complete public SnapshotFilter projection is required" })
	end
	if type(snapshot.Components.Prediction) ~= "table" then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "Authoritative prediction input frames are missing" })
	end
	for key in pairs(snapshot.Components) do
		if key ~= "Prediction" then
			return self:_result(Result.Type.SnapshotFailed, { Detail = "Unprojected root component data cannot be published" })
		end
	end
	local entities = self.World:GetEntities()
	table.sort(entities, function(a, b) return idOrder(a.Id, b.Id) end)
	if #snapshot.Entities ~= #entities then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot entity roster is not authoritative" })
	end
	for index, entity in ipairs(entities) do
		local entry = snapshot.Entities[index]
		if type(entry) ~= "table" or entry.Id ~= entity.Id or entry.State ~= entity.State
			or type(entry.Components) ~= "table" then
			return self:_result(Result.Type.SnapshotFailed, {
				Detail = "Snapshot entity data does not match authoritative World",
				EntityId = entity.Id,
			})
		end
		for key in pairs(entry) do
			if key ~= "Id" and key ~= "State" and key ~= "Components" then
				return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot entity contains an unprojected field" })
			end
			local predictionFrame = snapshot.Components.Prediction[entity.Id]
			if type(predictionFrame) ~= "table" or predictionFrame.Frame ~= snapshot.SimulationFrame
				or type(predictionFrame.Inputs) ~= "table" then
				return self:_result(Result.Type.SnapshotFailed, {
					Detail = "Snapshot prediction input frame is missing or invalid",
					EntityId = entity.Id,
				})
			end
			for key in pairs(predictionFrame) do
				if key ~= "Frame" and key ~= "Inputs" then
					return self:_result(Result.Type.SnapshotFailed, { Detail = "Prediction frame contains an unprojected field" })
				end
			end
			local inputComponent = entity:GetComponent(InputComponent)
			local recorded = inputComponent and inputComponent.InputBuffer:Get(snapshot.SimulationFrame)
			local actualInputs = recorded and recorded.Inputs or {}
			for inputId, state in pairs(actualInputs) do
				if predictionFrame.Inputs[inputId] ~= state then
					return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot prediction inputs are not authoritative" })
				end
			end
			for inputId, state in pairs(predictionFrame.Inputs) do
				if actualInputs[inputId] ~= state then
					return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot prediction inputs contain unrecorded data" })
				end
			end
		end
	end
	local simulation = self.World:GetSimulation()
	if snapshot.RNGState ~= simulation:GetRNG():GetState() then
		return self:_result(Result.Type.SnapshotFailed, { Detail = "Snapshot RNG state is not authoritative" })
	end
	local network = self.World:GetNetworkResolver()
	if not network then
		return self:_result(Result.Type.PublishingFailed, { Detail = "NetworkResolver is unavailable" })
	end
	local ok, networkSnapshot = pcall(NetworkSnapshot.new, {
		SimulationFrame = snapshot.SimulationFrame,
		Sequence = snapshot.NetworkSequence,
		Entities = snapshot.Entities,
		Components = snapshot.Components,
		Metadata = { Authority = true, Complete = snapshot.Complete, RNGState = snapshot.RNGState },
	})
	if not ok then
		return self:_result(Result.Type.SnapshotFailed, { Detail = tostring(networkSnapshot) })
	end
	local message = NetworkMessage.new({
		Type = NetworkMessage.Type.Snapshot,
		Channel = NetworkChannel.Snapshot,
		Sequence = snapshot.NetworkSequence,
		SimulationFrame = snapshot.SimulationFrame,
		Sender = "Server",
		Payload = networkSnapshot,
	})
	self.Component.AuthorityState = State.Publishing
	local result = network:Broadcast(message)
	self.Component.AuthorityState = self.Component.Enabled and State.Active or State.Inactive
	if not result.Accepted then
		self:_emit(Event.Type.Error, { SimulationFrame = snapshot.SimulationFrame, Detail = "Network snapshot publication failed" })
		return self:_result(Result.Type.PublishingFailed, {
			SimulationFrame = snapshot.SimulationFrame, NetworkResult = result,
		})
	end
	self.Component.LastPublishedFrame = snapshot.SimulationFrame
	self:_emit(Event.Type.SnapshotPublished, {
		SimulationFrame = snapshot.SimulationFrame, NetworkSequence = snapshot.NetworkSequence,
		Count = result.Count,
	})
	return self:_result(Result.Type.Success, {
		SimulationFrame = snapshot.SimulationFrame, NetworkResult = result, Count = result.Count,
	})
end

function Resolver:GetEvents()
	return table.clone(self.Events)
end

function Resolver:GetResults()
	return table.clone(self.Results)
end

function Resolver:Clear()
	self.Events, self.Results = {}, {}
	return self
end

return Resolver
