class_name Vase
## The look of painted pottery, for screens that are moments rather than menus. Two grounds,
## as on the pots themselves: fired clay (figures painted on it in black glaze) and black
## glaze (figures left in the colour of the clay). Everything here is drawn by code, with
## the small unevenness of a thing made by hand: streaks from the wheel, a brush that
## wavers.

const CLAY := Color("#c8693a")
const CLAY_DEEP := Color("#8a3f20")
const GLAZE := Color("#15100c")
const SLIP := Color("#f1dfc0")   ## the white paint added for detail
const WINE := Color("#7a2219")   ## the purple-red added for blood and cloth

static var _cache := {}


## Fired clay: a tile that repeats, lighter and darker in bands as the wheel left it.
static func clay() -> Texture2D:
	return _ground("clay",CLAY,.05,.035,CLAY_DEEP,.012)


## Black glaze, thin in places so the clay shows through as a rare speck.
static func glaze() -> Texture2D:
	return _ground("glaze",GLAZE,.03,.02,CLAY_DEEP,.004)


static func _ground(key: String, base: Color, banding: float, grain: float, fleck: Color, flecks: float) -> Texture2D:
	if not _cache.has(key):
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(key)
		var side := 128
		var image := Image.create(side,side,false,Image.FORMAT_RGBA8)
		var band := 0.0
		for y in side:
			# The wheel's bands drift rather than jump.
			band = clampf(band+rng.randf_range(-banding,banding)*.5,-banding,banding)
			for x in side:
				var tone := base.lightened(band) if band >= 0 else base.darkened(-band)
				var speck := rng.randf_range(-grain,grain)
				tone = tone.lightened(speck) if speck >= 0 else tone.darkened(-speck)
				if rng.randf() < flecks: tone = tone.lerp(fleck,.6)
				image.set_pixel(x,y,tone)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## The key pattern that runs round the neck of a pot, as a strip `cells` units long. Each
## unit is eight dots wide and seven tall, drawn `dot` pixels to the dot.
static func meander(tone: Color, dot := 2) -> Texture2D:
	var key := "meander/%s/%d" % [tone.to_html(),dot]
	if not _cache.has(key):
		var rows := ["XXXXXXX.","X.......","X.XXXXX.","X.X...X.","X.XXX.X.","X.....X.","XXXXXXX."]
		var image := Image.create(8*dot,7*dot,false,Image.FORMAT_RGBA8)
		for y in 7:
			for x in 8:
				if rows[y][x] == "X": image.fill_rect(Rect2i(x*dot,y*dot,dot,dot),tone)
		_cache[key] = ImageTexture.create_from_image(image)
	return _cache[key]


## A run of the key pattern across `rect`, between two painted lines.
static func band(parent: Control, rect: Rect2, tone: Color, dot := 2) -> void:
	var strip := TextureRect.new()
	strip.texture = meander(tone,dot)
	strip.stretch_mode = TextureRect.STRETCH_TILE
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = rect.position+Vector2(0,3)
	strip.size = Vector2(rect.size.x,7*dot)
	parent.add_child(strip)
	Px.block(parent,Rect2(rect.position,Vector2(rect.size.x,1)),tone)
	Px.block(parent,Rect2(rect.position.x,rect.position.y+7*dot+5,rect.size.x,1),tone)


## The key pattern alone, as a strip across `rect`, in one colour.
static func frieze(parent: Control, rect: Rect2, tone: Color, dot := 1) -> TextureRect:
	var strip := TextureRect.new()
	strip.texture = meander(Color.WHITE,dot)
	strip.modulate = tone
	strip.stretch_mode = TextureRect.STRETCH_TILE
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.position = rect.position
	strip.size = Vector2(rect.size.x,7*dot)
	parent.add_child(strip)
	return strip


## A line as a loaded brush draws it: nearly straight, never quite. Returns the points.
static func stroke(from: Vector2, to: Vector2, waver: float, salt: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = salt
	var points := PackedVector2Array()
	var steps := maxi(4,int(from.distance_to(to)/28.0))
	var across := (to-from).orthogonal().normalized()
	var drift := 0.0
	for i in steps+1:
		var t := float(i)/steps
		drift = clampf(drift+rng.randf_range(-waver,waver)*.6,-waver,waver)
		points.append(from.lerp(to,t)+across*(drift if i > 0 and i < steps else 0.0))
	return points


## A roundel: a disc of one colour ringed by another, as painted inside a cup.
static func roundel(art: Control, at: Vector2, radius: float, fill: Color, ring: Color, width := 1.0) -> void:
	art.draw_circle(at,radius,ring)
	art.draw_circle(at,radius-width,fill)
