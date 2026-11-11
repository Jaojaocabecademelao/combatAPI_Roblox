local Component = require(script.Parent.Parent.Core.Component)
local MotionResolver = require(script.Parent.MotionResolver)
local MotionRequest = require(script.Parent.MotionRequest)
local MotionResult = require(script.Parent.MotionResult)
local EntityState = require(script.Parent.Parent.Core.EntityState)
local HitstopComponent = require(script.Parent.HitstopComponent)

local MotionComponent = setmetatable({}, Component)
MotionComponent.__index = MotionComponent
MotionComponent.RollbackKey = "Combat.MotionComponent"

local function finite(value)
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function encodeReference(value, label, optional)
	if value == nil then
		if optional then return nil, false end
		return nil, false, label .. " is required"
	end
	if type(value) == "table" then
		local id = value.Id
		if (type(id) ~= "number" and type(id) ~= "string") or id == "" then
			return nil, false, label .. " entity must have a stable ID"
		end
		return id, true
	end
	if type(value) == "string" or (type(value) == "number" and finite(value)) then return value, false end
	return nil, false, label .. " must be an entity or stable string/number ID"
end

local function resolveReference(id, isEntity, context, label, optional)
	if id == nil then
		if optional then return nil end
		return nil, label .. " is missing"
	end
	if not isEntity then return id end
	local entities = context and context.EntitiesById
	local entity = entities and entities[id]
	if not entity then return nil, label .. " entity is absent from staged roster: " .. tostring(id) end
	return entity
end

local function isAlive(entity)
	return entity ~= nil and not entity.Destroyed and entity:GetState() ~= EntityState.Dead
end

function MotionComponent.new()
	local self = setmetatable(Component.new(), MotionComponent)
	self.PendingRequests = {}
	self.MotionResolver = MotionResolver.new()
	self.MotionResults = {}
	return self
end

function MotionComponent:ApplyRequest(request)
	if not self:IsEnabled() then
		return nil
	end
	assert(request and type(request) == "table", "MotionComponent:ApplyRequest() expects a MotionRequest")
	if self.Entity and not isAlive(self.Entity) then
		return nil
	end
	local motionRequest = MotionRequest.new(request)
	table.insert(self.PendingRequests, motionRequest)
	-- PendingRequests is the authoritative queue and is captured by this component.
	-- Do not mirror it into MotionResolver.PendingRequests: Process receives this
	-- queue explicitly, so mirroring creates a second mutable copy outside the snapshot.
	return motionRequest
end

function MotionComponent:GetPendingRequests()
	local requests = {}
	for _, request in ipairs(self.PendingRequests) do
		table.insert(requests, request)
	end
	return requests
end

function MotionComponent:Process(frame)
	if not self:IsEnabled() then
		return {}
	end
	if self.Entity and self.Entity:GetState() == EntityState.Dead then
		self.PendingRequests = {}
		self.MotionResults = {}
		return {}
	end
	local hitstop = self.Entity and self.Entity:GetComponent(HitstopComponent)
	if hitstop and hitstop:IsFrozen() then
		-- Keep queued motion intact; this subsystem opts into entity-local combat time.
		return {}
	end

	local results = self.MotionResolver:Process(self.PendingRequests, frame)
	self.MotionResults = results
	self.PendingRequests = {}
	return results
end

function MotionComponent:Update(deltaTime)
	-- Deterministic motion processing occurs from the simulation step, not arbitrary scheduler ticks.
end

function MotionComponent:Step(deltaTime)
	-- Motion arrives from the world pipeline; no physics here.
end

function MotionComponent:OnEntityStateChanged(state)
	if state == EntityState.Dead then
		self.PendingRequests = {}
		self.MotionResults = {}
	end
end

function MotionComponent:Destroy()
	self.PendingRequests = {}
	self.MotionResults = {}
	self.MotionResolver:Clear()
end

function MotionComponent:GetMotionResults()
	local results = {}
	for _, result in ipairs(self.MotionResults) do
		table.insert(results, result)
	end
	return results
end

function MotionComponent:CaptureRollbackState()
	local requests = {}
	for index, request in ipairs(self.PendingRequests) do
		local sourceId, sourceIsEntity, sourceError = encodeReference(request.Source, "Motion Source", true)
		assert(not sourceError, sourceError)
		local targetId, targetIsEntity, targetError = encodeReference(request.Target, "Motion Target", false)
		assert(not targetError, targetError)
		local direction = request.Direction
		assert(direction and finite(direction.X) and finite(direction.Y) and finite(direction.Z),
			"Motion request direction is not finite")
		requests[index] = {
			SourceId = sourceId, SourceIsEntity = sourceIsEntity,
			TargetId = targetId, TargetIsEntity = targetIsEntity,
			Type = request.Type, Direction = { direction.X, direction.Y, direction.Z },
			Magnitude = request.Magnitude, Duration = request.Duration, Priority = request.Priority,
			Frame = request.Frame, Time = request.Time,
		}
	end
	return { Version = 1, PendingRequests = requests }
end

function MotionComponent:ValidateRollbackState(state, context)
	if type(state) ~= "table" or getmetatable(state) ~= nil or state.Version ~= 1
		or type(state.PendingRequests) ~= "table" then
		return false, "Invalid MotionComponent state version or request list"
	end
	for key in pairs(state) do
		if key ~= "Version" and key ~= "PendingRequests" then return false, "Unknown MotionComponent field: " .. tostring(key) end
	end
	for index, saved in ipairs(state.PendingRequests) do
		if type(saved) ~= "table" or getmetatable(saved) ~= nil then return false, "Invalid MotionRequest at index " .. index end
		for key in pairs(saved) do
			local allowed = key == "SourceId" or key == "SourceIsEntity" or key == "TargetId"
				or key == "TargetIsEntity" or key == "Type" or key == "Direction" or key == "Magnitude"
				or key == "Duration" or key == "Priority" or key == "Frame" or key == "Time"
			if not allowed then return false, "Unknown MotionRequest field: " .. tostring(key) end
		end
		if type(saved.SourceIsEntity) ~= "boolean" or type(saved.TargetIsEntity) ~= "boolean"
			or (saved.SourceId ~= nil and type(saved.SourceId) ~= "number" and type(saved.SourceId) ~= "string")
			or (type(saved.TargetId) ~= "number" and type(saved.TargetId) ~= "string") then
			return false, "MotionRequest references are invalid"
		end
		if saved.SourceIsEntity and saved.SourceId == nil then return false, "MotionRequest entity source ID is missing" end
		if type(saved.Direction) ~= "table" or #saved.Direction ~= 3
			or not finite(saved.Direction[1]) or not finite(saved.Direction[2]) or not finite(saved.Direction[3]) then
			return false, "MotionRequest direction is invalid"
		end
		if type(saved.Type) ~= "string" or saved.Type == "" then return false, "MotionRequest type is invalid" end
		local ok = pcall(MotionRequest.new, {
			Type = saved.Type, Direction = saved.Direction, Magnitude = saved.Magnitude,
			Duration = saved.Duration, Priority = saved.Priority,
		})
		if not ok then return false, "MotionRequest data is invalid" end
		if (saved.Frame ~= nil and (not finite(saved.Frame) or saved.Frame < 0 or saved.Frame % 1 ~= 0))
			or (saved.Time ~= nil and not finite(saved.Time)) then return false, "MotionRequest timing is invalid" end
		if context and context.EntitiesById then
			if saved.TargetIsEntity and not context.EntitiesById[saved.TargetId] then
				return false, "MotionRequest target is absent from staged roster"
			end
			if saved.SourceIsEntity and saved.SourceId ~= nil and not context.EntitiesById[saved.SourceId] then
				return false, "MotionRequest source is absent from staged roster"
			end
		end
	end
	local count, maxIndex = 0, 0
	for key in pairs(state.PendingRequests) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false, "MotionRequest list must be dense" end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	if count ~= maxIndex then return false, "MotionRequest list must be dense" end
	return true
end

function MotionComponent:RestoreRollbackState(state, context)
	local valid, detail = self:ValidateRollbackState(state, context)
	if not valid then return false, detail end
	local requests = {}
	for _, saved in ipairs(state.PendingRequests) do
		local source, sourceError = resolveReference(saved.SourceId, saved.SourceIsEntity, context, "Motion Source", true)
		if sourceError then return false, sourceError end
		local target, targetError = resolveReference(saved.TargetId, saved.TargetIsEntity, context, "Motion Target", false)
		if targetError then return false, targetError end
		requests[#requests + 1] = MotionRequest.new({
			Source = source, Target = target, Type = saved.Type, Direction = saved.Direction,
			Magnitude = saved.Magnitude, Duration = saved.Duration, Priority = saved.Priority,
			Frame = saved.Frame, Time = saved.Time,
		})
	end
	self.PendingRequests = requests
	self.MotionResolver.PendingRequests = {}
	self.MotionResolver.Results = {}
	self.MotionResults = {}
	return true
end

function MotionComponent:FinalizeRollbackRestore()
	self.MotionResolver.PendingRequests = {}
	for _, request in ipairs(self.PendingRequests) do
		table.insert(self.MotionResolver.PendingRequests, request)
	end
	return true
end

return MotionComponent
