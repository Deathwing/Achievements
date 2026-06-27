# Changelog

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