# Changelog

## 1.0.6 - 2026-07-16

- Fixed a "blocked action" (`ADDON_ACTION_FORBIDDEN`) error that prevented logging out or exiting from the game menu on The Burning Crusade. The addon defined globals such as `HasCompletedAnyAchievement` that already exist natively on that client; overwriting them tainted Blizzard's protected code that reads them while opening the game menu, which then blocked the Log Out and Exit buttons. These globals are now only defined when the client does not already provide them.
- The Burning Crusade now uses the addon's bundled achievement UI (updated to the 2.5.6 interface code) instead of loading the native `Blizzard_AchievementUI` addon, whose UI changes in 2.5.6 caused unfixable taint when driven from an addon. The bundled UI ships in per-client copies (`Vanilla/`, `TBC/`) and the native addon is never loaded; a chat warning is shown if another addon force-loads `Blizzard_AchievementUI`, since that conflicts with the bundled UI.
- The bundled achievement window frame is now named `AchievementsFrame` instead of `AchievementFrame`. Blizzard's protected micro-button code reads the global `AchievementFrame` while the game menu opens and closes; a frame created under that name by an addon is permanently tainted and blocked logging out. Public functions such as `AchievementFrame_LoadUI` and `ToggleAchievementFrame` keep their original names, so keybindings and cross-addon integrations continue to work.
- Further reduced zone-transition and general gameplay stutter. `ZONE_CHANGED_NEW_AREA` no longer discards the permanent all-map exploration cache or scans battleground world-state POIs in ordinary zones, and unrelated events such as quest, spell, skill, faction, and currency updates no longer invalidate the exploration cache before refreshing criteria.
- Fixed achievement-window open and close sounds not being played.
- The category order tables (`categoryOrder`, `statisticsCategoryOrder`) are now exported by reference through `Achievements.private.data`. Extension addons that insert their own categories must mutate the same tables the category sidebar reads; falling back to `_G.AchievementsData` was unreliable because a standalone AchievementsData addon can replace that global after the main addon has loaded.
- Updated The Burning Crusade interface compatibility to `20506`.

## 1.0.5 - 2026-06-26

- Fixed a small FPS stutter when changing subzones. Two open-world events that fire on subzone transitions each triggered a full all-achievement scan:
  - Revealing new map areas (`MAP_EXPLORATION_UPDATED`) previously discarded and rebuilt the entire all-maps exploration cache; the addon now incrementally merges only the current map's newly revealed overlays and refreshes only exploration criteria, and only when something actually changed.
  - Area POI updates (`AREA_POIS_UPDATED`) ran a battleground/world-state area-POI sweep and a full refresh in every zone; this work now only runs when the player is actually in a world-state context (battleground/arena or a zone exposing a world-state UI), so ordinary leveling-zone subzone changes do no extra work.

## 1.0.4 - 2026-06-20

- Fixed loot-acquisition criteria (such as fish caught and items disenchanted) counting far too fast. A single catch could be counted multiple times because it was recorded once per looted item and again on both the loot window and loot chat message; these counters now increment exactly once per catch. "Catch fish in pool" and "use object" counters are likewise counted once per source object per loot.
- Fixed criteria progress (such as Gold Looted and emote counts) being wrongly discarded on login with "ignored modified criteria progress saved data". The saved-data integrity seal included a per-character owner string derived from APIs whose return values are not stable across the login lifecycle, so the addon could reject its own freshly written data. The seal no longer depends on those values, and existing sealed progress is preserved across the update.

## 1.0.3 - 2026-06-15

- Further reduced raid stutter: combat-log criteria handling now bails out early for unrelated actors before any context building, and `UNIT_AURA`/`UNIT_SPELLCAST_SUCCEEDED` are registered for the player unit only so the event handler is no longer entered for every visible unit.

## 1.0.2 - 2026-05-24

- Improved achievement criteria handling performance by caching displayable criteria and tree-flag lookups, trimming per-event criteria scans, and short-circuiting single-child criteria resolution.

## 1.0.1 - 2026-05-17

- Reduced raid-combat stutter by narrowing high-frequency combat-log and aura criteria refreshes.

## 1.0.0 - 2026-05-06

- Initial release