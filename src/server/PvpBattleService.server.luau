local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")

local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local PvpProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("PvpProtocol"))
local BattleBalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BattleBalanceConfig"))
local CombatFormulas = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatFormulas"))
local DamagePipeline = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("DamagePipeline"))
local CombatAutoAbilities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatAutoAbilities"))
local CombatEventBus = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatEventBus"))

local MAX_DECK_SIZE = 5
local DEFAULT_ATTACK_INTERVAL_SECONDS = 5
local ATTACK_STAGGER_SECONDS = 0.7
local PVP_ABILITY_TICK_INTERVAL_SECONDS = math.max(0.02, tonumber(BattleBalanceConfig.Pvp.AbilityTickIntervalSeconds) or 0.08)
local DEFAULT_ABILITY_FIRST_CAST_DELAY_SECONDS = math.max(0, tonumber(BattleBalanceConfig.Pvp.AbilityFirstCastDelaySeconds) or 2.0)
local MIN_ABILITY_COOLDOWN_SECONDS = math.max(1, tonumber(BattleBalanceConfig.Defaults.AbilityMinCooldownSeconds) or 1)
local INVITE_TIMEOUT_SECONDS = 20
local CHALLENGE_THROTTLE_SECONDS = 0.75
local pvpWinsStore = DataStoreService:GetDataStore("PvpWinsV1")

local function shallowCopyStatBlock(t)
	if type(t) ~= "table" then
		return {}
	end
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

local inviteById = {}
local pendingInviteByTargetUserId = {}
local sessionByUserId = {}
local lastChallengeAtByUserId = {}
local winsByUserId = {}
local getPlayerByUserId

local function getOrCreateLeaderstats(player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if not (leaderstats and leaderstats:IsA("Folder")) then
		if leaderstats then
			leaderstats:Destroy()
		end
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local wins = leaderstats:FindFirstChild("PvpWins")
	if not (wins and wins:IsA("IntValue")) then
		if wins then
			wins:Destroy()
		end
		wins = Instance.new("IntValue")
		wins.Name = "PvpWins"
		wins.Value = 0
		wins.Parent = leaderstats
	end

	return wins
end

local function applyWins(player, winsCount)
	local safeWins = math.max(0, math.floor(tonumber(winsCount) or 0))
	winsByUserId[player.UserId] = safeWins
	getOrCreateLeaderstats(player).Value = safeWins
end

local function loadWins(player)
	getOrCreateLeaderstats(player).Value = 0
	local ok, result = pcall(function()
		return pvpWinsStore:GetAsync(player.UserId)
	end)
	if ok then
		applyWins(player, result)
	else
		warn("[PvP] Failed to load wins for " .. player.Name .. ": " .. tostring(result))
		applyWins(player, 0)
	end
end

local function saveWins(player)
	local wins = math.max(0, math.floor(tonumber(winsByUserId[player.UserId]) or 0))
	local ok, err = pcall(function()
		pvpWinsStore:SetAsync(player.UserId, wins)
	end)
	if not ok then
		warn("[PvP] Failed to save wins for " .. player.Name .. ": " .. tostring(err))
	end
end

local function awardWin(userId)
	userId = tonumber(userId)
	if not userId then
		return
	end
	local nextWins = math.max(0, math.floor(tonumber(winsByUserId[userId]) or 0)) + 1
	winsByUserId[userId] = nextWins
	local winnerPlayer = getPlayerByUserId(userId)
	if winnerPlayer then
		getOrCreateLeaderstats(winnerPlayer).Value = nextWins
	end
end

local function ensureRemoteFolder()
	local folder = ReplicatedStorage:FindFirstChild(PvpProtocol.Remotes.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = PvpProtocol.Remotes.FolderName
	folder.Parent = ReplicatedStorage
	return folder
end

local function ensureRemoteEvent(folder, remoteName)
	local remote = folder:FindFirstChild(remoteName)
	if remote and remote:IsA("RemoteEvent") then
		return remote
	end
	if remote then
		remote:Destroy()
	end
	remote = Instance.new("RemoteEvent")
	remote.Name = remoteName
	remote.Parent = folder
	return remote
end

local remotesFolder = ensureRemoteFolder()
local challengeRequestEvent = ensureRemoteEvent(remotesFolder, PvpProtocol.Remotes.ChallengeRequest)
local inviteEvent = ensureRemoteEvent(remotesFolder, PvpProtocol.Remotes.InviteEvent)
local inviteResponseEvent = ensureRemoteEvent(remotesFolder, PvpProtocol.Remotes.InviteResponse)
local sessionEvent = ensureRemoteEvent(remotesFolder, PvpProtocol.Remotes.SessionEvent)
local actionEvent = ensureRemoteEvent(remotesFolder, PvpProtocol.Remotes.ActionEvent)

local function sendInviteEvent(player, payload)
	if not player then
		return
	end
	local out = payload or {}
	out.protocolVersion = PvpProtocol.Version
	inviteEvent:FireClient(player, out)
end

local function sendSessionEvent(player, payload)
	if not player then
		return
	end
	local out = payload or {}
	out.protocolVersion = PvpProtocol.Version
	sessionEvent:FireClient(player, out)
end

getPlayerByUserId = function(userId)
	if type(userId) ~= "number" then
		return nil
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.UserId == userId then
			return p
		end
	end
	return nil
end

local function clearInvite(invite)
	if not invite then
		return
	end
	inviteById[invite.inviteId] = nil
	if pendingInviteByTargetUserId[invite.targetUserId] == invite then
		pendingInviteByTargetUserId[invite.targetUserId] = nil
	end
end

local function buildCardState(slotIndex, cardId)
	local profile = CardDatabase.GetCombatProfile(cardId, nil)
	if not profile then
		warn("[PvpBattle] Missing CardDatabase row for cardId=" .. tostring(cardId))
		return nil
	end
	local abilityCooldownSeconds = math.max(MIN_ABILITY_COOLDOWN_SECONDS, profile.abilityCooldownSeconds)
	local st = shallowCopyStatBlock(profile.statBlock)
	return {
		slotIndex = slotIndex,
		cardId = cardId,
		cardName = profile.cardName,
		attack = profile.baseAttack,
		baseAttack = profile.baseAttack,
		attackIntervalSeconds = profile.attackIntervalSeconds,
		baseAttackIntervalSeconds = profile.baseAttackIntervalSeconds,
		maxHealth = profile.maxHealth,
		health = profile.maxHealth,
		nextAttackAt = 0,
		nextAbilityAt = 0,
		abilityId = profile.abilityId,
		abilityCooldownSeconds = abilityCooldownSeconds,
		speedBoostMagnitude = 0,
		speedBoostUntil = 0,
		damageBoostMagnitude = 0,
		damageBoostUntil = 0,
		outgoingAttackDebuffPercent = 0,
		outgoingAttackDebuffUntil = 0,
		statBlock = st,
		deathNotified = false,
	}
end

local function sanitizeDeckSnapshot(rawDeck)
	if type(rawDeck) ~= "table" then
		return {}
	end
	local out = {}
	for _, rawEntry in ipairs(rawDeck) do
		if #out >= MAX_DECK_SIZE then
			break
		end
		local cardRef = rawEntry
		local slotIndex = nil
		if type(rawEntry) == "table" then
			cardRef = rawEntry.cardId
			slotIndex = tonumber(rawEntry.slotIndex)
		end
		if type(cardRef) == "string" and cardRef ~= "" then
			local resolved = CardDatabase.ResolveCardIdStrict(cardRef)
			if resolved then
				table.insert(out, {
					slotIndex = math.max(1, math.min(MAX_DECK_SIZE, math.floor(slotIndex or (#out + 1)))),
					cardId = resolved,
				})
			end
		end
	end
	table.sort(out, function(a, b)
		return a.slotIndex < b.slotIndex
	end)
	return out
end

local function aliveCards(cardStates)
	return CombatFormulas.FilterAlive(cardStates)
end

local function serializeCardStates(cardStates, now)
	local out = {}
	local currentNow = tonumber(now) or os.clock()
	for _, state in ipairs(cardStates or {}) do
		local sb = state.statBlock
		local statBlockOut = nil
		if type(sb) == "table" then
			statBlockOut = shallowCopyStatBlock(sb)
		end
		local debuffPct = tonumber(state.outgoingAttackDebuffPercent) or 0
		local debuffUntil = tonumber(state.outgoingAttackDebuffUntil) or 0
		local debuffRem = (debuffUntil > currentNow) and (debuffUntil - currentNow) or 0
		table.insert(out, {
			slotIndex = state.slotIndex,
			cardId = state.cardId,
			cardName = state.cardName,
			attack = CombatFormulas.GetEffectiveAttack(state, currentNow),
			maxHealth = state.maxHealth,
			health = state.health,
			isAlive = state.health > 0,
			statBlock = statBlockOut,
			outgoingAttackDebuffPercent = debuffPct,
			outgoingAttackDebuffRemainingSec = debuffRem,
		})
	end
	return out
end

local function finishSession(session, reason, winnerUserId)
	if not session or session.phase == PvpProtocol.SessionPhase.Ended then
		return
	end
	session.phase = PvpProtocol.SessionPhase.Ended
	session.endedReason = reason or "Ended"

	if winnerUserId == session.playerAUserId or winnerUserId == session.playerBUserId then
		awardWin(winnerUserId)
	end

	for _, userId in ipairs(session.playerUserIds) do
		sessionByUserId[userId] = nil
		local player = getPlayerByUserId(userId)
		if player then
			sendSessionEvent(player, {
				eventType = PvpProtocol.EventType.SessionEnded,
				sessionId = session.sessionId,
				phase = PvpProtocol.SessionPhase.Ended,
				reason = session.endedReason,
			})
		end
	end
end

local function emitStateUpdate(session, extra)
	local now = os.clock()
	local base = {
		eventType = PvpProtocol.EventType.StateUpdate,
		sessionId = session.sessionId,
		phase = session.phase,
		playerAUserId = session.playerAUserId,
		playerBUserId = session.playerBUserId,
		playerAName = session.playerAName,
		playerBName = session.playerBName,
		playerAStates = serializeCardStates(session.cardStatesByUserId[session.playerAUserId], now),
		playerBStates = serializeCardStates(session.cardStatesByUserId[session.playerBUserId], now),
	}
	if type(extra) == "table" then
		for k, v in pairs(extra) do
			base[k] = v
		end
	end

	for _, userId in ipairs(session.playerUserIds) do
		local player = getPlayerByUserId(userId)
		if player then
			sendSessionEvent(player, base)
		end
	end
end

local function runCombatLoop(session)
	task.spawn(function()
		local t0 = os.clock()
		local entryEvents = {}
		CombatAutoAbilities.ApplyOnBattleStartPvp(session, t0, entryEvents)
		if #entryEvents > 0 then
			emitStateUpdate(session, {
				reason = "OnEntryAbilities",
				abilityEvents = entryEvents,
			})
		end

		while session.phase == PvpProtocol.SessionPhase.InProgress do
			local playerAAlive = aliveCards(session.cardStatesByUserId[session.playerAUserId])
			local playerBAlive = aliveCards(session.cardStatesByUserId[session.playerBUserId])

			if #playerAAlive == 0 and #playerBAlive == 0 then
				finishSession(session, "Draw")
				break
			end
			if #playerAAlive == 0 then
				finishSession(session, session.playerBName .. " won", session.playerBUserId)
				break
			end
			if #playerBAlive == 0 then
				finishSession(session, session.playerAName .. " won", session.playerAUserId)
				break
			end

			local now = os.clock()
			local attacksThisTick = {}
			local abilityEvents = {}
			local lastHitByTargetKey = {}

			for _, attacker in ipairs(playerAAlive) do
				if attacker.abilityId ~= "" and attacker.nextAbilityAt <= now then
					CombatAutoAbilities.TryApply(
						session.cardStatesByUserId[session.playerAUserId],
						attacker,
						now,
						abilityEvents,
						{ attackerUserId = session.playerAUserId }
					)
					attacker.nextAbilityAt = now + math.max(MIN_ABILITY_COOLDOWN_SECONDS, tonumber(attacker.abilityCooldownSeconds) or MIN_ABILITY_COOLDOWN_SECONDS)
				end

				if attacker.nextAttackAt <= now then
					local defenders = aliveCards(session.cardStatesByUserId[session.playerBUserId])
					if #defenders > 0 then
						local target = defenders[math.random(1, #defenders)]
						local rawDamage = CombatFormulas.GetEffectiveAttack(attacker, now)
						local hitResult = DamagePipeline.ResolveHit(attacker, target, rawDamage, now)
						table.insert(attacksThisTick, {
							attackerUserId = session.playerAUserId,
							attackerSlotIndex = attacker.slotIndex,
							targetUserId = session.playerBUserId,
							targetSlotIndex = target.slotIndex,
							damage = hitResult.finalDamage,
							rawDamage = hitResult.rawDamage,
							isCrit = hitResult.isCrit,
							isDodged = hitResult.isDodged,
							absorbed = hitResult.absorbed,
						})
						lastHitByTargetKey[tostring(session.playerBUserId) .. ":" .. tostring(target.slotIndex)] = attacker
					end
					attacker.nextAttackAt = now + CombatFormulas.GetEffectiveAttackInterval(attacker, now, DEFAULT_ATTACK_INTERVAL_SECONDS)
				end
			end

			for _, attacker in ipairs(playerBAlive) do
				if attacker.abilityId ~= "" and attacker.nextAbilityAt <= now then
					CombatAutoAbilities.TryApply(
						session.cardStatesByUserId[session.playerBUserId],
						attacker,
						now,
						abilityEvents,
						{ attackerUserId = session.playerBUserId }
					)
					attacker.nextAbilityAt = now + math.max(MIN_ABILITY_COOLDOWN_SECONDS, tonumber(attacker.abilityCooldownSeconds) or MIN_ABILITY_COOLDOWN_SECONDS)
				end

				if attacker.nextAttackAt <= now then
					local defenders = aliveCards(session.cardStatesByUserId[session.playerAUserId])
					if #defenders > 0 then
						local target = defenders[math.random(1, #defenders)]
						local rawDamage = CombatFormulas.GetEffectiveAttack(attacker, now)
						local hitResult = DamagePipeline.ResolveHit(attacker, target, rawDamage, now)
						session.hitSeq = (session.hitSeq or 0) + 1
						table.insert(attacksThisTick, {
							attackerUserId = session.playerBUserId,
							attackerSlotIndex = attacker.slotIndex,
							targetUserId = session.playerAUserId,
							targetSlotIndex = target.slotIndex,
							damage = hitResult.finalDamage,
							rawDamage = hitResult.rawDamage,
							isCrit = hitResult.isCrit,
							isDodged = hitResult.isDodged,
							absorbed = hitResult.absorbed,
							hitSeq = session.hitSeq,
						})
						lastHitByTargetKey[tostring(session.playerAUserId) .. ":" .. tostring(target.slotIndex)] = attacker
					end
					attacker.nextAttackAt = now + CombatFormulas.GetEffectiveAttackInterval(attacker, now, DEFAULT_ATTACK_INTERVAL_SECONDS)
				end
			end

			if #attacksThisTick > 0 then
				for _, targetState in ipairs(session.cardStatesByUserId[session.playerAUserId]) do
					if targetState.health <= 0 and not targetState.deathNotified then
						targetState.deathNotified = true
						local killer = lastHitByTargetKey[tostring(session.playerAUserId) .. ":" .. tostring(targetState.slotIndex)]
						CombatEventBus.Fire("OnDeath", {
							session = session,
							unit = targetState,
							killer = killer,
						})
						if killer then
							CombatEventBus.Fire("OnKill", {
								session = session,
								attacker = killer,
								victim = targetState,
							})
						end
					end
				end
				for _, targetState in ipairs(session.cardStatesByUserId[session.playerBUserId]) do
					if targetState.health <= 0 and not targetState.deathNotified then
						targetState.deathNotified = true
						local killer = lastHitByTargetKey[tostring(session.playerBUserId) .. ":" .. tostring(targetState.slotIndex)]
						CombatEventBus.Fire("OnDeath", {
							session = session,
							unit = targetState,
							killer = killer,
						})
						if killer then
							CombatEventBus.Fire("OnKill", {
								session = session,
								attacker = killer,
								victim = targetState,
							})
						end
					end
				end

				emitStateUpdate(session, {
					attacks = attacksThisTick,
					abilityEvents = abilityEvents,
				})
				local aAliveAfter = aliveCards(session.cardStatesByUserId[session.playerAUserId])
				local bAliveAfter = aliveCards(session.cardStatesByUserId[session.playerBUserId])
				if #aAliveAfter == 0 or #bAliveAfter == 0 then
					task.wait(0.1)
				end
			elseif #abilityEvents > 0 then
				emitStateUpdate(session, {
					reason = "AbilityTriggered",
					abilityEvents = abilityEvents,
				})
			end

			task.wait(PVP_ABILITY_TICK_INTERVAL_SECONDS)
		end
	end)
end

local function createSession(playerA, playerB)
	local sessionId = PvpProtocol.MakeSessionId(playerA.UserId, playerB.UserId)
	local session = {
		sessionId = sessionId,
		phase = PvpProtocol.SessionPhase.Lobby,
		playerAUserId = playerA.UserId,
		playerBUserId = playerB.UserId,
		playerAName = playerA.Name,
		playerBName = playerB.Name,
		playerUserIds = {playerA.UserId, playerB.UserId},
		deckSubmittedByUserId = {
			[playerA.UserId] = false,
			[playerB.UserId] = false,
		},
		hitSeq = 0,
		cardStatesByUserId = {
			[playerA.UserId] = {},
			[playerB.UserId] = {},
		},
	}

	sessionByUserId[playerA.UserId] = session
	sessionByUserId[playerB.UserId] = session

	sendSessionEvent(playerA, {
		eventType = PvpProtocol.EventType.SessionStarted,
		sessionId = sessionId,
		phase = PvpProtocol.SessionPhase.Lobby,
		opponentUserId = playerB.UserId,
		opponentName = playerB.Name,
		selfUserId = playerA.UserId,
		rules = {
			maxDeckSize = MAX_DECK_SIZE,
				attackIntervalSeconds = DEFAULT_ATTACK_INTERVAL_SECONDS,
		},
	})

	sendSessionEvent(playerB, {
		eventType = PvpProtocol.EventType.SessionStarted,
		sessionId = sessionId,
		phase = PvpProtocol.SessionPhase.Lobby,
		opponentUserId = playerA.UserId,
		opponentName = playerA.Name,
		selfUserId = playerB.UserId,
		rules = {
			maxDeckSize = MAX_DECK_SIZE,
				attackIntervalSeconds = DEFAULT_ATTACK_INTERVAL_SECONDS,
		},
	})

	return session
end

challengeRequestEvent.OnServerEvent:Connect(function(challenger, payload)
	if type(payload) ~= "table" then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "InvalidPayload"})
		return
	end

	local targetUserId = tonumber(payload.targetUserId)
	if not targetUserId or targetUserId == challenger.UserId then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "InvalidTarget"})
		return
	end

	local now = os.clock()
	local last = lastChallengeAtByUserId[challenger.UserId] or 0
	if (now - last) < CHALLENGE_THROTTLE_SECONDS then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "ChallengeThrottled"})
		return
	end
	lastChallengeAtByUserId[challenger.UserId] = now

	if sessionByUserId[challenger.UserId] then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "AlreadyInSession"})
		return
	end

	local targetPlayer = getPlayerByUserId(targetUserId)
	if not targetPlayer then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "TargetOffline"})
		return
	end

	if sessionByUserId[targetUserId] then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "TargetBusy"})
		return
	end

	if pendingInviteByTargetUserId[targetUserId] then
		sendInviteEvent(challenger, {eventType = PvpProtocol.EventType.ErrorEvent, reason = "TargetHasPendingInvite"})
		return
	end

	local inviteId = PvpProtocol.MakeInviteId(challenger.UserId, targetUserId)
	local invite = {
		inviteId = inviteId,
		challengerUserId = challenger.UserId,
		challengerName = challenger.Name,
		targetUserId = targetUserId,
		targetName = targetPlayer.Name,
		createdAt = now,
		expiresAt = now + INVITE_TIMEOUT_SECONDS,
	}
	inviteById[inviteId] = invite
	pendingInviteByTargetUserId[targetUserId] = invite

	sendInviteEvent(challenger, {
		eventType = PvpProtocol.EventType.InviteSent,
		inviteId = inviteId,
		targetUserId = targetUserId,
		targetName = targetPlayer.Name,
		timeoutSeconds = INVITE_TIMEOUT_SECONDS,
	})

	sendInviteEvent(targetPlayer, {
		eventType = PvpProtocol.EventType.InviteReceived,
		inviteId = inviteId,
		challengerUserId = challenger.UserId,
		challengerName = challenger.Name,
		timeoutSeconds = INVITE_TIMEOUT_SECONDS,
	})

	task.delay(INVITE_TIMEOUT_SECONDS, function()
		local activeInvite = inviteById[inviteId]
		if not activeInvite then
			return
		end
		clearInvite(activeInvite)
		local challengerPlayer = getPlayerByUserId(activeInvite.challengerUserId)
		local target = getPlayerByUserId(activeInvite.targetUserId)
		if challengerPlayer then
			sendInviteEvent(challengerPlayer, {
				eventType = PvpProtocol.EventType.InviteExpired,
				inviteId = inviteId,
				targetName = activeInvite.targetName,
			})
		end
		if target then
			sendInviteEvent(target, {
				eventType = PvpProtocol.EventType.InviteExpired,
				inviteId = inviteId,
				challengerName = activeInvite.challengerName,
			})
		end
	end)
end)

inviteResponseEvent.OnServerEvent:Connect(function(targetPlayer, payload)
	if type(payload) ~= "table" then
		return
	end
	local inviteId = tostring(payload.inviteId or "")
	if inviteId == "" then
		return
	end
	local accepted = payload.accepted == true

	local invite = inviteById[inviteId]
	if not invite then
		return
	end
	if invite.targetUserId ~= targetPlayer.UserId then
		return
	end
	if os.clock() > invite.expiresAt then
		clearInvite(invite)
		return
	end

	local challengerPlayer = getPlayerByUserId(invite.challengerUserId)
	if not challengerPlayer then
		clearInvite(invite)
		sendInviteEvent(targetPlayer, {
			eventType = PvpProtocol.EventType.ErrorEvent,
			reason = "ChallengerOffline",
		})
		return
	end

	if not accepted then
		clearInvite(invite)
		sendInviteEvent(challengerPlayer, {
			eventType = PvpProtocol.EventType.InviteDeclined,
			inviteId = invite.inviteId,
			targetName = invite.targetName,
		})
		return
	end

	if sessionByUserId[challengerPlayer.UserId] or sessionByUserId[targetPlayer.UserId] then
		clearInvite(invite)
		sendInviteEvent(challengerPlayer, {
			eventType = PvpProtocol.EventType.ErrorEvent,
			reason = "PlayerBusy",
		})
		sendInviteEvent(targetPlayer, {
			eventType = PvpProtocol.EventType.ErrorEvent,
			reason = "PlayerBusy",
		})
		return
	end

	clearInvite(invite)
	createSession(challengerPlayer, targetPlayer)
end)

actionEvent.OnServerEvent:Connect(function(player, payload)
	local session = sessionByUserId[player.UserId]
	if not session then
		sendSessionEvent(player, {
			eventType = PvpProtocol.EventType.ErrorEvent,
			reason = "NoActiveSession",
		})
		return
	end
	if type(payload) ~= "table" then
		return
	end

	local actionType = payload.actionType
	if actionType == PvpProtocol.ActionType.Surrender then
		local winnerUserId = (player.UserId == session.playerAUserId) and session.playerBUserId or session.playerAUserId
		local winnerName = (player.UserId == session.playerAUserId) and session.playerBName or session.playerAName
		finishSession(session, winnerName .. " won by surrender", winnerUserId)
		return
	end

	if actionType ~= PvpProtocol.ActionType.SubmitDeckSnapshot then
		return
	end

	if session.phase == PvpProtocol.SessionPhase.Ended then
		return
	end

	local deck = sanitizeDeckSnapshot(payload.deck)
	local cardStates = {}
	for _, entry in ipairs(deck) do
		local st = buildCardState(entry.slotIndex, entry.cardId)
		if st then
			table.insert(cardStates, st)
		end
	end

	local now = os.clock()
	table.sort(cardStates, function(a, b)
		return a.slotIndex < b.slotIndex
	end)
	for index, state in ipairs(cardStates) do
		state.nextAttackAt = now + ((index - 1) * ATTACK_STAGGER_SECONDS)
		state.nextAbilityAt = now + DEFAULT_ABILITY_FIRST_CAST_DELAY_SECONDS
	end

	session.cardStatesByUserId[player.UserId] = cardStates
	session.deckSubmittedByUserId[player.UserId] = true

	local aReady = session.deckSubmittedByUserId[session.playerAUserId]
	local bReady = session.deckSubmittedByUserId[session.playerBUserId]
	if aReady and bReady and session.phase == PvpProtocol.SessionPhase.Lobby then
		session.phase = PvpProtocol.SessionPhase.InProgress
		emitStateUpdate(session, {
			reason = "BattleStarted",
		})
		runCombatLoop(session)
	else
		emitStateUpdate(session, {
			reason = "AwaitingBothDecks",
		})
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local session = sessionByUserId[player.UserId]
	if session then
		local winnerUserId = (player.UserId == session.playerAUserId) and session.playerBUserId or session.playerAUserId
		local winnerName = (player.UserId == session.playerAUserId) and session.playerBName or session.playerAName
		finishSession(session, winnerName .. " won (opponent left)", winnerUserId)
	end

	if pendingInviteByTargetUserId[player.UserId] then
		clearInvite(pendingInviteByTargetUserId[player.UserId])
	end

	local removeInviteIds = {}
	for inviteId, invite in pairs(inviteById) do
		if invite.challengerUserId == player.UserId or invite.targetUserId == player.UserId then
			table.insert(removeInviteIds, inviteId)
		end
	end
	for _, inviteId in ipairs(removeInviteIds) do
		clearInvite(inviteById[inviteId])
	end

	lastChallengeAtByUserId[player.UserId] = nil
	saveWins(player)
	winsByUserId[player.UserId] = nil
end)

for _, p in ipairs(Players:GetPlayers()) do
	loadWins(p)
end

Players.PlayerAdded:Connect(function(p)
	loadWins(p)
end)
