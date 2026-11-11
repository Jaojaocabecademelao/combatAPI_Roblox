local Definition = require(script.Parent.CombatActionDefinition)

local Profiles = {}

local function definition(options)
	return Definition.new(options)
end

function Profiles.Melee()
	return definition({
		Id = "profile.melee.light",
		StartupFrames = 2,
		ActiveFrames = 2,
		RecoveryFrames = 3,
		Cancelable = true,
		Tags = { "Melee", "SingleTarget" },
	})
end

function Profiles.Projectile()
	return definition({
		Id = "profile.projectile.basic",
		StartupFrames = 1,
		ActiveFrames = 1,
		RecoveryFrames = 2,
		Cancelable = true,
		Tags = { "Projectile", "Ranged" },
	})
end

function Profiles.AreaOfEffect()
	return definition({
		Id = "profile.area.burst",
		StartupFrames = 3,
		ActiveFrames = 3,
		RecoveryFrames = 4,
		Cancelable = false,
		Tags = { "AreaOfEffect", "MultiTarget" },
	})
end

return table.freeze(Profiles)
