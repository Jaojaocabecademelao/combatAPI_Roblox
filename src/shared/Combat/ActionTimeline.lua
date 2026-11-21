local ActionTimeline = {}
ActionTimeline.__index = ActionTimeline

function ActionTimeline.new(definition)
	assert(type(definition) == "table", "ActionTimeline.new requires an action definition")
	local startup = definition.StartupFrames or 0
	local active = definition.ActiveFrames or 0
	local recovery = definition.RecoveryFrames or 0
	local entries = {}
	for frame = 1, startup do
		table.insert(entries, { Frame = frame, Phase = "Startup" })
	end
	for frame = startup + 1, startup + active do
		table.insert(entries, { Frame = frame, Phase = "Active" })
	end
	for frame = startup + active + 1, startup + active + recovery do
		table.insert(entries, { Frame = frame, Phase = "Recovery" })
	end
	for _, event in ipairs(definition.GameplayEvents or {}) do
		for _, entry in ipairs(entries) do
			if entry.Frame == event.FrameOffset then
				entry.Events = entry.Events or {}
				table.insert(entry.Events, event)
				break
			end
		end
	end
	return table.freeze(setmetatable({
		Id = definition.Id,
		DurationModel = definition.DurationModel,
		Entries = table.freeze(entries),
	}, ActionTimeline))
end

function ActionTimeline:GetFrame(frame)
	for _, entry in ipairs(self.Entries) do
		if entry.Frame == frame then return entry end
	end
	return nil
end

return ActionTimeline
