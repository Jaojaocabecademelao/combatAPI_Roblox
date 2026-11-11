local CharacterAdapter = require(script.Parent.CharacterAdapter)

local Adapter = {}

local function valueOf(representation)
	if type(representation) == "table" and type(representation.GetValue) == "function" then
		return representation:GetValue()
	end
	return representation
end

local function isHumanoidModel(value)
	return typeof(value) == "Instance"
		and value:IsA("Model")
		and value:FindFirstChildOfClass("Humanoid") ~= nil
end

function Adapter.new(adapterId)
	return CharacterAdapter.new(adapterId or "RobloxHumanoid", {
		IsValid = function(representation)
			return isHumanoidModel(valueOf(representation))
		end,
		GetRepresentation = function(representation)
			return valueOf(representation)
		end,
		GetRoot = function(representation)
			local model = valueOf(representation)
			return model and model:FindFirstChild("HumanoidRootPart")
				or (model and model.PrimaryPart)
		end,
		GetPart = function(representation, partName)
			local model = valueOf(representation)
			return model and model:FindFirstChild(partName) or nil
		end,
	})
end

return Adapter
