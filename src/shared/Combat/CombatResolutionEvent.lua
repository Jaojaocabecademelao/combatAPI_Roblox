local CombatResolutionEvent = {}
CombatResolutionEvent.__index = CombatResolutionEvent

function CombatResolutionEvent.new(data)
	assert(type(data) == "table", "CombatResolutionEvent.new() expects a data table")
	return setmetatable({
		Id = data.Id,
		Frame = data.Frame,
		Outcome = data.Outcome,
		OutcomeA = data.OutcomeA,
		OutcomeB = data.OutcomeB,
		AttackInstanceA = data.AttackInstanceA,
		AttackInstanceB = data.AttackInstanceB,
		AttackInstanceIdA = data.AttackInstanceIdA,
		AttackInstanceIdB = data.AttackInstanceIdB,
		HitEventA = data.HitEventA,
		HitEventB = data.HitEventB,
		PriorityA = data.PriorityA,
		PriorityB = data.PriorityB,
		AttackerEntityIdA = data.AttackerEntityIdA,
		TargetEntityIdA = data.TargetEntityIdA,
		AttackerEntityIdB = data.AttackerEntityIdB,
		TargetEntityIdB = data.TargetEntityIdB,
		HitboxIdA = data.HitboxIdA,
		HurtboxIdA = data.HurtboxIdA,
		Winner = data.Winner,
		Loser = data.Loser,
		WinnerAttackInstance = data.WinnerAttackInstance,
		LoserAttackInstance = data.LoserAttackInstance,
	}, CombatResolutionEvent)
end

return CombatResolutionEvent
