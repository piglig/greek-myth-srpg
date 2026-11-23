extends Control
## Transient ceramic plaque drawn in logical pixels at the HUD's scale.

const INK := Color("#241e1c")
const IVORY := Color("#fff1d4")
const BRONZE := Color("#c59762")
const WIDTH := 334.0
const HEIGHT := 72.0

var round_number := 1
var player_turn := true
var emblem: Texture2D


func fit(window: Vector2, factor: float) -> void:
	scale = Vector2.ONE * factor
	size = Vector2(WIDTH, HEIGHT)
	position = Vector2(roundf((window.x - WIDTH * factor) * 0.5), roundf(window.y * 0.205))


func present(number: int, friendly: bool, icon: Texture2D) -> void:
	round_number = number
	player_turn = friendly
	emblem = icon
	queue_redraw()


func _draw() -> void:
	var lettering := Px.font(24)
	var accent := Color("#87c8bb") if player_turn else Color("#ff9372")
	var glaze := Color("#31564f") if player_turn else Color("#813e32")
	var rim := PackedVector2Array([Vector2(9,1),Vector2(325,1),Vector2(333,9),
		Vector2(333,63),Vector2(325,71),Vector2(9,71),Vector2(1,63),Vector2(1,9),Vector2(9,1)])
	draw_colored_polygon(rim.slice(0,8), INK)
	draw_polyline(rim, BRONZE, 2, true)
	for y in [6,66]:
		draw_line(Vector2(12,y), Vector2(322,y), Color("#715941"), 1)
	var center := Vector2(42,36)
	draw_circle(center, 25, glaze, true, -1, true)
	draw_arc(center, 25, 0, TAU, 64, accent, 1.5, true)
	if emblem:
		draw_texture_rect(emblem, Rect2(24,18,36,36), false, IVORY)
	draw_string(lettering, Vector2(74,47), "我方行动" if player_turn else "敌方行动",
		HORIZONTAL_ALIGNMENT_CENTER, 135, 24, IVORY)
	draw_line(Vector2(222,18), Vector2(222,54), BRONZE, 1)
	draw_string(Px.font(20), Vector2(229,44), "第 %d 回合" % round_number,
		HORIZONTAL_ALIGNMENT_CENTER, 90, 20, accent)
