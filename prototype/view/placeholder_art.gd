class_name PlaceholderArt
extends RefCounted
## Procedurally drawn placeholder sprites (texels at 32 per tile). Replaced by real art later.

const SKIN := Color(0.93, 0.74, 0.58)
const DARK := Color(0.16, 0.12, 0.1)
const LEG := Color(0.3, 0.24, 0.2)
const WOOD := Color(0.5, 0.33, 0.18)
const METAL := Color(0.78, 0.8, 0.84)

static var _cache := {}


static func texture(def_id: String) -> ImageTexture:
	if not _cache.has(def_id):
		_cache[def_id] = ImageTexture.create_from_image(_draw(def_id))
	return _cache[def_id]


static func _draw(def_id: String) -> Image:
	match def_id:
		"hero":
			return _humanoid(18, 26, Color(0.22, 0.4, 0.72), Color(0.86, 0.68, 0.22), "shield_spear")
		"atalanta":
			return _humanoid(18, 26, Color(0.3, 0.55, 0.3), Color(0.55, 0.36, 0.2), "bow")
		"heracles":
			return _humanoid(22, 30, Color(0.62, 0.42, 0.22), Color(0.85, 0.66, 0.3), "club")
		"bandit":
			return _humanoid(18, 26, Color(0.66, 0.2, 0.18), Color(0.4, 0.3, 0.25), "sword")
		"bandit_archer":
			return _humanoid(18, 26, Color(0.5, 0.18, 0.22), Color(0.4, 0.3, 0.25), "bow")
		"bandit_chief":
			return _humanoid(20, 28, Color(0.72, 0.16, 0.14), Color(0.6, 0.6, 0.62), "shield_spear")
		"wolf":
			return _beast(24, 16, Color(0.52, 0.52, 0.55), Color(0.38, 0.38, 0.42), false)
		"boar":
			return _beast(52, 32, Color(0.42, 0.28, 0.2), Color(0.3, 0.2, 0.14), true)
		"lion":
			return _beast(58, 38, Color(0.86, 0.66, 0.3), Color(0.6, 0.36, 0.14), false)
	return _humanoid(18, 26, Color(0.6, 0.6, 0.6), Color(0.4, 0.4, 0.4), "")


static func _humanoid(w: int, h: int, torso: Color, accent: Color, kit: String) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var cx := w / 2
	var s := float(h) / 26.0
	var head := int(6 * s)
	_rect(img, cx - head / 2, 1, head, head, SKIN)
	_rect(img, cx - head / 2, 1, head, 2, accent.darkened(0.3))  # hair / helmet
	var tw := int(8 * s)
	var th := int(9 * s)
	var ty := 1 + head
	_rect(img, cx - tw / 2, ty, tw, th, torso)
	_rect(img, cx - tw / 2, ty + th - 2, tw, 1, accent)  # belt
	_rect(img, cx - tw / 2 - 2, ty + 1, 2, th - 2, SKIN)
	_rect(img, cx + tw / 2, ty + 1, 2, th - 2, SKIN)
	var lw := maxi(2, tw / 2 - 1)
	_rect(img, cx - tw / 2 + 1, ty + th, lw, h - ty - th - 1, LEG)
	_rect(img, cx + tw / 2 - 1 - lw, ty + th, lw, h - ty - th - 1, LEG)
	match kit:
		"shield_spear":
			_rect(img, w - 2, 0, 1, h - 2, WOOD)
			_rect(img, w - 3, 0, 3, 2, METAL)
			_rect(img, 1, ty + 1, 5, 7, accent)
			_rect(img, 2, ty + 3, 3, 3, accent.lightened(0.3))
		"bow":
			for y in range(ty - 4, ty + th + 2):
				var x := w - 2 - int(absf(float(y - (ty + th / 2)) / 3.0))
				_rect(img, x, y, 1, 1, accent)
			_rect(img, w - 1, ty - 4, 1, th + 6, Color(0.9, 0.9, 0.85))
		"club":
			_rect(img, w - 4, ty - 6, 3, th + 4, WOOD)
			_rect(img, w - 5, ty - 7, 5, 4, WOOD.darkened(0.2))
		"sword":
			_rect(img, w - 2, ty - 3, 1, th, METAL)
			_rect(img, w - 3, ty + th - 4, 3, 1, WOOD)
	_outline(img)
	return img


static func _beast(w: int, h: int, body: Color, shade: Color, tusks: bool) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var bh := int(h * 0.42)
	var by := int(h * 0.3)
	_rect(img, int(w * 0.12), by, int(w * 0.62), bh, body)
	_rect(img, int(w * 0.12), by + bh - 2, int(w * 0.62), 2, shade)
	var hw := int(w * 0.26)
	var hh := int(h * 0.36)
	_rect(img, w - hw - 1, by - hh / 3, hw, hh, body)
	_rect(img, w - hw - 1, by - hh / 3, int(hw * 0.45), hh, shade)  # mane / ruff
	_rect(img, w - 4, by, 2, 2, DARK)  # eye
	if tusks:
		_rect(img, w - 3, by + hh - 4, 2, 3, Color(0.95, 0.93, 0.85))
	var lh := h - by - bh - 1
	for lx in [0.16, 0.3, 0.56, 0.68]:
		_rect(img, int(w * lx), by + bh, maxi(2, w / 16), lh, shade)
	_rect(img, 1, by, int(w * 0.12), 2, shade)  # tail
	_outline(img)
	return img


static func _rect(img: Image, x: int, y: int, w: int, h: int, c: Color) -> void:
	for yy in range(maxi(y, 0), mini(y + h, img.get_height())):
		for xx in range(maxi(x, 0), mini(x + w, img.get_width())):
			img.set_pixel(xx, yy, c)


static func _outline(img: Image) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var src := img.duplicate() as Image
	for y in h:
		for x in w:
			if src.get_pixel(x, y).a > 0.0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and src.get_pixel(nx, ny).a > 0.0:
					img.set_pixel(x, y, DARK)
					break
