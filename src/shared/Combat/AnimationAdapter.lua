local Adapter = {}
Adapter.__index = Adapter
function Adapter.new(adapterId, callbacks)
	assert(type(adapterId) == "string" and adapterId ~= "", "AnimationAdapter id is required")
	callbacks = callbacks or {}
	return setmetatable({
		Id = adapterId, IsValid = callbacks.IsValid, Play = callbacks.Play,
		Pause = callbacks.Pause, Resume = callbacks.Resume, Stop = callbacks.Stop,
		SetSpeed = callbacks.SetSpeed, SetWeight = callbacks.SetWeight,
		SetPriority = callbacks.SetPriority,
	}, Adapter)
end
function Adapter:Validate(entity, definition, context)
	return self.IsValid == nil or self.IsValid(entity, definition, context) == true
end
function Adapter:Call(name, ...) if self[name] then return self[name](...) ~= false end; return true end
return Adapter
