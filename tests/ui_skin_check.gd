# The front end's skin (issue #51, wiki document 122): UiSkin defaults to the Win95 look, a pack's ui/skin.json changes any of its colours and the font size, and the
# front-end screens are drawn from it. Run:
#   godot --headless --path .harness --script res://addons/openfire_engine/tests/ui_skin_check.gd
extends SceneTree

const Fixture := preload("fixtures/synthetic_pack.gd")

var _failures := 0


func _check(ok: bool, what: String) -> void:
	print("%s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failures += 1


func _init() -> void:
	var d := UiSkin.new()
	_check(d.style == "plain" and d.theme() == null, "the engine's default skin is plain: no theme of its own")
	_check(d.face == Color("c0c0c0") and d.caption_a == Color("000080") and d.font_size == 14, "and its colours default to the Win95 system colours, for a pack that asks for the bevel style")
	var s := UiSkin.from_dict({"style": "bevel", "face": "#202830", "caption_a": "#ff0000", "font_size": 20})
	_check(s.face == Color("202830") and s.caption_a == Color("ff0000") and s.font_size == 20 and s.shadow == d.shadow, "a skin file changes the keys it names and keeps the other defaults")
	_check(s.theme().default_font_size == 20, "the theme takes the font size")
	var w := s.window("Test")
	_check(w["root"] is PanelContainer and w["body"] is VBoxContainer, "a bevel window has a frame and a body")
	w["root"].free()
	var pw := d.window("Plain")
	_check(pw["root"] == pw["body"], "a plain window is just a titled column")
	pw["root"].free()
	var base := Fixture.build("user://packs")
	PackWriter.write_json(base.path_join("ui/skin.json"), {"face": "#102030"})
	var pack := Pack.new()
	pack.load_from(base)
	_check(UiSkin.from_dict(pack.ui_skin).face == Color("102030"), "Pack.ui_skin is the pack's ui/skin.json")
	var screen := PlaceholderScreen.new()
	screen.skin = s
	get_root().add_child(screen)
	screen.setup("Menu", "", [["Go", func(): pass]])
	_check(screen.find_children("*", "Button", true, false).size() == 1, "a front-end screen draws its buttons from the skin")
	print("ui_skin_check: %d failures" % _failures)
	quit(_failures)
