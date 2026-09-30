class_name WinRibbon
extends Control
## The end-of-match victory ribbon (document 92): after the winning capture the original fades the game to black (FUN_004225d0 starts a 1000 ms fade, the handler
## 0x4222a0 waits for it), then shows the winner's ribbon bitmap over the cleared screen (FUN_00430b10 draws TITLE\Ban{B,G}{L,H}.bmp with FUN_004306b0: the winner
## picks tan or green, the display mode low or high resolution) while a victory jingle plays (TITLE\Win*.stm, decoded by tools/extract_win_jingles.py, document 101: the
## level's LEVL picks one of four by the byte table at 0x44e120), and fades it out over 500 ms when the jingle ends; the handler then returns to the front end.
## Traced: the fade to black (1000 ms), the ribbon choice, its placement (centred, top edge at y 180 of a 240-high low-res screen, doubled in high-res), the jingle's choice
## and that the ribbon is held until it ends, the 500 ms fade-out.
## PORT CHOICES / UNTRACED: the port has no front end, so `sequence_done` (after the fade-out) only shows the restart hint; the 500 ms fade-in of the ribbon is the port's (the
## original's own bitmap appears at once, entry+0xc = 0 in the step table); the black background is inferred (the sequence has no scene draw between the fade and the bitmap);
## the high-resolution bitmap is drawn at 1.5x so it is 540 wide, the size the low-res one would have at the port's 3x scale.
## The jingle's 0 dB volume is CONFIRMED, not a guess (document 101, addendum): the original does tie the stream's volume to a shared fade variable, but that variable is
## already at full by the time the jingle ever starts and doesn't move again until after it has stopped, so it is never actually heard attenuated.
## The jingle now starts the instant the ribbon phase begins (document 101, addendum: FUN_00430b10's frame 0 opens and starts the stream the same frame it draws the bitmap,
## with no delay between the two, whatever fade-in the port draws the bitmap with) -- it had waited for the port's own invented fade-in to finish first, which nothing traced asked for.
## The video backdrop (issue #60) is now real: CinepakDecoder decodes the same .cvid Cinepak stream
## tools/extract_win_jingles.py already extracts alongside the audio, played full-screen behind the ribbon
## via StmVideo, in sync with the jingle's own AudioStreamPlayer position. Confirmed pixel-for-pixel against
## ffmpeg's own Cinepak decoder on all four tiers (document 101's addendum). Whether it is *exactly*
## full-screen, or some other placement, is still a port choice -- nothing traced pins down the video's own
## on-screen rect (see document 101's addendum on the still-unconfirmed decompression target).

const FADE_OUT_S := 1.0        ## FUN_0042fdd0(0, 1000)
const RIBBON_FADE_IN_S := 0.5  ## port choice
const RIBBON_FADE_OUT_S := 0.5 ## FUN_00430b10: the fade after the jingle, the sequence entry's +0x10 = 500 ms
const TOP_FRACTION := 180.0 / 240.0
const SCALE_HIGH := 1.5

signal sequence_done   ## the jingle has ended and the ribbon has faded out (the original returns to the front end here)

var _black: ColorRect
var _player: AudioStreamPlayer
var _jingle: AudioStream
var _jingle_started := false
var _out_t := -1.0             ## seconds since the jingle ended, -1 while it plays
var _done := false
var _ribbon: TextureRect
var _t := -1.0
var _tex: Texture2D
var _video: TextureRect
var _stm: StmVideo


func setup(pack: Pack) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_black = ColorRect.new()
	_black.color = Color(0, 0, 0, 0)
	_black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_black)
	_black.set_anchors_preset(Control.PRESET_FULL_RECT)
	_video = TextureRect.new()
	_video.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video.stretch_mode = TextureRect.STRETCH_SCALE
	_video.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_video.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_video)
	_ribbon = TextureRect.new()
	_ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ribbon.stretch_mode = TextureRect.STRETCH_SCALE
	_ribbon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_ribbon.modulate.a = 0.0
	add_child(_ribbon)
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_jingle_finished)
	_pack = pack


var _pack: Pack


## The ribbon file of `winner_idx` (0 tan, 1 green), read from the pack's hud folder (tools/extract_win_banners.py); null when the pack has none.
func _load(winner_idx: int) -> Texture2D:
	var name := "win_banner_%s_high.png" % ("tan" if winner_idx == 0 else "green")
	for i in range(_pack.layers.size() - 1, -1, -1):
		var path := "%s/hud/%s" % [_pack.layers[i], name]
		if FileAccess.file_exists(path):
			var img := Image.load_from_file(path)
			if img != null:
				return ImageTexture.create_from_image(img)
	return null


## The victory jingle for a level's LEVL (FUN_00430620: the tier byte table, clamped to tier 3; music/jingles.json from tools/extract_win_jingles.py), or null.
## Also stashes the matching tier's own dict and directory in `_video_tier`/`_video_dir` so `start()` can load its video (issue #60), if the pack has one.
var _video_tier: Dictionary
var _video_dir := ""


func _load_jingle(levl: int) -> AudioStream:
	_video_tier = {}
	_video_dir = ""
	for i in range(_pack.layers.size() - 1, -1, -1):
		var dir := "%s/music" % _pack.layers[i]
		var path := "%s/jingles.json" % dir
		if not FileAccess.file_exists(path):
			continue
		var doc = JSON.parse_string(FileAccess.get_file_as_string(path))
		if not doc is Dictionary:
			continue
		var by_levl: Array = doc.get("tier_by_levl", [])
		var tiers: Array = doc.get("tiers", [])
		if by_levl.is_empty() or tiers.is_empty():
			continue
		var tier_idx := mini(int(by_levl[clampi(levl, 0, by_levl.size() - 1)]), tiers.size() - 1)
		var tier: Dictionary = tiers[tier_idx]
		var file := "%s/%s" % [dir, String(tier["file"])]
		if FileAccess.file_exists(file):
			_video_tier = tier
			_video_dir = _pack.layers[i]
			return AudioStreamOggVorbis.load_from_file(file)
	return null


## True when the ribbon is followed by a jingle, so `sequence_done` will come.
func has_jingle() -> bool:
	return _jingle != null


## True when a ribbon will be shown (the caller keeps its own text otherwise). `levl` is the level's LEVL, which picks the jingle.
func start(winner_idx: int, levl: int = 0) -> bool:
	_tex = _load(winner_idx)
	if _tex == null:
		return false
	_jingle = _load_jingle(levl)
	_jingle_started = false
	_out_t = -1.0
	_done = false
	_ribbon.texture = _tex
	_ribbon.size = Vector2(_tex.get_size()) * SCALE_HIGH
	_video.texture = null
	_stm = null
	if not _video_tier.is_empty():
		var stm := StmVideo.new()
		if stm.load_tier(_video_dir, _video_tier):
			_stm = stm
	_t = 0.0
	visible = true
	return true


func _process(delta: float) -> void:
	if _t < 0.0:
		return
	_t += delta
	_black.color.a = clampf(_t / FADE_OUT_S, 0.0, 1.0)
	var fade_in := clampf((_t - FADE_OUT_S) / RIBBON_FADE_IN_S, 0.0, 1.0)
	if _jingle != null and not _jingle_started and _t >= FADE_OUT_S:
		_jingle_started = true   # the ribbon sequence (FUN_00430b10) starts the stream the same frame it draws the bitmap
		_player.stream = _jingle
		_player.play()
		if OS.get_environment("RF_DEBUG_MUSIC") == "1":
			print("[win] jingle started, %.1f s" % _jingle.get_length())
	if _stm != null and _jingle_started and _player.playing:
		var tex := _stm.advance(_player.get_playback_position())
		if tex != null:
			_video.texture = tex
	if _out_t >= 0.0:
		_out_t += delta
		fade_in = 1.0 - clampf(_out_t / RIBBON_FADE_OUT_S, 0.0, 1.0)
		if _out_t >= RIBBON_FADE_OUT_S and not _done:
			_done = true
			if OS.get_environment("RF_DEBUG_MUSIC") == "1":
				print("[win] sequence done")
			sequence_done.emit()
	_ribbon.modulate.a = fade_in
	var vp := get_viewport_rect().size
	size = vp   # a Control under a CanvasLayer is not laid out by anchors (placeholder_hud.gd sizes its fade the same way)
	_black.size = vp
	_video.size = vp
	_ribbon.position = Vector2((vp.x - _ribbon.size.x) * 0.5, vp.y * TOP_FRACTION)


## The jingle has ended (FUN_00436520 reports the stream no longer playing): the ribbon fades out.
func _on_jingle_finished() -> void:
	if _out_t < 0.0:
		_out_t = 0.0
