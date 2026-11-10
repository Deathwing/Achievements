# Changelog

## 1.2.0 - 2026-11-10

- Added support for World of Warcraft: Forever (interface 16001). Forever runs the Mainline API, so the addon ships a small compatibility layer that maps the Classic-era functions it relies on onto it (file-local, without defining them globally), and a fully namespaced Forever copy of the bundled achievement window that coexists with Blizzard's Legacy system (which is built on the native achievement API, so the addon no longer overrides those functions there). On Forever the default keys are `SHIFT-Y` for achievements and `CTRL-Y` for statistics, because `Y` belongs to the Legacy window. Tracked achievements appear as an "Achievements" section in the objective tracker, styled like Blizzard's own, and follow the tracker's own re-layouts. Forever gets its own generated data set (`AchievementsData_Camelot.lua`) built from Forever's game tables, so zones, exploration overlays, reputations, quests and titles resolve against Forever's real IDs, and achievements Forever also defines natively use Forever's criteria. Forever closes the combat log to addons, so kills, casts, honorable kills, damage, healing and deaths are tracked from encounter results, visible unit deaths, loot, chat messages, your own casts and combat text, Blizzard's damage meter and the death recap instead; killing blows, the longest fall survived, the largest hit dealt and the largest heal cast remain untracked there (see the README for the full list).
- On Forever, achievement chat links are handled through the client's link handler registry instead of replacing `SetItemRef`, so Blizzard's own Legacy links stay clickable. Abandoning quests, posting auctions and bidding, accepting summons and buying bank tabs are tracked through Forever's API, and skill criteria also count professions listed under a collapsed header. The addon's shipped `Y` default would take the Legacy window's key, so a one-time migration moves the addon to `SHIFT-Y`/`CTRL-Y` and gives `Y` back to the Legacy window. It runs once per binding set (after combat if you log in mid-fight), and only while both addon keys are still at their shipped defaults, the Legacy window has no key and `CTRL-Y` is free, so your own bindings are left alone. Bosses that survive a won encounter are not credited as kills, and unit tracking is limited to your target, focus, their targets, mouseover and nameplates.
- The CurseForge release of `Achievements` now carries a copy of `AchievementsData` inside `Achievements/Data/`, so installing only the main addon no longer leaves it without data. A separately installed `AchievementsData` addon keeps working as before; when both are present the newest installed copy is used. `/ach versions` reports which copy is in use and shows the data version as its build date. The Wago, WoWInterface and GitHub bundled zips still ship both addon folders side by side.
- Fixed the WoWInterface button sticking out of the "update available" window. The download-source buttons now sit in a two-per-row grid, and the window is sized to fit them. CurseForge is now listed first and preselected.
- Chat channels stay in order. The addon could re-join its discovery channel although the game had already restored it at login, which hands the channel number back and can push General and Trade down. It now waits until the game has restored its cached channels, reuses the one it already belongs to and only joins when it is not a member of any.
- Removed Old Crafty, Old Ironjaw and The Bread Winner from the Classic Era achievement list (shipped through the `AchievementsData` package). Old Crafty and Old Ironjaw only became fishable in patch 2.3, and 10,000 gold from quest rewards is out of reach without repeatable daily quests. All three remain available on The Burning Crusade. Thanks for the report.

## 1.1.0 - 2026-07-26

- Added `/ach locale <code>` to show achievement names, descriptions, criteria, categories and rewards in any language included in the `AchievementsData` package, independently of your game client language. `/ach locale` on its own shows the current selection and the available language codes, and `/ach locale auto` returns to the client language. The choice is account-wide and applies to every character. Blizzard-owned window labels, tabs, buttons and date formats stay in the client language, and achievement tracking is unaffected by the selection. Thanks to @Yudaev for contributing this feature.

## 1.0.9 - 2026-07-24

- The update-available popup now only appears while you are resting (in an inn or city) instead of anywhere out of combat, so it no longer interrupts you in the open world.
- Added a `/ach versions` command that prints the versions of Achievements and its bundled components (the data package, if installed), and notes when a newer version has been seen from other players.

## 1.0.8 - 2026-07-23

- Updated Classic Era interface compatibility to `11509` (1.15.9).

## 1.0.7 - 2026-07-22

- Added an in-game update notification and `/ach update` source chooser with official GitHub, CurseForge, and Wago download links. The new `/ach` (or `/achievements`) command without arguments toggles the achievement frame.
- Release tags now produce installable GitHub assets and publish the bundled addon to Wago while retaining split dependency packages on CurseForge.
- Fixed the achievement micro button appearing faded (half transparent) and unclickable on The Burning Crusade. Blizzard's micro-button update disables the native achievement button when the built-in achievement system reports no achievements, which is always the case there; the addon now re-enables the button after every micro-button update since it provides its own achievements.

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
