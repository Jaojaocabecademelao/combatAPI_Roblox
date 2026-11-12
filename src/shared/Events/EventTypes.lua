--!strict

return table.freeze({
	EntityCreated = "EntityCreated", EntityDestroyed = "EntityDestroyed", EntityRespawned = "EntityRespawned",
	HitConfirmed = "HitConfirmed", HitRejected = "HitRejected",
	DamageApplied = "DamageApplied", HealApplied = "HealApplied",
	StatusEffectApplied = "StatusEffectApplied", Death = "Death", Block = "Block", Parry = "Parry",
	GuardBreak = "GuardBreak", ComboStarted = "ComboStarted", ComboUpdated = "ComboUpdated",
	ComboEnded = "ComboEnded", JuggleStarted = "JuggleStarted", JuggleEnded = "JuggleEnded",
	MovementStateChanged = "MovementStateChanged", CancelAllowed = "CancelAllowed",
	CancelRejected = "CancelRejected", InputPressed = "InputPressed", InputReleased = "InputReleased",
	PredictionDiverged = "PredictionDiverged", FrameConfirmed = "FrameConfirmed",
	RollbackStarted = "RollbackStarted", RollbackCompleted = "RollbackCompleted",
	RollbackFailed = "RollbackFailed", AuthorityInputAccepted = "AuthorityInputAccepted",
	AuthorityInputRejected = "AuthorityInputRejected", AuthoritySnapshotPublished = "AuthoritySnapshotPublished",
	Clash = "Clash", ArmorApplied = "ArmorApplied", MotionApplied = "MotionApplied",
	HitstopStarted = "HitstopStarted", HitstopEnded = "HitstopEnded", CounterHit = "CounterHit",
	ProtectionApplied = "ProtectionApplied",
	PluginRegistered = "PluginRegistered", PluginInitializing = "PluginInitializing", PluginStarted = "PluginStarted",
	PluginStopping = "PluginStopping", PluginStopped = "PluginStopped", PluginFailed = "PluginFailed",
	PluginEnabled = "PluginEnabled", PluginDisabled = "PluginDisabled", PluginDependencyFailed = "PluginDependencyFailed",
	PluginCapabilityRegistered = "PluginCapabilityRegistered", PluginCapabilityUnregistered = "PluginCapabilityUnregistered",
})
