class_name HudLayout
extends RefCounted
## The two arrangements of the player's panel (document 96), chosen by GameSettings.hud_layout:
##  - "classic" is the original's one-player screen: a 320 x 240 picture whose top 152 rows are the game view (FUN_00409420: the view is 0x140 x 0x98) and whose bottom 88 rows
##    are the backdrop strip (ART\1PBSCRL.RFA: camouflage, a rail, the frame), with the vehicle's panel at (87, 168) (FUN_00412ad0: 0x570000, 0xa80000) and its frame cel
##    1940 at (-3, -2) from that. The picture is scaled to the window (the largest 4:3 area that fits, centred) and everything outside it is black.
##  - "modern" is the port's own arrangement: the game view fills the window and the panel sits at its bottom left, 3 window pixels per original pixel.
## The scale and the picture's placement in the window are the port's (the original was drawn to a 320 x 240 or 640 x 480 screen).
## The original has a second layout for another screen size (DAT_0048c7dc != 0: a 357 x 169 view and the panel at (116, 185)); the mode that selects it is untraced.

const CLASSIC := "classic"
const MODERN := "modern"

const SCREEN := Vector2(320.0, 240.0)
const VIEW_SIZE := Vector2(320.0, 152.0)
const STRIP_TOP := 152.0
const PANEL_POS := Vector2(87.0, 168.0)
const FRAME_OFFSET := Vector2(-3.0, -2.0)
const MODERN_SCALE := 3.0
const MODERN_MARGIN := Vector2(12.0, 198.0)   ## the panel's top left from the window's left edge and bottom edge


static func is_classic() -> bool:
	return GameSettings.hud_layout == CLASSIC


## Window pixels per original pixel in the classic layout: the largest 4:3 picture that fits.
static func classic_scale(viewport: Vector2) -> float:
	return minf(viewport.x / SCREEN.x, viewport.y / SCREEN.y)


## The 320 x 240 picture's rectangle in the window (classic).
static func picture_rect(viewport: Vector2) -> Rect2:
	var k := classic_scale(viewport)
	var size := SCREEN * k
	return Rect2((viewport - size) * 0.5, size)


## The game view's rectangle in the window: the top 320 x 152 of the picture (classic), the whole window (modern).
static func view_rect(viewport: Vector2) -> Rect2:
	if not is_classic():
		return Rect2(Vector2.ZERO, viewport)
	var p := picture_rect(viewport)
	return Rect2(p.position, VIEW_SIZE * classic_scale(viewport))


static func panel_scale(viewport: Vector2) -> float:
	return classic_scale(viewport) if is_classic() else MODERN_SCALE


## Where the vehicle panel's top left goes in the window.
static func panel_position(viewport: Vector2) -> Vector2:
	if is_classic():
		return picture_rect(viewport).position + PANEL_POS * classic_scale(viewport)
	return Vector2(MODERN_MARGIN.x, viewport.y - MODERN_MARGIN.y)


## A pack image (hud/<name>) from the top layer that has it, or null.
static func load_pack_image(pack: Pack, name: String) -> Texture2D:
	for i in range(pack.layers.size() - 1, -1, -1):
		var path := "%s/hud/%s" % [pack.layers[i], name]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null:
				return ImageTexture.create_from_image(img)
	return null
