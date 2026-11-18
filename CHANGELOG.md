# Changelog

## 1.2.1 - 2026-11-19

- Battleground achievements with a condition, such as Arathi Basin Perfection, We Had It All Along *cough*, Resilient Victory or Warsong Gulch Perfection, are no longer awarded for any win. They now need their condition at the moment you win, and a score the addon cannot read never counts. Resilient Victory now works for every race, and every battleground win counts again, not only the first one per battleground until a reload.
- Damage Control is no longer awarded the moment you enter a battleground once your lifetime damage or healing passes 300,000. It now needs 300,000 damage to players or 300,000 healing within a single battle, and its zone check now recognizes the battleground you are in. On WoW Forever only the healing counts, because the addon gets only your damage total there, not whom you hit. On The Burning Crusade, World Wide Winner no longer counts arena wins below level 70.
- Alterac Valley: Everything Counts now checks that your team holds both Irondeep Mine and Coldtooth Mine when you win, in every game language. It used to credit the mines to the other team on English clients and never worked in other languages. Stormpike Perfection and Frostwolf Perfection can no longer be earned, because the game does not tell addons whether Captain Balinda Stonehearth or Captain Galvangar is still alive.
- Check Your Head and Let It Snow now count the race and class of the player you hit. A Dwarf used to check off Gnome, Night Elf, Tauren and Undead but not Dwarf, some races checked off nothing, Let It Snow could not be completed, and one pumpkin head on a player whose race the addon could not read completed Check Your Head at once.
- Achievements of the other faction are no longer awarded. When their conditions were met, for example a win in Alterac Valley while the other team held both mines, you got the other faction's Everything Counts, with a toast and a guild message for an achievement you cannot see.
- Classic Era and The Burning Crusade: kills of enemy players now count. Wrecking Ball, The Grim Reaper, That Takes Class, Know Thy Enemy, Wrath of the Horde, Wrath of the Alliance, Arathi Basin Assassin, Not So Fast, on The Burning Crusade also Stormtrooper, Bloodthirsty Berserker and Take a Chill Pill, and the killing blow and honorable kill statistics never moved, because the addon only counted a kill when the victim was you. Killing blows count your own kills, including those of your pet and totems, but not while you are dead. Honorable kills count every kill the game gives you honor for, including your group's. Players of your own faction outside arenas and victims the addon cannot identify never count. The statistics count from this version on; World Honorable Kills and World Killing Blows do not count kills in the Eastern Kingdoms yet.
- The zone check of The Fishing Diplomat, Wrath of the Horde, Wrath of the Alliance, Supreme Defender, Wrecking Ball and, on The Burning Crusade, Torch Juggler now recognizes where you are, in every game language. It never matched before, so a catch in Orgrimmar or a kill in an enemy capital did not count. A zone with the same name somewhere else, such as the second Stormwind City and Warsong Gulch in WoW Forever's game files, does not count, and on Classic Era and WoW Forever fishing in a dungeon no longer checks off the Orgrimmar half of The Fishing Diplomat.
- City Defender, The Sickly Gazelle, Save The Day and Not In My House cannot be earned, because the game does not tell addons where the player you kill is standing. On WoW Forever, City Defender used to count honorable kills anywhere the game reported no map for you. Quick Cap and, on The Burning Crusade, A Frosty Shake cannot be earned either: they need a Warsong Gulch flag room or Northrend's Dalaran, which do not exist in these versions of the game.
- Achievements that must be done within a single battle, such as Everything Counts and The Grim Reaper, no longer carry progress over from a battle you left by logging out, disconnecting or going straight into another battleground. On WoW Forever, The Grim Reaper could add up honorable kills from two battles that way. Reconnecting during a battle starts their progress in that battle over, and so does reloading the interface for those that start over with every battle, such as Damage Control and Wrecking Ball. A reload no longer counts the battle a second time as a battle played.
- WoW Forever: earning an achievement shows the addon's own toast instead of raising an error in Blizzard's alert code, and several achievements earned at once no longer block the following toasts.
- WoW Forever: your chat messages in battlegrounds, dungeons and raids are no longer blocked with "AddOn 'Achievements' tried to call the protected function". The addon used to replace the game's chat send functions to shorten achievement links; it now does that in the chat box just before the game sends the message, on every game version. Forever does not let addons put text into chat there at all, so shift-clicking an achievement shows the game's "can't do that" error instead of a link that would block the message.
- WoW Forever: tracking or untracking an achievement from the achievement window no longer raises an error.
- WoW Forever: no more errors in dungeons when the game hides a unit's name or identity. Hovering monsters raised thousands of errors per session from the title shown in unit tooltips; nameplates, unit right-click menus, chat links, the discovery channel, duel messages, buffs, casts, loot and emotes now skip hidden values the same way. Titles still show for players whose names are visible, and the tooltip title now hooks the game's tooltip callbacks instead of replacing `GameTooltip:SetUnit`.
- WoW Forever: fewer kills are lost in dungeons that hide the monster's name and ID. Kills credited from a looted corpse or a recently seen monster no longer fail silently, and on English game clients the experience message now also credits kills for creatures named by kill criteria, matched against the names shipped in `AchievementsData`.
- WoW Forever: damage taken now counts from Blizzard's damage meter after each fight, because Forever hides the amounts in your own combat text. The largest hit taken, healing received and the largest heal received can no longer be tracked on Forever and keep their saved progress.
- `/ach versions` no longer says "embedded in Achievements" when a newer `AchievementsData` copy comes from somewhere else than the copy inside Achievements.

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
