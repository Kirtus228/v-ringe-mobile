extends Control
## Кнопка-шестерёнка в углу экрана. Рисуем сами, чтобы не тащить картинки:
## диск под курсором + восемь зубцов + отверстие в центре.

signal pressed

const C_ICON := Color(0.66, 0.72, 0.82)
const C_ICON_HOT := Color(0.92, 0.95, 1.0)
const C_BG := Color(0.03, 0.04, 0.06, 0.52)
const C_BG_HOT := Color(0.06, 0.09, 0.14, 0.86)
const C_HOLE := Color(0.05, 0.06, 0.09, 0.96)

var hover := false
var active := false


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    if size == Vector2.ZERO:
        size = Vector2(46, 46)
    mouse_entered.connect(_on_hover.bind(true))
    mouse_exited.connect(_on_hover.bind(false))


func set_active(v: bool) -> void:
    active = v
    queue_redraw()


func _on_hover(v: bool) -> void:
    hover = v
    queue_redraw()


func _gui_input(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed \
            and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
        accept_event()
        pressed.emit()


func _draw() -> void:
    var c := size * 0.5
    var r := minf(size.x, size.y) * 0.5
    var hot := hover or active
    draw_circle(c, r, C_BG_HOT if hot else C_BG)
    draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.42 if hot else 0.16), 1.5, true)

    var col := C_ICON_HOT if hot else C_ICON
    var teeth := 8
    var r_out := r * 0.60
    var r_in := r * 0.46
    for i in teeth:
        var a := TAU * float(i) / float(teeth)
        var w := TAU / float(teeth) * 0.26
        var pts := PackedVector2Array([
            c + Vector2(cos(a - w), sin(a - w)) * r_in,
            c + Vector2(cos(a - w * 0.55), sin(a - w * 0.55)) * r_out,
            c + Vector2(cos(a + w * 0.55), sin(a + w * 0.55)) * r_out,
            c + Vector2(cos(a + w), sin(a + w)) * r_in,
        ])
        draw_colored_polygon(pts, col)
    draw_circle(c, r_in + 1.0, col)
    draw_circle(c, r * 0.19, C_HOLE)
