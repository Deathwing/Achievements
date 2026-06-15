# Changelog

## 1.0.3 - 2026-06-15

- Further reduced raid stutter: combat-log criteria handling now bails out early for unrelated actors before any context building, and `UNIT_AURA`/`UNIT_SPELLCAST_SUCCEEDED` are registered for the player unit only so the event handler is no longer entered for every visible unit.

## 1.0.2 - 2026-05-24

- Improved achievement criteria handling performance by caching displayable criteria and tree-flag lookups, trimming per-event criteria scans, and short-circuiting single-child criteria resolution.

## 1.0.1 - 2026-05-17

- Reduced raid-combat stutter by narrowing high-frequency combat-log and aura criteria refreshes.

## 1.0.0 - 2026-05-06

- Initial release