local Definition = require(script.Parent.CombatActionDefinition)

local Instance = {}
Instance.__index = Instance
Instance.State = table.freeze({ Startup = "Startup", Active = "Active", Recovery = "Recovery", Finished = "Finished", Cancelled = "Cancelled" })

function Instance.new(definition, owner, id, startFrame)
	assert(type(definition) == "table" and definition.Version == Definition.Version, "Action definition is invalid")
	assert(owner and owner.Id ~= nil, "Action instance requires an owner")
	assert(type(id) == "number" or type(id) == "string", "Action instance requires a stable ID")
	assert(type(startFrame) == "number" and startFrame >= 0 and startFrame % 1 == 0,
		"Action start frame must be a non-negative integer")
	local phase = Instance.State.Startup
	if definition.DurationModel ~= "Phased" then phase = Instance.State.Active end
	return setmetatable({
		Id = id,
		Definition = definition,
		Owner = owner,
		StartFrame = startFrame,
		CurrentFrame = startFrame,
		Phase = phase,
		State = phase,
	}, Instance)
end

function Instance:Advance(frame)
	assert(type(frame) == "number" and frame >= self.StartFrame and frame % 1 == 0,
		"Action frame must be an integer at or after StartFrame")
	if self.State == Instance.State.Finished or self.State == Instance.State.Cancelled then
		return self.State
	end
	self.CurrentFrame = frame
	if self.Definition.DurationModel == "Persistent" then
		self.Phase = Instance.State.Active
		self.State = Instance.State.Active
		return self.State
	elseif self.Definition.DurationModel == "Instant" then
		self.Phase = Instance.State.Finished
		self.State = Instance.State.Finished
		return self.State
	end
	local elapsed = frame - self.StartFrame
	if elapsed < self.Definition.StartupFrames then
		self.Phase = Instance.State.Startup
	elseif elapsed < self.Definition.StartupFrames + self.Definition.ActiveFrames then
		self.Phase = Instance.State.Active
	elseif elapsed < self.Definition:GetTotalFrames() then
		self.Phase = Instance.State.Recovery
	else
		self.Phase = Instance.State.Finished
		self.State = Instance.State.Finished
	end
	if self.State ~= Instance.State.Finished then self.State = self.Phase end
	return self.State
end

function Instance:Cancel(frame)
	if self.State == Instance.State.Finished or self.State == Instance.State.Cancelled then return false end
	if not self.Definition.Cancelable then return false end
	self.CurrentFrame = frame or self.CurrentFrame
	self.State = Instance.State.Cancelled
	self.Phase = Instance.State.Cancelled
	return true
end

function Instance:IsActive() return self.State == Instance.State.Active end
function Instance:IsFinished() return self.State == Instance.State.Finished or self.State == Instance.State.Cancelled end

return Instance
