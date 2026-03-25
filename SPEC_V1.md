# SPEC_V1 - Game Architecture Specification

## Table of Contents
- [Scope](#scope)
- [Related Docs](#related-docs)
- [Canonical Data Schemas](#canonical-data-schemas)
- [Server Core Module Architecture](#server-core-module-architecture)
- [Client Architecture](#client-architecture)
- [Runtime Invariants](#runtime-invariants)
- [Server Call Flows](#server-call-flows)
- [Edge Cases](#edge-cases)
- [Validation Rules](#validation-rules)
- [Future Patch Placeholders](#future-patch-placeholders)
- [Testing Checklist](#testing-checklist)

---

## Related Docs

- [docs/GAME_ARCHITECTURE.md](docs/GAME_ARCHITECTURE.md) — Module map, flowcharts, data schema
- [docs/SAVE_AND_PERFORMANCE_WORKFLOW.md](docs/SAVE_AND_PERFORMANCE_WORKFLOW.md) — Save fixes, performance, HoverPreview readability

---

## Scope

This specification reflects the current live architecture of the server-core state layer and its direct integrations.

Primary authority for this document:
- `src/server/core/ServerStateManager.luau`
- `src/server/core/state/PlayerStateConstants.luau`
- `src/server/core/state/PlayerStateSchema.luau`
- `src/server/core/state/PlayerStateStore.luau`
- `src/server/core/state/PlayerProgressionState.luau`
- `src/server/core/state/PlayerCollectionsState.luau`
- `src/server/core/state/PlayerStatsState.luau`
- `src/server/core/state/PlayerStateEvents.luau`

Secondary integration points (server):
- `src/server/SmokeChecks.server.luau` — startup config/remotes sanity checks (requires `StatsHandler` for `AllocatePointsRemote` wiring)
- `src/server/SaveManager.luau`
- `src/server/PlayerStatsService.luau`
- `src/server/StatsHandler.server.luau` — get-or-creates `AllocatePointsRemote` (RemoteFunction) and `StatsUpdatedEvent` (RemoteEvent) in `ReplicatedStorage`
- `src/server/core/state/PlayerStateEvents.luau` — get-or-creates the same `StatsUpdatedEvent` instance (by name) when firing stats sync from the state layer (e.g. level-up); must stay compatible with `StatsHandler`
- `src/server/EconomyService.server.luau`
- `src/server/IdleRollService.server.luau`
- `src/server/NpcBattleService.server.luau`
- `src/server/PvpBattleService.server.luau`
- `src/server/AutoRollRuntime.luau`

Client state layer (mirrors server schema):
- `src/client/core/ClientStateManager.luau` — single source of truth for client state
- `src/client/core/BuffBridge.luau` — centralized buff event/IntValue bridges
- `src/client/IdleCardGainer.client.luau` — consumes IdleCardEvent, syncs to ClientStateManager
- `src/client/IdleRollBridge.client.luau` — forwards RewardEvent to IdleCardEvent
- `src/client/InventoryController.client.luau` — canonical SaveDataEvent handler

Client UI layer:
- `src/client/ui/controllers/RPGHUDController.luau` — main HUD, toggle bar, modals (Backpack, Deck, Shop, Profile, Settings)
- `src/client/ui/controllers/ProfileUIController.luau`
- `src/client/ui/controllers/SettingsUIController.luau`
- `src/client/shop/ShopUIController.luau`, `ShopCatalog.luau`, `ShopRenderer.luau`
- `src/client/ui/ParallaxNameLabel.luau` — card name display helper

Legacy / thin facades: `UIManager.luau` (deprecated no-op), `ShopUI.luau` (delegates to `ShopUIController`). `InventoryUIController.luau` remains a minimal `Setup` stub still required from `UIUtility.client.luau`; backpack UI is owned by `InventoryController.client.luau` and `RPGHUDController.luau`.

---

## Progression Constants

| Constant | Location | Value | Formula |
|---|---|---|---|
| `ROLLS_PER_LEVEL` | `src/shared/BalanceConfig.luau` | `100` | `level = floor(totalRollCount / ROLLS_PER_LEVEL) + 1` |

All server and client level-derivation code **must** read `BalanceConfig.ROLLS_PER_LEVEL` rather than hardcoding `100`. Changing this constant rebalances leveling speed globally without touching any other module.

---

## Remote Event / Function Contract

| Remote | Direction | Payload |
|---|---|---|
| `SaveDataEvent` (RemoteEvent) | Server → Client | Full snapshot: `{coins, rollCount, level, stats, inventory, combat, boosterPacks, items, ...}` (may include `buffs`, `clientSettings` on load) |
| `StatsUpdatedEvent` (RemoteEvent) | Server → Client | Stats only: `{Luck, RollSpeed, PotionDuration, FoilChance, Points}` |
| `AllocatePointsRemote` (RemoteFunction) | Client ↔ Server | Request: `{action, stat?}`; Response: stats table or nil. Get-or-create: `StatsHandler.server.luau`. |
| `EconomyRequest` (RemoteFunction) | Client ↔ Server | Under `ReplicatedStorage/EconomyRemotes`. EconomyProtocol actions: GetState, BuyPack, OpenPack, BuyItem, UseItem, SellCards, BuyDirectCard |
| `EconomySnapshotEvent` (RemoteEvent) | Server → Client | Partial economy sync on join: `coins`, `boosterPacks`, `items`, `rollCount`, `level`, `stats`. Get-or-create: `SaveManager.luau` |
| `IdleRollReward` (RemoteEvent) | Server → Client | Under `ReplicatedStorage/IdleRollRemotes` per `IdleRollProtocol`. Payload: `{cardId, rollCount, level, stats}` |
| `IdleRollControl` (RemoteEvent) | Client ↔ Server | Under `IdleRollRemotes`; idle-roll control channel (see `IdleRollProtocol`) |

---

## Canonical Data Schemas

### Player State Schema
```lua
PlayerState = {
    level = number,               -- Integer, minimum 1
    rollCount = number,           -- Integer, minimum 0
    coins = number,               -- Integer, minimum 0

    stats = {
        Luck = number,            -- Integer, minimum 0
        RollSpeed = number,       -- Integer, minimum 1
        PotionDuration = number,  -- Integer, minimum 0
        FoilChance = number,     -- Integer, minimum 0
        Points = number,          -- Integer, minimum 0
    },

    inventory = { cardRef },      -- Ordered list, duplicates allowed
    combat = { cardRef | "" },   -- Ordered slot list, empty string means empty slot

    boosterPacks = {
        [packId] = count          -- Integer, minimum 0
    },

    items = {
        [itemId] = count          -- Integer, minimum 0
    },
}
```

### Card Reference Schema
```lua
CardRef = string

-- Plain card example
"BeliodusX"

-- Bordered card example
"BeliodusX::Bordered"

ParsedCardReference = {
    CardRef = string,
    BaseCardId = string,
    IsBordered = boolean,
}
```

### Save Payload Schema
```lua
SavePayload = {
    level = number,
    rollCount = number,
    coins = number,
    stats = PlayerState.stats,
    inventory = PlayerState.inventory,
    combat = PlayerState.combat,
    boosterPacks = PlayerState.boosterPacks,
    items = PlayerState.items,
}
```

### Stats Updated Payload Schema
```lua
StatsUpdatedPayload = {
    Luck = number,
    RollSpeed = number,
    PotionDuration = number,
    FoilChance = number,
    Points = number,
}
```

---

## Server Core Module Architecture

### `ServerStateManager.luau`
- Compatibility facade.
- Preserves the public require path used by existing services.
- Delegates all real work into focused state modules.

### `state/PlayerStateConstants.luau`
- Owns canonical defaults.
- Owns allocatable-stat validation rules.
- Prevents magic-string drift.

### `state/PlayerStateSchema.luau`
- Creates default state.
- Sanitizes loaded data.
- Serializes save-safe snapshots.

### `state/PlayerStateStore.luau`
- Owns the in-memory player-state cache.
- Lazily creates player state.
- Clears cached state on player removal.

### `state/PlayerProgressionState.luau`
- Owns `coins`, `rollCount`, and `level` mutations.
- Keeps progression writes isolated from stats and collections.

### `state/PlayerCollectionsState.luau`
- Owns inventory-card grants.
- Owns item counters.
- Owns booster-pack counters.

### `state/PlayerStatsState.luau`
- Owns stat snapshots and mutations.
- Owns point allocation, resets, and level-up stat rewards.
- Exposes fast scalar stat getters.

### `state/PlayerStateEvents.luau`
- Get-or-creates `StatsUpdatedEvent` (same name as `StatsHandler`) and fires `SyncStatsToPlayer`.
- Keeps client sync out of pure state modules; does not duplicate handler wiring on `AllocatePointsRemote`.

---

## Client Architecture

### ClientStateManager (`src/client/core/ClientStateManager.luau`)
- Single source of truth for client-side player state.
- Mirrors server state: `level`, `rollCount`, `coins`, `stats`, `inventory`, `combatDeck`, `boosterPacks`, `items`.
- `syncFromServer(data)` — idempotent full-state update from `SaveDataEvent` or equivalent.
- `subscribe(key, callback)` — reactive updates for UI.
- Exposes getters: `getLevel`, `getRollCount`, `getStats`, etc.
- No local duplication of progression; IdleCardGainer and others read/write via ClientStateManager.

### BuffBridge (`src/client/core/BuffBridge.luau`)
- Centralized get-or-create for buff-related BindableEvents and IntValues in `ReplicatedStorage`.
- Exports: `GetLuckBuffEvent()`, `GetFoilChanceBuffEvent()`, `GetLuckBuffBonusValue()`, `GetFoilChanceBuffBonusValue()`.
- **Writers**: IdleCardGainer updates `LuckBuffBonus` and `FoilChanceBuffBonus` IntValues when potions are used or expire.
- **Firers**: ItemsTab fires `LuckBuffEvent` and `BorderChanceBuffEvent` when the player uses potions.
- **Readers**: ProfileUIController reads the IntValues for the Effects tab.
- IdleCardGainer, ItemsTab, and ProfileUIController must `require` BuffBridge; do not duplicate creation logic elsewhere.

### Key Client Data Flows

| Flow | Path |
|------|------|
| Save sync | `SaveDataEvent` → InventoryController, IdleCardGainer → `ClientStateManager.syncFromServer(data)` |
| Economy snapshot (join) | `EconomySnapshotEvent` → `UIUtility`, `InventoryController` (booster snapshot) + `ClientStateManager` via `EconomyClient` bindable where applicable |
| Idle roll reward | `IdleRollRemotes/IdleRollReward` → IdleRollBridge → `IdleCardEvent` → IdleCardGainer → `ClientStateManager.setLevel/setRollCount/setStats` |
| Stats allocation | `AllocatePointsRemote` → StatsHandler → PlayerStatsService → `StatsUpdatedEvent` → ClientStateManager |
| Luck/FoilChance potion use | ItemsTab → `LuckBuffEvent` / `FoilChanceBuffEvent` → IdleCardGainer (HUD timer) |
| Effects tab display | ProfileUIController → BuffBridge `GetLuckBuffBonusValue` / `GetFoilChanceBuffBonusValue` + `ClientStateManager.getStats` |

### Client-Side Bridges (ReplicatedStorage)

| Instance | Type | Owner | Purpose |
|----------|------|-------|---------|
| `IdleCardEvent` | BindableEvent | IdleRollBridge (get-or-create) | Forwards RewardEvent payload to IdleCardGainer |
| `LuckBuffEvent` | BindableEvent | BuffBridge | ItemsTab fires; IdleCardGainer shows HUD timer |
| `FoilChanceBuffEvent` | BindableEvent | BuffBridge | ItemsTab fires; IdleCardGainer shows HUD timer |
| `LuckBuffBonus` | IntValue | BuffBridge | IdleCardGainer writes; ProfileUIController reads |
| `FoilChanceBuffBonus` | IntValue | BuffBridge | IdleCardGainer writes; ProfileUIController reads |

### Canonical Item IDs (`PlayerStateConstants.DEFAULT_ITEMS`)

| ItemId | Purpose |
|--------|---------|
| `AutoRoll2x20s` | 2x auto-roll speed for 20 seconds |
| `LuckPotion` | Temporary Luck stat bonus; duration scales with PotionDuration |
| `FoilChancePotion` | Temporary FoilChance stat bonus; duration scales with PotionDuration |

### HoloFoil Tiers (Foil Card Variants)

| Tier | Description |
|------|-------------|
| Silver | Obsidian Chrome — deep steel to pure white gradient |
| Gold | Warm amber with sunlit stripe |
| Diamond | Prismatic Glitch — Cyan/Magenta shards, math.sin gradient rotation |
| Cosmic | Midnight Nebula — 5-keypoint nebula gradient, Star Dust particles |
| Corrupted | Ember Vein — heat gradient, dual-frequency breath |

---

## Runtime Invariants

- All stored counters are integers.
- `level >= 1`. Derived: `level = floor(rollCount / BalanceConfig.ROLLS_PER_LEVEL) + 1`.
- `rollCount >= 0`.
- `coins >= 0`.
- `stats.RollSpeed >= 1`.
- All other stats are `>= 0`.
- `inventory` preserves insertion order and allows duplicates.
- `combat` preserves slot order and may contain `""` placeholders for empty slots.
- `boosterPacks` and `items` accept unknown future keys, but all counts are clamped to non-negative integers.
- The server-core layer treats card refs as opaque strings and preserves bordered refs instead of collapsing them.
- `ServerStateManager.luau` must remain a stable facade path unless all external requires are migrated together.

---

## Server Call Flows

### Player Load Flow
```
SaveManager.LoadPlayerData
    -> ServerStateManager.loadPlayerData(userId, loadedData)
        -> PlayerStateStore.GetState(userId)
        -> PlayerStateSchema.ApplyLoadedData(state, loadedData)
```

### Save Snapshot Flow
```
SaveManager.PersistPlayerData
    -> ServerStateManager.getSaveData(userId)
        -> PlayerStateStore.GetState(userId)
        -> PlayerStateSchema.CreateSaveData(state)
```

### Stat Allocation Flow
```
StatsHandler.server
    -> PlayerStatsService.AllocatePoint(player, statName)
        -> ServerStateManager.allocateStatPoint(userId, statName)
            -> PlayerStatsState.AllocateStatPoint(userId, statName)
```

### Level-Up Stat Sync Flow
```
PlayerStatsService.OnLevelUp(player)
    -> ServerStateManager.onLevelUp(userId)
        -> PlayerStatsState.GrantLevelUpPoint(userId)
        -> PlayerStateEvents.SyncStatsToPlayer(userId, stats)
```

### Inventory Grant Flow
```
Any server grant path
    -> ServerStateManager.addCardToInventory(userId, cardRef)
        -> PlayerCollectionsState.AddCardToInventory(userId, cardRef)
```

---

## Edge Cases

### Load and Save Edge Cases
```lua
-- Invalid or missing loaded data should not crash the state layer.
if type(data) ~= "table" then
    return existingStateOrDefault
end

-- Unknown future item ids and pack ids are preserved as numeric counters.
if type(key) == "string" then
    out[key] = math.max(0, math.floor(tonumber(value) or 0))
end

-- Combat slot arrays preserve empty-string placeholders when loading and saving.
if value == "" then
    table.insert(combat, "")
end
```

### Stat Mutation Edge Cases
```lua
-- Invalid stat names must fail safely.
if not IsAllocatableStat(statName) then
    return false, "InvalidStat"
end

-- Allocations without available points must fail safely.
if state.stats.Points <= 0 then
    return false, "NoPoints"
end

-- Resetting stats always refunds at least one point.
local refundPoints = math.max(1, math.floor(tonumber(level) or 1))
```

### Collection Mutation Edge Cases
```lua
-- Invalid card refs are rejected for single-card grants.
if type(cardRef) ~= "string" or cardRef == "" then
    return false
end

-- Batch card grants skip invalid entries instead of corrupting inventory state.
for _, cardRef in ipairs(cardRefs) do
    if type(cardRef) == "string" and cardRef ~= "" then
        table.insert(inventory, cardRef)
    end
end

-- Counter collections never go negative.
count = math.max(0, count + delta)
```

### Networking Edge Cases
```lua
-- Stats sync is optional when the player object is gone.
local player = Players:GetPlayerByUserId(userId)
if not player then
    return false
end

-- StatsUpdatedEvent is reused if present and recreated if missing or invalid.
if not (statsEvent and statsEvent:IsA("RemoteEvent")) then
    recreateEvent()
end
```

---

## Validation Rules

### Input Validation
- All progression and stat values are normalized with integer flooring.
- All progression counters except `level` clamp to a minimum of `0`.
- `level` clamps to a minimum of `1`.
- Only these stats are allocatable:
  - `Luck`
  - `RollSpeed`
  - `PotionDuration`
  - `FoilChance`
- Inventory card refs must be non-empty strings.
- Item ids and pack ids must be non-empty strings before mutation.

### State Validation
- `inventory` is an ordered list, not a count map.
- `combat` is an ordered slot list, not a dictionary.
- `stats` is nested under `PlayerState.stats`.
- Bordered card refs must be preserved as decorated refs and not normalized away by the core cache.
- Save snapshots must always be detached clones of live state.

### Architectural Validation
- `ServerStateManager.luau` remains the only compatibility facade exposed to existing callers.
- Pure state mutation must stay out of remote-event creation code.
- Remote-event creation and firing must stay in `PlayerStateEvents.luau`.
- Defaults and allowlists must stay in `PlayerStateConstants.luau`.

---

## Future Patch Placeholders

### Versioned Save Migration
- Add a save-schema version field when a breaking persistence change is introduced.
- Keep migration logic in `PlayerStateSchema.luau`, not in the facade.

### Additional Stats
- Add new stat defaults in `PlayerStateConstants.luau`.
- Add sanitization in `PlayerStateSchema.SanitizeStats`.
- Add getter/setter/allocation behavior in `PlayerStatsState.luau`.
- Update `StatsUpdatedPayload` in this spec.

### Additional Collections
- Add new counter-based collections next to `items` or `boosterPacks` if they behave like keyed ledgers.
- Add list-based collections only when ordering matters.
- Keep collection mutation rules inside `PlayerCollectionsState.luau`.

### Additional Client Sync Events
- Add new transport concerns in `PlayerStateEvents.luau`.
- Do not embed new remote creation or remote firing logic in `PlayerStatsState.luau` or `PlayerProgressionState.luau`.

### Additional Client Buff Types
- Add new buff events and IntValue bridges in `src/client/core/BuffBridge.luau` (get-or-create + exports).
- IdleCardGainer remains the writer for buff IntValues; ItemsTab fires events; ProfileUIController reads for Effects tab.

---

## Testing Checklist

### Unit Tests
- Create default state and verify all defaults.
- Load malformed save data and verify clamps.
- Allocate valid and invalid stat points.
- Reset stats and verify minimum refund behavior.
- Add inventory refs, items, and booster packs with valid and invalid inputs.

### Integration Tests
- Save/load round trip preserves:
  - stats
  - inventory order
  - bordered card refs
  - combat slot placeholders
  - items
  - booster packs
- `PlayerStatsService` remains compatible with the `ServerStateManager` facade.
- `SaveManager` remains compatible with the `ServerStateManager` facade.
- Level-up still fires a client stats sync.

### Regression Tests
- Player state is cleared on `Players.PlayerRemoving`.
- Existing `require(script.Parent.core:WaitForChild("ServerStateManager"))` call sites continue to work.
- No module outside `src/server/core/state` needs to know the internal cache layout.

### Client Integration Tests
- SaveDataEvent → ClientStateManager.syncFromServer; Profile UI shows correct level/Points.
- IdleCardEvent with rollCount/level/stats → ClientStateManager updated; level-up popup at correct level.
- Luck/FoilChance potion use → HUD timer appears; Profile Effects tab shows buff bonus in foil chance and luck.
