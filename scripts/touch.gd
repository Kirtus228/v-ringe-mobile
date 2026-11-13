extends CanvasLayer
## Мобильное управление (v21): движение — стик слева, удары — справа (v48).
##
## Слой живёт поверх HUD и включается только в бою/тренировке: в меню все кнопки
## уже нажимаются тапом (Godot сам превращает тач в мышь). Экранные координаты —
## те же 1280x720, что и у HUD, поэтому на любом телефоне кнопки масштабируются
## вместе с интерфейсом.

signal punch(kind: String)
signal dodge()
signal pause_pressed()
## нажата большая кнопка «ВСТАТЬ» — она видна только в нокдауне
signal getup()

const W := 1280.0
const H := 720.0
const LangText = preload("res://scripts/lang.gd")
## кнопка подъёма: по центру, между стиком и ударами
const GETUP_POS := Vector2(640.0, 470.0)
const GETUP_R := 88.0

const AMBER := Color(0.98, 0.75, 0.14)
const TEXT := Color(0.94, 0.96, 1.0)
const GLASS := Color(0.04, 0.05, 0.08, 0.42)
const GLASS_HOT := Color(0.98, 0.75, 0.14, 0.36)

## Верхняя граница стика: значения в долях радиуса (−1…1).
const STICK_POS := Vector2(226.0, 596.0)
const STICK_R := 104.0
const KNOB_R := 46.0
const DEAD := 0.16

## v58: своя раскладка кнопок и джойстика (настройки → «управление» → «кнопки»).
## Позиции хранятся в сейве секцией touch_layout как [x, y]; если для контрола
## записи нет — берётся позиция по умолчанию из BTN / STICK_POS.
const LAYOUT_SECTION := "touch_layout"
## Отступ, ближе которого центр контрола к краю кадра не ставим (палец у края
## экрана + вырез камеры).
const EDIT_MARGIN := 10.0
## Кнопки редактора рисуем сверху под заголовком: снизу мешает джойстик,
## который по умолчанию стоит в левом нижнем углу.
const EDIT_BTN_Y := 92.0
const EDIT_BTN_H := 68.0

## v48: по просьбе заказчика движение — СЛЕВА, удары — СПРАВА.
## Раньше было наоборот (удары слева, стик справа). Раскладка просто
## зеркалится по X: правый большой палец бьёт, левый ведёт бойца.
const BTN := [
    {"id": "body", "label": "КОРПУС", "pos": Vector2(912, 348), "r": 50.0, "toggle": true},
    {"id": "dodge", "label": "УКЛОН", "pos": Vector2(1094, 348), "r": 50.0},
    {"id": "block", "label": "БЛОК", "pos": Vector2(1210, 348), "r": 50.0, "hold": true},
    {"id": "cross", "label": "КРОСС", "pos": Vector2(912, 458), "r": 48.0},
    {"id": "hook_r", "label": "ПРАВЫЙ", "pos": Vector2(1028, 458), "r": 48.0},
    {"id": "hook_l", "label": "ЛЕВЫЙ", "pos": Vector2(1144, 458), "r": 48.0},
    {"id": "jab", "label": "ДЖЕБ", "pos": Vector2(1028, 586), "r": 54.0},
    {"id": "upper", "label": "АППЕР", "pos": Vector2(1144, 586), "r": 48.0},
    {"id": "upper_l", "label": "АППЕР Л", "pos": Vector2(912, 586), "r": 48.0},
    {"id": "pause", "label": "II", "pos": Vector2(1200, 240), "r": 50.0},
]

## v58: пришли из редактора раскладки — главный экран настроек перерисуется сам.
signal editor_closed

var active := false
var move := Vector2.ZERO
var block := false
## переключатель «бить в корпус»: пока включён, все удары идут по корпусу
var body_mode := false
## боец лежит: показываем кнопку «ВСТАТЬ» (на мобилке нет Space)
var downed := false
## прогресс активного подъёма: сколько нажатий уже набрано
var mash_progress := 0.0
var mash_done := 0
var mash_need := 1

var pad: Control
var font: SystemFont
var font_b: SystemFont
var _stick_id := -1
var _stick_vec := Vector2.ZERO
var _held := {}          # кнопка → индекс касания
var _hot := {}           # для подсветки: id → true
var _block_id := -1
## v58: раскладка игрока (id → Vector2). Пусто — всё по умолчанию.
var layout := {}
var stick_pos := STICK_POS
## v58: режим редактора раскладки (перетаскивание кнопок и джойстика).
var editor := false
var _edit_drag := ""
var _edit_drag_idx := -1
var _editor_msg := ""
var _editor_msg_t := 0.0
var _editor_layer_before := 2
## последняя отрисованная позиция стика — для проверки в тестах
var _debug_last_drag := ""


func build() -> void:
    layer = 2
    font = SystemFont.new()
    font.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
    font_b = SystemFont.new()
    font_b.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
    font_b.font_weight = 700
    load_layout()
    pad = Control.new()
    pad.set_anchors_preset(Control.PRESET_TOP_LEFT)
    pad.size = Vector2(W, H)
    _layout_pad()
    pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pad.draw.connect(_draw_pad)
    pad.gui_input.connect(_on_gui_input)
    add_child(pad)
    if not get_viewport().size_changed.is_connected(_layout_pad):
        get_viewport().size_changed.connect(_layout_pad)
    set_active(false)
    # T6: аудит мобильного интерфейса (headless-тест, как --uitest)
    if OS.get_cmdline_user_args().has("--mobiletest"):
        call_deferred("_run_mobiletest")


## Канва может быть шире 16:9 (телефон): кнопки боя держим в центральном
## 16:9-кадре, поэтому координаты кнопок остаются прежними.
func _layout_pad() -> void:
    if pad == null:
        return
    var cs := get_viewport().get_visible_rect().size
    pad.position = Vector2(maxf(0.0, (cs.x - W) * 0.5), maxf(0.0, (cs.y - H) * 0.5))


func set_active(on: bool) -> void:
    active = on
    body_mode = false
    downed = false
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


# ---------------------------------------------------------------- v58: раскладка

## Позиция по умолчанию для контрола (кнопки из BTN, «stick» — STICK_POS).
func default_pos(id: String) -> Vector2:
    if id == "stick":
        return STICK_POS
    for b in BTN:
        if String(b["id"]) == id:
            return Vector2(b["pos"])
    return Vector2(W * 0.5, H * 0.5)


## Текущая позиция контрола: раскладка игрока или позиция по умолчанию.
func pos_of(id: String) -> Vector2:
    if id == "stick":
        return stick_pos
    if layout.has(id):
        return layout[id]
    return default_pos(id)


## Радиус/зона попадания контрола (для перетаскивания и проверок).
func hit_radius(id: String) -> float:
    if id == "stick":
        return STICK_R + 30.0
    for b in BTN:
        if String(b["id"]) == id:
            return float(b["r"]) + 14.0
    return 24.0


func load_layout() -> void:
    layout.clear()
    stick_pos = STICK_POS
    if SaveManager == null:
        return
    for b in BTN:
        var id := String(b["id"])
        var v = SaveManager.load_value(LAYOUT_SECTION, id, null)
        if v is Array and (v as Array).size() == 2:
            layout[id] = Vector2(float(v[0]), float(v[1]))
    var sv = SaveManager.load_value(LAYOUT_SECTION, "stick", null)
    if sv is Array and (sv as Array).size() == 2:
        stick_pos = Vector2(float(sv[0]), float(sv[1]))


func save_layout() -> void:
    if SaveManager == null:
        return
    for b in BTN:
        var id := String(b["id"])
        var p := pos_of(id)
        SaveManager.save_value(LAYOUT_SECTION, id, [p.x, p.y])
    SaveManager.save_value(LAYOUT_SECTION, "stick", [stick_pos.x, stick_pos.y])
    SaveManager.flush()


## Сброс на заводскую раскладку (и сразу в сейв).
func reset_layout() -> void:
    layout.clear()
    stick_pos = STICK_POS
    if SaveManager != null:
        SaveManager.replace_section(LAYOUT_SECTION, {})
        SaveManager.flush()
    if pad != null:
        pad.queue_redraw()


## Новая позиция контрола (с ограничением по краям кадра). Можно звать из тестов.
func move_control(id: String, p: Vector2) -> void:
    var r: float = hit_radius(id)
    var np := Vector2(clampf(p.x, r + EDIT_MARGIN, W - r - EDIT_MARGIN),
            clampf(p.y, r + EDIT_MARGIN, H - r - EDIT_MARGIN))
    if id == "stick":
        stick_pos = np
    else:
        layout[id] = np
    if pad != null:
        pad.queue_redraw()


## Включить/выключить редактор раскладки. Пока редактор включён, пад ловит всё
## касание сам, кнопки не бьют — только переставляются.
func set_editor(on: bool) -> void:
    var was_editor := editor
    editor = on
    if pad == null:
        return
    if on:
        load_layout()
        _editor_layer_before = layer
        layer = 20            # выше HUD: настройки за ним скрывает main
        active = true
        downed = false
        body_mode = false
        move = Vector2.ZERO
        block = false
        _stick_id = -1
        _held.clear()
        _hot.clear()
        _edit_drag = ""
        _edit_drag_idx = -1
        _editor_msg = ""
        _editor_msg_t = 0.0
        pad.visible = true
        pad.mouse_filter = Control.MOUSE_FILTER_STOP
        _layout_pad()
    else:
        _edit_drag = ""
        _edit_drag_idx = -1
        # закрытие редактора всегда сохраняет: Esc и «ГОТОВО» дают один результат
        if was_editor:
            save_layout()
        _editor_msg = ""
        layer = _editor_layer_before
        active = false
        pad.visible = false
        pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
    pad.queue_redraw()


## Показать/убрать кнопку подъёма (её включает main.gd по сигналу downed).
func set_downed(on: bool) -> void:
    downed = on
    if not on:
        _hot.erase("getup")
        mash_progress = 0.0
        mash_done = 0
    if pad != null and active:
        pad.queue_redraw()


## Прогресс «расжатия» кнопки: заполняем круг по мере нажатий.
func set_mash(progress: float, done: int, need: int) -> void:
    mash_progress = clampf(progress, 0.0, 1.0)
    mash_done = done
    mash_need = maxi(need, 1)
    if pad != null and active:
        pad.queue_redraw()


func _btn_rect(b: Dictionary) -> Rect2:
    var r: float = float(b["r"]) + 8.0
    var c: Vector2 = pos_of(String(b["id"]))
    return Rect2(c - Vector2(r, r), Vector2(r * 2.0, r * 2.0))


func _btn_at(p: Vector2) -> Dictionary:
    for b in BTN:
        if p.distance_to(pos_of(String(b["id"]))) <= float(b["r"]) + 12.0:
            return b
    return {}


func _in_stick(p: Vector2) -> bool:
    return p.distance_to(stick_pos) <= STICK_R + 40.0


func _on_gui_input(event: InputEvent) -> void:
    # v58: в редакторе раскладки весь ввод — перетаскивание контролов
    if editor:
        _editor_input(event)
        return
    if not active:
        return
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        if t.pressed:
            # в нокдауне единственное действие — встать, остальное не работает
            if downed:
                if t.position.distance_to(GETUP_POS) <= GETUP_R + 16.0:
                    _hot["getup"] = true
                    getup.emit()
                    pad.queue_redraw()
                pad.accept_event()
                return
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
                if not b.is_empty() and d.position.distance_to(pos_of(String(id))) > float(b["r"]) + 34.0:
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
        "upper_l":
            punch.emit("upper_l")
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
    var v := (p - stick_pos) / STICK_R
    if v.length() > 1.0:
        v = v.normalized()
    _stick_vec = v
    move = Vector2.ZERO if v.length() < DEAD else v
    pad.queue_redraw()


# ---------------------------------------------------------------- рисование

func _draw_pad() -> void:
    if not active and not editor:
        return
    if editor:
        _draw_editor()
        return
    # в нокдауне оставляем на экране только кнопку «ВСТАТЬ»: удары, блок,
    # уклон и стик всё равно не работают — нечего и показывать
    if downed:
        _draw_getup()
        return
    # удары и вспомогательные кнопки
    for b in BTN:
        var id := String(b["id"])
        var c: Vector2 = pos_of(id)
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
    pad.draw_circle(stick_pos, STICK_R, Color(0.04, 0.05, 0.08, 0.34))
    pad.draw_arc(stick_pos, STICK_R, 0.0, TAU, 56, Color(0.86, 0.90, 1.0, 0.45), 3.0, true)
    pad.draw_arc(stick_pos, STICK_R * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.10), 2.0, true)
    var knob := stick_pos + _stick_vec * (STICK_R - KNOB_R)
    pad.draw_circle(knob, KNOB_R, Color(0.98, 0.75, 0.14, 0.30))
    pad.draw_arc(knob, KNOB_R, 0.0, TAU, 32, AMBER, 3.0, true)


# ---------------------------------------------------------------- v58: редактор раскладки

## Кнопки редактора: сохранить / сбросить / готово.
func _editor_rects() -> Dictionary:
    return {
        "save": Rect2(44.0, EDIT_BTN_Y, 264.0, EDIT_BTN_H),
        "reset": Rect2(324.0, EDIT_BTN_Y, 264.0, EDIT_BTN_H),
        "done": Rect2(604.0, EDIT_BTN_Y, 264.0, EDIT_BTN_H),
    }


func _ed_text(text: String, x: float, y: float, w: float, size: int, col: Color,
        align: int = HORIZONTAL_ALIGNMENT_CENTER, f: SystemFont = null) -> void:
    var use_f: SystemFont = f if f != null else font
    pad.draw_string(use_f, Vector2(x, y + float(size)), text, align, w, size, col)


## Один контрол в редакторе: круг, пунктирная зона захвата, подпись.
func _draw_editor_control(id: String, label: String, r: float) -> void:
    var c := pos_of(id)
    var drag := id == _edit_drag
    var col := AMBER if drag else Color(0.86, 0.90, 1.0, 0.78)
    pad.draw_circle(c, r, Color(0.10, 0.13, 0.19, 0.88))
    pad.draw_arc(c, r, 0.0, TAU, 48, col, 3.0, true)
    pad.draw_arc(c, r + 14.0, 0.0, TAU, 48, Color(col.r, col.g, col.b, 0.28), 1.5, true)
    pad.draw_line(c + Vector2(-r * 0.35, 0), c + Vector2(r * 0.35, 0),
            Color(1, 1, 1, 0.10), 1.0)
    pad.draw_line(c + Vector2(0, -r * 0.35), c + Vector2(0, r * 0.35),
            Color(1, 1, 1, 0.10), 1.0)
    var fs := 18 if id == "stick" else 15
    _ed_text(label, c.x - r, c.y - float(fs) * 0.5, r * 2.0, fs, TEXT,
            HORIZONTAL_ALIGNMENT_CENTER, font_b)


func _draw_editor() -> void:
    pad.draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.03, 0.05, 0.92), true)
    var title := "РАССТАНОВКА КНОПОК" if not LangText.is_en() else "BUTTON LAYOUT"
    var sub := "Тяни кнопку или джойстик — куда удобно" \
            if not LangText.is_en() else "Drag a button or the stick where it fits you"
    var sub2 := "Нажми «СОХРАНИТЬ», чтобы раскладка осталась в следующих боях" \
            if not LangText.is_en() else "Press SAVE to keep this layout in future fights"
    _ed_text(title, 0, 8, W, 26, AMBER, HORIZONTAL_ALIGNMENT_CENTER, font_b)
    _ed_text(sub, 0, 42, W, 15, Color(0.72, 0.78, 0.88), HORIZONTAL_ALIGNMENT_CENTER, font)
    _ed_text(sub2, 0, 62, W, 12, Color(0.55, 0.62, 0.72), HORIZONTAL_ALIGNMENT_CENTER, font)
    for b in BTN:
        var id := String(b["id"])
        _draw_editor_control(id, String(b["label"]), float(b["r"]))
    _draw_editor_control("stick", "СТИК" if not LangText.is_en() else "STICK", STICK_R)
    var rects := _editor_rects()
    var labels := {"save": "СОХРАНИТЬ", "reset": "СБРОС", "done": "ГОТОВО"}
    if LangText.is_en():
        labels = {"save": "SAVE", "reset": "RESET", "done": "DONE"}
    for k in ["save", "reset", "done"]:
        var r: Rect2 = rects[k]
        pad.draw_rect(r, Color(0.10, 0.12, 0.17, 0.96), true)
        pad.draw_rect(r, AMBER if k == "done" else Color(0.86, 0.90, 1.0, 0.45), false, 2.0)
        _ed_text(String(labels[k]), r.position.x, r.position.y + (r.size.y - 20.0) * 0.5,
                r.size.x, 19, TEXT, HORIZONTAL_ALIGNMENT_CENTER, font_b)
    if _editor_msg != "":
        _ed_text(_editor_msg, 0, EDIT_BTN_Y + EDIT_BTN_H + 20.0, W, 17,
                Color(0.55, 0.86, 0.62), HORIZONTAL_ALIGNMENT_CENTER, font_b)
    # v71: на телефоне клавиатуры нет — подсказка про «ГОТОВО», на ПК — Esc
    var close_hint := "Esc — закрыть" if not LangText.is_en() else "Esc — close"
    if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
            or OS.get_cmdline_user_args().has("--touch"):
        close_hint = "«ГОТОВО» — закрыть и сохранить" if not LangText.is_en() \
                else "«DONE» — close and save"
    _ed_text(close_hint, 0, H - 26.0, W, 12, Color(0.45, 0.52, 0.62),
            HORIZONTAL_ALIGNMENT_CENTER, font)


## Ввод в редакторе: перетаскивание контролов + три кнопки.
func _editor_input(event: InputEvent) -> void:
    var p := Vector2.ZERO
    var idx := 0
    var pressed := false
    var released := false
    var motion := false
    if event is InputEventScreenTouch:
        var t := event as InputEventScreenTouch
        p = t.position
        idx = t.index
        pressed = t.pressed
        released = not t.pressed
    elif event is InputEventScreenDrag:
        var d := event as InputEventScreenDrag
        p = d.position
        idx = d.index
        motion = true
    elif event is InputEventMouseButton:
        var mb := event as InputEventMouseButton
        if mb.button_index != MOUSE_BUTTON_LEFT:
            return
        p = mb.position
        pressed = mb.pressed
        released = not mb.pressed
    elif event is InputEventMouseMotion:
        p = (event as InputEventMouseMotion).position
        motion = true
    else:
        return

    if pressed:
        for k in _editor_rects():
            if (_editor_rects()[k] as Rect2).has_point(p):
                _editor_action(String(k))
                pad.accept_event()
                return
        # ближайший контрол под пальцем: сначала кнопки, потом стик
        var best := ""
        var best_d := 9999.0
        for b in BTN:
            var id := String(b["id"])
            var dd := p.distance_to(pos_of(id))
            if dd <= float(b["r"]) + 22.0 and dd < best_d:
                best = id
                best_d = dd
        if best == "" and p.distance_to(stick_pos) <= STICK_R + 30.0:
            best = "stick"
        if best != "":
            _edit_drag = best
            _edit_drag_idx = idx
            move_control(best, p)
            pad.accept_event()
        return

    if motion and _edit_drag != "" and idx == _edit_drag_idx:
        move_control(_edit_drag, p)
        _debug_last_drag = _edit_drag
        pad.accept_event()
        return

    if released and _edit_drag != "" and idx == _edit_drag_idx:
        _edit_drag = ""
        _edit_drag_idx = -1
        pad.queue_redraw()
        pad.accept_event()


func _editor_action(what: String) -> void:
    match what:
        "save":
            save_layout()
            _editor_msg = "СОХРАНЕНО" if not LangText.is_en() else "SAVED"
            _editor_msg_t = 1.6
        "reset":
            reset_layout()
            _editor_msg = "ЗАВОДСКАЯ РАСКЛАДКА" if not LangText.is_en() else "DEFAULT LAYOUT"
            _editor_msg_t = 1.6
        "done":
            save_layout()
            editor_closed.emit()
    pad.queue_redraw()


## Большая кнопка «ВСТАТЬ»: пульсирует и заполняется по мере нажатий.
func _draw_getup() -> void:
    var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
    var hot := bool(_hot.get("getup", false))
    pad.draw_circle(GETUP_POS, GETUP_R, Color(0.98, 0.75, 0.14, 0.30 + 0.22 * pulse))
    pad.draw_arc(GETUP_POS, GETUP_R, 0.0, TAU, 56, AMBER, 4.0, true)
    # заполнение по кругу: видно, сколько ещё жать
    if mash_progress > 0.001:
        pad.draw_arc(GETUP_POS, GETUP_R - 5.0, -PI * 0.5, -PI * 0.5 + TAU * mash_progress,
                56, Color(0.99, 0.90, 0.52), 7.0, true)
    pad.draw_arc(GETUP_POS, GETUP_R - 12.0, 0.0, TAU, 48,
            Color(0.99, 0.90, 0.52, 0.75 if hot else 0.45 + 0.35 * pulse), 2.0, true)
    var label := "ВСТАТЬ"
    var size := 30
    var tw := font_b.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
    pad.draw_string(font_b, GETUP_POS + Vector2(-tw * 0.5, size * 0.36), label,
            HORIZONTAL_ALIGNMENT_LEFT, -1, size, TEXT)
    if mash_need > 1:
        var cnt := "%d/%d" % [mash_done, mash_need]
        var cs := font_b.get_string_size(cnt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
        pad.draw_string(font_b, GETUP_POS + Vector2(-cs * 0.5, 58), cnt,
                HORIZONTAL_ALIGNMENT_LEFT, -1, 20, AMBER)


# ---------------------------------------------------------------- T6: аудит мобильного UI
## --mobiletest (headless): обходит все экраны через штатные переключатели main,
## проверяет размеры тач-целей, отсутствие перекрывающих Control с фильтром STOP,
## «клавиатурные» подписи на тач-экранах и что кнопка реально нажимается
## (клик через тот же путь, что эмулирует палец: mouse из touch).
const MIN_DP_UNITS := 96.0   # 48 dp при content scale 1.5 на xhdpi
const FORBIDDEN_TOUCH_TOKENS := ["WASD", "ESC", "ENTER", "SHIFT", "CTRL", "SPACE",
        "СПЕЙС", "F1", "F11", "ПРОБЕЛ"]

var _mt_ok := true
var _mt_rows: Array = []


func _run_mobiletest() -> void:
    # страховка: тест не должен висеть, если что-то в main не готово
    get_tree().create_timer(45.0).timeout.connect(func() -> void:
        print("MOBILETEST ок=false (таймаут 45 с)")
        get_tree().quit())
    await get_tree().process_frame
    await get_tree().process_frame
    var main := get_tree().current_scene
    if main == null:
        print("MOBILETEST ок=false (нет main)")
        get_tree().quit()
        return
    var hud = main.get("hud")
    if hud == null:
        print("MOBILETEST ок=false (нет HUD)")
        get_tree().quit()
        return
    # 1) размеры тач-кнопок боя (touch.gd) в dp-единицах
    var min_btn := 999.0
    for b in BTN:
        min_btn = minf(min_btn, float(b["r"]) * 2.0)
    var stick_size := STICK_R * 2.0
    var getup_size := GETUP_R * 2.0
    _mt_check(min_btn >= MIN_DP_UNITS, "кнопки боя: диаметр min=%.0f (нужно ≥%.0f)" % [min_btn, MIN_DP_UNITS])
    _mt_check(stick_size >= MIN_DP_UNITS, "стик: диаметр %.0f" % stick_size)
    _mt_check(getup_size >= MIN_DP_UNITS, "«ВСТАТЬ»: диаметр %.0f" % getup_size)
    # 2) экраны: открыть штатным методом main и проверить оверлей HUD
    var screens: Array = [
        ["menu", "_leave_to_menu", -1, 96.0],
        ["settings_keys", "_open_settings", 0, 72.0],
        ["settings_sound", "_open_settings", 1, 72.0],
        ["settings_game", "_open_settings", 2, 72.0],
        ["story", "_open_story", -1, 96.0],
        ["stats", "_open_stats", -1, 84.0],
        ["locker", "_open_locker", -1, 42.0],
        ["upgrade", "_open_upgrades", -1, 42.0],
        ["tour", "_open_tournaments", -1, 84.0],
        ["howto", "_open_howto", -1, 84.0],
        ["prefight", "_start_prefight", -1, 84.0],
        ["pause", "_mt_pause", -1, 96.0],
        ["result", "_mt_result", -1, 80.0],
    ]
    for row in screens:
        var name := String(row[0])
        var fn := String(row[1])
        var arg := int(row[2])
        var need_h := float(row[3])
        main.call("_leave_to_menu")
        await get_tree().process_frame
        if fn == "_open_settings":
            main.call("_open_settings", arg)
        elif fn == "_mt_pause":
            main.call("_start_fight")
            main.call("_on_touch_pause")
        elif fn == "_mt_result":
            main.call("_reset_fight")
            main.set("pending", "win")
            main.set("score", 640)
            main.call("_finalize")
        elif main.has_method(fn):
            main.call(fn)
        await get_tree().process_frame
        await get_tree().process_frame
        _mt_audit_screen(hud, name, need_h, main)
        main.call("_leave_to_menu")
        await get_tree().process_frame
    # 3) реальное нажатие: клик по «ГАРДЕРОБ» в меню через GUI (эмуляция пальца)
    main.call("_leave_to_menu")
    await get_tree().process_frame
    await get_tree().process_frame
    var tap_ok := _mt_tap_by_text(hud, LangText.t("locker"), main)
    _mt_check(tap_ok, "нажатие кнопки в меню через GUI (эмуляция тапа): %s" % ("ок" if tap_ok else "НЕТ"))
    if main.get("state") == 5:  # St.CUSTOM
        main.call("_close_locker")
    # итог
    for r in _mt_rows:
        print("MOBILETEST ", r)
    print("MOBILETEST ок=", str(_mt_ok))
    get_tree().quit()


## Экран HUD не в оверлее (арена/тренировка — свои CanvasLayer) — пропускаем.
func _mt_audit_screen(hud: Node, name: String, need_h: float, main: Node) -> void:
    var overlay: Control = hud.get("overlay") as Control
    if overlay == null or not overlay.visible:
        _mt_rows.append("экран=%s HUD-оверлея нет (свой модуль) — пропуск" % name)
        return
    var buttons: Array = []
    _mt_collect_buttons(overlay, buttons)
    if buttons.is_empty():
        _mt_rows.append("экран=%s кнопок=0 — пропуск" % name)
        return
    var min_h := 999.0
    var small := 0
    var out_of_canvas := 0
    var safe_bad := 0
    var blockers := 0
    var cs: Vector2 = hud.call("_canvas")
    var safe: Vector4 = hud.get("_safe")
    for b in buttons:
        var btn: Button = b
        if not btn.is_visible_in_tree():
            continue
        min_h = minf(min_h, btn.size.y)
        if btn.size.y < need_h - 0.5:
            small += 1
        var r := btn.get_global_rect()
        if r.position.x < -1.0 or r.position.y < -1.0 \
                or r.end.x > cs.x + 1.0 or r.end.y > cs.y + 1.0:
            out_of_canvas += 1
        # safe area: вырез/жесты — кнопка не должна уходить под них
        if r.position.x < safe.x - 1.0 or r.position.y < safe.y - 1.0 \
                or r.end.x > cs.x - safe.z + 1.0 or r.end.y > cs.y - safe.w + 1.0:
            out_of_canvas += 0
            safe_bad += 1
        var top: Control = _mt_topmost_at(overlay, btn.get_global_rect().get_center())
        if top != null and top != btn and not btn.is_ancestor_of(top) and not top.is_ancestor_of(btn):
            blockers += 1
    # клавиатурные подписи на тач-экране (кроме экрана настройки клавиш)
    var bad_labels := 0
    var bad_first := ""
    if name != "settings_keys":
        var labels: Array = []
        _mt_collect_labels(overlay, labels)
        for l in labels:
            var t := String((l as Label).text).to_upper()
            for token in FORBIDDEN_TOUCH_TOKENS:
                if t.find(token) >= 0:
                    bad_labels += 1
                    if bad_first == "":
                        bad_first = t.substr(0, 40)
                    break
    _mt_check(small == 0, "экран=%s кнопок=%d мин_высота=%.0f (нужно ≥%.0f) мелких=%d"
            % [name, buttons.size(), min_h, need_h, small])
    _mt_check(out_of_canvas == 0, "экран=%s за канвой=%d" % [name, out_of_canvas])
    _mt_check(safe_bad == 0, "экран=%s в safe-area=%d" % [name, safe_bad])
    _mt_check(blockers == 0, "экран=%s перекрыто STOP-контролами=%d" % [name, blockers])
    _mt_check(bad_labels == 0, "экран=%s клавиатурных_подписей=%d %s" % [name, bad_labels, bad_first])


func _mt_check(ok: bool, text: String) -> void:
    if not ok:
        _mt_ok = false
    _mt_rows.append(("ок  " if ok else "НЕТ ") + text)


func _mt_collect_buttons(node: Node, out: Array) -> void:
    for ch in node.get_children():
        if ch is Button and not (ch as Button).text == "":
            out.append(ch)
        _mt_collect_buttons(ch, out)


func _mt_collect_labels(node: Node, out: Array) -> void:
    for ch in node.get_children():
        if ch is Label and (ch as Label).visible:
            out.append(ch)
        _mt_collect_labels(ch, out)


## Верхний Control в точке (порядок отрисовки как у Godot: поздние дети выше).
func _mt_topmost_at(node: Control, p: Vector2) -> Control:
    for i in range(node.get_child_count() - 1, -1, -1):
        var ch := node.get_child(i)
        if not (ch is Control):
            continue
        var c := ch as Control
        if not c.is_visible_in_tree() or not c.get_global_rect().has_point(p):
            continue
        var deep := _mt_topmost_at(c, p)
        if deep != null:
            return deep
        if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
            return c
    return null


## Эмуляция тапа: mouse press/release в центр кнопки с текстом, начинающимся с text
## (Android превращает касание в такое же событие мыши при emulate_mouse_from_touch).
func _mt_tap_by_text(hud: Node, text: String, main: Node) -> bool:
    var overlay: Control = hud.get("overlay") as Control as Control
    var buttons: Array = []
    _mt_collect_buttons(overlay, buttons)
    for b in buttons:
        var btn: Button = b
        if not btn.is_visible_in_tree() or btn.text.find(text) < 0:
            continue
        var c := btn.get_global_rect().get_center()
        for down in [true, false]:
            var ev := InputEventMouseButton.new()
            ev.button_index = MOUSE_BUTTON_LEFT
            ev.pressed = down
            ev.position = c
            ev.global_position = c
            get_viewport().push_input(ev)
        return true
    return false






