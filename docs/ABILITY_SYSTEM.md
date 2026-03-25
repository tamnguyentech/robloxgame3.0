# Ability System (Data-Driven Guide)

This repo uses a **data-only** card-to-ability mapping, plus a small set of **generic effect handlers** that can be parameterized per card.

---

## 1) Mental Model

1. **Card rows** declare which ability they have by setting `CardData.AbilityId`.
2. **AbilityDatabase** holds canonical ability definitions keyed by ability id (string).
3. **CombatAutoAbilities** runs abilities based on trigger type (battle start vs auto timer).
4. **EffectResolver** executes an `EffectType` handler with the ability’s parameters.
5. **DamagePipeline** resolves crit/dodge/shields and (for on-hit procs) evaluates aggregated proc state stored on the attacker.

---

## 2) Key Files

- [`src/shared/CardDatabase.luau`](../src/shared/CardDatabase.luau)  
  Cards reference abilities via `AbilityId`.
- [`src/shared/AbilityDatabase.luau`](../src/shared/AbilityDatabase.luau)  
  Canonical ability definitions. Abilities are keyed by the ability id (string).
- [`src/shared/combat/CombatAutoAbilities.luau`](../src/shared/combat/CombatAutoAbilities.luau)  
  Trigger routing (`OnEntry` handled at battle start, other triggers handled by the auto-timer).
- [`src/shared/combat/EffectResolver.luau`](../src/shared/combat/EffectResolver.luau)  
  `EffectType` registry: `EffectResolver.RegisterEffectHandler(effectType, fn)`.
- [`src/shared/combat/DamagePipeline.luau`](../src/shared/combat/DamagePipeline.luau)  
  Hit resolution + evaluation of on-hit proc state for landed attacks.
- [`src/shared/combat/CombatEventBus.luau`](../src/shared/combat/CombatEventBus.luau)  
  Emits `OnHit`, `OnDeath`, etc. (UI feedback is mostly driven by abilityEvents for *entry* effects).

---

## 3) Ability Record Shape (what to set)

In `src/shared/AbilityDatabase.luau`, each ability definition is a table with these commonly-used fields:

- `Id` (string): must match the table key and match the card’s `AbilityId`.
- `Trigger` (string): controls when it runs.
- `EffectType` (string): selects the handler from `EffectResolver`.
- `Magnitude` (number): generic parameter (meaning depends on the handler).
- `DurationSeconds` (number): generic parameter (meaning depends on the handler).
- `ProcDamageBonus` (number, optional): used by the on-hit damage proc handler.
- `Description` (string, optional): UI/help text (not required for correctness).

`Trigger` currently used by the battle system:

- `OnEntry`: applied when the battle starts (PvP and PvE/NPC are handled separately).
- `AutoTimer`: used by the auto-timer loop (note: `CombatAutoAbilities.TryApply` currently ignores `OnEntry` abilities).

---

## 4) Existing EffectTypes You Can Reuse

The effect handlers currently registered in `src/shared/combat/EffectResolver.luau` are:

- `TeamAttackSpeedBoost`  
  Adds a temporary attack-speed buff to all allies.
- `TeamAttackDamageBoost`  
  Adds a temporary damage buff to all allies.
- `HealLowestAlly`  
  Heals the lowest health ally.
- `EnemyPartyAttackDown`  
  Applies outgoing-attack debuff to enemy attackers.
- `LastAllyHealthShare`  
  On entry, transfers health into the last ally (battle start).
- `SealOneEnemy`  
  On entry, seals a randomly selected enemy.
- `StunOneEnemy`  
  On entry, stuns a randomly selected enemy.
- `StunAllEnemies`  
  On entry, stuns all enemies.
- `DisableDodgeAllEnemies`  
  On entry, disables dodges for all enemies.
- `DamageMultiplierOnHitProc`  
  **Passive/on-hit proc** evaluated on every landed hit:
  - `Magnitude` is interpreted as proc chance in `[0,1]`.
  - `ProcDamageBonus` is interpreted as **bonus amount**, where:
    - total multiplier = `1 + ProcDamageBonus`
    - example: `ProcDamageBonus = 1.5` means total multiplier = `2.5` (**+150%**).

---

## 5) Scalable “On-Hit Proc” Pattern (No proc abilityEvents spam)

For on-hit procs, this repo follows a scalable pattern:

1. The ability handler (EffectType) **does not emit per-hit ability events**.
2. Instead, it stores aggregated proc config on the attacker:
   - `attacker.onHitDamageProcs` (array)
3. `DamagePipeline.ResolveHit` runs each landed hit and evaluates the proc list:
   - removes expired procs
   - rolls each proc’s chance
   - multiplies damage by `(1 + bonus)` for each proc that triggers

This means adding “a ton of proc abilities” does not create “a ton of proc events” in the NPC battle service.

---

## 6) How to Add a New Ability

### Step A: Decide trigger

- If it happens at battle start: `Trigger = "OnEntry"`
- If it’s evaluated periodically via the ability auto-timer: use the existing non-`OnEntry` mechanism (and ensure `CombatAutoAbilities.TryApply` should handle it).

### Step B: Reuse an existing `EffectType` if possible

Most “same effect, different ratios” should be represented by:
- `Magnitude` and/or `DurationSeconds`
- plus `ProcDamageBonus` for on-hit procs

### Step C: If you truly need a new effect handler

Add a new handler in `src/shared/combat/EffectResolver.luau`:

1. `EffectResolver.RegisterEffectHandler("YourNewEffectType", function(context) ... end)`
2. Ensure it returns a table with `applied = true/false` and any fields needed by the combat engine.

### Step D: Add the ability definition to `AbilityDatabase`

In `src/shared/AbilityDatabase.luau`, add an entry keyed by the ability id string:

```lua
["myabilityid"] = {
	Id = "myabilityid",
	Name = "My Ability Name",
	Trigger = "OnEntry",
	EffectType = "SomeEffectType",
	Magnitude = 0.2,
	DurationSeconds = 5.0,
	Description = "Optional",
}
```

### Step E: Point cards to it

In `src/shared/CardDatabase.luau`, set:
- `AbilityId = "myabilityid"`

For example, `lightyagami` already references `noteofdeath`.

---

## 7) Copy/Paste Example: `noteofdeath` (Light Yagami)

The card row (already present):

- `src/shared/CardDatabase.luau`: `["lightyagami"]` has `AbilityId = "noteofdeath"`

The ability definition:

```lua
["noteofdeath"] = {
	Id = "noteofdeath",
	Name = "Note of Death",
	Tags = {"Passive", "Damage", "OnAttack"},
	Conditions = {},
	HandlerModule = nil,
	Trigger = "OnEntry",
	EffectType = "DamageMultiplierOnHitProc",
	Magnitude = 0.10,          -- 10% proc chance per landed hit
	ProcDamageBonus = 1.5,     -- +150% bonus damage (total multiplier 2.5x)
	DurationSeconds = 9999,
	Effects = {
		{
			EffectType = "DamageMultiplierOnHitProc",
			Targeting = "Self",
			Magnitude = 0.10,
			ProcDamageBonus = 1.5,
			Duration = 9999,
		},
	},
	DefaultCooldownSeconds = 0,
	Description = "Passive: every landed attack has a 10% chance to deal 150% more damage.",
}
```

---

## 8) Quick Checklist

- Ability table key matches `Id` and matches card `AbilityId`.
- `EffectType` exists in `src/shared/combat/EffectResolver.luau`.
- On-hit procs use `EffectType = "DamageMultiplierOnHitProc"` and provide:
  - `Magnitude` (0..1)
  - `ProcDamageBonus` (bonus amount, not total multiplier)
- If you want NPC scalability, ensure proc logic is evaluated in `DamagePipeline` (via aggregated state), not emitted as per-hit `abilityEvents`.

