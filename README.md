# openfire-engine

A data-driven Godot 4 engine for top-down vehicle combat games: content **packs**, **mods** layered over
them, the front-end **game flow**, the match simulation and its renderers, and a **mod tool** for editing
packs. It was extracted from [openfire](https://github.com/alexdia25/openfire), a reimplementation of
*Return Fire* (1996), and it knows no particular game. A game is a pack plus a few project settings.
This repo holds no game's content and no code specific to one game.

## How the pieces fit

```mermaid
flowchart TB
    subgraph engine["openfire-engine (this repo, public)"]
        direction LR
        G["game/<br/>runtime: Pack, ModLoader, GameFlow,<br/>Vehicle, MatchController, renderers"]
        E["editor/<br/>the mod tool: ModWorkspace, PackWriter"]
        T["tests/<br/>engine checks on a synthetic pack"]
    end

    subgraph openfire["openfire (public): Return Fire"]
        OF_ADDON["addons/openfire_engine/<br/>(submodule)"]
        OF_RF["tools/ (Python RE pipeline)<br/>importer/ (first-run import)<br/>packs/registry, docs, wiki"]
    end

    subgraph newgame["the new game (private)"]
        NG_ADDON["addons/openfire_engine/<br/>(submodule)"]
        NG_OWN["packs/its_id/ (its own content)<br/>its own scenes and code"]
    end

    engine -- "git submodule" --> OF_ADDON
    engine -- "git submodule" --> NG_ADDON
```

Every game mounts this repo at the same place, **`res://addons/openfire_engine/`**, as a git
submodule. The engine's own paths depend on that location, the same way most Godot addons do. Nothing
flows back the other way: a game never edits files inside its submodule checkout (see
[Changing the engine](#changing-the-engine)).

## What a game tells the engine

The engine reads a few optional `ProjectSettings` keys (`game/engine_config.gd`). The game sets them
in its own `project.godot`:

| Setting | Meaning | Return Fire (`openfire`) | A bundled new game |
|---|---|---|---|
| `openfire/packs/base_pack` | the pack the game runs on | `res://packs/original_pc` in dev; `user://packs/original_pc` in the "Open Fire" export, where the pack is imported on first run | `res://packs/<id>` |
| `openfire/editor/asset_registry` | optional JSON notes the mod tool shows beside sprite ids | `res://packs/registry/asset_ids.json` | usually unset |

A setting can vary per export through Godot's feature-tag overrides, for example
`packs/base_pack.openfire_import="user://packs/original_pc"`. With nothing set, the game runs as an empty
project, which is where a brand-new game starts.

```mermaid
flowchart LR
    S["project.godot<br/>openfire/packs/base_pack"] --> BP["ModLoader.base_pack_dir()"]
    ENV["RF_PACK=dir<br/>(one run: tests, the mod tool's Play)"] -.overrides.-> LGP
    BP --> LGP["ModLoader.load_game_pack()"]
    MODS["GameSettings.enabled_mods<br/>(user://settings.cfg)"] --> LGP
    LGP --> STACK["Pack.load_stack()<br/>base, then each mod, later wins per id"]
    STACK --> FLOW["GameFlow<br/>title, menu, level select, level"]
    STACK --> TOOL["mod tool (ModWorkspace)<br/>edits one mod layer only"]
```

A mod's `pack.json` names its base by **id** (`"base_pack": "original_pc"`). That id is resolved next to
the mod first, then under `res://packs`, then under `user://packs` (`EngineConfig.PACK_SEARCH_ROOTS`).
So a mod works the same whether its base is bundled with the game or was generated on the player's
machine. A pack with no `base_pack` at all is a **standalone project**: a whole game made in the mod tool,
with nothing underneath it.

## Using it in a game

The full walk-through, from an empty repo to an export with the pack inside, is
[`docs/STARTING_A_GAME.md`](docs/STARTING_A_GAME.md). In short:

```bash
git submodule add https://github.com/alexdia25/openfire-engine.git addons/openfire_engine
```

Then, in the game's `project.godot`:

```ini
[application]
run/main_scene="res://addons/openfire_engine/game/game_flow.tscn"   ; or your own boot scene that changes to it

[openfire]
packs/base_pack="res://packs/my_game"
```

Enabling the plugin (Project Settings > Plugins > Open Fire Engine) is optional. It only lists the
settings above in the Project Settings dialog; the classes and scenes work without it. The mod tool is
`res://addons/openfire_engine/editor/editor_main.tscn`.

The pack format (`pack.json`, `sprites/`, `vehicles/`, `levels/`, `audio/`, ...) is the one `Pack`
(`game/pack.gd`) reads and `PackWriter` (`editor/pack_writer.gd`) writes. See
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the runtime's internals.

## Changing the engine

Anything a game needs falls into one of three tiers:

1. **It can be pack data** using the engine's existing vocabulary: no engine change, nothing to sync.
2. **It generalises** into something the engine should support natively: a normal PR to this repo, and
   every game picks it up when it bumps its submodule.
3. **It is one-off** for one game: it stays entirely in that game's repo, composing or extending engine
   classes, and is never edited inside the submodule checkout.

The rule that keeps the engine reusable is that it **names no game**. A file name, sprite id, level id
or format that only one game has belongs in that game's repo. Return Fire's binary-format parsers
(`ART.CAR`, `.RFM`, `.SDT`) and its first-run importer stay in `openfire`. They reuse the engine's
`PackWriter` to write their output and add nothing here. Comments that cite "document NN" refer to
the [openfire wiki](https://github.com/alexdia25/openfire/wiki)'s worked examples. Those pages are where
most of this engine's behaviour was traced from, and they stay there as its history.

### Developing the engine from a game checkout

A tier-2 change is usually driven by a game, and the quickest place to develop it is inside that game,
against its real content. The submodule at `addons/openfire_engine/` is a complete clone of this repo,
and Godot runs whatever is on disk, so engine edits there take effect straight away with nothing
committed:

```mermaid
flowchart LR
    A["switch the submodule<br/>to a branch"] --> B["edit engine + game files<br/>in the one project"]
    B --> C["run the game, its checks,<br/>and the engine's checks"]
    C -- "not yet" --> B
    C -- "ready" --> D["commit + push<br/>the engine"]
    D --> E["commit the game change<br/>with the new submodule pointer,<br/>push"]
```

1. **Put the submodule on a branch.** It starts as a detached HEAD at the game's pinned commit:
   `git -C addons/openfire_engine switch main` (or `switch -c <topic>` for a longer change).
2. **Edit and test freely.** Change engine files under `addons/openfire_engine/` and game files in the
   same project. Run the game, the game's checks, and the engine's own checks
   (`addons/openfire_engine/tools/run_tests.sh`), all against the uncommitted engine. The game's
   `git status` shows the engine as `modified content` until then. That's expected.
3. **Commit once it works, engine first.** Commit and push from inside `addons/openfire_engine`. Then,
   in the game, commit the game-side change together with the new submodule pointer, and push.

The order in step 3 matters: a game commit that points at an engine commit nobody else can fetch breaks
every other clone. Setting `git config push.recurseSubmodules check` in the game repo makes git refuse
that push.

Keep unfinished engine edits out of any checkout other people or sessions run the game from. A
`git worktree` of the game gets its own copy of the submodule (`git submodule update --init` in the
new worktree), so changes there stay separate until they're pushed. Tier-3 code, the game's own one-offs,
still never goes in the submodule.

## Tests

```bash
GODOT=/path/to/Godot_v4.7 tools/run_tests.sh
```

This runs every check in `tests/` headless against a small synthetic pack that
`tests/fixtures/synthetic_pack.gd` writes fresh each run, so the engine is tested with no game present.
The script creates a bare harness project in `.harness/` that mounts this checkout as an addon. Remove it
with `tools/run_tests.sh --clean`, not `rm -rf`: on Windows the mount is a junction. Each game built on
the engine also runs its own checks against its real pack, and those cover what needs a playable pack
(a full match, the HUD, the front end).
