-- CombatAutoAbilities.luau
-- Data-driven auto abilities (TeamAttackSpeedBoost, TeamAttackDamageBoost, HealLowestAlly).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardAbilityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardAbilityConfig"))
local DamagePipeline = require(script.Parent:WaitForChild("DamagePipeline"))
local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))

local CombatAutoAbilities = {}

function CombatAutoAbilities.TryApply(allies, casterState, now, abilityEvents, options)
	options = options or {}
	if not casterState or (tonumber(casterState.health) or 0) <= 0 then
		return false
	end
	local abilityDef = CardAbilityConfig.GetAbility(casterState.abilityId)
	if not abilityDef then
		return false
	end
	-- OnEntry-only abilities are resolved in ApplyOnBattleStart*; not on the auto-timer.
	if abilityDef.Trigger == "OnEntry" then
		return false
	end

	local aliveAllies = CombatFormulas.FilterAlive(allies)
	if #aliveAllies == 0 then
		return false
	end

	local magnitude = math.max(0, tonumber(abilityDef.Magnitude) or 0)
	local durationSeconds = math.max(0, tonumber(abilityDef.DurationSeconds) or 0)
	local targetSlotIndices = {}

	if abilityDef.EffectType == "TeamAttackSpeedBoost" then
		for _, ally in ipairs(aliveAllies) do
			ally.speedBoostMagnitude = math.max(tonumber(ally.speedBoostMagnitude) or 0, magnitude)
			ally.speedBoostUntil = math.max(tonumber(ally.speedBoostUntil) or 0, now + durationSeconds)
			table.insert(targetSlotIndices, ally.slotIndex)
		end
	elseif abilityDef.EffectType == "TeamAttackDamageBoost" then
		for _, ally in ipairs(aliveAllies) do
			ally.damageBoostMagnitude = math.max(tonumber(ally.damageBoostMagnitude) or 0, magnitude)
			ally.damageBoostUntil = math.max(tonumber(ally.damageBoostUntil) or 0, now + durationSeconds)
			table.insert(targetSlotIndices, ally.slotIndex)
		end
	elseif abilityDef.EffectType == "HealLowestAlly" then
		local lowest = nil
		local lowestRatio = 2
		for _, ally in ipairs(aliveAllies) do
			local ratio = (tonumber(ally.health) or 0) / math.max(1, tonumber(ally.maxHealth) or 1)
			if ratio < lowestRatio then
				lowestRatio = ratio
				lowest = ally
			end
		end
		if lowest then
			local healAmount = math.max(1, math.floor(math.max(1, lowest.maxHealth) * magnitude))
			DamagePipeline.ApplyHealToUnit(lowest, healAmount)
			table.insert(targetSlotIndices, lowest.slotIndex)
		end
	else
		return false
	end

	local event = {
		casterSlotIndex = casterState.slotIndex,
		casterCardId = casterState.cardId,
		abilityId = casterState.abilityId,
		effectType = abilityDef.EffectType,
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		timestamp = now,
	}
	if options.attackerUserId ~= nil then
		event.attackerUserId = options.attackerUserId
	end
	table.insert(abilityEvents, event)

	return true
end

local function appendOnEntryEvent(abilityEvents, options, casterState, abilityDef, targetSlotIndices, magnitude, durationSeconds, now)
	local event = {
		trigger = "OnEntry",
		casterSlotIndex = casterState.slotIndex,
		casterCardId = casterState.cardId,
		abilityId = casterState.abilityId,
		effectType = abilityDef.EffectType,
		targetSlotIndices = targetSlotIndices,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		timestamp = now,
	}
	if options and options.attackerUserId ~= nil then
		event.attackerUserId = options.attackerUserId
	end
	table.insert(abilityEvents, event)
end

-- PvP: run once when both decks are in play (before the combat tick loop).
function CombatAutoAbilities.ApplyOnBattleStartPvp(session, now, abilityEvents)
	if not session then
		return
	end
	local teamA = session.cardStatesByUserId[session.playerAUserId]
	local teamB = session.cardStatesByUserId[session.playerBUserId]
	local function applySide(casters, opponents, attackerUserId)
		for _, caster in ipairs(CombatFormulas.FilterAlive(casters)) do
			local def = CardAbilityConfig.GetAbility(caster.abilityId)
			if def and def.Trigger == "OnEntry" and def.EffectType == "EnemyPartyAttackDown" then
				local magnitude = math.min(0.95, math.max(0, tonumber(def.Magnitude) or 0))
				local durationSeconds = math.max(0, tonumber(def.DurationSeconds) or 0)
				local targets = CombatFormulas.FilterAlive(opponents)
				if #targets > 0 then
					local targetSlotIndices = {}
					for _, t in ipairs(targets) do
						t.outgoingAttackDebuffPercent = math.max(tonumber(t.outgoingAttackDebuffPercent) or 0, magnitude)
						t.outgoingAttackDebuffUntil = math.max(tonumber(t.outgoingAttackDebuffUntil) or 0, now + durationSeconds)
						table.insert(targetSlotIndices, t.slotIndex)
					end
					appendOnEntryEvent(abilityEvents, { attackerUserId = attackerUserId }, caster, def, targetSlotIndices, magnitude, durationSeconds, now)
				end
			end
		end
	end
	applySide(teamA, teamB, session.playerAUserId)
	applySide(teamB, teamA, session.playerBUserId)
end

-- PvE: single NPC enemy — debuff its outgoing damage only.
function CombatAutoAbilities.ApplyOnBattleStartNpc(session, now, abilityEvents)
	if not session then
		return
	end
	for _, caster in ipairs(CombatFormulas.FilterAlive(session.playerCardStates)) do
		local def = CardAbilityConfig.GetAbility(caster.abilityId)
		if def and def.Trigger == "OnEntry" and def.EffectType == "EnemyPartyAttackDown" then
			local magnitude = math.min(0.95, math.max(0, tonumber(def.Magnitude) or 0))
			local durationSeconds = math.max(0, tonumber(def.DurationSeconds) or 0)
			session.npcOutgoingAttackDebuffPercent = math.max(tonumber(session.npcOutgoingAttackDebuffPercent) or 0, magnitude)
			session.npcOutgoingAttackDebuffUntil = math.max(tonumber(session.npcOutgoingAttackDebuffUntil) or 0, now + durationSeconds)
			appendOnEntryEvent(abilityEvents, nil, caster, def, { 0 }, magnitude, durationSeconds, now)
		end
	end
end

return CombatAutoAbilities
