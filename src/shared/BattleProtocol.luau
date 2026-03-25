local BattleProtocol = {}

BattleProtocol.Version = 1

BattleProtocol.Remotes = {
	FolderName = "BattleRemotes",
	RequestBattle = "RequestNpcBattle",
	BattleInvite = "NpcBattleInvite",
	BattleState = "NpcBattleState",
	BattleAction = "NpcBattleAction",
}

BattleProtocol.SessionPhase = {
	Lobby = "Lobby",
	InProgress = "InProgress",
	Ended = "Ended",
}

BattleProtocol.ActionType = {
	SubmitDeckSnapshot = "SubmitDeckSnapshot",
	Surrender = "Surrender",
}

BattleProtocol.EventType = {
	SessionStarted = "SessionStarted",
	SessionEnded = "SessionEnded",
	-- PvE battle tick + damage visuals (enemy is a generic NPC, not boss-only).
	NpcState = "NpcState",
	-- Legacy alias: same wire string as NpcState.
	BossState = "NpcState",
	ActionAccepted = "ActionAccepted",
	Error = "Error",
}

function BattleProtocol.IsValidNpcId(value)
	return type(value) == "string" and value ~= ""
end

function BattleProtocol.MakeSessionId(playerUserId, npcId)
	local clockToken = math.floor(os.clock() * 1000)
	return string.format("%s_%d_%d", tostring(npcId), tonumber(playerUserId) or 0, clockToken)
end

return BattleProtocol
