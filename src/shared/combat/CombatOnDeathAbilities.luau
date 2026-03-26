-- CombatOnDeathAbilities.luau
-- Subscribes to CombatEventBus "OnDeath" and applies death-triggered effects.
--
-- Currently implemented:
-- - selfdestruct: on death, deal 100% max HP damage to the killer (or random enemy when killer is nil).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local CardAbilityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardAbilityConfig"))

local CombatEventBus = require(script.Parent:WaitForChild("CombatEventBus"))
local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))
local DamagePipeline = require(script.Parent:WaitForChild("DamagePipeline"))

local CombatOnDeathAbilities = {}

local ABILITY_ID = "selfdestruct"

local function isPvpSession(session)
	return type(session) == "table" and type(session.cardStatesByUserId) == "table" and session.playerAUserId ~= nil and session.playerBUserId ~= nil
end

local function isNpcSession(session)
	return type(session) == "table" and type(session.playerCardStates) == "table" and session.npcCardId ~= nil
end

local function resolveAbilityIdFromUnit(unit, session)
	if type(unit) == "table" and type(unit.abilityId) == "string" and unit.abilityId ~= "" then
		return unit.abilityId
	end

	local cardId = unit and unit.cardId
	if type(cardId) ~= "string" or cardId == "" then
		return nil
	end

	-- Use card database as a fallback for lightweight death payloads (e.g. NPC unit tables).
	local profile = CardDatabase.GetCombatProfile(cardId, nil)
	if profile and type(profile.abilityId) == "string" and profile.abilityId ~= "" then
		return profile.abilityId
	end

	return nil
end

local function resolveMaxHpFromUnit(unit, session)
	if not unit then
		return 0
	end
	local maxHp = tonumber(unit.maxHealth) or 0
	if maxHp > 0 then
		return math.max(0, math.floor(maxHp))
	end

	if isNpcSession(session) and session.npcCardId == unit.cardId then
		return math.max(0, math.floor(tonumber(session.npcMaxHealth) or tonumber(session.npcHealth) or 0))
	end

	local cardId = unit.cardId
	if type(cardId) == "string" and cardId ~= "" then
		local profile = CardDatabase.GetCombatProfile(cardId, nil)
		if profile and tonumber(profile.maxHealth) then
			return math.max(0, math.floor(tonumber(profile.maxHealth) or 0))
		end
	end

	return 0
end

local function applyDamageToNpc(session, attacker, rawDamage, now)
	if not session then
		return
	end
	local npcNow = tonumber(now) or os.clock()

	-- Keep damage resolution consistent with player hits:
	-- ResolveHit handles crit/procs; ApplyDamageToNpc only applies the final number.
	local hitResult = DamagePipeline.ResolveHit(attacker, nil, rawDamage, npcNow)
	local dealtDamage = tonumber(hitResult and hitResult.finalDamage) or 0

	-- Mirror the existing NPC incoming bonus logic from NpcBattleService.
	local incomingBonusUntil = tonumber(session.npcIncomingDamageBonusUntil) or 0
	if incomingBonusUntil > npcNow then
		local incomingBonusFraction = math.clamp(tonumber(session.npcIncomingDamageBonusFraction) or 0, 0, 2)
		if incomingBonusFraction > 0 then
			dealtDamage = math.max(0, math.floor(dealtDamage * (1 + incomingBonusFraction)))
		end
	end

	DamagePipeline.ApplyDamageToNpc(session, dealtDamage)
end

local function pickRandomAlive(list)
	if type(list) ~= "table" then
		return nil
	end
	if #list == 0 then
		return nil
	end
	return list[math.random(1, #list)]
end

local function getOpponentsAliveFromPvP(session, victimUnit)
	if not isPvpSession(session) then
		return {}
	end
	local slotIndex = tonumber(victimUnit and victimUnit.slotIndex)
	if not slotIndex then
		return {}
	end

	local listA = session.cardStatesByUserId[session.playerAUserId] or {}
	local listB = session.cardStatesByUserId[session.playerBUserId] or {}

	local victimInA = false
	for _, st in ipairs(listA) do
		if tonumber(st and st.slotIndex) == slotIndex then
			victimInA = true
			break
		end
	end

	local oppList = victimInA and listB or listA
	return CombatFormulas.FilterAlive(oppList)
end

local function resolveTargetFromKillerOrRandom(payload)
	local session = payload.session
	local unit = payload.unit
	local killer = payload.killer

	if killer then
		-- PvP/attacker cardState killer should have a health field.
		if killer.health ~= nil then
			if tonumber(killer.health) and tonumber(killer.health) > 0 then
				return { kind = "card", card = killer }
			end
		end

		-- PvE: NPC killer is represented as a lightweight { cardId, cardName } table.
		if isNpcSession(session) and killer.cardId ~= nil and killer.cardId == session.npcCardId then
			return { kind = "npc" }
		end

		-- Best-effort: PvE killer might be a player cardState object without health, try to locate by cardId.
		if isNpcSession(session) and killer.cardId ~= nil then
			for _, st in ipairs(session.playerCardStates or {}) do
				if st.cardId == killer.cardId and tonumber(st.health) and st.health > 0 then
					return { kind = "card", card = st }
				end
			end
		end
	end

	-- killer == nil: pick a random enemy (plan requirement).
	if isPvpSession(session) then
		local aliveOpp = getOpponentsAliveFromPvP(session, unit)
		return { kind = "card", card = pickRandomAlive(aliveOpp) }
	elseif isNpcSession(session) then
		-- If victim is NPC, enemy is player cards; otherwise enemy is NPC.
		if unit and session.npcCardId == unit.cardId then
			local alivePlayers = CombatFormulas.FilterAlive(session.playerCardStates)
			return { kind = "card", card = pickRandomAlive(alivePlayers) }
		else
			return { kind = "npc" }
		end
	end

	return nil
end

local function onDeathBusEvent(payload)
	if type(payload) ~= "table" then
		return
	end

	local session = payload.session
	local unit = payload.unit
	if not unit or not session then
		return
	end

	local abilityId = resolveAbilityIdFromUnit(unit, session)
	if abilityId ~= ABILITY_ID then
		return
	end

	local def = CardAbilityConfig.GetAbility(ABILITY_ID)
	local magnitude = tonumber(def and def.Magnitude) or 1

	local maxHp = resolveMaxHpFromUnit(unit, session)
	if maxHp <= 0 then
		return
	end

	local rawDamage = math.max(0, math.floor(maxHp * math.max(0, magnitude)))
	if rawDamage <= 0 then
		return
	end

	local now = os.clock()
	local targetInfo = resolveTargetFromKillerOrRandom(payload)
	if not targetInfo then
		return
	end

	-- Use the dying unit as the attacker for damage pipeline logic (crit/procs/shields/dodge).
	-- Even though the unit is dead, stats still exist on the cardState.
	local attacker = unit

	if targetInfo.kind == "card" then
		local targetCard = targetInfo.card
		if targetCard and tonumber(targetCard.health) and targetCard.health > 0 then
			DamagePipeline.ResolveHit(attacker, targetCard, rawDamage, now)
		end
	elseif targetInfo.kind == "npc" then
		if isNpcSession(session) and tonumber(session.npcHealth) and session.npcHealth > 0 then
			applyDamageToNpc(session, attacker, rawDamage, now)
		end
	end
end

CombatEventBus.Subscribe("OnDeath", 50, onDeathBusEvent)

return CombatOnDeathAbilities

