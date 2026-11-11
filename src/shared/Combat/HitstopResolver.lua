local HitstopRequest = require(script.Parent.HitstopRequest)
local HitstopComponent = require(script.Parent.HitstopComponent)
local TimeEffectResult = require(script.Parent.TimeEffectResult)

local HitstopResolver = {}
HitstopResolver.__index = HitstopResolver

local function compareIds(a, b)
	if a == b then return 0 end
	if a == nil then return -1 elseif b == nil then return 1 end
	if type(a) == type(b) then return a < b and -1 or 1 end
	return type(a) < type(b) and -1 or 1
end

local function requestOrder(a, b)
	local compared = compareIds(a.Target.Id, b.Target.Id)
	if compared ~= 0 then return compared < 0 end
	if a.Priority ~= b.Priority then return a.Priority > b.Priority end
	if a.Frames ~= b.Frames then return a.Frames > b.Frames end
	return compareIds(a.Source and a.Source.Id, b.Source and b.Source.Id) < 0
end

function HitstopResolver.new(world)
	return setmetatable({ World = world, PendingRequests = {}, Results = {}, Frame = 0 }, HitstopResolver)
end

function HitstopResolver:Submit(request)
	if getmetatable(request) ~= HitstopRequest then
		request = HitstopRequest.new(request)
	end
	table.insert(self.PendingRequests, request)
	return request
end

HitstopResolver.QueueRequest = HitstopResolver.Submit

function HitstopResolver:GetPendingRequests()
	local requests = {}
	for _, request in ipairs(self.PendingRequests) do table.insert(requests, request) end
	return requests
end

function HitstopResolver:Process(frame)
	if frame ~= nil then
		assert(type(frame) == "number" and frame >= 0 and frame % 1 == 0,
			"HitstopResolver:Process() expects a non-negative integer frame")
		self.Frame = frame
	end
	local ordered = {}
	for _, request in ipairs(self.PendingRequests) do table.insert(ordered, request) end
	table.sort(ordered, requestOrder)
	self.PendingRequests = {}
	self.Results = {}
	local handledTargets = {}
	for _, request in ipairs(ordered) do
		local target = request.Target
		if request.Frames == 0 then
			table.insert(self.Results, {
				Frame = self.Frame,
				Type = "Hitstop",
				Outcome = TimeEffectResult.ZeroFrames,
				Request = request,
				Source = request.Source,
				Target = target,
				TargetId = target.Id,
				Frames = 0,
				Priority = request.Priority,
			})
		elseif not handledTargets[target.Id] then
			handledTargets[target.Id] = true
			local result = TimeEffectResult.MissingComponent
			if target.Destroyed then
				result = TimeEffectResult.EntityUnavailable
			else
				local component = type(target.GetComponent) == "function"
					and target:GetComponent(HitstopComponent)
				if component then
					if not component:IsEnabled() then
						result = TimeEffectResult.Disabled
					else
						result = component:Apply(request.Frames, request.Priority, request.Source)
					end
				end
			end
			table.insert(self.Results, {
				Frame = self.Frame,
				Type = "Hitstop",
				Outcome = result,
				Request = request,
				Source = request.Source,
				Target = target,
				TargetId = target.Id,
				Frames = request.Frames,
				Priority = request.Priority,
			})
		end
	end
	return self:GetResults()
end

function HitstopResolver:AdvanceStep()
	if not self.World then return end
	for _, entity in ipairs(self.World:GetEntities()) do
		local component = entity:GetComponent(HitstopComponent)
		if component then component:AdvanceStep() end
	end
end

function HitstopResolver:GetResults()
	local results = {}
	for _, result in ipairs(self.Results) do table.insert(results, result) end
	return results
end



local function finiteNumber(value)
	return type(value) == "number" and value == value
		and value > -math.huge and value < math.huge
end

local function denseArray(value)
	if type(value) ~= "table" then return false end
	local count, maxIndex = 0, 0
	for key in pairs(value) do
		if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then return false end
		count += 1
		if key > maxIndex then maxIndex = key end
	end
	return count == maxIndex
end

-- Capture pending work by stable entity IDs. Result objects are intentionally not captured:
-- they are outputs from a completed processing pass and must not be replayed as fresh effects.
function HitstopResolver:CaptureRollbackState()
	local pending = {}
	for _, request in ipairs(self.PendingRequests) do
		assert(request.Target and request.Target.Id ~= nil, "Hitstop request has no stable target ID")
		assert(request.Source == nil or request.Source.Id ~= nil, "Hitstop request source has no stable ID")
		table.insert(pending, {
			TargetEntityId = request.Target.Id,
			SourceEntityId = request.Source and request.Source.Id or nil,
			Frames = request.Frames,
			Priority = request.Priority,
		})
	end
	return { Version = 1, Frame = self.Frame, PendingRequests = pending }
end

function HitstopResolver:ValidateRollbackState(state)
	if type(state) ~= "table" or state.Version ~= 1 then return false, "Invalid HitstopResolver state version" end
	if not finiteNumber(state.Frame) or state.Frame < 0 or state.Frame % 1 ~= 0 then return false, "Invalid HitstopResolver frame" end
	if not denseArray(state.PendingRequests) then return false, "PendingRequests must be a dense array" end
	for index, request in ipairs(state.PendingRequests) do
		if type(request) ~= "table" then return false, "Invalid pending Hitstop request at index " .. index end
		if (type(request.TargetEntityId) ~= "number" and type(request.TargetEntityId) ~= "string") then
			return false, "Invalid Hitstop target ID at index " .. index
		end
		if request.SourceEntityId ~= nil and type(request.SourceEntityId) ~= "number" and type(request.SourceEntityId) ~= "string" then
			return false, "Invalid Hitstop source ID at index " .. index
		end
		if not finiteNumber(request.Frames) or request.Frames < 0 or request.Frames % 1 ~= 0 then
			return false, "Invalid Hitstop frame count at index " .. index
		end
		if not finiteNumber(request.Priority) then return false, "Invalid Hitstop priority at index " .. index end
	end
	return true
end

function HitstopResolver:PrepareRollbackRestore(state)
	local valid, reason = self:ValidateRollbackState(state)
	if not valid then return nil, reason end
	if not self.World or type(self.World.GetEntity) ~= "function" then return nil, "HitstopResolver has no World" end
	local staged = {}
	for index, saved in ipairs(state.PendingRequests) do
		local target = self.World:GetEntity(saved.TargetEntityId)
		if not target or target.Destroyed then return nil, "Missing Hitstop target entity " .. tostring(saved.TargetEntityId) end
		local source
		if saved.SourceEntityId ~= nil then
			source = self.World:GetEntity(saved.SourceEntityId)
			if not source or source.Destroyed then return nil, "Missing Hitstop source entity " .. tostring(saved.SourceEntityId) end
		end
		local ok, request = pcall(HitstopRequest.new, {
			Target = target, Source = source, Frames = saved.Frames, Priority = saved.Priority,
		})
		if not ok then return nil, "Could not stage Hitstop request " .. index .. ": " .. tostring(request) end
		table.insert(staged, request)
	end
	local frame = state.Frame
	return function()
		self.PendingRequests = staged
		self.Frame = frame
		self.Results = {}
	end
end

function HitstopResolver:Clear()
	table.clear(self.PendingRequests)
	table.clear(self.Results)
end

return HitstopResolver
