# Save System, Performance & HoverPreview Readability — Master Workflow

**Authority:** SPEC_V1, GAME_ARCHITECTURE, Combat Deck & Potion Root Cause Fix plan.

**Use this as the primary workflow prompt for save fixes, performance tuning, and HoverPreview text readability.**

---

## 0. Workflow Prompt Template (Copy-Paste for AI/Agent)

```
Act as a senior principal Luau/Roblox architect. Follow SPEC_V1.md and docs/GAME_ARCHITECTURE.md strictly.

TASK: Implement the fixes in docs/SAVE_AND_PERFORMANCE_WORKFLOW.md.

REQUIREMENTS:
- Save: Combat deck must persist on rejoin. Potion item counts must persist. Fix merge validation, items normalization, PlayerRemoving grace period, and ensure combat slots exist before SaveDeckState.
- Performance: No lag. Minimal data leak. Throttle DataStore writes. Clear player state on leave. Single Heartbeat drivers for effects.
- HoverPreview: All text (Name, ATK, HP, SPD, Rarity, future Description) must be readable over any foil (Silver/Gold/Diamond/Cosmic/Corrupted), BeliodusAura, flash effects. Enforce ZIndex order: foil below text. TextStrokeTransparency = 0. Add PreviewDescription label for future ability descriptions.
- Code sync: Align with ServerStateManager, PlayerStateConstants, SaveManager flows. No duplication of schema logic.

Verify with the protocol in section 5. Do not skip steps.
```

---

## 1. Canonical References (Mandatory)

Before any edit, confirm alignment with:

| Document | Purpose |
|----------|---------|
| [SPEC_V1.md](../SPEC_V1.md) | Schemas, Remote contracts, Server Core, Client Architecture |
| [docs/GAME_ARCHITECTURE.md](GAME_ARCHITECTURE.md) | Module map, Save/Economy/Combat flows, Data Schema |

**Invariants (never violate):**
- `level = floor(rollCount / BalanceConfig.ROLLS_PER_LEVEL) + 1`
- `combat` is ordered slot list; `""` = empty slot
- `items` keys from `PlayerStateConstants.GetDefaultItems()`
- SaveManager `playerData` is single source for DataStore writes
- Client combat deck is client-authoritative; server only stores what client sends

---

## 2. Save System Fix Checklist (Combat Deck + Potion)

### 2.1 SaveManager — Items Normalization

**File:** `src/server/SaveManager.luau`

**Problem:** `normalizeLoadedData` never initializes `FoilChancePotion`; old saves may have nil.

**Fix:**
```lua
-- Replace lines 315-319 with:
local defaultItems = PlayerStateConstants.GetDefaultItems()
data.items = sanitizeNumberMap(savedData.items)
for key, defaultVal in pairs(defaultItems) do
    if data.items[key] == nil then
        data.items[key] = defaultVal
    end
end
```

### 2.2 SaveManager — Merge Validation & Logging

**File:** `src/server/SaveManager.luau` — `mergePlayerPatch`

**Problem:** Inflation check rejects valid merges; rejection is only `warn`ed with no context.

**Fixes:**
1. Log rejection with structured data: `warn("[SaveManager] Merge rejected for", playerName, "reason:", mergeErr)`
2. Consider: use `GetEconomyState` / `executeEconomyDelta`-updated counts as source of truth for inflation instead of `current` when `current` may lag behind grants
3. If relaxing: allow merge when `sum(mergedOwned) <= sum(currentOwned) + recentGrants` (requires tracking recent grants)

### 2.3 SaveManager — PlayerRemoving Grace Period

**File:** `src/server/SaveManager.luau` line ~802

**Change:** `task.wait(0.1)` → `task.wait(0.25)` to improve chance in-flight `SaveDataEvent` is processed under load.

### 2.4 InventoryController — Combat Slots Before Save

**File:** `src/client/InventoryController.client.luau` — `SaveDeckState`

**Problem:** Slots created in `SetupGridLayouts` (OnClientEvent). If `SaveDeckState` runs before first load, `getCombatSlot` returns nil → empty deck sent.

**Fix:** At start of `SaveDeckState`:
```lua
ensureCombatSlots()
local hasAnySlot = false
for i = 1, COMBAT_MAX_UNIQUE do
    if getCombatSlot(i) then
        hasAnySlot = true
        break
    end
end
if not hasAnySlot then
    return  -- Do not send empty combat; slots not ready
end
```

---

## 3. Performance & Scalability (No Lag, Minimal Data Leak)

### 3.1 DataStore Usage

| Rule | Implementation |
|------|----------------|
| Throttle persists | `SAVE_THROTTLE_SECONDS = 1`; avoid more than 1 write per player per second |
| Batch dirty checks | Use `dirtyPlayers` map; periodic flush every 8s only for dirty |
| Size limit | Reject merge if `#HttpService:JSONEncode(merged) > DATASTORE_MAX_BYTES` (4 MB) |
| Retries | Use `DATASTORE_RETRY_COUNT`; exponential backoff between attempts |

### 3.2 RemoteEvent / RemoteFunction

| Rule | Implementation |
|------|----------------|
| Payload size | Send only changed fields when possible; full snapshot only on RequestLoad |
| Rate limit | Client: 2s periodic deck save; avoid firing on every frame |
| No broadcast storms | FireClient per player; never broadcast full state to all |

### 3.3 Memory & CPU

| Rule | Implementation |
|------|----------------|
| Clear on leave | `playerData[userId] = nil`, `loadingPlayers[userId] = nil`, `PlayerStateStore.RemoveState` |
| Single Heartbeat driver | HoloFoilController, springs, aura effects use one shared connection |
| Lazy creation | `ensureCombatSlots` only when needed; avoid creating unused UI |
| Destroy on hide | Stop foil/aura controllers when preview hides |

### 3.4 Synchronization Invariants

| Check | Location |
|-------|----------|
| Stats | `persistPlayerData` copies `ServerStateManager.getStats` into `data.stats` before write |
| ServerStateManager | `loadPlayerData` after load; `PlayerStateStore` cleared on PlayerRemoving |
| ClientStateManager | All sync paths call `syncFromServer`; single source of truth |

---

## 4. HoverPreview Text Readability Overhaul

**Goal:** Name, ATK, HP, SPD, Rarity, and future Ability descriptions must remain readable over any foil (Silver/Gold/Diamond/Cosmic/Corrupted), BeliodusAura, UltraRareTextEffect, RainbowFoilStroke, or other layered effects.

### 4.1 Layering (ZIndex) Order

Enforce this hierarchy (bottom → top):

1. `PreviewArt` (art/image/video) — base
2. Foil overlay (HoloFoilController) — below text
3. **Text labels** — above foil; use highest ZIndex in the preview panel
4. Ability description panel — above foil, same tier as other text
5. Flash / aura / particles — above text only if they are non-opaque or do not cover text regions

**Rule:** All text (Name, ATK, HP, SPD, Rarity, Description) must have `ZIndex >= PREVIEW_BASE_ZINDEX + 10` and foil/effects `ZIndex <= PREVIEW_BASE_ZINDEX + 5`.

### 4.2 Text Contrast (Always Readable)

| Property | Value | Purpose |
|----------|-------|---------|
| TextStrokeColor3 | `Color3.fromRGB(0, 0, 0)` or dark `(8, 14, 32)` | Outline for legibility |
| TextStrokeTransparency | `0` | Never transparent stroke |
| TextColor3 | High-contrast (e.g. white, light blue, orange, green for stats) | Visible on any background |
| Optional | Semi-opaque dark `Frame` behind text (`BackgroundTransparency 0.3–0.5`) | Fallback for busy art |

### 4.3 Description / Ability Panel (Future-Proof)

**Reserve space:** Add `PreviewDescription` — a `TextLabel` or `TextButton` (for wrapping) below Rarity, above ATK/HP.

- `Position`: Below `PreviewRarity` (e.g. `PREVIEW_SPD_RARITY_Y + 2*PREVIEW_META_HEIGHT + 16`)
- `Size`: Full width minus padding; height ~48–60px for 2–3 lines
- `TextWrapped`: true
- `TextSize`: 12–14
- `Font`: Sans-serif (e.g. Gotham, SciFi)
- Same contrast rules: `TextStrokeTransparency = 0`, `TextColor3` light

**Data source:** `data.Description` or `CardAbilityConfig.GetDescription(abilityId)` when abilities are implemented. Show empty string if none.

### 4.4 Files to Edit

| File | Changes |
|------|---------|
| `src/client/ui/HoverPreview.luau` | 1) Raise text ZIndex above foil; 2) Add optional dark panel behind text regions; 3) Add `PreviewDescription` label; 4) Ensure `enforcePreviewLayering` sets text `ZIndex` higher than foil/aura |

---

## 5. Verification Protocol

### 5.1 Save Verification

1. Add 5 cards to combat deck → wait 2s → leave → rejoin → deck persists
2. Add deck → close Deck modal → leave → rejoin → deck persists
3. Use potion → leave → rejoin → potion item count persists
4. Server logs: no unexpected merge rejections

### 5.2 Performance Verification

1. 10+ players: no noticeable lag during rolls, shop, or modal open
2. Memory: `playerData` cleared on leave; no unbounded growth
3. DataStore: no more than ~1 write per player per second under normal play

### 5.3 HoverPreview Readability Verification

1. Hover each foil tier (Silver, Gold, Diamond, Cosmic, Corrupted) → all labels readable
2. Hover BeliodusX (aura) → name, ATK, HP readable
3. Hover God/Transcendent (flash) → labels readable
4. Add `Description` to a test card → description text visible and legible

---

## 6. Execution Order

1. SaveManager items normalization
2. SaveManager PlayerRemoving delay + merge logging
3. InventoryController ensureCombatSlots before SaveDeckState
4. HoverPreview ZIndex + contrast + PreviewDescription
5. (Optional) Merge validation relaxation if logs show false rejections
6. Run verification protocol

---

## 7. Quick Reference — Key Paths

```
Client Save:  Deck edit → SaveDeckState → FireServer(payload) → mergePlayerPatch → playerData → tryPersistPlayerData → DataStore
Client Load:  RequestLoad → ensurePlayerDataLoaded → FireClient(snapshot) → OnClientEvent → syncFromServer → Rebuild UI
PlayerLeave:  PlayerRemoving → task.wait(0.25) → savePlayerDataToStore → playerData = nil
```
