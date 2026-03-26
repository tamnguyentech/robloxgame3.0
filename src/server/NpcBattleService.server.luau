local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BattleProtocol = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BattleProtocol"))
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local ServerStateManager = require(script.Parent.core:WaitForChild("ServerStateManager"))
local BattleBalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BattleBalanceConfig"))
local CombatFormulas = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatFormulas"))
local DamagePipeline = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("DamagePipeline"))
local CombatAutoAbilities = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatAutoAbilities"))
local CombatEventBus = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatEventBus"))
local CombatFollowUpDispatcher = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatFollowUpDispatcher"))
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatOnHitAbilities"))
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("combat"):WaitForChild("CombatOnDeathAbilities"))

local FIRST_ATTACK_STAGGER_SECONDS = 2
local NPC_COUNTER_ATTACK_INTERVAL_SECONDS = 4
local DEFAULT_PLAYER_ATTACK_INTERVAL_SECONDS = 5
-- Client-side animation pacing for entry multi-hit visuals.
-- Keep in sync with `NpcBattleClient`'s `ENTRY_MULTI_HIT_STAGGER_SEC`.
local MULTI_HIT_VISUAL_STAGGER_SECONDS = 0.34
-- Keep Starburst's 3 follow-up hits readable as a true "triple hit" (~1s window).
local BURST_FOLLOWUP_STAGGER_SECONDS = 0.5
local ATTACK_ANIM_LOCK_SECONDS = 0.35
local PVE_ABILITY_TICK_INTERVAL_SECONDS = math.max(0.02, tonumber(BattleBalanceConfig.Pve.AbilityTickIntervalSeconds) or 0.08)
local DEFAULT_ABILITY_FIRST_CAST_DELAY_SECONDS = math.max(0, tonumber(BattleBalanceConfig.Pve.AbilityFirstCastDelaySeconds) or 2.0)
local MIN_ABILITY_COOLDOWN_SECONDS = math.max(1, tonumber(BattleBalanceConfig.Defaults.AbilityMinCooldownSeconds) or 1)

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

local NPC_REGISTRY = {
	PerfectCell = {
		NpcId = "PerfectCell",
		DisplayName = "Perfect Cell",
		WorkspaceName = "PerfectCell",
		InteractionRange = 24,
		PromptText = "Battle",
		ObjectText = "Perfect Cell",
		HoldDuration = 0.12,
		NpcCardId = "PerfectCell",
		NpcCardName = "Perfect Cell",
		NpcMaxHealth = 1000000,
		NpcAttack = 5000,
	},
	Aokoji = {
		NpcId = "Aokoji",
		DisplayName = "Aokoji",
		WorkspaceName = "Aokoji",
		InteractionRange = 24,
		PromptText = "Battle",
		ObjectText = "Aokoji",
		HoldDuration = 0.12,
		NpcCardId = "Aokoji",
		NpcCardName = "Aokoji",
		NpcMaxHealth = 10000000000,
		NpcAttack = 4000000,
	},
}

local npcById = {}
for _, record in pairs(NPC_REGISTRY) do
	npcById[record.NpcId] = record
end

local activeSessionByPlayer = {}
local lastRequestByPlayer = {}
local promptConnections = {}

local function scrubCharacterPrompts(character)
	if not character then
		return
	end
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			local conn = promptConnections[descendant]
			if conn then
				conn:Disconnect()
				promptConnections[descendant] = nil
			end
			descendant:Destroy()
		end
	end
end

local function attachCharacterPromptScrubber(player)
	player.CharacterAdded:Connect(function(character)
		task.defer(function()
			scrubCharacterPrompts(character)
			local descConn
			descConn = character.DescendantAdded:Connect(function(descendant)
				if descendant:IsA("ProximityPrompt") then
					local conn = promptConnections[descendant]
					if conn then
						conn:Disconnect()
						promptConnections[descendant] = nil
					end
					descendant:Destroy()
				end
			end)
			character.AncestryChanged:Connect(function(_, parent)
				if parent == nil and descConn then
					descConn:Disconnect()
					descConn = nil
				end
			end)
		end)
	end)

	if player.Character then
		task.defer(function()
			scrubCharacterPrompts(player.Character)
		end)
	end
end

local function ensureRemoteFolder()
	local folder = ReplicatedStorage:FindFirstChild(BattleProtocol.Remotes.FolderName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	if folder then
		folder:Destroy()
	end
	folder = Instance.new("Folder")
	folder.Name = BattleProtocol.Remotes.FolderName
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
local requestBattleEvent = ensureRemoteEvent(remotesFolder, BattleProtocol.Remotes.RequestBattle)
local battleInviteEvent = ensureRemoteEvent(remotesFolder, BattleProtocol.Remotes.BattleInvite)
local battleStateEvent = ensureRemoteEvent(remotesFolder, BattleProtocol.Remotes.BattleState)
local battleActionEvent = ensureRemoteEvent(remotesFolder, BattleProtocol.Remotes.BattleAction)

local function getWorldPosition(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		return instance:GetPivot().Position
	end
	return nil
end

local function findPromptPart(instance)
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		if instance.PrimaryPart then
			return instance.PrimaryPart
		end
		local humanoidRoot = instance:FindFirstChild("HumanoidRootPart")
		if humanoidRoot and humanoidRoot:IsA("BasePart") then
			return humanoidRoot
		end
		return instance:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function resolveNpcInstance(record)
	if not record then
		return nil
	end

	-- Prefer a direct top-level workspace object when available.
	local direct = Workspace:FindFirstChild(record.WorkspaceName)
	if direct then
		return direct
	end

	-- Fall back to descendants, but never bind prompts inside player characters.
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant.Name == record.WorkspaceName and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
			local isInCharacter = false
			for _, player in ipairs(Players:GetPlayers()) do
				local character = player.Character
				if character and descendant:IsDescendantOf(character) then
					isInCharacter = true
					break
				end
			end
			if not isInCharacter then
				return descendant
			end
		end
	end

	return nil
end

local function cleanupStalePrompts()
	for _, descendant in ipairs(Workspace:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			local promptLooksNpcBattle = descendant.Name == "NpcBattlePrompt"
				or descendant.ObjectText == "Perfect Cell"
				or descendant.ActionText == "Battle"
				or descendant.ActionText == "Challenge"

			if not promptLooksNpcBattle then
				continue
			end

			local shouldKeep = false
			for _, record in pairs(NPC_REGISTRY) do
				local npcInstance = resolveNpcInstance(record)
				if npcInstance and descendant:IsDescendantOf(npcInstance) then
					shouldKeep = true
					break
				end
			end

			if shouldKeep then
				for _, p in ipairs(Players:GetPlayers()) do
					local character = p.Character
					if character and descendant:IsDescendantOf(character) then
						shouldKeep = false
						break
					end
				end
			end

			if not shouldKeep then
				local conn = promptConnections[descendant]
				if conn then
					conn:Disconnect()
					promptConnections[descendant] = nil
				end
				descendant:Destroy()
			end
		end
	end
end

local function sendState(player, payload)
	if not player then
		return
	end
	local out = payload or {}
	out.protocolVersion = BattleProtocol.Version
	battleStateEvent:FireClient(player, out)
end

local function finishSession(player, reason)
	local session = activeSessionByPlayer[player]
	if not session then
		return
	end
	session.isClosed = true
	activeSessionByPlayer[player] = nil
	sendState(player, {
		eventType = BattleProtocol.EventType.SessionEnded,
		sessionId = session.sessionId,
		npcId = session.npcId,
		phase = BattleProtocol.SessionPhase.Ended,
		reason = reason or "Completed",
	})
end

local function sanitizeDeckSnapshot(rawDeck)
	if type(rawDeck) ~= "table" then
		return {}
	end

	local out = {}
	for _, rawEntry in ipairs(rawDeck) do
		if #out >= 5 then
			break
		end

		local cardRef = rawEntry
		local slotIndex = nil
		if type(rawEntry) == "table" then
			cardRef = rawEntry.cardId
			slotIndex = tonumber(rawEntry.slotIndex)
		end

		if type(cardRef) == "string" and cardRef ~= "" then
			local parsed = CardDatabase.ParseCardReference(cardRef)
			local resolved = (parsed and parsed.CardRef) or cardRef
			if resolved then
				table.insert(out, {
					cardId = resolved,
					slotIndex = (slotIndex and math.floor(slotIndex)) or (#out + 1),
				})
			end
		end
	end

	return out
end

local function buildPlayerCardStatePayload(session)
	local payload = {}
	local now = os.clock()
	for _, state in ipairs(session.playerCardStates or {}) do
		local sb = state.statBlock
		local statBlockOut = nil
		if type(sb) == "table" then
			statBlockOut = shallowCopyStatBlock(sb)
		end
		local spdUntil = tonumber(state.speedBoostUntil) or 0
		local spdMag = tonumber(state.speedBoostMagnitude) or 0
		local spdRem = (spdUntil > now and spdMag > 0) and (spdUntil - now) or 0
		local sealUntil = tonumber(state.sealUntil) or 0
		local sealRem = (sealUntil > now) and (sealUntil - now) or 0
		table.insert(payload, {
			slotIndex = state.slotIndex,
			cardId = state.cardId,
			cardName = state.cardName,
			attack = CombatFormulas.GetEffectiveAttack(state, now),
			maxHealth = state.maxHealth,
			health = state.health,
			isAlive = state.health > 0,
			statBlock = statBlockOut,
			speedBoostMagnitude = spdMag,
			speedBoostRemainingSec = spdRem,
			sealRemainingSec = sealRem,
		})
	end
	return payload
end

local function getAliveCardStates(session)
	local out = {}
	for _, state in ipairs(session.playerCardStates or {}) do
		if state.health > 0 then
			table.insert(out, state)
		end
	end
	return out
end

local function getCardStateBySlot(session, slotIndex)
	for _, state in ipairs(session.playerCardStates or {}) do
		if state.slotIndex == slotIndex then
			return state
		end
	end
	return nil
end

local function pruneDeadAttackers(session)
	if type(session.attackState) ~= "table" then
		return
	end

	local aliveBySlot = {}
	for _, state in ipairs(session.playerCardStates or {}) do
		if state.health > 0 then
			aliveBySlot[state.slotIndex] = true
		end
	end

	for i = #session.attackState, 1, -1 do
		local attacker = session.attackState[i]
		if not aliveBySlot[attacker.slotIndex] then
			table.remove(session.attackState, i)
		end
	end
end

local function shuffleInPlace(list)
	for i = #list, 2, -1 do
		local j = math.random(1, i)
		list[i], list[j] = list[j], list[i]
	end
end

local function applyPlayerHitDamageToNpc(session, hitResult, now)
	local dealtDamage = hitResult.finalDamage
	local incomingBonusUntil = tonumber(session.npcIncomingDamageBonusUntil) or 0
	if incomingBonusUntil > now then
		local incomingBonusFraction = math.clamp(tonumber(session.npcIncomingDamageBonusFraction) or 0, 0, 2)
		if incomingBonusFraction > 0 then
			dealtDamage = math.max(0, math.floor(dealtDamage * (1 + incomingBonusFraction)))
		end
	end
	DamagePipeline.ApplyDamageToNpc(session, dealtDamage)
	return dealtDamage
end

local function sendNpcState(player, session, payload)
	local out = payload or {}
	session.hitSeq = (session.hitSeq or 0) + 1
	out.hitSeq = session.hitSeq
	out.eventType = BattleProtocol.EventType.NpcState
	out.sessionId = session.sessionId
	out.npcId = session.npcId
	out.phase = session.phase
	out.npcCardId = session.npcCardId
	out.npcCardName = session.npcCardName
	out.npcMaxHealth = session.npcMaxHealth
	out.npcHealth = session.npcHealth
	out.npcAttack = session.npcAttack
	out.nextAttackInSeconds = DEFAULT_PLAYER_ATTACK_INTERVAL_SECONDS
	local now = os.clock()
	out.npcOutgoingAttackDebuffPercent = tonumber(session.npcOutgoingAttackDebuffPercent) or 0
	local untilT = tonumber(session.npcOutgoingAttackDebuffUntil) or 0
	out.npcOutgoingAttackDebuffRemainingSec = (untilT > now) and (untilT - now) or 0
	out.npcHealingReductionFraction = tonumber(session.npcHealingReductionFraction) or 0
	local healRedUntil = tonumber(session.npcHealingReductionUntil) or 0
	out.npcHealingReductionRemainingSec = (healRedUntil > now) and (healRedUntil - now) or 0
	local npcStunUntil = tonumber(session.npcStunUntil) or 0
	out.npcStunRemainingSec = (npcStunUntil > now) and (npcStunUntil - now) or 0
	out.npcIncomingDamageBonusFraction = tonumber(session.npcIncomingDamageBonusFraction) or 0
	local vulnUntil = tonumber(session.npcIncomingDamageBonusUntil) or 0
	out.npcIncomingDamageBonusRemainingSec = (vulnUntil > now) and (vulnUntil - now) or 0
	out.playerCardStates = buildPlayerCardStatePayload(session)
	sendState(player, out)
end

local function runNpcAttackLoop(player, session)
	task.spawn(function()
		while true do
			local current = activeSessionByPlayer[player]
			if not current or current ~= session or session.isClosed then
				break
			end

			if session.phase ~= BattleProtocol.SessionPhase.InProgress then
				break
			end

			if session.npcHealth <= 0 then
				finishSession(player, "NpcDefeated")
				break
			end

			if #getAliveCardStates(session) == 0 then
				finishSession(player, "PlayerDefeated")
				break
			end

			local now = os.clock()
			local dealtAny = false
			local stateSentThisTick = false
			local abilityEvents = {}
			local lastHitBySlot = {}
			for _, attacker in ipairs(session.attackState or {}) do
				local cardState = getCardStateBySlot(session, attacker.slotIndex)
				if not cardState or cardState.health <= 0 then
					continue
				end
				cardState.nextAttackAt = tonumber(attacker.nextAttackAt) or tonumber(cardState.nextAttackAt) or 0
				cardState.nextAbilityAt = tonumber(attacker.nextAbilityAt) or tonumber(cardState.nextAbilityAt) or 0

				if cardState.abilityId ~= "" and cardState.nextAbilityAt and cardState.nextAbilityAt <= now then
					local applied = CombatAutoAbilities.TryApply(session.playerCardStates, cardState, now, abilityEvents, { session = session, mode = "Npc" })
					if applied == true then
						dealtAny = true
						cardState.attackLockedUntil = math.max(tonumber(cardState.attackLockedUntil) or 0, now + ATTACK_ANIM_LOCK_SECONDS)
					end
					cardState.nextAbilityAt = now + math.max(MIN_ABILITY_COOLDOWN_SECONDS, tonumber(cardState.abilityCooldownSeconds) or MIN_ABILITY_COOLDOWN_SECONDS)
					attacker.nextAbilityAt = cardState.nextAbilityAt
				end

				local lockUntil = tonumber(cardState.attackLockedUntil) or 0
				if lockUntil > now then
					-- While busy staging abilities/multi-hits, skip auto-attacks.
					cardState.nextAttackAt = math.max(tonumber(cardState.nextAttackAt) or 0, lockUntil)
					attacker.nextAttackAt = cardState.nextAttackAt
				elseif cardState.nextAttackAt <= now then
					local rawDamage = CombatFormulas.GetEffectiveAttack(cardState, now)
					local hitResult = DamagePipeline.ResolveHit(cardState, nil, rawDamage, now, { session = session })
					local dealtDamage = applyPlayerHitDamageToNpc(session, hitResult, now)
					cardState.nextAttackAt = now + CombatFormulas.GetEffectiveAttackInterval(cardState, now, DEFAULT_PLAYER_ATTACK_INTERVAL_SECONDS)
					attacker.nextAttackAt = cardState.nextAttackAt
					dealtAny = true
					session.hitSeq = (session.hitSeq or 0) + 1
					local primaryHitSeq = session.hitSeq

					if session.npcHealth <= 0 then
						if not session.npcDeathNotified then
							session.npcDeathNotified = true
							CombatEventBus.Fire("OnDeath", {
								session = session,
								unit = {
									cardId = session.npcCardId,
									cardName = session.npcCardName,
									health = session.npcHealth,
								},
								killer = cardState,
							})
							CombatEventBus.Fire("OnKill", {
								session = session,
								attacker = cardState,
								victim = {
									cardId = session.npcCardId,
									cardName = session.npcCardName,
									health = session.npcHealth,
								},
							})
						end
						finishSession(player, "NpcDefeated")
						break
					end

					local followUps = CombatFollowUpDispatcher.maybeGetFollowUps(cardState, nil, hitResult, now, session)
					local burstNpcAttacks = nil
					if followUps then
						local npcDefeated = false
						burstNpcAttacks = {}
						for i, follow in ipairs(followUps) do
							local dealtFollow = applyPlayerHitDamageToNpc(session, follow, now)
							dealtAny = true
							session.hitSeq = (session.hitSeq or 0) + 1
							table.insert(burstNpcAttacks, {
								attackerCardId = attacker.cardId,
								attackerSlotIndex = attacker.slotIndex,
								dealtDamage = dealtFollow,
								rawDamage = follow.rawDamage,
								isCrit = follow.isCrit,
								isDodged = follow.isDodged,
								absorbed = follow.absorbed,
								isFangFollowup = follow.isFangFollowup == true,
								isStarburstFollowup = follow.isStarburstFollowup == true,
								entryHitIndex = i,
								hitSeq = session.hitSeq,
							})

							local burstLockUntil = now + math.max(0, i) * BURST_FOLLOWUP_STAGGER_SECONDS + ATTACK_ANIM_LOCK_SECONDS
							cardState.attackLockedUntil = math.max(tonumber(cardState.attackLockedUntil) or 0, burstLockUntil)

							if session.npcHealth <= 0 then
								if not session.npcDeathNotified then
									session.npcDeathNotified = true
									CombatEventBus.Fire("OnDeath", {
										session = session,
										unit = {
											cardId = session.npcCardId,
											cardName = session.npcCardName,
											health = session.npcHealth,
										},
										killer = cardState,
									})
									CombatEventBus.Fire("OnKill", {
										session = session,
										attacker = cardState,
										victim = {
											cardId = session.npcCardId,
											cardName = session.npcCardName,
											health = session.npcHealth,
										},
									})
								end
								finishSession(player, "NpcDefeated")
								npcDefeated = true
								break
							end
						end
						if npcDefeated then
							break
						end
					end

					sendNpcState(player, session, {
						attackerCardId = attacker.cardId,
						attackerSlotIndex = attacker.slotIndex,
						dealtDamage = dealtDamage,
						rawDamage = hitResult.rawDamage,
						isCrit = hitResult.isCrit,
						isDodged = hitResult.isDodged,
						absorbed = hitResult.absorbed,
						isFangFollowup = false,
						hitSeq = primaryHitSeq,
						burstNpcAttacks = burstNpcAttacks,
						abilityEvents = abilityEvents,
					})
					stateSentThisTick = true
				end
			end

			if session.nextNpcAttackAt <= now then
				local npcStunUntil = tonumber(session.npcStunUntil) or 0
				if npcStunUntil > now then
					-- Stunned NPC: skip its attack while stun is active.
					session.nextNpcAttackAt = npcStunUntil + 0.01
				else
					local alive = getAliveCardStates(session)
					if #alive > 0 then
						local target = alive[math.random(1, #alive)]
						local rawDamage = CombatFormulas.GetEffectiveNpcOutgoingDamage(session, session.npcAttack, now)
						local npcProf = CardDatabase.GetCombatProfile(session.npcCardId, nil)
						local npcCat = (npcProf and npcProf.cardCategory) or "Uncategorized"
						local hitResult = DamagePipeline.ResolveHit({
							cardId = session.npcCardId,
							cardName = session.npcCardName,
							baseAttack = session.npcAttack,
							statBlock = {},
							cardCategory = npcCat,
						}, target, rawDamage, now)
						pruneDeadAttackers(session)
						local interval = CardDatabase.GetNpcCounterAttackIntervalSeconds(session.npcCardId, NPC_COUNTER_ATTACK_INTERVAL_SECONDS)
						session.nextNpcAttackAt = now + interval
						dealtAny = true

						sendNpcState(player, session, {
							npcAttackDealtDamage = hitResult.finalDamage,
							npcAttackRawDamage = hitResult.rawDamage,
							npcAttackIsCrit = hitResult.isCrit,
							npcAttackIsDodged = hitResult.isDodged,
							npcAttackAbsorbed = hitResult.absorbed,
							npcAttackTargetSlotIndex = target.slotIndex,
							npcAttackTargetCardId = target.cardId,
							abilityEvents = abilityEvents,
						})
						lastHitBySlot[target.slotIndex] = {
							cardId = session.npcCardId,
							cardName = session.npcCardName,
						}
						if target.health <= 0 and not target.deathNotified then
							target.deathNotified = true
							local killer = lastHitBySlot[target.slotIndex]
							CombatEventBus.Fire("OnDeath", {
								session = session,
								unit = target,
								killer = killer,
							})
							if killer then
								CombatEventBus.Fire("OnKill", {
									session = session,
									attacker = killer,
									victim = target,
								})
							end
						end
						stateSentThisTick = true
					end
				end
			end

			if #abilityEvents > 0 and not stateSentThisTick then
				sendNpcState(player, session, {
					reason = "AbilityTriggered",
					abilityEvents = abilityEvents,
					dealtDamage = 0,
				})
			end

			if session.npcHealth <= 0 then
				break
			end

			if #getAliveCardStates(session) == 0 then
				for _, state in ipairs(session.playerCardStates or {}) do
					if state.health <= 0 and not state.deathNotified then
						state.deathNotified = true
						local killer = lastHitBySlot[state.slotIndex]
						CombatEventBus.Fire("OnDeath", {
							session = session,
							unit = state,
							killer = killer,
						})
					end
				end
				finishSession(player, "PlayerDefeated")
				break
			end

			if not dealtAny then
				task.wait(PVE_ABILITY_TICK_INTERVAL_SECONDS)
			else
				task.wait(0.02)
			end
		end
	end)
end

local function startSession(player, record)
	local sessionId = BattleProtocol.MakeSessionId(player.UserId, record.NpcId)
	local session = {
		sessionId = sessionId,
		npcId = record.NpcId,
		createdAt = os.clock(),
		phase = BattleProtocol.SessionPhase.Lobby,
		npcCardId = record.NpcCardId,
		npcCardName = record.NpcCardName,
		npcMaxHealth = math.max(1, math.floor(record.NpcMaxHealth or 1000000)),
		npcHealth = math.max(1, math.floor(record.NpcMaxHealth or 1000000)),
		npcAttack = math.max(1, math.floor(record.NpcAttack or 100)),
		npcOutgoingAttackDebuffPercent = 0,
		npcOutgoingAttackDebuffUntil = 0,
		-- Control effects on the NPC (used to gate its attack loop).
		npcStunUntil = 0,
		npcDeathNotified = false,
		hitSeq = 0,
		playerDeck = {},
		playerCardStates = {},
		nextNpcAttackAt = os.clock() + 1.5,
		isClosed = false,
	}
	activeSessionByPlayer[player] = session

	sendState(player, {
		eventType = BattleProtocol.EventType.SessionStarted,
		sessionId = sessionId,
		npcId = record.NpcId,
		npcName = record.DisplayName,
		npcCardId = session.npcCardId,
		npcCardName = session.npcCardName,
		npcMaxHealth = session.npcMaxHealth,
		npcHealth = session.npcHealth,
		npcAttack = session.npcAttack,
		phase = session.phase,
		rules = {
			maxDeckSize = 5,
			attackIntervalSeconds = DEFAULT_PLAYER_ATTACK_INTERVAL_SECONDS,
			npcAttackIntervalSeconds = NPC_COUNTER_ATTACK_INTERVAL_SECONDS,
			firstAttackStaggerSeconds = FIRST_ATTACK_STAGGER_SECONDS,
			requiresDeckSnapshot = true,
		},
	})
end

local function tryStartBattleForRecord(player, record, throttleWindow)
	if not (player and player:IsA("Player")) then
		return false
	end
	if not record then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "NpcNotRegistered"})
		return false
	end

	local now = os.clock()
	local throttle = tonumber(throttleWindow) or 0
	if throttle > 0 then
		local last = lastRequestByPlayer[player] or 0
		if (now - last) < throttle then
			sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "RequestThrottled"})
			return false
		end
	end
	lastRequestByPlayer[player] = now

	if activeSessionByPlayer[player] then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "AlreadyInSession"})
		return false
	end

	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	local npcInstance = resolveNpcInstance(record)
	local npcPosition = getWorldPosition(npcInstance)
	if not (hrp and npcPosition) then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "NpcUnavailable", npcId = record.NpcId})
		return false
	end

	local distance = (hrp.Position - npcPosition).Magnitude
	if distance > record.InteractionRange + 3 then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "TooFar", npcId = record.NpcId})
		return false
	end

	startSession(player, record)
	return true
end

local function onPromptTriggered(record, player)
	if not (player and player:IsA("Player")) then
		return
	end
	battleInviteEvent:FireClient(player, {
		npcId = record.NpcId,
		npcName = record.DisplayName,
		interactionType = "ProximityPrompt",
		protocolVersion = BattleProtocol.Version,
	})
	tryStartBattleForRecord(player, record, 0.2)
end

local function bindPrompt(record)
	local instance = resolveNpcInstance(record)
	local promptPart = findPromptPart(instance)
	if not promptPart then
		return false
	end

	local prompt = promptPart:FindFirstChild("NpcBattlePrompt")
	if not (prompt and prompt:IsA("ProximityPrompt")) then
		if prompt then
			prompt:Destroy()
		end
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "NpcBattlePrompt"
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = record.InteractionRange
		prompt.HoldDuration = record.HoldDuration
		prompt.Parent = promptPart
	end

	prompt.ActionText = record.PromptText
	prompt.ObjectText = record.ObjectText

	if not promptConnections[prompt] then
		promptConnections[prompt] = prompt.Triggered:Connect(function(player)
			onPromptTriggered(record, player)
		end)
	end

	return true
end

local function bindAllPrompts()
	cleanupStalePrompts()
	for _, record in pairs(NPC_REGISTRY) do
		bindPrompt(record)
	end
end

bindAllPrompts()
Workspace.DescendantAdded:Connect(function(descendant)
	if descendant.Name == "PerfectCell" then
		task.defer(bindAllPrompts)
	end
end)

for _, p in ipairs(Players:GetPlayers()) do
	attachCharacterPromptScrubber(p)
	p.CharacterAdded:Connect(function(character)
		task.defer(function()
			scrubCharacterPrompts(character)
			bindAllPrompts()
		end)
	end)
end

Players.PlayerAdded:Connect(function(p)
	attachCharacterPromptScrubber(p)
	p.CharacterAdded:Connect(function(character)
		task.defer(function()
			scrubCharacterPrompts(character)
			bindAllPrompts()
		end)
	end)
end)

requestBattleEvent.OnServerEvent:Connect(function(player, payload)
	local npcId = payload and payload.npcId
	if not BattleProtocol.IsValidNpcId(npcId) then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "InvalidNpcId"})
		return
	end

	local record = npcById[npcId]
	if not record then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "NpcNotRegistered", npcId = npcId})
		return
	end
	tryStartBattleForRecord(player, record, 0.4)
end)

battleActionEvent.OnServerEvent:Connect(function(player, payload)
	local session = activeSessionByPlayer[player]
	if not session then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "NoActiveSession"})
		return
	end

	if type(payload) ~= "table" then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "InvalidActionPayload"})
		return
	end

	if payload.sessionId ~= nil and payload.sessionId ~= session.sessionId then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "SessionMismatch"})
		return
	end

	local actionType = payload and payload.actionType
	if type(actionType) ~= "string" or actionType == "" then
		sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "InvalidAction"})
		return
	end

	if actionType == BattleProtocol.ActionType.SubmitDeckSnapshot then
		if session.phase == BattleProtocol.SessionPhase.Ended then
			sendState(player, {eventType = BattleProtocol.EventType.Error, reason = "SessionAlreadyEnded"})
			return
		end

		local deck = sanitizeDeckSnapshot(payload.deck)
		session.playerDeck = deck
		session.playerCardStates = {}
		local foilChancePoints = ServerStateManager.getFoilChance(player.UserId)
		for _, entry in ipairs(deck) do
			local profile = CardDatabase.GetCombatProfile(entry.cardId, { foilChancePoints = foilChancePoints })
			if not profile then
				warn("[NpcBattle] Missing CardDatabase row for cardId=" .. tostring(entry.cardId))
			else
				local ps = profile["statBlock"]
				local statBlockCopy = {}
				if type(ps) == "table" then
					for k, v in pairs(ps) do
						statBlockCopy[k] = v
					end
				end
				table.insert(session.playerCardStates, {
					slotIndex = entry.slotIndex,
					cardId = entry.cardId,
					cardName = profile.cardName,
					maxHealth = profile.maxHealth,
					health = profile.maxHealth,
					baseAttack = profile.baseAttack,
					baseAttackIntervalSeconds = profile.baseAttackIntervalSeconds,
					abilityId = profile.abilityId,
					abilityCooldownSeconds = math.max(MIN_ABILITY_COOLDOWN_SECONDS, profile.abilityCooldownSeconds),
					speedBoostMagnitude = 0,
					speedBoostUntil = 0,
					damageBoostMagnitude = 0,
					damageBoostUntil = 0,
					-- Generic on-hit damage procs (see AbilityDatabase / EffectResolver / DamagePipeline).
					onHitDamageProcs = {},
					abilityCounters = {},
					abilityFlags = {},
					-- Reduced healing debuff (fraction 0..1), applied in DamagePipeline.ApplyHealToUnit.
					healingReductionFraction = 0,
					healingReductionUntil = 0,
					-- Control effects (implemented server-side by gating loops + DamagePipeline).
					stunUntil = 0,
					sealUntil = 0,
					dodgeDisabledUntil = 0,
					nextAttackAt = 0,
					nextAbilityAt = 0,
					deathNotified = false,
					cardCategory = profile.cardCategory or "Uncategorized",
					damageReductionVsMageAttacks = 0,
					incomingDamageBonusFraction = 0,
					incomingDamageBonusUntil = 0,
					-- Server-side lock to prevent starting another basic attack
					-- while the client is still staging multi-hits/ability visuals.
					attackLockedUntil = 0,
				})
				local n = #session.playerCardStates
				session.playerCardStates[n]["statBlock"] = statBlockCopy
				session.playerCardStates[n].outgoingAttackDebuffPercent = 0
				session.playerCardStates[n].outgoingAttackDebuffUntil = 0
			end
		end

		local entryNow = os.clock()
		local entryEvents = {}
		local entryNpcAttacks = {}
		CombatAutoAbilities.ApplyOnBattleStartNpc(session, entryNow, entryEvents, entryNpcAttacks)
		if #entryNpcAttacks > 0 then
			for _, attack in ipairs(entryNpcAttacks) do
				session.hitSeq = (session.hitSeq or 0) + 1
				attack.hitSeq = session.hitSeq
			end
		end

		-- Lock per-card auto-attacks while the client is staging entry hits.
		if #entryNpcAttacks > 0 then
			local lockBySlot = {}
			for i, attack in ipairs(entryNpcAttacks) do
				if type(attack) == "table" and type(attack.attackerSlotIndex) == "number" then
					local isFollowup = attack.isFangFollowup == true or attack.isStarburstFollowup == true
					local displayIndex = (isFollowup and i) or tonumber(attack.entryHitIndex) or i
					local delay = math.max(0, displayIndex - 1) * MULTI_HIT_VISUAL_STAGGER_SECONDS
					local lockUntil = entryNow + delay + ATTACK_ANIM_LOCK_SECONDS
					lockBySlot[attack.attackerSlotIndex] = math.max(tonumber(lockBySlot[attack.attackerSlotIndex]) or 0, lockUntil)
				end
			end

			for _, st in ipairs(session.playerCardStates or {}) do
				local lockUntil = lockBySlot[st.slotIndex]
				if type(lockUntil) == "number" and lockUntil > (tonumber(st.attackLockedUntil) or 0) then
					st.attackLockedUntil = lockUntil
				end
			end
		end

		session.attackState = {}
		if #deck > 0 then
			local firstWave = {}
			for _, d in ipairs(deck) do
				table.insert(firstWave, d)
			end
			shuffleInPlace(firstWave)
			local now = os.clock()
			for i, entry in ipairs(firstWave) do
				local state = getCardStateBySlot(session, entry.slotIndex)
				if state then
					table.insert(session.attackState, {
						cardId = entry.cardId,
						slotIndex = entry.slotIndex,
						attackIntervalSeconds = state.baseAttackIntervalSeconds,
						nextAttackAt = now + ((i - 1) * FIRST_ATTACK_STAGGER_SECONDS),
						nextAbilityAt = now + DEFAULT_ABILITY_FIRST_CAST_DELAY_SECONDS,
					})
					state.nextAttackAt = now + ((i - 1) * FIRST_ATTACK_STAGGER_SECONDS)
					state.nextAbilityAt = now + DEFAULT_ABILITY_FIRST_CAST_DELAY_SECONDS
				end
			end
		end

		if session.phase == BattleProtocol.SessionPhase.Lobby then
			session.phase = BattleProtocol.SessionPhase.InProgress
			session.nextNpcAttackAt = os.clock() + 1.5
		end

		sendState(player, {
			eventType = BattleProtocol.EventType.ActionAccepted,
			sessionId = session.sessionId,
			npcId = session.npcId,
			actionType = actionType,
			phase = session.phase,
			deckSize = #deck,
		})

		local npcStatePayload = {
			dealtDamage = 0,
			reason = (#deck > 0) and "BattleStarted" or "AwaitingCombatDeck",
		}
		if #entryEvents > 0 then
			npcStatePayload.abilityEvents = entryEvents
			npcStatePayload.reason = "BattleStarted"
		end
		if #entryNpcAttacks > 0 then
			npcStatePayload.entryNpcAttacks = entryNpcAttacks
			npcStatePayload.reason = "BattleStarted"
		end
		sendNpcState(player, session, npcStatePayload)

		if #deck > 0 and not session.loopStarted then
			session.loopStarted = true
			runNpcAttackLoop(player, session)
		end
		return
	end

	if actionType == BattleProtocol.ActionType.Surrender then
		finishSession(player, "PlayerSurrendered")
		return
	end

	sendState(player, {
		eventType = BattleProtocol.EventType.Error,
		reason = "UnsupportedAction",
		sessionId = session.sessionId,
		npcId = session.npcId,
		actionType = actionType,
		phase = session.phase,
	})
end)

Players.PlayerRemoving:Connect(function(player)
	finishSession(player, "PlayerLeft")
	lastRequestByPlayer[player] = nil
end)
