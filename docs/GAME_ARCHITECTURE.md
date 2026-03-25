# Game Architecture — Flowcharts & Datasheet

Principal architect reference: module map, data flows, and visual diagrams for in-game logic.

**Related:** [SAVE_AND_PERFORMANCE_WORKFLOW.md](SAVE_AND_PERFORMANCE_WORKFLOW.md) — Master workflow for save fixes, performance tuning, and HoverPreview readability.

---

## 0. Rojo layout

Source of truth: [default.project.json](../default.project.json).

| Path | Roblox location |
|------|-----------------|
| `src/shared` | `ReplicatedStorage/Shared` |
| `src/server` | `ReplicatedStorage/Server` **and** `ServerScriptService/Server` (same tree mounted twice) |
| `src/client` | `StarterPlayer/StarterPlayerScripts/Client` |

---

## 1. Module Directory

### src/client

| Module | Purpose |
|--------|---------|
| `core/ClientStateManager` | Client-side player state (level, rollCount, coins, stats, inventory, combatDeck, boosterPacks, items) |
| `core/BuffBridge` | Luck/FoilChance buff BindableEvents and IntValues |
| `core/DeviceContext` | Mobile detection, safe insets, responsive UI constants |
| `IdleRollBridge.client` | Forwards `IdleRollRemotes/IdleRollReward` → `IdleCardEvent` (BindableEvent) |
| `IdleCardGainer.client` | IdleCardEvent, card gains, HUD buff timers, syncs to ClientStateManager |
| `InventoryController.client` | SaveDataEvent, deck/inventory UI, SaveDeckState, sell/bindable bridges, EconomySnapshotEvent handling |
| `BoosterPackSystem` | Owned boosters state, change events |
| `services/EconomyClient` | EconomyRequest calls; local `EconomySnapshotEvent` bindable for UI sync |
| `services/ShopClient` | BuyItem, BuyDirectCard, UseItem, SellCards via EconomyClient |
| `shop/ShopCatalog` | Shop tabs (Packs, Items, Cards), EconomyCatalog entries |
| `shop/ShopRenderer` | Currency, tabs, product cards, border gallery |
| `shop/ShopUIController` | Shop modal setup, purchase handlers |
| `tabs/TabController` | Backpack tab bar (Cards, Boosters, Items) |
| `tabs/CardsTab` | Cards tab |
| `tabs/BoosterPacksTab` | Boosters tab, open packs |
| `tabs/ItemsTab` | Items tab, potions via BuffBridge |
| `ui/controllers/RPGHUDController` | Main HUD, toggle bar, modals (Backpack, Deck, Shop, Profile, Settings) |
| `ui/controllers/ProfileUIController` | Profile modal, stats, allocation, effects |
| `ui/controllers/SettingsUIController` | Settings modal (Audio, Graphics, Controls, Gameplay) |
| `ui/controllers/ButtonStyler` | Shared button styling |
| `ui/controllers/FrameFactory` | Frame/card construction helpers |
| `ui/controllers/LayoutController` | Layout helpers |
| `ui/controllers/PreviewController` | Preview sub-UI |
| `ui/controllers/ToggleController` | Toggle control helpers |
| `ui/HoverPreview` | Shared card hover panel |
| `ui/HoverPreviewBridge` | Wires HoverPreview for shop/catalog surfaces |
| `ui/ParallaxNameLabel` | Card name display helper |
| `ui/BoosterOpenSequence` | Booster opening animation sequence |
| `ui/styles/StyleConfig` | Shared style tokens (includes `DamageNumbers` for combat popups) |
| `ui/DamageNumberView` | Config-driven floating damage numbers (PvE + PvP) |
| `ui/groups/DecksLayer` | Deck layer grouping |
| `ui/effects/HoloFoilController` | Foil overlays (Silver, Gold, Diamond, Cosmic, Corrupted) |
| `ui/effects/LightningOverlayController` | Lightning-style overlay for special cards |
| `ui/effects/RainbowBorderStroke` | Rainbow border stroke effect |
| `ui/effects/UltraRareTextEffect` | Ultra-rare title treatment |
| `vfx/VFXController` | Shared VFX hooks |
| `Spring` | Spring animation utility |
| `RarityConfig` | Client rarity styling |
| `BoosterBalanceConfig` | Client copy of pack defs (sync with shared where applicable) |
| `UIUtility.client` | Init: ClientStateManager, RPGHUDController, Profile/Inventory stub/Shop/Settings setup, EconomySnapshotEvent |
| `UIManager` | Deprecated stub (use UIUtility) |
| `InventoryUIController` | Minimal `Setup` stub; backpack built in InventoryController |
| `ShopUI` | Thin facade → `ShopUIController.Setup` |
| `NpcBattleClient.client` | NPC battle UI |
| `PvpBattleClient.client` | PvP battle flow |

### src/server

| Module | Purpose |
|--------|---------|
| `SaveManager` | DataStore load/save, SaveDataEvent, mergePlayerPatch, EconomySnapshotEvent on join |
| `StatsHandler.server` | Get-or-create AllocatePointsRemote + StatsUpdatedEvent; allocation invoke handler |
| `PlayerStatsService` | Stat allocation, reset, level-up via ServerStateManager |
| `EconomyService.server` | EconomyRequest handler (GetState, BuyPack, OpenPack, BuyItem, UseItem, SellCards, BuyDirectCard) |
| `IdleRollService.server` | Idle roll ticks; `IdleRollRemotes/IdleRollReward`, `IdleRollControl` |
| `AutoRollRuntime` | Auto-roll timing, luck/foil buff application |
| `NpcBattleService.server` | NPC battles (`BattleRemotes` per BattleProtocol) |
| `PvpBattleService.server` | PvP battles (`PvpRemotes` per PvpProtocol) |
| `SmokeChecks.server` | Startup validation (config, remotes; requires StatsHandler) |
| `ResetAllRolls.server` / `ResetRollsChatCommand.server` | Admin/reset roll tooling |
| `core/ServerStateManager` | Facade for player state |
| `core/state/PlayerStateConstants` | Defaults, allocatable-stat allowlists |
| `core/state/PlayerStateStore` | In-memory player state cache |
| `core/state/PlayerStateSchema` | Default state, sanitization, save payloads |
| `core/state/PlayerProgressionState` | coins, rollCount, level |
| `core/state/PlayerCollectionsState` | inventory, items, boosterPacks |
| `core/state/PlayerStatsState` | stats, allocation, level-up |
| `core/state/PlayerStateEvents` | StatsUpdatedEvent get-or-create + FireClient for state-layer sync |

### src/shared

| Module | Purpose |
|--------|---------|
| `EconomyProtocol` | EconomyRemotes folder, EconomyRequest, ActionType |
| `EconomyCatalog` | Item offers, direct card offers, sell values |
| `IdleRollProtocol` | IdleRollRemotes folder, IdleRollReward, IdleRollControl |
| `BattleProtocol` | NPC battle remotes and session/action enums (`EventType.NpcState` for PvE ticks) |
| `PvpProtocol` | PvP remotes and session/action enums |
| `BalanceConfig` | ROLLS_PER_LEVEL, luck formulas, auto-roll interval |
| `combat/CombatStatDefaults` | Default secondary combat stats + `MergeStatBlock` |
| `combat/CombatFormulas` | Effective attack/interval, `FilterAlive` |
| `combat/DamagePipeline` | Centralized damage/heal/PvE NPC HP application (`ApplyDamageToNpc`) |
| `combat/CombatAutoAbilities` | Data-driven auto abilities (shared by PvP + NPC) |
| `CardDatabase` | Card data, rarity, combat power; `GetCombatProfile`, `GetNpcCounterAttackIntervalSeconds`, `ResolveCardIdStrict` |
| `CardVisualResolver` | Card visuals from refs |
| `AbilityDatabase` | Canonical ability defs by Id (`Abilities`, `GetAbility`); cards set `AbilityId` on the row |
| `CardAbilityConfig` | Facade over `AbilityDatabase` for existing requires |
| `BoosterBalanceConfig` | Pack definitions |
| `BattleBalanceConfig` | Battle tuning |
| `Server` | Placeholder module under Shared (minimal) |

---

## 2. Save/Load Flow

```mermaid
flowchart TB
    subgraph clientLoad [Client Load]
        RequestLoad[FireServer RequestLoad]
        OnClientEvent[OnClientEvent snapshot]
        SyncClient[ClientStateManager.syncFromServer]
        RebuildUI[Rebuild inventory/combat UI]
        RequestLoad --> OnClientEvent
        OnClientEvent --> SyncClient
        SyncClient --> RebuildUI
    end

    subgraph serverLoad [Server Load]
        EnsureLoaded[ensurePlayerDataLoaded]
        DataStoreGet[DataStore GetAsync]
        Normalize[normalizeLoadedData]
        FireClient[FireClient snapshot]
        EnsureLoaded --> DataStoreGet
        DataStoreGet --> Normalize
        Normalize --> FireClient
    end

    subgraph clientSave [Client Save]
        DeckEdit[User edits deck]
        SaveDeck[SaveDeckState]
        FirePayload[FireServer payload]
        DeckEdit --> SaveDeck
        SaveDeck --> FirePayload
    end

    subgraph serverSave [Server Save]
        MergePatch[mergePlayerPatch]
        PlayerData[playerData]
        TryPersist[tryPersistPlayerData]
        DataStoreUpdate[DataStore UpdateAsync]
        FirePayload --> MergePatch
        MergePatch --> PlayerData
        PlayerData --> TryPersist
        TryPersist --> DataStoreUpdate
    end

    subgraph leave [Player Leave]
        PlayerRemoving[PlayerRemoving]
        BriefWait[task.wait 0.1]
        FinalSave[savePlayerDataToStore]
        PlayerRemoving --> BriefWait
        BriefWait --> FinalSave
    end

    RequestLoad --> EnsureLoaded
    FireClient --> OnClientEvent
```

---

## 3. Economy Flow

```mermaid
flowchart TB
    subgraph clientEcon [Client]
        ShopUI[ShopUIController]
        EconomyClient[EconomyClient.Request]
        ShopClient[ShopClient]
        ShopUI --> ShopClient
        ShopClient --> EconomyClient
    end

    subgraph serverEcon [Server]
        EconomyRequest[EconomyRequest RemoteFunction]
        EconomyService[EconomyService]
        Bridge[SaveManagerBridge Invoke]
        EconomyRequest --> EconomyService
        EconomyService --> Bridge
    end

    subgraph actions [Action Types]
        GetState[GetState]
        BuyPack[BuyPack]
        OpenPack[OpenPack]
        BuyItem[BuyItem]
        UseItem[UseItem]
        SellCards[SellCards]
        BuyDirectCard[BuyDirectCard]
    end

    EconomyClient --> EconomyRequest
    EconomyService --> actions
```

---

## 4. Idle Roll Flow

```mermaid
flowchart TB
    subgraph serverRoll [Server]
        IdleRollService[IdleRollService]
        Tick[tick]
        PickCard[pick card by luck/border]
        IdleRollReward[IdleRollReward FireClient]
        IdleRollService --> Tick
        Tick --> PickCard
        PickCard --> IdleRollReward
    end

    subgraph clientRoll [Client]
        IdleRollBridge[IdleRollBridge]
        IdleCardEvent[IdleCardEvent BindableEvent]
        IdleCardGainer[IdleCardGainer]
        ClientState[ClientStateManager]
        CardAnim[Card animation]
        IdleRollReward --> IdleRollBridge
        IdleRollBridge --> IdleCardEvent
        IdleCardEvent --> IdleCardGainer
        IdleCardGainer --> ClientState
        IdleCardGainer --> CardAnim
    end
```

---

## 5. Stats Allocation Flow

```mermaid
flowchart TB
    subgraph clientStats [Client]
        ProfileUI[ProfileUIController]
        AllocateInvoke[AllocatePointsRemote InvokeServer]
        StatsEvent[StatsUpdatedEvent OnClientEvent]
        ClientState[ClientStateManager]
        ProfileUI --> AllocateInvoke
        StatsEvent --> ClientState
    end

    subgraph serverStats [Server]
        StatsHandler[StatsHandler]
        PlayerStatsService[PlayerStatsService]
        ServerState[ServerStateManager.allocateStatPoint]
        StatsUpdatedEvent[StatsUpdatedEvent FireClient]
        Persist[SaveManager.tryPersistPlayerData]
        AllocateInvoke --> StatsHandler
        StatsHandler --> PlayerStatsService
        PlayerStatsService --> ServerState
        StatsHandler --> StatsUpdatedEvent
        StatsHandler --> Persist
    end

    StatsUpdatedEvent --> StatsEvent
```

---

## 6. Combat Deck Flow

```mermaid
flowchart TB
    subgraph clientDeck [Client]
        DeckUI[Deck modal UI]
        DragDrop[Drag/drop cards]
        SaveDeck[SaveDeckState]
        GetSlots[getCombatSlot getCombatCardsInSlot]
        Payload[payload inventory combat]
        FireServer[SaveDataEvent FireServer]
        DeckUI --> DragDrop
        DragDrop --> SaveDeck
        SaveDeck --> GetSlots
        GetSlots --> Payload
        Payload --> FireServer
    end

    subgraph serverDeck [Server]
        OnServerEvent[SaveDataEvent OnServerEvent]
        Merge[mergePlayerPatch]
        SanitizeCombat[sanitizeCombatSlots]
        EnforceUnique[enforceUniqueTranscendentOwnership]
        PlayerData[playerData]
        OnServerEvent --> Merge
        Merge --> SanitizeCombat
        SanitizeCombat --> EnforceUnique
        EnforceUnique --> PlayerData
    end

    FireServer --> OnServerEvent
```

---

## 7. Shop Flow

```mermaid
flowchart TB
    subgraph shopClient [Client Shop]
        ShopUIController[ShopUIController]
        ShopCatalog[ShopCatalog.GetTabs]
        ShopRenderer[ShopRenderer]
        CreateCurrency[CreateCurrencyPanel]
        CreateContent[CreateContentArea]
        CreateProduct[CreateProductCard]
        OnPurchase[onPurchase]
        EconomyClient[EconomyClient.Request]
        HoverPreview[HoverPreview via HoverPreviewBridge]
        ShopUIController --> ShopCatalog
        ShopUIController --> ShopRenderer
        ShopRenderer --> CreateCurrency
        ShopRenderer --> CreateContent
        ShopRenderer --> CreateProduct
        CreateProduct --> OnPurchase
        OnPurchase --> EconomyClient
        CreateProduct --> HoverPreview
    end

    subgraph tabs [Shop Tabs]
        Packs[Packs]
        Items[Items]
        Cards[Cards]
    end

    ShopCatalog --> tabs
```

---

## 8. Buff/Potion Flow

```mermaid
flowchart TB
    subgraph potionUse [Potion Use]
        ItemsTab[ItemsTab]
        LuckEvent[LuckBuffEvent Fire]
        FoilEvent[FoilChanceBuffEvent Fire]
        BuffBridge[BuffBridge]
        ItemsTab --> LuckEvent
        ItemsTab --> FoilEvent
        LuckEvent --> BuffBridge
        FoilEvent --> BuffBridge
    end

    subgraph economyApply [Server Apply]
        EconomyService[EconomyService UseItem]
        AutoRollRuntime[AutoRollRuntime AddLuckBuff AddFoilChanceBuff]
        EconomyService --> AutoRollRuntime
    end

    subgraph buffDisplay [Display]
        IdleCardGainer[IdleCardGainer]
        LuckBonus[LuckBuffBonus IntValue]
        FoilBonus[FoilChanceBuffBonus IntValue]
        ProfileUI[ProfileUIController Effects tab]
        IdleCardGainer --> LuckBonus
        IdleCardGainer --> FoilBonus
        LuckBonus --> ProfileUI
        FoilBonus --> ProfileUI
    end

    BuffBridge --> IdleCardGainer
```

---

## 9. Modal/Tab Hierarchy

```mermaid
flowchart TB
    RPGHUD[RPGHUDController]
    ToggleBar[Toggle Bar]

    subgraph modals [Modals]
        Backpack[Backpack]
        Deck[Deck]
        Shop[Shop]
        Profile[Profile]
        Settings[Settings]
    end

    subgraph backpackTabs [Backpack Tabs]
        CardsTab[CardsTab]
        BoosterTab[BoosterPacksTab]
        ItemsTab[ItemsTab]
    end

    RPGHUD --> ToggleBar
    RPGHUD --> modals
    Backpack --> backpackTabs
```

---

## 10. Data Schema Quick Reference

### PlayerState
```lua
{
    level = number,
    rollCount = number,
    coins = number,
    stats = { Luck, RollSpeed, PotionDuration, FoilChance, Points },
    inventory = { cardRef },
    combat = { cardRef | "" },
    boosterPacks = { [packId] = count },
    items = { [itemId] = count },
}
```

### EconomyProtocol.ActionType
- GetState, BuyPack, OpenPack, BuyItem, UseItem, SellCards, BuyDirectCard

### Remotes (high level)

Named folders and remotes also live in `EconomyProtocol`, `IdleRollProtocol`, `BattleProtocol`, and `PvpProtocol`.

| Name | Type | Notes |
|------|------|-------|
| SaveDataEvent | RemoteEvent | SaveManager — full save snapshot |
| StatsUpdatedEvent | RemoteEvent | Get-or-create in `StatsHandler.server` and `PlayerStateEvents` (same instance name) |
| AllocatePointsRemote | RemoteFunction | StatsHandler |
| EconomyRequest | RemoteFunction | Under `EconomyRemotes`; EconomyService |
| EconomySnapshotEvent | RemoteEvent | SaveManager — join-time economy partial sync |
| IdleRollReward | RemoteEvent | Under `IdleRollRemotes`; IdleRollService |
| IdleRollControl | RemoteEvent | Under `IdleRollRemotes`; IdleRollService |
| BattleRemotes / PvpRemotes | RemoteEvents | NpcBattleService / PvpBattleService per shared protocols |
