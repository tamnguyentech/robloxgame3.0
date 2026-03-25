# Game Architecture — Flowcharts & Datasheet

Principal architect reference: module map, data flows, and visual diagrams for in-game logic.

**Related:** [SAVE_AND_PERFORMANCE_WORKFLOW.md](SAVE_AND_PERFORMANCE_WORKFLOW.md) — Master workflow for save fixes, performance tuning, and HoverPreview readability.

---

## 1. Module Directory

### src/client

| Module | Purpose |
|--------|---------|
| `core/ClientStateManager` | Client-side player state (level, rollCount, coins, stats, inventory, combatDeck, boosterPacks, items) |
| `core/BuffBridge` | Luck/FoilChance buff BindableEvents and IntValues |
| `IdleRollBridge.client` | Forwards RewardEvent → IdleCardEvent |
| `IdleCardGainer.client` | Handles IdleCardEvent, card gains, HUD buff timers, syncs to ClientStateManager |
| `InventoryController.client` | SaveDataEvent handler, deck/inventory UI, SaveDeckState |
| `services/EconomyClient` | EconomyRequest RemoteFunction calls |
| `services/ShopClient` | BuyItem, BuyDirectCard, UseItem, SellCards via EconomyClient |
| `shop/ShopCatalog` | Shop tabs (Packs, Items, Cards), EconomyCatalog entries |
| `shop/ShopRenderer` | Currency, tabs, product cards, border gallery |
| `shop/ShopUIController` | Shop modal setup, purchase handlers, HoverPreview |
| `tabs/TabController` | Backpack tab bar (Cards, Boosters, Items) |
| `tabs/CardsTab` | Cards tab |
| `tabs/BoosterPacksTab` | Boosters tab, open packs |
| `tabs/ItemsTab` | Items tab, potions via BuffBridge events |
| `ui/controllers/RPGHUDController` | Main HUD, toggle bar, modals (Backpack, Deck, Shop, Profile, Settings) |
| `ui/controllers/ProfileUIController` | Profile modal, stats, allocation, effects |
| `ui/controllers/SettingsUIController` | Settings modal (Audio, Graphics, Controls, Gameplay) |
| `ui/HoverPreview` | Shared card hover panel |
| `ui/ParallaxNameLabel` | Card name display helper |
| `ui/effects/HoloFoilController` | Foil overlays for bordered cards (Silver, Gold, Diamond, Cosmic, Corrupted) |
| `UIUtility.client` | Init: ClientStateManager, RPGHUDController, modal setup |
| `NpcBattleClient.client` | NPC battle UI |
| `PvpBattleClient.client` | PvP battle flow |

### src/server

| Module | Purpose |
|--------|---------|
| `SaveManager` | DataStore load/save, SaveDataEvent, mergePlayerPatch |
| `StatsHandler.server` | AllocatePointsRemote, StatsUpdatedEvent handler |
| `PlayerStatsService` | Stat allocation, reset, level-up via ServerStateManager |
| `EconomyService.server` | EconomyRequest handler (GetState, BuyPack, OpenPack, BuyItem, UseItem, SellCards, BuyDirectCard) |
| `IdleRollService.server` | Idle roll ticks, RewardEvent |
| `AutoRollRuntime` | Auto-roll timing per player |
| `NpcBattleService.server` | NPC battles |
| `PvpBattleService.server` | PvP battles |
| `core/ServerStateManager` | Facade for player state |
| `core/state/PlayerStateStore` | In-memory player state cache |
| `core/state/PlayerStateSchema` | Default state, sanitization, save payloads |
| `core/state/PlayerProgressionState` | coins, rollCount, level |
| `core/state/PlayerCollectionsState` | inventory, items, boosterPacks |
| `core/state/PlayerStatsState` | stats, allocation, level-up |
| `core/state/PlayerStateEvents` | StatsUpdatedEvent creation/firing |

### src/shared

| Module | Purpose |
|--------|---------|
| `EconomyProtocol` | EconomyRemotes folder, EconomyRequest, ActionType |
| `EconomyCatalog` | Item offers, direct card offers, sell values |
| `IdleRollProtocol` | RewardEvent, ControlEvent |
| `BattleProtocol` | NPC battle remotes |
| `PvpProtocol` | PvP remotes |
| `BalanceConfig` | ROLLS_PER_LEVEL, luck formulas, auto-roll interval |
| `CardDatabase` | Card data, rarity, combat power |
| `CardVisualResolver` | Card visuals from refs |
| `BoosterBalanceConfig` | Pack definitions |
| `BattleBalanceConfig` | Battle tuning |

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
        Bridge[SaveManagerBridge]
        ExecuteDelta[executeEconomyDelta]
        EconomyRequest --> EconomyService
        EconomyService --> Bridge
        EconomyService --> ExecuteDelta
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
        RewardEvent[RewardEvent FireClient]
        IdleRollService --> Tick
        Tick --> PickCard
        PickCard --> RewardEvent
    end

    subgraph clientRoll [Client]
        IdleRollBridge[IdleRollBridge]
        IdleCardEvent[IdleCardEvent BindableEvent]
        IdleCardGainer[IdleCardGainer]
        ClientState[ClientStateManager]
        CardAnim[Card animation]
        RewardEvent --> IdleRollBridge
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
        Persist[SaveManager.persistPlayerData]
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

### Remotes
| Name | Type | Owner |
|------|------|-------|
| SaveDataEvent | RemoteEvent | SaveManager |
| StatsUpdatedEvent | RemoteEvent | StatsHandler |
| AllocatePointsRemote | RemoteFunction | StatsHandler |
| EconomyRequest | RemoteFunction | EconomyService |
| RewardEvent | RemoteEvent | IdleRollService |
