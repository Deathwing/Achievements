# Achievements Data

AchievementsData is the required generated data package for the Achievements addon. It contains the achievement database, criteria trees, statistics, localizations, title metadata, and fallback icon assets used by the runtime addon.

This package does not add an achievement UI by itself. Install it beside the main `Achievements` addon.

## Install

Install both addon folders side by side:

```text
Interface/AddOns/Achievements
Interface/AddOns/AchievementsData
```

Enable both addons at the character-select addon list. The CurseForge build of `Achievements` also ships a copy of this package inside `Achievements/Data/` as a fallback: when the standalone `AchievementsData` addon is installed and enabled as well, the newest installed copy is used, so this package can still be updated independently. Builds without that embedded copy (the plain GitHub `Achievements` zip) cannot load when `AchievementsData` is missing or disabled, because they have no generated achievement data.

World of Warcraft: Forever loads its own generated data set, `AchievementsData_Camelot.lua`, built from Forever's game tables (areas, exploration overlays, factions, quests, titles, skills, spells and items) with the Classic Era achievement definitions; achievements Forever defines natively use Forever's criteria trees. Quest zones and creature names for Forever come from QuestieDB's Forever database.

## Current Data

- Data version: the build date shown by `/ach versions`
- Source: 3.4.5.63697 CSV data, plus Forever's own game tables for World of Warcraft: Forever
- Classic Era: 383 achievements and 177 statistics
- The Burning Crusade: 643 achievements and 254 statistics
- Included localizations: `deDE`, `esES`, `esMX`, `frFR`, `koKR`, `ptBR`, `ruRU`, `zhCN`, and `zhTW`

## What This Package Contains

- `AchievementsData_Camelot.lua`: the World of Warcraft: Forever data set, generated from Forever's DB2 exports.
- `AchievementsData_Classic.lua`: generated Classic Era achievement, criteria, statistic, category, quest, map, reputation, item, spell, skill, title, and localization data.
- `AchievementsData_TBC.lua`: generated Burning Crusade achievement, criteria, statistic, category, quest, map, reputation, item, spell, skill, title, and localization data.
- `AchievementsIconAssets.lua`: icon override and fallback texture paths used when client icon paths are missing or incompatible.
- `assets/icons/`: bundled fallback icon textures.
- `Media/`: package artwork used by the addon manager and release pages.

## Why It Is Separate

The runtime addon lives in `Achievements`; this package keeps generated data and icon assets separate so data-only updates can be released without replacing the runtime framework. Keeping the data split also makes it clearer which files are generated and which files contain addon behavior.

Use the `Achievements` and `AchievementsData` packages from the same release whenever possible. Newer data can add or correct metadata, icons, criteria, and localizations, while the runtime addon handles the UI, saved progress, tracking, chat links, networking, comparison, and title support.

## Community

Join our community on [Discord](https://discord.gg/TrJFGcah7z) for support, bug reports, and feedback.

## Notes

- These files are generated and should not be edited manually.
- The addon automatically loads the Classic Era, Burning Crusade or World of Warcraft: Forever data file that matches the active client.
- This package is released under the GNU GPL3 license.
