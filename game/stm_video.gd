class_name StmVideo
extends RefCounted
## Plays back a pack's extracted `.cvid` Cinepak elementary stream (tools/extract_win_jingles.py, issue #60)
## in sync with the matching jingle's own audio playback position, decoding one frame at a time with
## CinepakDecoder. The real chunk count is usually a little below the file's own nominal frame rate/count
## (document 101's addendum), so frames are spread evenly across the audio's own known duration rather than
## assumed to run at a fixed fps.

var width := 320
var height := 240
var _decoder: CinepakDecoder
var _offsets: PackedInt32Array
var _cvid: PackedByteArray
var _pixels: PackedByteArray
var _image: Image
var _texture: ImageTexture
var _shown_frame := -1
var _seconds := 0.0


## `tier`: one entry of a pack's music/jingles.json "tiers" array (the same dictionary win_ribbon.gd already
## reads to pick the jingle). Returns false if the pack has no video for this tier (an older pack, or a
## pack built without RF_ISO set).
func load_tier(pack_dir: String, tier: Dictionary) -> bool:
	if not tier.has("video_file"):
		return false
	var path := "%s/music/%s" % [pack_dir, String(tier["video_file"])]
	if not FileAccess.file_exists(path):
		return false
	_cvid = FileAccess.get_file_as_bytes(path)
	width = int(tier.get("video_width", 320))
	height = int(tier.get("video_height", 240))
	_seconds = float(tier.get("seconds", 0.0))
	var lengths: Array = tier["video_frame_lengths"]
	_offsets = PackedInt32Array()
	_offsets.resize(lengths.size() + 1)
	_offsets[0] = 0
	for i in lengths.size():
		_offsets[i + 1] = _offsets[i] + int(lengths[i])
	_decoder = CinepakDecoder.new()
	_pixels = PackedByteArray()
	_pixels.resize(width * height * 3)
	_image = Image.create_from_data(width, height, false, Image.FORMAT_RGB8, _pixels)
	_texture = ImageTexture.create_from_image(_image)
	_shown_frame = -1
	return true


func frame_count() -> int:
	return maxi(_offsets.size() - 1, 0)


## Decodes and shows every frame up to (and including) the one due at `playback_pos_sec` of the jingle's
## own playback, frames spread evenly across the tier's known audio duration. Returns the current texture
## (null if no tier is loaded). Decoding is cheap enough to run inline (~19 ms/frame measured on the
## longest tier against a 66 ms/frame budget at 15 fps -- tools/tests/cinepak_decoder_check.gd's own timing
## check), so catching up several frames in one call (e.g. after a hitch) is fine.
func advance(playback_pos_sec: float) -> Texture2D:
	if _decoder == null or frame_count() == 0:
		return null
	var target := 0
	if _seconds > 0.0:
		target = clampi(int(playback_pos_sec / _seconds * frame_count()), 0, frame_count() - 1)
	while _shown_frame < target:
		_shown_frame += 1
		var raw := _cvid.slice(_offsets[_shown_frame], _offsets[_shown_frame + 1])
		_decoder.decode_frame(raw, _pixels, width, height)
	_image.set_data(width, height, false, Image.FORMAT_RGB8, _pixels)
	_texture.update(_image)
	return _texture
