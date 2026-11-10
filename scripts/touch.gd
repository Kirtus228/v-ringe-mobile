extends CanvasLayer
## Мобильное управление (v21): удары — в левом нижнем углу, движение — стик справа.
##
## Слой живёт поверх HUD и включается только в бою/тренировке: в меню все кнопки
## уже нажимаются тапом (Godot сам превращает тач в мышь). Экранные координаты —
## те же 1280x720, что и у HUD, поэтому на любом телефоне кнопки масштабируются
## вместе с интерфейсом.

signal punch(kind: String)
signal dodge()
signal pause_pressed()

const W := 1280.0
const H := 720.0

const AMBER := Color(0.98, 0.75, 0.14)
const TEXT := Color(0.94, 0.96, 1.0)
const GLASS := Color(0.04, 0.05, 0.08, 0.42)
const GLASS_HOT := Color(0.98, 0.75, 0.14, 0.36)

## Верхняя граница стика: значения в долях радиуса (−1…1).
const STICK_POS := Vector2(1054.0, 596.0)
const STICK_R := 104.0
const KNOB_R := 46.0
const DEAD := 0.16

const BTN := [
    {"id": "hook_l", "label": "ЛЕВЫЙ", "pos": Vector2(136, 458), "r": 48.0},
    {"id": "hook_r", "label": "ПРАВЫЙ", "pos": Vector2(252, 458), "r": 48.0},
    {"id": "cross", "label": "КРОСС", "pos": Vector2(368, 458), "r": 48.0},
    {"id": "upper", "label": "АППЕР", "pos": Vector2(136, 586), "r": 48.0},
    {"id": "jab", "label": "ДЖЕБ", "pos": Vector2(252, 586), "r": 54.0},
    {"id": "body", "label": "КОРПУС", "pos": Vector2(368, 348), "r": 44.0, "toggle": true},
    {"id": "block", "label": "БЛОК", "pos": Vector2(70, 348), "r": 42.0, "hold": true},
    {"id": "dodge", "label": "УКЛОН", "pos": Vector2(186, 348), "r": 42.0},
    {"id": "pause", "label": "II", "pos": Vector2(1216, 236), "r": 34.0},
]

var active := false
var move := Vector2.ZERO
var block := false
## переключатель «бить в корпус»: пока включён, все удары идут по корпусу
var body_mode := false

var pad: Control
var font: SystemFont
var font_b: SystemFont
var _stick_id := -1
var _stick_vec := Vector2.ZERO
var _held := {}          # кнопка → индекс касания
var _hot := {}           # для подсветки: id → true
var _block_id := -1


func build() -> void:
    layer = 2
    font = SystemFont.new()
    font.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
    font_b = SystemFont.new()
    font_b.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
    font_b.font_weight = 700
    pad = Control.new()
    pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pad.draw.connect(_draw_pad)
    pad.gui_input.connect(_on_gui_input)
    add_child(pad)
    set_active(false)


func set_active(on: bool) -> void:
    active = on
    body_mode = false
    if pad != null:
        pad.visible = on
        pad.mouse_filter = Control.MOUSE_FILTER_STOP if on else Control.MOUSE_FILTER_IGNORE
        if not on:
            move = Vector2.ZERO
            block = false
            _stick_id = -1
            _stick_vec = Vector2.ZERO
            _held.clear()
            _block_id = -1
            _hot.clear()
        pad.queue_redraw()


func _btn_rect(b: Dictionary) -> Rect2:
    var r: float = float(b["r"]) + 8.0
    return Rect2(Vector2(b["pos"]) - Vector2(r, r), Vector2(r * 2.0, r * 2.0))


func _btn_at(p: Vector2) -> Dictionary:
    for b in BTN:
        if p.distance_to(Vector2(b["pos"])) <= float(b["r"]) + 12.0:
            return b
    return {}


func _in_stick(p: Vector2) -> bool:
    return p.distance_to(STICK_POS) <= STICK_R + 40.0


func _on_gui_input(event: InputEvent) -> void:
    if not active:
        return
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        if t.pressed:
            var b := _btn_at(t.position)
            if not b.is_empty():
                var id := String(b["id"])
                _held[id] = t.index
                _hot[id] = true
                _press(id, bool(b.get("hold", false)), t.index)
                pad.queue_redraw()
                pad.accept_event()
                return
            if _in_stick(t.position) and _stick_id < 0:
                _stick_id = t.index
                _stick_update(t.position)
                pad.accept_event()
                return
        else:
            for id in _held.keys():
                if int(_held[id]) == t.index:
                    _held.erase(id)
                    _hot.erase(id)
                    if id == "block" and _block_id >= 0:
                        _block_id = -1
                        block = false
                    pad.queue_redraw()
                    pad.accept_event()
                    return
            if _stick_id == t.index:
                _stick_id = -1
                _stick_vec = Vector2.ZERO
                move = Vector2.ZERO
                pad.queue_redraw()
                pad.accept_event()
                return
    elif event is InputEventScreenDrag:
        var d := event as InputEventScreenDrag
        for id in _held.keys():
            if int(_held[id]) == d.index:
                # палец уполз с кнопки — отпускаем, если это не «держать»
                var b := _btn_by_id(String(id))
                if not b.is_empty() and d.position.distance_to(Vector2(b["pos"])) > float(b["r"]) + 34.0:
                    if not bool(b.get("hold", false)):
                        _held.erase(id)
                        _hot.erase(id)
                        pad.queue_redraw()
                pad.accept_event()
                return
        if _stick_id == d.index:
            _stick_update(d.position)
            pad.accept_event()
            return


func _btn_by_id(id: String) -> Dictionary:
    for b in BTN:
        if String(b["id"]) == id:
            return b
    return {}


func _press(id: String, hold: bool, index: int) -> void:
    match id:
        "jab":
            punch.emit("jab")
        "cross":
            punch.emit("cross")
        "hook_l":
            punch.emit("lhook")
        "hook_r":
            punch.emit("rhook")
        "upper":
            punch.emit("upper")
        "body":
            # кнопка-переключатель: следующий удар (и все, пока горит) — в корпус
            body_mode = not body_mode
        "dodge":
            dodge.emit()
        "pause":
            pause_pressed.emit()
        "block":
            if hold:
                block = true
                _block_id = index


func _stick_update(p: Vector2) -> void:
    var v := (p - STICK_POS) / STICK_R
    if v.length() > 1.0:
        v = v.normalized()
    _stick_vec = v
    move = Vector2.ZERO if v.length() < DEAD else v
    pad.queue_redraw()


# ---------------------------------------------------------------- рисование

func _draw_pad() -> void:
    if not active:
        return
    # удары и вспомогательные кнопки
    for b in BTN:
        var id := String(b["id"])
        var c := Vector2(b["pos"])
        var r: float = float(b["r"])
        var hot := bool(_hot.get(id, false))
        var body_on := id == "body" and body_mode
        var base := GLASS_HOT if hot else GLASS
        if body_on:
            base = Color(0.98, 0.75, 0.14, 0.58)
        pad.draw_circle(c, r, base)
        var ring := AMBER if (hot or id == "jab" or body_on) else Color(0.86, 0.90, 1.0, 0.55)
        pad.draw_arc(c, r, 0.0, TAU, 40, ring, 3.0, true)
        if id == "body" and body_mode:
            # включённый корпус подсвечивает и сами удары — чтобы не забыть
            pad.draw_arc(c, r - 8.0, 0.0, TAU, 32, Color(0.99, 0.86, 0.45), 2.0, true)
        var f: SystemFont = font_b if id != "pause" else font_b
        var size := 16 if id == "body" else (17 if id != "pause" else 22)
        var tw := f.get_string_size(String(b["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
        var col := TEXT
        if body_on:
            col = Color(0.07, 0.08, 0.12)
        pad.draw_string(f, c + Vector2(-tw * 0.5, size * 0.36), String(b["label"]),
                HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

    # стик движения
    pad.draw_circle(STICK_POS, STICK_R, Color(0.04, 0.05, 0.08, 0.34))
    pad.draw_arc(STICK_POS, STICK_R, 0.0, TAU, 56, Color(0.86, 0.90, 1.0, 0.45), 3.0, true)
    pad.draw_arc(STICK_POS, STICK_R * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.10), 2.0, true)
    var knob := STICK_POS + _stick_vec * (STICK_R - KNOB_R)
    pad.draw_circle(knob, KNOB_R, Color(0.98, 0.75, 0.14, 0.30))
    pad.draw_arc(knob, KNOB_R, 0.0, TAU, 32, AMBER, 3.0, true)
