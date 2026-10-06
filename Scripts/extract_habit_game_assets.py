#!/usr/bin/env python3
"""Build Tenora's HabitGame asset catalog from the approved production sheets.

The source package deliberately ships transparent sprite sheets rather than a pile
of hand-cropped files. This script keeps the extraction repeatable and documents
the cell-to-runtime-name mapping used by the app.
"""

from __future__ import annotations

import argparse
import json
import shutil
from collections import deque
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


@dataclass(frozen=True)
class Sprite:
    name: str
    group: str
    sheet: str
    box: tuple[int, int, int, int]
    anchor: str = "bottom"


SHEET_WIDTH = 1448


def cells(sheet: str, group: str, y0: int, y1: int, names: list[str], anchor: str = "bottom") -> list[Sprite]:
    width = SHEET_WIDTH / len(names)
    return [
        Sprite(name, group, sheet, (round(index * width), y0, round((index + 1) * width), y1), anchor)
        for index, name in enumerate(names)
    ]


SPRITES: list[Sprite] = []

# Terrain, water, paths, cliffs, and distant scenery.
SPRITES += cells("01_terrain_tiles.png", "World/Terrain", 0, 270, [
    "world_terrain_grass_01", "world_terrain_grass_02", "world_terrain_grass_flowers",
    "world_terrain_dirt_01", "world_terrain_dirt_02", "world_terrain_stone_01",
    "world_terrain_stone_02", "world_terrain_stone_mossy",
])
SPRITES += cells("01_terrain_tiles.png", "World/Terrain", 260, 525, [
    "world_path_straight", "world_path_curve", "world_path_intersection", "world_path_stepping",
    "world_water_pond", "world_water_stream", "world_water_edge",
])
SPRITES += cells("01_terrain_tiles.png", "World/Terrain", 510, 820, [
    "world_shore_grass", "world_shore_rock", "world_cliff_small", "world_cliff_medium",
    "world_cliff_large", "world_cliff_corner", "world_island_tree",
])
SPRITES += cells("01_terrain_tiles.png", "World/Backgrounds", 805, 1086, [
    "world_background_clouds", "world_background_mountains", "world_background_forest",
], "center")

# Vegetation.
SPRITES += cells("02_vegetation.png", "World/Vegetation", 0, 355, [
    "world_tree_sapling", "world_tree_young", "world_tree_medium", "world_tree_large",
    "world_tree_flowering", "world_tree_fruit", "world_tree_pine", "world_tree_autumn",
])
SPRITES += cells("02_vegetation.png", "World/Vegetation", 345, 520, [
    "world_bush_small", "world_bush_round", "world_bush_lush", "world_bush_flowering",
    "world_bush_berry", "world_bush_pink", "world_bush_hydrangea", "world_bush_rocky",
])
SPRITES += cells("02_vegetation.png", "World/Vegetation", 510, 690, [
    "world_flower_white", "world_flower_yellow", "world_flower_blue", "world_flower_purple",
    "world_flower_pink", "world_flower_mixed", "world_grass_small", "world_grass_medium",
    "world_grass_tall", "world_reeds", "world_wildflowers", "world_dandelions",
    "world_fern_small", "world_fern_large",
])
SPRITES += cells("02_vegetation.png", "World/Vegetation", 675, 885, [
    "world_mushroom_brown", "world_mushroom_red", "world_mushroom_cluster", "world_fungus_log",
    "world_decor_log", "world_plant_stump", "world_decor_rock_large", "world_vine_hanging",
    "world_vine_flowering", "world_vine_dense", "world_stump_vines",
])
SPRITES += cells("02_vegetation.png", "World/Vegetation", 870, 1086, [
    "world_sprout_01", "world_sprout_02", "world_sprout_03", "world_ground_plant",
    "world_vegetation_cluster",
])

# Small and medium structures.
SPRITES += cells("03_structures_small_medium.png", "World/Structures", 0, 350, [
    "world_structure_sign", "world_structure_bench", "world_structure_lantern",
    "world_structure_lamp_post", "world_structure_fence_wood", "world_structure_fence_stone",
    "world_structure_gate",
])
SPRITES += cells("03_structures_small_medium.png", "World/Structures", 335, 625, [
    "world_structure_bridge_wood", "world_structure_bridge_stone", "world_structure_birdhouse",
    "world_structure_garden_bed", "world_structure_well", "world_structure_fire_pit",
])
SPRITES += cells("03_structures_small_medium.png", "World/Structures", 610, 880, [
    "world_structure_hammock", "world_decor_picnic_table", "world_structure_dock",
    "world_structure_archway", "world_structure_mailbox", "world_structure_sign_flowering",
    "world_structure_lantern_pair",
])

# Large upgrades.
SPRITES += cells("04_structures_large_upgrades.png", "World/Structures", 0, 380, [
    "world_structure_gazebo", "world_structure_cabin", "world_structure_cabin_upgraded",
    "world_structure_windmill", "world_structure_fountain",
])
SPRITES += cells("04_structures_large_upgrades.png", "World/Structures", 365, 765, [
    "world_structure_lookout", "world_structure_observatory", "world_structure_grand_archway",
    "world_structure_pergola", "world_structure_pavilion",
])
SPRITES += cells("04_structures_large_upgrades.png", "World/Structures", 745, 1086, [
    "world_structure_bridge_grand", "world_structure_dock_grand", "world_structure_shed",
    "world_structure_tower", "world_structure_greenhouse",
])

# Decorations and wildlife.
SPRITES += cells("05_decorations_wildlife.png", "World/Decorations", 0, 285, [
    "world_decor_rock_small", "world_decor_rocks", "world_decor_rock_flowers",
    "world_decor_log_mushrooms", "world_decor_hollow_log", "world_decor_stump",
])
SPRITES += cells("05_decorations_wildlife.png", "World/Decorations", 275, 515, [
    "world_decor_watering_can", "world_decor_bucket", "world_decor_shovel",
    "world_decor_wheelbarrow", "world_decor_crate", "world_decor_basket",
])
SPRITES += cells("05_decorations_wildlife.png", "World/Decorations", 500, 735, [
    "world_decor_bicycle", "world_decor_books", "world_decor_blanket", "world_decor_tea",
    "world_decor_backpack", "world_decor_telescope", "world_decor_planter",
])
SPRITES += cells("05_decorations_wildlife.png", "World/Wildlife", 720, 955, [
    "world_animal_butterfly", "world_animal_bee", "world_animal_ladybug", "world_animal_bird",
    "world_animal_squirrel", "world_animal_rabbit", "world_animal_duck", "world_animal_frog",
    "world_animal_fox", "world_animal_owl", "world_animal_deer",
])
SPRITES += cells("05_decorations_wildlife.png", "World/Wildlife", 935, 1086, ["world_animal_fish"])

# Keeper frames. Every frame is normalized to one bottom-aligned canvas below.
SPRITES += cells("06_keeper_animation_frames.png", "Keeper", 0, 280, [
    "keeper_idle_01", "keeper_idle_02", "keeper_idle_03", "keeper_idle_04",
    "keeper_walk_01", "keeper_walk_02",
])
SPRITES += cells("06_keeper_animation_frames.png", "Keeper", 270, 555, [
    "keeper_walk_03", "keeper_walk_04", "keeper_water_01", "keeper_water_02",
    "keeper_read_01", "keeper_read_02",
])
SPRITES += cells("06_keeper_animation_frames.png", "Keeper", 540, 820, [
    "keeper_celebrate_01", "keeper_celebrate_02", "keeper_celebrate_03",
    "keeper_sit_01", "keeper_sit_02", "keeper_sleep_01",
])
SPRITES += cells("06_keeper_animation_frames.png", "Keeper", 805, 1086, [
    "keeper_sleep_02", "keeper_look_01", "keeper_carry_01", "keeper_carry_02", "keeper_carry_03",
])

# Habit icon grid.
SPRITES += cells("07_habit_icons.png", "HabitIcons", 0, 181, [
    "habit_icon_water", "habit_icon_medication", "habit_icon_exercise", "habit_icon_walk",
    "habit_icon_sleep", "habit_icon_stretch",
], "center")
SPRITES += cells("07_habit_icons.png", "HabitIcons", 181, 362, [
    "habit_icon_meditate", "habit_icon_breathe", "habit_icon_therapy", "habit_icon_reflection",
    "habit_icon_food", "habit_icon_vitamins",
], "center")
SPRITES += cells("07_habit_icons.png", "HabitIcons", 362, 543, [
    "habit_icon_bible", "habit_icon_prayer", "habit_icon_church", "habit_icon_study",
    "habit_icon_service", "habit_icon_book",
], "center")
SPRITES += cells("07_habit_icons.png", "HabitIcons", 543, 724, [
    "habit_icon_journal", "habit_icon_language", "habit_icon_music", "habit_icon_dishes",
    "habit_icon_laundry", "habit_icon_cleaning",
], "center")
SPRITES += cells("07_habit_icons.png", "HabitIcons", 724, 905, [
    "habit_icon_trash", "habit_icon_organize", "habit_icon_hygiene", "habit_icon_skincare",
    "habit_icon_call", "habit_icon_finances",
], "center")
SPRITES += cells("07_habit_icons.png", "HabitIcons", 905, 1086, [
    "habit_icon_planning", "habit_icon_writing", "habit_icon_connection", "habit_icon_home",
    "habit_icon_laptop", "habit_icon_gratitude",
], "center")

# Achievement badge grid.
SPRITES += cells("08_achievement_badges.png", "Badges", 0, 272, [
    "badge_first_step", "badge_getting_started", "badge_completions_10", "badge_completions_50",
    "badge_completions_100", "badge_completions_500",
], "center")
SPRITES += cells("08_achievement_badges.png", "Badges", 272, 543, [
    "badge_momentum_3", "badge_momentum_7", "badge_momentum_14", "badge_momentum_30",
    "badge_momentum_60", "badge_momentum_100",
], "center")
SPRITES += cells("08_achievement_badges.png", "Badges", 543, 815, [
    "badge_perfect_day", "badge_perfect_days_5", "badge_perfect_days_25",
    "badge_level_5", "badge_level_10", "badge_level_20",
], "center")
SPRITES += cells("08_achievement_badges.png", "Badges", 815, 1086, [
    "badge_level_30", "badge_level_50", "badge_back_in_motion", "badge_second_wind",
    "badge_fresh_start", "badge_world_thriving",
], "center")

# Effects, seasons, stages, and distant backgrounds.
SPRITES += cells("09_effects_seasons_world_progression.png", "Effects", 0, 230, [
    "effect_sparkle_01", "effect_star", "effect_sparkle_02", "effect_xp_orb", "effect_glow",
    "effect_leaf", "effect_petal", "effect_heart", "effect_confetti", "effect_rays",
    "effect_firefly", "effect_cloud", "effect_bubble",
], "center")
SPRITES += cells("09_effects_seasons_world_progression.png", "Seasonal", 220, 545, [
    "season_spring_tree", "season_summer_tree", "season_fall_tree", "season_winter_tree",
    "season_spring_bush", "season_summer_bush", "season_fall_bush", "season_winter_bush",
])
SPRITES += cells("09_effects_seasons_world_progression.png", "Scenes/Stages", 520, 870, [
    "scene_stage_1", "scene_stage_2", "scene_stage_3", "scene_stage_4", "scene_stage_5",
], "center")
SPRITES += cells("09_effects_seasons_world_progression.png", "Scenes/Backgrounds", 850, 1086, [
    "scene_clouds", "scene_mountains", "scene_forest",
], "center")

# The environment sheets intentionally mix differently sized objects. These
# hand-verified boundaries replace equal-width cells for the sprites used by the
# runtime scene so adjacent art never leaks into an exported asset.
OVERRIDE_BOXES: dict[str, tuple[int, int, int, int]] = {
    "world_tree_sapling": (0, 0, 120, 350),
    "world_tree_young": (105, 0, 255, 350),
    "world_tree_medium": (235, 0, 415, 350),
    "world_tree_large": (405, 0, 650, 355),
    "world_tree_flowering": (650, 0, 865, 355),
    "world_tree_fruit": (845, 0, 1050, 355),
    "world_tree_pine": (1035, 0, 1235, 355),
    "world_tree_autumn": (1215, 0, 1448, 355),
    "world_structure_bench": (200, 0, 420, 350),
    "world_structure_lantern": (420, 0, 610, 350),
    "world_structure_lamp_post": (590, 0, 780, 350),
    "world_structure_fence_wood": (750, 0, 1005, 350),
    "world_structure_fence_stone": (975, 0, 1240, 350),
    "world_structure_gate": (1215, 0, 1448, 350),
    "world_structure_bridge_wood": (0, 325, 310, 625),
    "world_structure_bridge_stone": (285, 325, 610, 625),
    "world_structure_birdhouse": (590, 325, 785, 625),
    "world_structure_garden_bed": (755, 325, 1020, 625),
    "world_structure_well": (995, 325, 1230, 625),
    "world_structure_fire_pit": (1200, 325, 1448, 625),
    "world_structure_gazebo": (0, 0, 310, 390),
    "world_structure_cabin": (285, 0, 610, 390),
    "world_structure_cabin_upgraded": (570, 0, 900, 390),
    "world_structure_windmill": (850, 0, 1175, 390),
    "world_structure_fountain": (1135, 0, 1448, 390),
    "world_structure_lookout": (0, 360, 310, 770),
    "world_structure_observatory": (280, 360, 600, 770),
    "world_structure_pergola": (825, 360, 1175, 770),
    "world_animal_butterfly": (0, 710, 135, 955),
    "world_animal_bee": (145, 710, 245, 955),
    "world_animal_ladybug": (255, 710, 345, 955),
    "world_animal_bird": (365, 710, 495, 955),
    "world_animal_squirrel": (500, 710, 630, 955),
    "world_animal_rabbit": (635, 710, 760, 955),
    "world_animal_duck": (765, 710, 880, 955),
    "world_animal_frog": (890, 710, 1005, 955),
    "world_animal_fox": (1015, 710, 1135, 955),
    "world_animal_owl": (1150, 710, 1275, 955),
    "world_animal_deer": (1280, 710, 1448, 955),
    "scene_stage_1": (0, 510, 265, 880),
    "scene_stage_2": (230, 510, 535, 880),
    "scene_stage_3": (480, 510, 810, 880),
    "scene_stage_4": (740, 510, 1110, 880),
    "scene_stage_5": (1030, 510, 1448, 880),
    "scene_clouds": (0, 835, 430, 1086),
    "scene_mountains": (380, 835, 1010, 1086),
    "scene_forest": (900, 835, 1448, 1086),
}


def group_contents(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)
    contents = path / "Contents.json"
    if not contents.exists():
        contents.write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")


def primary_component_mask(alpha: Image.Image, threshold: int = 4, join_size: int = 1) -> Image.Image:
    """Keep the principal sprite while rejecting fragments from adjacent cells."""
    binary = alpha.point(lambda value: 255 if value > threshold else 0)
    joined = binary if join_size == 1 else binary.filter(ImageFilter.MaxFilter(join_size))
    pixels = np.asarray(joined) > 0
    visited = np.zeros(pixels.shape, dtype=bool)
    best: list[tuple[int, int]] = []
    height, width = pixels.shape

    for y in range(height):
        for x in range(width):
            if not pixels[y, x] or visited[y, x]:
                continue
            queue = deque([(y, x)])
            visited[y, x] = True
            component: list[tuple[int, int]] = []
            while queue:
                py, px = queue.popleft()
                component.append((py, px))
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        ny, nx = py + dy, px + dx
                        if 0 <= ny < height and 0 <= nx < width and pixels[ny, nx] and not visited[ny, nx]:
                            visited[ny, nx] = True
                            queue.append((ny, nx))
            if len(component) > len(best):
                best = component

    selected = np.zeros(pixels.shape, dtype=np.uint8)
    for y, x in best:
        selected[y, x] = 255
    return Image.fromarray(selected, mode="L")


def trim(image: Image.Image, threshold: int = 4, join_size: int = 1) -> Image.Image:
    alpha = image.getchannel("A")
    component = primary_component_mask(alpha, threshold, join_size)
    isolated = image.copy()
    isolated.putalpha(Image.fromarray(
        np.where(np.asarray(component) > 0, np.asarray(alpha), 0).astype(np.uint8),
        mode="L",
    ))
    box = isolated.getchannel("A").getbbox()
    if box is None:
        raise ValueError("Sprite cell contains no visible pixels")
    left, top, right, bottom = box
    pad = max(4, round(max(right - left, bottom - top) * 0.025))
    return isolated.crop((max(0, left - pad), max(0, top - pad), min(image.width, right + pad), min(image.height, bottom + pad)))


def normalized(image: Image.Image, anchor: str, size: tuple[int, int]) -> Image.Image:
    max_width = size[0] - 16
    max_height = size[1] - 16
    scale = min(max_width / image.width, max_height / image.height, 1.0)
    if scale < 1:
        image = image.resize((round(image.width * scale), round(image.height * scale)), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    x = (size[0] - image.width) // 2
    y = size[1] - image.height - 8 if anchor == "bottom" else (size[1] - image.height) // 2
    canvas.alpha_composite(image, (x, y))
    return canvas


def export_sprite(sprite: Sprite, sheets: Path, catalog: Path) -> dict[str, object]:
    source = Image.open(sheets / sprite.sheet).convert("RGBA")
    box = OVERRIDE_BOXES.get(sprite.name, sprite.box)
    join_size = 7 if sprite.group in {"Keeper", "Effects"} else 1
    image = trim(source.crop(box), join_size=join_size)
    if sprite.group == "Keeper":
        image = normalized(image, "bottom", (320, 320))
    elif sprite.group == "HabitIcons":
        image = normalized(image, "center", (256, 256))
    elif sprite.group == "Badges":
        image = normalized(image, "center", (288, 288))
    elif sprite.group == "Effects":
        image = normalized(image, "center", (256, 256))

    group = catalog / "HabitGame" / sprite.group
    parts = group.relative_to(catalog).parts
    cursor = catalog
    for part in parts:
        cursor = cursor / part
        group_contents(cursor)

    image_set = group / f"{sprite.name}.imageset"
    group_contents(image_set)
    filename = f"{sprite.name}.png"
    image.save(image_set / filename, optimize=True)
    (image_set / "Contents.json").write_text(json.dumps({
        "images": [{"filename": filename, "idiom": "universal", "scale": "1x"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": False},
    }, indent=2) + "\n")
    return {
        "name": sprite.name,
        "group": sprite.group,
        "source_sheet": sprite.sheet,
        "source_box": list(box),
        "anchor": sprite.anchor,
        "size": list(image.size),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source_package", type=Path, help="Tenora_Production_Assets_For_Codex directory")
    parser.add_argument("catalog", type=Path, help="Existing Assets.xcassets directory")
    args = parser.parse_args()
    sheets = args.source_package / "ProductionSpriteSheets"
    if not sheets.is_dir():
        raise SystemExit(f"Missing production sheets: {sheets}")
    if not args.catalog.is_dir():
        raise SystemExit(f"Missing asset catalog: {args.catalog}")

    names = [sprite.name for sprite in SPRITES]
    if len(names) != len(set(names)):
        raise SystemExit("Production sprite names must be unique")
    generated_group = args.catalog / "HabitGame"
    if generated_group.exists():
        shutil.rmtree(generated_group)

    manifest = [export_sprite(sprite, sheets, args.catalog) for sprite in SPRITES]
    manifest_path = args.catalog.parent / "HabitGameAssetManifest.json"
    manifest_path.write_text(json.dumps({"version": 1, "assets": manifest}, indent=2) + "\n")
    print(f"Exported {len(manifest)} production assets to {args.catalog / 'HabitGame'}")


if __name__ == "__main__":
    main()
