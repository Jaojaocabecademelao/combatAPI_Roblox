local State = require(script.Parent.AuthorityState)

local Component = {}
Component.__index = Component

function Component.new(profile)
	return setmetatable({
		Enabled = false,
		AuthorityState = State.Inactive,
		CurrentAuthoritativeFrame = 0,
		LastProcessedInputFrame = nil,
		LastPublishedFrame = nil,
		PendingInputFrames = {},
		AcceptedInputFrames = {},
		RejectedInputFrames = {},
		Profile = profile,
	}, Component)
end

return Component
