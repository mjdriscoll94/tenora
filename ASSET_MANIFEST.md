# Tenora Habit Game Asset Manifest

## Integrated production art

Tenora currently includes 249 individually addressable, transparent production assets in
`Tenora/Resources/Assets.xcassets/HabitGame`. The app renders these individual assets at
runtime; it does not display the supplied reference sheets or full sprite sheets.

The integrated catalog includes:

- Terrain, paths, water, cliffs, distant scenery, vegetation, structures, decorations, and wildlife
- 23 Keeper animation frames covering idle, walking, watering, reading, celebrating, sitting, sleeping, looking, and carrying
- 36 habit icons used by the habit editor and habit views
- 24 achievement badges used by the collection and celebration views
- Seasonal trees and bushes for spring, summer, fall, and winter
- Celebration effects, world-stage scenes, and environmental backgrounds

`Tenora/Resources/HabitGameAssetManifest.json` records every runtime name, source sheet,
crop rectangle, anchor, and exported size. `Scripts/extract_habit_game_assets.py` reproduces
the catalog from the approved `ProductionSpriteSheets` package and replaces the generated
`HabitGame` group on every run so stale sprites cannot remain in the build.

## Supplied sheets

All nine supplied production sprite sheets were processed:

1. `01_terrain_tiles.png`
2. `02_vegetation.png`
3. `03_structures_small_medium.png`
4. `04_structures_large_upgrades.png`
5. `05_decorations_wildlife.png`
6. `06_keeper_animation_frames.png`
7. `07_habit_icons.png`
8. `08_achievement_badges.png`
9. `09_effects_seasons_world_progression.png`

## Standalone names not present in the production sheets

The following names appeared in the package's legacy template catalog but did not have a
distinct matching sprite in the supplied production sheets. They are not referenced by the
app. Closely related production art is used where appropriate.

- `effect_burst`
- `effect_magic_circle`
- `effect_water_sparkle`
- `keeper_look_02`
- `season_fall_flower`
- `season_fall_pumpkin`
- `season_spring_flower`
- `season_spring_flowering_bush`
- `season_summer_flower`
- `season_summer_sunflower`
- `season_winter_flower`
- `season_winter_snowman`
- `world_water_lily`

If those thirteen standalone images are supplied later, they can be added without changing
saved habit or progression data.
