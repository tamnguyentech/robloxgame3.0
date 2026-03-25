# Patch Notes

## Patch — Recent Changes

### Foil & Effects

- **Cosmic → Lightning**: Removed Cosmic foil tier; replaced with **Lightning** concept (procedural bolt overlay).
- **LightningOverlayController**: Midpoint-displacement bolts, traveling wave animation, thicker streaks (6–8px), ~0.55s flash.
- **HoverPreview**: Supports Lightning overlay for concept previews.

### Shop Gallery

- **2-row layout**: Row 1 = border tiers (Silver/Gold/Diamond/Rainbow), Row 2 = concept tiles (Ultra Rare, Lightning, Ember Vein).
- **Split placeholder cards**: Border tiers use `GALLERY_BASE_CARD` (OmegaBoku); Lightning concept uses `GALLERY_LIGHTNING_CARD` (ZinbaLightningGod).
- **Rainbow preview**: Uses OmegaBoku as placeholder.

### Settings & Save

- **Idle roll notifications**: New toggle "Show Idle Roll Card Popups"; persisted in `clientSettings`, default ON.

### Card Database

- **50+ new cards**: Custom Epic/Rare/God tier including Ginoya, Laughffy, KingBoku, SuperBoku, OmegaBoku, Zinba Lightning God, BeastNurudo, CursedZosuke, Freezer, Revy, Wantengo, Saki, Kyoko, and many more.
- **Cosmic cleanup**: Removed from `VALID_FOIL_TIERS`, `TIER_STROKE_COLORS`, `BORDER_TIER_ORDER`.

---

## Major Changes Since Last Release

### Combat Deck & Persistence

- **Combat deck save reliability**: Reduced periodic deck save interval from 8s to 2s when deck is dirty; reduces risk of deck loss on abrupt disconnect.
- **Player leave grace period**: Added 0.1s wait in `PlayerRemoving` before persisting to allow in-flight `SaveDataEvent` to be processed.
- **Items defaults alignment**: `SaveManager` now uses `PlayerStateConstants.GetDefaultItems()` (includes `FoilChancePotion`) instead of hardcoded item maps.

---

### UI and Visual Overhaul

- **ParallaxNameLabel**: New helper module for card name display with depth/parallax effect.
- **HoloFoilController**: Silver + Diamond foil overhaul; new **Cosmic** (Midnight Nebula) and **Corrupted** (Ember Vein) tiers.
- **Diamond Prismatic Glitch**: Math.sin gradient rotation plus Cyan/Magenta shards for glitch refraction.
- **Deck UI**: Visual overhaul for combat deck layout and styling.
- **Profile UI**: Overhaul with player identity, stats, and professional layout.
- **Hover Preview**: Art fill, ATK/HP corners, speed format, name stack.

---

### Shop and Economy

- **Shop modularization**: `ShopCatalog`, `ShopRenderer`, `ShopUIController` for tabs (Packs, Items, Cards), product cards, and purchase flow.
- **EconomyClient / ShopClient**: Refactored wrappers for EconomyRequest actions.

---

### Server State and Persistence

- **Server core**: `ServerStateManager`, `PlayerStateStore`, `PlayerStateSchema`, `PlayerCollectionsState`, `PlayerProgressionState`, `PlayerStatsState`, `PlayerStateEvents`.
- **StatsHandler.server**: Replaces standalone `AllocatePointsRemote` module; owns `AllocatePointsRemote` and `StatsUpdatedEvent`.
- **SaveManager**: Integrated with server core; uses `PlayerStateConstants` for defaults.
- **BalanceConfig**, **PlayerStateConstants**: Centralized constants and defaults.

---

### Client State and Controllers

- **ClientStateManager**, **BuffBridge**: Central client state and buff event bridges.
- **RPGHUDController**: Main HUD with toggle bar and modals (Backpack, Deck, Shop, Profile, Settings).
- **SettingsUIController**: Settings modal (Audio, Graphics, Controls, Gameplay).
- **ProfileUIController**: Stats allocation, effects from BuffBridge.

---

### Documentation

- **Modal/tab UI pattern**: `.windsurf/workflows/modal-tab-ui-pattern.md` — how to create modal/tab-specific UI elements.
