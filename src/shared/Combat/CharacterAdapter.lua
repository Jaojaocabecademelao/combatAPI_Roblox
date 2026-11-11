local Adapter = {}
Adapter.__index = Adapter

function Adapter.new(adapterId, callbacks)
	assert(type(adapterId) == "string" and adapterId ~= "", "CharacterAdapter id is required")
	assert(type(callbacks) == "table", "CharacterAdapter callbacks are required")
	return setmetatable({
		Id = adapterId,
		IsValid = callbacks.IsValid,
		Attach = callbacks.Attach,
		Detach = callbacks.Detach,
		GetRepresentation = callbacks.GetRepresentation,
		GetRoot = callbacks.GetRoot,
		GetPart = callbacks.GetPart,
	}, Adapter)
end

function Adapter:Validate(representation, context)
	return type(self.IsValid) == "function" and self.IsValid(representation, context) == true
end

function Adapter:AttachRepresentation(entityId, representation, context)
	if self.Attach then return self.Attach(entityId, representation, context) ~= false end
	return true
end

function Adapter:DetachRepresentation(entityId, representation, context)
	if self.Detach then return self.Detach(entityId, representation, context) ~= false end
	return true
end

function Adapter:GetRepresentation(representation, context)
	if self.GetRepresentation then return self.GetRepresentation(representation, context) end
	return representation
end

function Adapter:GetRoot(representation, context)
	if self.GetRoot then return self.GetRoot(representation, context) end
	return nil
end

function Adapter:GetPart(representation, partName, context)
	if self.GetPart then return self.GetPart(representation, partName, context) end
	return nil
end

return Adapter
