# Achievements Data

AchievementsData is the required generated data package for the Achievements addon. It contains the achievement database, criteria trees, statistics, localizations, title metadata, and fallback icon assets used by the runtime addon.

This package does not add an achievement UI by itself. Install it beside the main `Achievements` addon.

## Install

Install both addon folders side by side:

```text
Interface/AddOns/Achievements
Interface/AddOns/AchievementsData
```

Enable both addons at the character-select addon list. If `AchievementsData` is missing or disabled, `Achievements` cannot load because it has no generated achievement data.

## Current Data

- Data version: `efd2b30f`
- Source: 3.4.5.63697 CSV data
- Classic Era: 386 achievements and 177 statistics
- The Burning Crusade: 643 achievements and 254 statistics
- Included localizations: `deDE`, `esES`, `esMX`, `frFR`, `koKR`, `ptBR`, `ruRU`, `zhCN`, and `zhTW`

## What This Package Contains

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
- The addon automatically loads the Classic Era or Burning Crusade data file that matches the active client.
- This package is released under the GNU GPL3 license.
