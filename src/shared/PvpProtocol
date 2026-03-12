local PvpProtocol = {}

PvpProtocol.Version = 1

PvpProtocol.Remotes = {
	FolderName = "PvpRemotes",
	ChallengeRequest = "PvpChallengeRequest",
	InviteEvent = "PvpInviteEvent",
	InviteResponse = "PvpInviteResponse",
	SessionEvent = "PvpSessionEvent",
	ActionEvent = "PvpActionEvent",
}

PvpProtocol.ActionType = {
	SubmitDeckSnapshot = "SubmitDeckSnapshot",
	Surrender = "Surrender",
}

PvpProtocol.EventType = {
	InviteSent = "InviteSent",
	InviteReceived = "InviteReceived",
	InviteExpired = "InviteExpired",
	InviteDeclined = "InviteDeclined",
	SessionStarted = "SessionStarted",
	StateUpdate = "StateUpdate",
	SessionEnded = "SessionEnded",
	ErrorEvent = "ErrorEvent",
}

PvpProtocol.SessionPhase = {
	Lobby = "Lobby",
	InProgress = "InProgress",
	Ended = "Ended",
}

function PvpProtocol.MakeInviteId(challengerUserId, targetUserId)
	return string.format("%d_%d_%d", tonumber(challengerUserId) or 0, tonumber(targetUserId) or 0, math.floor(os.clock() * 1000))
end

function PvpProtocol.MakeSessionId(playerAUserId, playerBUserId)
	local a = tonumber(playerAUserId) or 0
	local b = tonumber(playerBUserId) or 0
	if b < a then
		a, b = b, a
	end
	return string.format("pvp_%d_%d_%d", a, b, math.floor(os.clock() * 1000))
end

return PvpProtocol
