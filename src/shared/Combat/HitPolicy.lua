local HitPolicy = {
	Once = "Once",
	Multi = "Multi",
	Scope = {
		AttackInstance = "AttackInstance",
		Hitbox = "Hitbox",
	},
}

function HitPolicy.Validate(policy)
	assert(policy == HitPolicy.Once or policy == HitPolicy.Multi,
		"HitPolicy must be HitPolicy.Once or HitPolicy.Multi")
	return policy
end

function HitPolicy.ValidateScope(scope)
	assert(scope == HitPolicy.Scope.AttackInstance or scope == HitPolicy.Scope.Hitbox,
		"Hit scope must be AttackInstance or Hitbox")
	return scope
end

return HitPolicy
