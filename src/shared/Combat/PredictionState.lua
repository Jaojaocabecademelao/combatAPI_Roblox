local History = require(script.Parent.PredictionHistory)

local State = {}
State.__index = State

function State.new(entityId, profile)
	return setmetatable({
		EntityId = entityId,
		Profile = profile,
		Enabled = true,
		Started = false,
		CurrentFrame = nil,
		ConfirmedFrame = nil,
		PredictionFrameCount = 0,
		History = History.new(profile.MaxHistoryFrames),
	}, State)
end

function State:Reset()
	self.Started = false
	self.CurrentFrame, self.ConfirmedFrame = nil, nil
	self.PredictionFrameCount = 0
	self.History:Clear()
	return self
end

return State
