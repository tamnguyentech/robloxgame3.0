-- CombatAutoAbilities.luau
-- Data-driven auto abilities (TeamAttackSpeedBoost, TeamAttackDamageBoost, HealLowestAlly).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardAbilityConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardAbilityConfig"))
local CombatFormulas = require(script.Parent:WaitForChild("CombatFormulas"))
local EffectResolver = require(script.Parent:WaitForChild("EffectResolver"))

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
	local resolved = EffectResolver.ApplyEffect(abilityDef.EffectType, {
		allies = aliveAllies,
		caster = casterState,
		now = now,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		session = options and options.session,
		mode = options and options.mode,
	})
	if not resolved or not resolved.applied then
		return false
	end

	local event = {
		casterSlotIndex = casterState.slotIndex,
		casterCardId = casterState.cardId,
		abilityId = casterState.abilityId,
		effectType = abilityDef.EffectType,
		targetSlotIndices = resolved.targetSlotIndices or {},
		magnitude = tonumber(resolved.magnitude) or magnitude,
		durationSeconds = tonumber(resolved.durationSeconds) or durationSeconds,
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
				local resolved = EffectResolver.ApplyEffect(def.EffectType, {
					caster = caster,
					opponents = CombatFormulas.FilterAlive(opponents),
					now = now,
					magnitude = def.Magnitude,
					durationSeconds = def.DurationSeconds,
				})
				if resolved and resolved.applied then
					appendOnEntryEvent(
						abilityEvents,
						{ attackerUserId = attackerUserId },
						caster,
						def,
						resolved.targetSlotIndices or {},
						tonumber(resolved.magnitude) or 0,
						tonumber(resolved.durationSeconds) or 0,
						now
					)
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
			local resolved = EffectResolver.ApplyEffect(def.EffectType, {
				caster = caster,
				now = now,
				magnitude = def.Magnitude,
				durationSeconds = def.DurationSeconds,
				session = session,
				mode = "Npc",
			})
			if resolved and resolved.applied then
				appendOnEntryEvent(
					abilityEvents,
					nil,
					caster,
					def,
					resolved.targetSlotIndices or { 0 },
					tonumber(resolved.magnitude) or 0,
					tonumber(resolved.durationSeconds) or 0,
					now
				)
			end
		end
	end
end

return CombatAutoAbilities
