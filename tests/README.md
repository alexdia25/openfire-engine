# Engine tests

Headless checks of what holds for any game built on the engine: packs and mods layering, `ModLoader`'s base-pack
resolution, standalone projects, level overrides, the game flow and its settings entries, a level running (HUD layer
order, the terrain backdrop, decoration chunks, the dev level switch), the hangar's roster paging, the render-descriptor
vocabulary and the coplanar shift, team recolouring (masked art included), the mod tool's workspace and UI, and the pure
maths (HUD layout, sound levels, the camera swoop). Each builds its content fresh from `fixtures/synthetic_pack.gd`, a
small generated pack with generic ids (`fx.*`, `LEVEL01`): two playable 16 x 16 levels, three vehicles, a team-coloured
sprite pair. So no game's content is ever needed, and no check passes because it knows one game's names.

Run them all with `tools/run_tests.sh` (or one: `tools/run_tests.sh mod_loading`). A single check by hand,
once the harness exists:

```bash
godot --headless --audio-driver Dummy --path .harness --script res://addons/openfire_engine/tests/<name>.gd
```

Each prints `ok`/`FAIL` lines and exits non-zero on failure. Behaviour that needs a playable pack (a full
match, the HUD over a level, the front end end to end) is checked by the games built on the engine, against
their real packs; openfire's `tools/tests/` is the reference set.
