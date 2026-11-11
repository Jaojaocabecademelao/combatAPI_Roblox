local DamageRequest = require(script.Parent.DamageRequest)

local Resolver = {}
Resolver.__index = Resolver

local function copyArray(values)
	local result = {}
	for _, value in ipairs(values) do result[#result + 1] = value end
	return result
end

function Resolver.new(world)
	return setmetatable({ World = world, Events = {} }, Resolver)
end

function Resolver:Process(requests, frame, time)
	assert(type(requests) == "table", "StatusEffectResolver:Process() expects effect requests")
	assert(type(frame) == "number" and frame >= 0 and frame < math.huge and frame % 1 == 0,
		"StatusEffectResolver frame must be a non-negative integer")
	assert(type(time) == "number" and time == time and time > -math.huge and time < math.huge,
		"StatusEffectResolver time must be finite")
	table.clear(self.Events)
	if #requests == 0 then return self:GetEvents() end

	local damageResolver = self.World:GetDamageResolver()
	assert(damageResolver ~= nil, "Periodic status effects require a DamageResolver")
	for _, request in ipairs(requests) do
		local status, target = request.Status, request.Target
		if status and status.Active and status:IsEnabled() and status.Entity == target
			and target and not target.Destroyed and self.World:GetEntity(target.Id) == target then
			local resolved
			if request.Type == "DamageOverTime" then
				resolved = damageResolver:Resolve(DamageRequest.new({
					Amount = request.Amount,
					Type = request.DamageType,
					Source = request.Source,
					Target = target,
					Frame = frame,
					Time = time,
				}), frame, time)
			elseif request.Type == "HealingOverTime" then
				resolved = damageResolver:Heal(target, request.Amount, frame, time, {
					Reason = "StatusEffect",
					Source = request.Source,
					StatusName = request.StatusName,
					EffectId = request.EffectId,
				})
			else
				error("Unsupported periodic status effect type: " .. tostring(request.Type))
			end
			if resolved then
				table.insert(self.Events, {
					Type = request.Type,
					Target = target,
					Source = request.Source,
					StatusName = request.StatusName,
					EffectId = request.EffectId,
					Amount = request.Amount,
					AppliedAmount = request.Type == "DamageOverTime"
						and resolved.AppliedAmount or resolved.Delta,
					Frame = frame,
					Time = time,
				})
			end
		end
	end
	return self:GetEvents()
end

function Resolver:GetEvents()
	return copyArray(self.Events)
end

return Resolver
