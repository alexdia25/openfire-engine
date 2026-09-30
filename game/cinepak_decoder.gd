class_name CinepakDecoder
extends RefCounted
## A real-time Cinepak decoder (issue #60): the win-screen video backdrop's `.stm` files carry a genuine
## Cinepak video track that the original decodes and displays live (confirmed by a real ICSendMessage
## decompress-call chain in RFIRE.BIN, not a discard -- see wiki document 101's addendum). Cinepak itself is a
## public, generic codec unrelated to Return Fire's own code, so this is written from the format, not from
## RFIRE.BIN, and cross-checked pixel-for-pixel against ffmpeg's own Cinepak decoder on all four extracted
## Win*.stm elementary streams (tools/extract_win_jingles.py's *.cvid output) -- every one of the 1865 real
## frames across all four tiers decodes to an EXACT byte-for-byte match.
##
## Format (from the codec's own public spec, not reverse engineered): a frame is a 10-byte header
## (flags:u8, size:u24be [includes this header], width:u16be, height:u16be, numStrips:u16be) followed by
## that many strips. A strip is a 12-byte header (id:u8 [0x10 intra/0x11 inter -- informational only, not
## used to decode], pad:u8, size:u24be [includes this header], y1/x1/y2/x2:u16be each -- y1==0 means
## "y1/y2 are relative to the previous strip's bottom, y2 is a height"; nonzero y1 means both are absolute)
## then a sequence of chunks. A chunk is a 4-byte header (id:u8, size:u24be [includes this header]) then
## `size - 4` bytes of payload. Chunk ids (bit0 = masked/partial update, bit1 = force-V1/no per-block
## mode bit, bit2 = 4-byte mono entries instead of 6-byte color -- never seen in these files):
##   0x20/0x21/0x24/0x25 -> update the V4 codebook (0x21/0x25 = masked)
##   0x22/0x23/0x26/0x27 -> update the V1 codebook (0x23/0x27 = masked)
##   0x30/0x31/0x32       -> the strip's vector data (0x31 = masked/inter, adds a per-block skip flag;
##                            0x32 = force-V1, no per-block mode flag at all)
## A codebook update walks all 256 slots in order; for a masked update a shared 32-bit-at-a-time,
## MSB-first flag word (refilled from the data whenever exhausted) says per slot whether a fresh 6-byte
## entry follows or the existing slot is left untouched -- so codebooks are NOT reset per chunk: a strip's
## codebooks persist across frames, and (unless the frame's own flags byte has bit0 set) each strip after
## the first starts as a COPY of the previous strip's codebooks in the same frame, before its own chunks
## are applied.
## A 6-byte codebook entry is Y0,Y1,Y2,Y3,U,V (U,V SIGNED bytes). Vector data walks the strip in 4x4-pixel
## blocks, left to right then top to bottom. A masked (0x31) chunk spends one flag bit per block on a skip
## flag (0 = leave this block as whatever was already there, i.e. copy-from-previous-frame); the same
## shared flag word then spends one more bit (unless force-V1) choosing V1 (0) or V4 (1) for the block.
## V1 reads one V1-codebook index and paints its four Y values as four SOLID 2x2 quadrants of the 4x4
## block (Y0 top-left, Y1 top-right, Y2 bottom-left, Y3 bottom-right); V4 reads four V4-codebook indices,
## one per 2x2 quadrant in the same TL/TR/BL/BR order, each applying its own 4 Y values as a real 2x2
## pattern within its quadrant (Y0/Y1/Y2/Y3 = that quadrant's own top-left/top-right/bottom-left/bottom-right
## pixel). The colour conversion (also from the codec's own spec, not a generic YUV formula):
## r = Y + 2V, g = Y - U/2 - V, b = Y + 2U (each clipped to 0-255; the U/2 term truncates toward zero).


class Strip:
	var v1_codebook: Array  ## 256 x (PackedByteArray of 6 or null)
	var v4_codebook: Array

	func _init() -> void:
		v1_codebook.resize(256)
		v4_codebook.resize(256)


var _strips: Array[Strip] = []  ## persists across frames, indexed by strip position within a frame


## Decodes one frame's raw bytes (a single element of a pack's `<tier>.cvid` frame-index) into `pixels`,
## a PackedByteArray of `width * height * 3` RGB8 bytes, updated in place (unwritten/skipped pixels keep
## whatever was already there, i.e. the previous frame's content -- callers must supply the same buffer
## across consecutive frames for inter-frame skip blocks to work, and a zero-filled buffer for the first).
func decode_frame(raw: PackedByteArray, pixels: PackedByteArray, width: int, height: int) -> void:
	var frame_flags := raw[0]
	var num_strips := (raw[8] << 8) | raw[9]
	var pos := 10
	var y0 := 0
	for i in num_strips:
		var sid := raw[pos]
		var ssize := _u24(raw, pos + 1) - 12
		var sy1 := _u16(raw, pos + 4)
		var sx1 := _u16(raw, pos + 6)
		var raw_y2 := _u16(raw, pos + 8)
		var sx2 := _u16(raw, pos + 10)
		var sy2: int
		if sy1 == 0:
			sy1 = y0
			sy2 = y0 + raw_y2
		else:
			sy2 = raw_y2
		var strip_h := sy2 - sy1
		var strip_w := sx2 - sx1

		while _strips.size() <= i:
			_strips.append(Strip.new())
		var st: Strip = _strips[i]
		if i > 0 and (frame_flags & 0x01) == 0:
			var prev: Strip = _strips[i - 1]
			st.v1_codebook = prev.v1_codebook.duplicate()
			st.v4_codebook = prev.v4_codebook.duplicate()

		var cpos := pos + 12
		var cend := pos + 12 + ssize
		var vec_start := -1
		var vec_len := 0
		var vec_id := 0
		while cpos < cend:
			var cid := raw[cpos]
			var clen := _u24(raw, cpos + 1) - 4
			if cid == 0x20 or cid == 0x21 or cid == 0x24 or cid == 0x25:
				_parse_codebook(st.v4_codebook, raw, cpos + 4, clen, (cid & 0x01) != 0)
			elif cid == 0x22 or cid == 0x23 or cid == 0x26 or cid == 0x27:
				_parse_codebook(st.v1_codebook, raw, cpos + 4, clen, (cid & 0x01) != 0)
			elif cid == 0x30 or cid == 0x31 or cid == 0x32:
				vec_start = cpos + 4
				vec_len = clen
				vec_id = cid
			cpos += 4 + clen

		if vec_start >= 0:
			_decode_vectors(raw, vec_start, vec_len, vec_id, st, pixels, width, height, sx1, sy1, strip_w, strip_h)
		y0 = sy2
		pos += 12 + ssize


func _u16(b: PackedByteArray, o: int) -> int:
	return (b[o] << 8) | b[o + 1]


func _u24(b: PackedByteArray, o: int) -> int:
	return (b[o] << 16) | (b[o + 1] << 8) | b[o + 2]


func _parse_codebook(cb: Array, raw: PackedByteArray, start: int, length: int, masked: bool) -> void:
	var p := start
	var endp := start + length
	if not masked:
		for i in 256:
			if p + 6 > endp:
				return
			cb[i] = raw.slice(p, p + 6)
			p += 6
		return
	var idx := 0
	var mask := 0
	var flag := 0
	while idx < 256:
		if mask == 0:
			if p + 4 > endp:
				return
			flag = (raw[p] << 24) | (raw[p + 1] << 16) | (raw[p + 2] << 8) | raw[p + 3]
			p += 4
			mask = 0x80000000
		if (flag & mask) != 0:
			if p + 6 > endp:
				return
			cb[idx] = raw.slice(p, p + 6)
			p += 6
		mask = mask >> 1
		idx += 1


func _decode_vectors(raw: PackedByteArray, start: int, length: int, vec_id: int, st: Strip,
		pixels: PackedByteArray, width: int, height: int, sx1: int, sy1: int, strip_w: int, strip_h: int) -> void:
	var bpos := start
	var endp := start + length
	var flag := 0
	var mask := 0
	var masked_skip := (vec_id & 0x01) != 0
	var force_v1 := (vec_id & 0x02) != 0

	var by := 0
	while by < strip_h:
		var bx := 0
		while bx < strip_w:
			var abx := sx1 + bx
			var aby := sy1 + by
			if masked_skip:
				if mask == 0:
					flag = (raw[bpos] << 24) | (raw[bpos + 1] << 16) | (raw[bpos + 2] << 8) | raw[bpos + 3]
					bpos += 4
					mask = 0x80000000
				var skip_bit := flag & mask
				mask = mask >> 1
				if skip_bit == 0:
					bx += 4
					continue
			var use_v4 := false
			if not force_v1:
				if mask == 0:
					flag = (raw[bpos] << 24) | (raw[bpos + 1] << 16) | (raw[bpos + 2] << 8) | raw[bpos + 3]
					bpos += 4
					mask = 0x80000000
				use_v4 = (flag & mask) != 0
				mask = mask >> 1
			if use_v4:
				for q in 4:
					var qx := (q % 2) * 2
					var qy := (q / 2) * 2
					var idx: int = raw[bpos]
					bpos += 1
					var e: PackedByteArray = st.v4_codebook[idx]
					if e:
						_paint_quad(pixels, width, height, abx + qx, aby + qy, e, true)
			else:
				var idx: int = raw[bpos]
				bpos += 1
				var e: PackedByteArray = st.v1_codebook[idx]
				if e:
					_paint_quad(pixels, width, height, abx, aby, e, false)
			bx += 4
		by += 4


## `solid_2x2`=false (V1): each of e's 4 Y values solidly fills its own 2x2 quadrant of a 4x4 block starting
## at (bx,by). `solid_2x2`=true (V4): e is ONE quadrant's own vector, applied as a real 2x2 pattern at (bx,by).
func _paint_quad(pixels: PackedByteArray, width: int, height: int, bx: int, by: int, e: PackedByteArray, solid_2x2: bool) -> void:
	var u: int = e[4]
	var v: int = e[5]
	if u >= 128:
		u -= 256
	if v >= 128:
		v -= 256
	var half_u := (-((-u) / 2)) if u < 0 else u / 2
	if solid_2x2:
		# e[0..3] = TL,TR,BL,BR pixel of a real 2x2 pattern at (bx,by)
		for i in 4:
			var px := bx + (i % 2)
			var py := by + (i / 2)
			if px < width and py < height:
				_put(pixels, width, px, py, e[i], u, v, half_u)
	else:
		# e[0..3] = TL,TR,BL,BR quadrant, each filled solidly across its own 2x2 area
		for i in 4:
			var qx := bx + (i % 2) * 2
			var qy := by + (i / 2) * 2
			var yy: int = e[i]
			for dx in 2:
				for dy in 2:
					var px := qx + dx
					var py := qy + dy
					if px < width and py < height:
						_put(pixels, width, px, py, yy, u, v, half_u)


func _put(pixels: PackedByteArray, width: int, px: int, py: int, y: int, u: int, v: int, half_u: int) -> void:
	var o := (py * width + px) * 3
	pixels[o] = clampi(y + v * 2, 0, 255)
	pixels[o + 1] = clampi(y - half_u - v, 0, 255)
	pixels[o + 2] = clampi(y + u * 2, 0, 255)
