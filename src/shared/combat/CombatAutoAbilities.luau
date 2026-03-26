-- CombatAutoAbilities.luau
-- Timer-driven casts: TryApply runs on the battle tick for Trigger == "AutoTimer".
-- See AbilityDatabase header for full trigger map (OnEntry / Passive / OnHit live elsewhere).
-- On-hit effects: CombatOnHitAbilities + DamagePipeline OnHit event.

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
	-- Passives (e.g. low-HP damage) are applied in CombatFormulas.GetEffectiveAttack, not here.
	if abilityDef.Trigger == "Passive" then
		return false
	end
	-- OnHit abilities run from CombatOnHitAbilities (CombatEventBus), not the auto-cast timer.
	if abilityDef.Trigger == "OnHit" then
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
		opponents = options and options.opponents,
		caster = casterState,
		now = now,
		magnitude = magnitude,
		durationSeconds = durationSeconds,
		procDamageBonus = tonumber(abilityDef.ProcDamageBonus) or nil,
		hitCount = tonumber(abilityDef.HitCount) or nil,
		healingReductionFraction = tonumber(abilityDef.HealingReductionFraction) or nil,
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
function CombatAutoAbilities.ApplyOnBattleStartPvp(session, now, abilityEvents, entryAttacks)
	if not session then
		return
	end
	local teamA = session.cardStatesByUserId[session.playerAUserId]
	local teamB = session.cardStatesByUserId[session.playerBUserId]
	entryAttacks = entryAttacks or {}
	local function applySide(casters, opponents, attackerUserId, targetUserId)
		local aliveCasters = CombatFormulas.FilterAlive(casters)
		local aliveOpponents = CombatFormulas.FilterAlive(opponents)
		for _, caster in ipairs(aliveCasters) do
			local def = CardAbilityConfig.GetAbility(caster.abilityId)
			if def and def.Trigger == "OnEntry" then
				local resolved = EffectResolver.ApplyEffect(def.EffectType, {
					caster = caster,
					allies = aliveCasters,
					opponents = aliveOpponents,
					now = now,
					magnitude = def.Magnitude,
					durationSeconds = def.DurationSeconds,
					procDamageBonus = tonumber(def.ProcDamageBonus) or nil,
					hitCount = tonumber(def.HitCount) or nil,
					healingReductionFraction = tonumber(def.HealingReductionFraction) or nil,
					vsMageDamageReductionFraction = tonumber(def.VsMageDamageReductionFraction) or nil,
					session = session,
				})
				if resolved and type(resolved.entryAttacks) == "table" then
					for _, attack in ipairs(resolved.entryAttacks) do
						if type(attack) == "table" then
							attack.attackerUserId = attackerUserId
							attack.targetUserId = targetUserId
							table.insert(entryAttacks, attack)
						end
					end
				end
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
	applySide(teamA, teamB, session.playerAUserId, session.playerBUserId)
	applySide(teamB, teamA, session.playerBUserId, session.playerAUserId)
end

-- PvE: single NPC enemy — debuff its outgoing damage only.
function CombatAutoAbilities.ApplyOnBattleStartNpc(session, now, abilityEvents, entryNpcAttacks)
	if not session then
		return
	end
	local aliveCasters = CombatFormulas.FilterAlive(session.playerCardStates)
	entryNpcAttacks = entryNpcAttacks or {}
	for _, caster in ipairs(aliveCasters) do
		local def = CardAbilityConfig.GetAbility(caster.abilityId)
		if def and def.Trigger == "OnEntry" then
			local resolved = EffectResolver.ApplyEffect(def.EffectType, {
				caster = caster,
				allies = aliveCasters,
				now = now,
				magnitude = def.Magnitude,
				durationSeconds = def.DurationSeconds,
				procDamageBonus = tonumber(def.ProcDamageBonus) or nil,
				hitCount = tonumber(def.HitCount) or nil,
				healingReductionFraction = tonumber(def.HealingReductionFraction) or nil,
				vsMageDamageReductionFraction = tonumber(def.VsMageDamageReductionFraction) or nil,
				session = session,
				mode = "Npc",
			})
			if resolved and type(resolved.entryNpcAttacks) == "table" then
				for _, attack in ipairs(resolved.entryNpcAttacks) do
					if type(attack) == "table" then
						table.insert(entryNpcAttacks, attack)
					end
				end
			end
			if resolved and resolved.applied then
				appendOnEntryEvent(
					abilityEvents,
					nil,
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

return CombatAutoAbilities
