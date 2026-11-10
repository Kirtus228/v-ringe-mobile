extends CanvasLayer
## HUD: полоски здоровья/выносливости, таймер, очки и экраны поверх сцены.

const W := 1280.0
const ACCENT := Color(0.22, 0.74, 0.97)
const TEXT := Color(0.91, 0.93, 0.99)
const MUTED := Color(0.49, 0.53, 0.59)
const RED := Color(0.97, 0.44, 0.44)
const AMBER := Color(0.98, 0.75, 0.14)
const DARK := Color(0.035, 0.04, 0.055, 0.92)

const LookScript = preload("res://scripts/look.gd")
const GearScript = preload("res://scripts/gear.gd")
const Lang = preload("res://scripts/lang.gd")

var root: Control
var battle: Control
var overlay: Control

## Заставка меню (кадр боя) и обработчики кнопок мыши.
var splash_tex: Texture2D
var on_button: Callable
var on_tab: Callable
var gear: Control

var p_hp_fill: ColorRect
var p_stam_fill: ColorRect
var e_hp_fill: ColorRect
var e_stam_fill: ColorRect
var timer_lbl: Label
var score_lbl: Label
var hs_lbl: Label
var combo_lbl: Label
var chain_lbl: Label
var chain_bar: ColorRect
var chain_bg: ColorRect
var knockdown_lbl: Label
var training_lbl: Label

var font_n: SystemFont
var font_b: SystemFont


func build() -> void:
    font_n = SystemFont.new()
    font_n.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
    font_b = SystemFont.new()
    font_b.font_names = PackedStringArray(["Segoe UI", "Arial", "Noto Sans"])
    font_b.font_weight = 700

    root = Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(root)

    battle = Control.new()
    battle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(battle)

    _label(Lang.t("you"), 44, 26, 320, 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
    p_hp_fill = _bar(44, 44, 300, 16, ACCENT)
    p_stam_fill = _bar(44, 66, 300, 6, AMBER)

    _label(Lang.t("opponent"), 936, 26, 300, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, true)
    e_hp_fill = _bar(936, 44, 300, 16, RED)
    e_stam_fill = _bar(936, 66, 300, 6, AMBER)

    _label(Lang.t("round"), 540, 14, 200, 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
    timer_lbl = _label("1:30", 540, 30, 200, 40, TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)

    _label(Lang.t("score"), 44, 636, 200, 12, MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
    score_lbl = _label("0", 44, 656, 260, 26, TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
    hs_lbl = _label(Lang.t("record").to_upper() + " 0", 936, 660, 300, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, true)
    combo_lbl = _label("", 540, 604, 300, 18, AMBER, HORIZONTAL_ALIGNMENT_CENTER, true)

    chain_bg = ColorRect.new()
    chain_bg.position = Vector2(560, 126)
    chain_bg.size = Vector2(160, 4)
    chain_bg.color = Color(1, 1, 1, 0.12)
    chain_bg.visible = false
    chain_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(chain_bg)
    chain_bar = ColorRect.new()
    chain_bar.position = Vector2(560, 126)
    chain_bar.size = Vector2(160, 4)
    chain_bar.color = AMBER
    chain_bar.visible = false
    chain_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(chain_bar)
    chain_lbl = _label("", 540, 100, 200, 14, AMBER, HORIZONTAL_ALIGNMENT_CENTER, true)
    chain_lbl.visible = false

    knockdown_lbl = _label(Lang.t("knockdown"), 0, 200, W, 46, Color(0.98, 0.45, 0.35),
            HORIZONTAL_ALIGNMENT_CENTER, true)
    knockdown_lbl.visible = false

    training_lbl = _label(Lang.t("training_hud") + " · " + Lang.t("form").to_upper() + " 0 · "
            + Lang.t("exit_hint"), 0, 540, W, 20, AMBER,
            HORIZONTAL_ALIGNMENT_CENTER, true)
    training_lbl.visible = false

    overlay = Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.visible = false
    root.add_child(overlay)


# ---------------------------------------------------------------- helpers

func _label(text: String, x: float, y: float, w: float, size: int, col: Color,
        align: int = HORIZONTAL_ALIGNMENT_LEFT, bold: bool = false) -> Label:
    var l := Label.new()
    l.text = text
    l.position = Vector2(x, y)
    l.size = Vector2(w, float(size) * 1.6)
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.add_theme_font_override("font", font_b if bold else font_n)
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(l)
    return l


func _bar(x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
    var bg := ColorRect.new()
    bg.position = Vector2(x, y)
    bg.size = Vector2(w, float(h))
    bg.color = Color(1, 1, 1, 0.10)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(bg)
    var fill := ColorRect.new()
    fill.position = Vector2(x, y)
    fill.size = Vector2(w, float(h))
    fill.color = col
    fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(fill)
    return fill


func set_stats(php: float, pst: float, ehp: float, est: float) -> void:
    p_hp_fill.size.x = 300.0 * clampf(php, 0.0, 1.0)
    p_stam_fill.size.x = 300.0 * clampf(pst, 0.0, 1.0)
    var ew := 300.0 * clampf(ehp, 0.0, 1.0)
    e_hp_fill.size.x = maxf(0.0, ew)
    e_hp_fill.position.x = 936.0 + (300.0 - ew)
    e_stam_fill.size.x = 300.0 * clampf(est, 0.0, 1.0)


func set_timer(seconds: float) -> void:
    var s := maxi(0, ceili(seconds))
    timer_lbl.text = "%d:%02d" % [int(s / 60), s % 60]
    timer_lbl.add_theme_color_override("font_color", RED if seconds <= 10.0 else TEXT)


func set_score(value: int, combo: int, high: int) -> void:
    score_lbl.text = str(value)
    hs_lbl.text = Lang.t("record").to_upper() + " " + str(high)
    if combo >= 2:
        combo_lbl.text = "СЕРИЯ ×" + str(combo)
    else:
        combo_lbl.text = ""


# ---------------------------------------------------------------- экраны

func _clear_overlay() -> void:
    for c in overlay.get_children():
        c.queue_free()
    overlay.visible = true


func _overlay_label(text: String, x: float, y: float, w: float, size: int, col: Color,
        align: int = HORIZONTAL_ALIGNMENT_CENTER, bold: bool = true) -> Label:
    var l := Label.new()
    l.text = text
    l.position = Vector2(x, y)
    l.size = Vector2(w, float(size) * 1.5)
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.add_theme_font_override("font", font_b if bold else font_n)
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", col)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.55))
    l.add_theme_constant_override("shadow_offset_x", 1)
    l.add_theme_constant_override("shadow_offset_y", 2)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(l)
    return l


func _dim() -> void:
    var d := ColorRect.new()
    d.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    d.color = DARK
    d.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(d)


## Заставка: кадр боя на весь экран и плавное затемнение снизу под текст.
## Заставка: кадр боя на весь экран, затемнение из левого нижнего угла.
func _splash_bg() -> void:
    if splash_tex != null:
        var art := TextureRect.new()
        art.texture = splash_tex
        art.position = Vector2.ZERO
        art.size = Vector2(W, 720.0)
        art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
        art.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay.add_child(art)

        # мягкое затемнение из левого нижнего угла, где живут название и кнопка
        var grad := Gradient.new()
        grad.set_color(0, Color(0.008, 0.011, 0.020, 0.96))
        grad.set_color(1, Color(0.008, 0.011, 0.020, 0.0))
        grad.add_point(0.40, Color(0.008, 0.011, 0.020, 0.80))
        grad.add_point(0.70, Color(0.008, 0.011, 0.020, 0.28))
        var gt := GradientTexture2D.new()
        gt.gradient = grad
        gt.fill = GradientTexture2D.FILL_RADIAL
        gt.fill_from = Vector2(0.02, 1.03)
        gt.fill_to = Vector2(0.92, 0.02)
        gt.width = 256
        gt.height = 256
        var fade := TextureRect.new()
        fade.texture = gt
        fade.position = Vector2.ZERO
        fade.size = Vector2(W, 720.0)
        fade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        fade.stretch_mode = TextureRect.STRETCH_SCALE
        fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay.add_child(fade)

        # тонкая полоса снизу: под строку с клавишами
        var g2 := Gradient.new()
        g2.set_color(0, Color(0.008, 0.011, 0.020, 0.0))
        g2.set_color(1, Color(0.008, 0.011, 0.020, 0.85))
        var gt2 := GradientTexture2D.new()
        gt2.gradient = g2
        gt2.fill_from = Vector2(0.5, 0.80)
        gt2.fill_to = Vector2(0.5, 1.0)
        gt2.width = 8
        gt2.height = 128
        var fade2 := TextureRect.new()
        fade2.texture = gt2
        fade2.position = Vector2.ZERO
        fade2.size = Vector2(W, 720.0)
        fade2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        fade2.stretch_mode = TextureRect.STRETCH_SCALE
        fade2.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay.add_child(fade2)
    else:
        _dim()


## Заставка приходит из main после рендера сцены боя.
func set_splash(t: Texture2D) -> void:
    splash_tex = t


## Кнопка HUD. style: "cta" — большая жёлтая, "ghost" — маленькая тёмная.
func _btn(text: String, pos: Vector2, sz: Vector2, id: String, style: String = "ghost") -> Button:
    var b := Button.new()
    b.text = text
    b.position = pos
    b.size = sz
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_filter = Control.MOUSE_FILTER_STOP
    b.add_theme_font_override("font", font_b)
    var dark := Color(0.05, 0.045, 0.03)
    var normal := StyleBoxFlat.new()
    var hot := StyleBoxFlat.new()
    var press := StyleBoxFlat.new()
    if style == "cta":
        normal.bg_color = AMBER
        hot.bg_color = AMBER.lightened(0.14)
        press.bg_color = AMBER.darkened(0.10)
        b.add_theme_font_size_override("font_size", 30)
        b.add_theme_color_override("font_color", dark)
        b.add_theme_color_override("font_hover_color", dark)
        b.add_theme_color_override("font_pressed_color", dark)
    else:
        normal.bg_color = Color(0.02, 0.03, 0.05, 0.66)
        hot.bg_color = Color(0.05, 0.08, 0.12, 0.88)
        press.bg_color = Color(0.08, 0.12, 0.18, 0.95)
        b.add_theme_font_size_override("font_size", 13)
        b.add_theme_color_override("font_color", Color(0.86, 0.90, 0.97))
        b.add_theme_color_override("font_hover_color", TEXT)
        b.add_theme_color_override("font_pressed_color", TEXT)
    for sb in [normal, hot, press]:
        var s: StyleBoxFlat = sb
        s.corner_radius_top_left = 10 if style == "cta" else 6
        s.corner_radius_top_right = s.corner_radius_top_left
        s.corner_radius_bottom_left = s.corner_radius_top_left
        s.corner_radius_bottom_right = s.corner_radius_top_left
        if style != "cta":
            s.border_width_left = 1
            s.border_width_right = 1
            s.border_width_top = 1
            s.border_width_bottom = 1
            s.border_color = Color(1, 1, 1, 0.16)
    b.add_theme_stylebox_override("normal", normal)
    b.add_theme_stylebox_override("hover", hot)
    b.add_theme_stylebox_override("pressed", press)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.pressed.connect(func() -> void:
        if on_button.is_valid():
            on_button.call(id))
    overlay.add_child(b)
    return b


## Шестерёнка в правом верхнем углу: открывает окно настроек.
func _gear_button() -> void:
    gear = GearScript.new()
    gear.position = Vector2(1214, 20)
    gear.size = Vector2(46, 46)
    gear.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.add_child(gear)
    gear.pressed.connect(func() -> void:
        if on_button.is_valid():
            on_button.call("settings"))


## Кнопка «назад» в левом верхнем углу — общая для всех экранов, кроме меню и боя.
func _back_btn() -> Button:
    return _btn(Lang.t("back_btn"), Vector2(18, 12), Vector2(148, 42), "back_all")


## Прозрачная зона нажатия поверх строки списка: работает и мышью, и пальцем.
func _hit(x: float, y: float, w: float, h: float, id: String) -> Button:
    var b := Button.new()
    b.text = ""
    b.position = Vector2(x, y)
    b.size = Vector2(w, h)
    b.focus_mode = Control.FOCUS_NONE
    b.flat = true
    var empty := StyleBoxEmpty.new()
    for s in ["normal", "hover", "pressed", "focus", "disabled"]:
        b.add_theme_stylebox_override(s, empty)
    b.mouse_filter = Control.MOUSE_FILTER_STOP
    b.pressed.connect(func() -> void:
        if on_button.is_valid():
            on_button.call(id))
    overlay.add_child(b)
    return b


func show_menu(d: Dictionary) -> void:
    _clear_overlay()
    var k: Dictionary = d.get("keys", {})
    if k.is_empty():
        k = {"move": "WASD", "dodge": "SHIFT", "block": "L", "jab": "J",
            "hook_l": "K", "hook_r": "I", "upper": "U"}
    var high: int = int(d.get("high", 0))
    var coins: int = int(d.get("coins", 0))
    var form: int = int(d.get("form", 0))
    var lv: int = int(d.get("level", 0))
    var wins: int = int(d.get("wins", 0))
    var matches: int = int(d.get("matches", 0))
    var belt: int = int(d.get("belt", 0))
    var belt_wins: int = int(d.get("belt_wins", 0))
    var belt_name: String = String(d.get("belt_name", ""))
    var belt_col: Color = d.get("belt_color", AMBER)
    var belt_max: int = int(d.get("belt_max", 6))
    var belt_fights: int = int(d.get("belt_fights", 10))
    var champion: bool = bool(d.get("champion", false))

    _splash_bg()
    _gear_button()

    _overlay_label(Lang.t("version"), 48, 20, 420, 10, Color(0.62, 0.66, 0.74),
            HORIZONTAL_ALIGNMENT_LEFT, false)
    _btn(Lang.t("howto") + "  H", Vector2(1006, 20), Vector2(196, 40), "howto")
    _btn(Lang.t("exit"), Vector2(1142, 674), Vector2(104, 32), "exit")

    # название и обещание
    _overlay_label(Lang.t("title"), 46, 336, 620, 60, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
    _overlay_label(Lang.t("hook"), 50, 408, 660, 17, Color(0.88, 0.91, 0.97),
            HORIZONTAL_ALIGNMENT_LEFT, false)

    # карьера: пояс, десять соперников
    if champion:
        _overlay_label(Lang.t("champion"), 50, 452, 700, 15, AMBER,
                HORIZONTAL_ALIGNMENT_LEFT)
    else:
        _overlay_label(Lang.t("belt") + " " + str(belt + 1) + " " + Lang.t("of") + " "
                + str(belt_max) + " · " + belt_name, 50, 452, 700, 15, belt_col,
                HORIZONTAL_ALIGNMENT_LEFT)
    for i in belt_fights:
        var on := i < belt_wins or champion
        _overlay_rect(50 + i * 28, 482, 22, 10, belt_col if on else Color(1, 1, 1, 0.16))
    _overlay_label(str(mini(belt_wins, belt_fights)) + " / " + str(belt_fights), 50 + belt_fights * 28 + 4,
            474, 120, 13, Color(0.80, 0.84, 0.91), HORIZONTAL_ALIGNMENT_LEFT, false)

    _overlay_label(Lang.t("coins") + " " + str(coins) + " · " + Lang.t("form") + " "
            + str(form) + " · " + Lang.t("level") + " " + str(lv), 50, 506, 620, 12,
            Color(0.74, 0.78, 0.86), HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(Lang.t("wins") + " " + str(wins) + " / " + str(matches) + " · "
            + Lang.t("record") + " " + str(high), 50, 526, 620, 11, MUTED,
            HORIZONTAL_ALIGNMENT_LEFT, false)
    var tour_name := String(d.get("tour_name", ""))
    if tour_name != "":
        _overlay_label(Lang.t("tour") + ": " + tour_name + " · "
                + str(int(d.get("tour_wins", 0))) + " / 3", 50, 544, 620, 11,
                Color(0.72, 0.84, 0.98), HORIZONTAL_ALIGNMENT_LEFT, false)
    elif int(d.get("tour_done", 0)) > 0:
        _overlay_label(Lang.t("tour") + ": " + str(int(d.get("tour_done", 0))) + " / "
                + str(int(d.get("tour_total", 3))), 50, 544, 620, 11,
                Color(0.55, 0.86, 0.62), HORIZONTAL_ALIGNMENT_LEFT, false)

    # одно большое действие и пять маленьких
    _btn(Lang.t("play"), Vector2(46, 570), Vector2(340, 78), "play", "cta")
    _btn(Lang.t("locker") + "  C", Vector2(404, 586), Vector2(148, 46), "locker")
    _btn(Lang.t("upgrade") + "  P", Vector2(558, 586), Vector2(148, 46), "upgrade")
    _btn(Lang.t("training") + "  F", Vector2(712, 586), Vector2(148, 46), "training")
    _btn(Lang.t("tour") + "  G", Vector2(866, 586), Vector2(148, 46), "tour")
    _btn(Lang.t("story") + "  Y", Vector2(1020, 586), Vector2(148, 46), "story")

    var hint := Lang.t("controls_hint_touch") if bool(d.get("touch", false)) else Lang.t("controls_hint")
    _overlay_label(hint, 0, 690, W, 11, Color(0.56, 0.61, 0.70),
            HORIZONTAL_ALIGNMENT_CENTER, false)
    if bool(d.get("saved", false)):
        _overlay_label("✓ " + Lang.t("saved"), 50, 545, 620, 11, Color(0.55, 0.86, 0.62),
                HORIZONTAL_ALIGNMENT_LEFT, false)


## Карточка перед боем: тренер даёт совет, дальше — на ринг.
func show_prefight(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var tip := String(d.get("tip", ""))
    var belt: int = int(d.get("belt", 0))
    var belt_name := String(d.get("belt_name", ""))
    var belt_col: Color = d.get("belt_color", AMBER)
    var tour_txt := String(d.get("tour", ""))
    _overlay_label(Lang.t("coach").to_upper(), 0, 116, W, 14, AMBER)
    _overlay_rect(180, 150, 920, 132, Color(0.02, 0.03, 0.05, 0.88))
    _overlay_rect(180, 150, 920, 3, AMBER)
    _overlay_label("«" + tip + "»", 220, 186, 840, 20, Color(0.94, 0.96, 1.0),
            HORIZONTAL_ALIGNMENT_LEFT, false)
    var line := Lang.t("belt") + " " + str(belt + 1) + " · " + belt_name + " · "
    line += str(int(d.get("belt_wins", 0))) + " / " + str(int(d.get("belt_fights", 10)))
    _overlay_label(line, 0, 312, W, 14, belt_col)
    if tour_txt != "":
        _overlay_label(tour_txt, 0, 338, W, 14, Color(0.86, 0.90, 0.98))
    if bool(d.get("champion", false)):
        _overlay_label(Lang.t("champion"), 0, 364, W, 13, AMBER)
    _btn(Lang.t("fight"), Vector2(470, 396), Vector2(340, 72), "fight", "cta")
    var hint := Lang.t("prefight_hint_touch") if bool(d.get("touch", false)) else Lang.t("prefight_hint")
    _overlay_label(hint, 0, 486, W, 12, MUTED)


## Сюжетные турниры: список с условиями, наградой и статусом.
func show_tournaments(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var rows: Array = d.get("rows", [])
    var sel: int = int(d.get("sel", 0))
    var msg := String(d.get("msg", ""))
    _overlay_label(Lang.t("tournaments"), 0, 44, W, 28, AMBER)
    _overlay_rect(150, 96, 980, 360, Color(0.02, 0.03, 0.05, 0.86))
    for i in rows.size():
        var r: Dictionary = rows[i]
        var y := 120.0 + float(i) * 108.0
        if i == sel:
            _overlay_rect(162, y - 12, 956, 92, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14))
            _overlay_rect(162, y - 12, 4, 92, ACCENT)
        var open := bool(r["open"])
        var name_col := TEXT if open else Color(0.55, 0.60, 0.68)
        _overlay_label(String(r["name"]), 190, y, 420, 19, name_col, HORIZONTAL_ALIGNMENT_LEFT, true)
        _overlay_label(String(r["intro"]), 190, y + 30, 640, 12, MUTED,
                HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(r["reward"]), 190, y + 54, 420, 12, AMBER,
                HORIZONTAL_ALIGNMENT_LEFT, false)
        var tag := String(r["state"])
        var tag_col := Color(0.62, 0.86, 0.66) if bool(r["done"]) else (
                AMBER if tag == "" else Color(0.82, 0.86, 0.94))
        if bool(r["done"]):
            tag = Lang.t("tour_done") + " · " + str(int(r["fights"])) + "/" + str(int(r["fights"]))
        elif tag.begins_with("В ХОДЕ"):
            tag = tag.replace("В ХОДЕ", Lang.t("tour_progress").to_upper())
        _overlay_label(tag, 830, y + 8, 270, 13, tag_col, HORIZONTAL_ALIGNMENT_RIGHT, true)
        _hit(162, y - 12, 956, 92, "tourrow%d" % i)
    if msg != "":
        _overlay_label(msg, 0, 476, W, 14, AMBER)
    _btn(Lang.t("tour_start"), Vector2(470, 512), Vector2(340, 64), "tourstart", "cta")
    var thint := Lang.t("touch_tour_hint") if bool(d.get("touch", false)) else Lang.t("tour_hint")
    _overlay_label(thint, 0, 596, W, 12, MUTED)

## История: пролог и главы, открываются по поясам.
func show_story(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var pages: Array = d.get("pages", [])
    var sel: int = clampi(int(d.get("sel", 0)), 0, maxi(0, pages.size() - 1))
    var page: Dictionary = pages[sel] if pages.size() > 0 else {}
    _overlay_label(Lang.t("story"), 0, 40, W, 30, AMBER)
    var num := String(page.get("num", ""))
    var title := String(page.get("title", ""))
    var head: String = title
    if num != "":
        head = num + " · " + title
    _overlay_label(head, 0, 84, W, 16, Color(0.72, 0.78, 0.88))

    # лист с текстом: главы читаются как записка тренера
    _overlay_rect(120, 126, 1040, 396, Color(0.015, 0.02, 0.035, 0.90))
    _overlay_rect(120, 126, 1040, 3, AMBER)
    if bool(page.get("open", true)):
        var body := Label.new()
        body.text = String(page.get("text", ""))
        # обёртку включаем до размера: иначе Label растягивается под всю строку
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        body.position = Vector2(168, 164)
        body.size = Vector2(944, 330)
        body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
        body.add_theme_font_override("font", font_n)
        body.add_theme_font_size_override("font_size", 17)
        body.add_theme_constant_override("line_spacing", 9)
        body.add_theme_color_override("font_color", Color(0.92, 0.94, 0.99))
        body.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay.add_child(body)
    else:
        _overlay_label(Lang.t("story_locked") + " " + str(int(page.get("need", 1)) + 1),
                0, 280, W, 18, Color(0.72, 0.78, 0.88))
        _overlay_label("«" + title + "»", 0, 314, W, 15, MUTED, HORIZONTAL_ALIGNMENT_CENTER, false)

    # лента глав: точка на каждую, текущая — жёлтая
    var n: int = pages.size()
    var step := 26.0
    var x0 := W * 0.5 - (float(n - 1) * step) * 0.5
    for i in n:
        var open := bool(pages[i].get("open", true))
        var col := AMBER if i == sel else (Color(0.70, 0.76, 0.86) if open else Color(1, 1, 1, 0.14))
        _overlay_rect(x0 + float(i) * step - 4.0, 542, 8, 8, col)
    _overlay_label(Lang.t("story_hint"), 0, 566, W, 12, MUTED)
    _btn(Lang.t("back"), Vector2(578, 606), Vector2(124, 44), "storyback")
    # листание глав пальцем: тап по широким полосам слева и справа от листа
    _hit(20, 126, 92, 396, "storyprev")
    _hit(1168, 126, 92, 396, "storynext")


func show_pause() -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    _overlay_label(Lang.t("paused"), 0, 200, W, 44, TEXT)
    _btn(Lang.t("resume"), Vector2(540, 268), Vector2(200, 52), "resume")
    _btn(Lang.t("settings"), Vector2(540, 332), Vector2(200, 46), "settings")
    _btn(Lang.t("howto"), Vector2(540, 386), Vector2(200, 46), "howto")
    _btn(Lang.t("to_menu"), Vector2(540, 448), Vector2(200, 46), "tomenu")
    _overlay_label(Lang.t("pause_hint"), 0, 512, W, 12, MUTED)


## «Как играть»: раскладка и правила, без простыни на главном экране.
func show_howto(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var k: Dictionary = d.get("keys", {})
    if k.is_empty():
        k = {"move": "WASD", "dodge": "SHIFT", "block": "L", "jab": "J",
            "hook_l": "K", "hook_r": "I", "upper": "U"}
    _overlay_label(Lang.t("howto"), 0, 26, W, 28, AMBER)
    _overlay_label(Lang.t("howto_sub"), 0, 64, W, 12, MUTED)

    _overlay_rect(64, 104, 560, 232, Color(0.02, 0.03, 0.05, 0.86))
    _overlay_label(Lang.t("movement"), 88, 116, 300, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)

    if bool(d.get("touch", false)):
        _overlay_label(Lang.t("touch_move"), 88, 146, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(Lang.t("touch_punch"), 88, 180, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(Lang.t("touch_guard"), 88, 214, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label("ESC/«назад» — пауза и меню", 88, 256, 520, 12,
                Color(0.70, 0.75, 0.84), HORIZONTAL_ALIGNMENT_LEFT, false)
    else:
        _overlay_label(String(k["move"]) + " — шаг", 88, 146, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["dodge"]) + " — уклон", 88, 176, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["block"]) + " — блок (держать)", 88, 206, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["jab"]) + " — джеб    " + String(k["hook_l"]) + " — левый хук",
                88, 236, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["hook_r"]) + " — правый хук    " + String(k["upper"]) + " — апперкот",
                88, 266, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label("Enter / Space — в бой      C — гардероб      P — прокачка      F — тренировка",
                88, 300, 520, 12, Color(0.70, 0.75, 0.84), HORIZONTAL_ALIGNMENT_LEFT, false)

    _overlay_rect(656, 104, 560, 232, Color(0.02, 0.03, 0.05, 0.86))
    var y := 124.0
    for line in [Lang.t("howto_move"), Lang.t("howto_punch"), Lang.t("howto_rope"),
            Lang.t("howto_career"), Lang.t("howto_form")]:
        _overlay_label("•  " + line, 680, y, 520, 13, Color(0.84, 0.88, 0.95),
                HORIZONTAL_ALIGNMENT_LEFT, false)
        y += 42.0

    _btn(Lang.t("back"), Vector2(540, 372), Vector2(200, 48), "back")
    _overlay_label(Lang.t("howto_back"), 0, 436, W, 12, MUTED)


func show_ko(text: String) -> void:
    _clear_overlay()
    var l := _overlay_label(text, 0, 250, W, 84 if text.length() <= 4 else 64, AMBER)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
    l.add_theme_constant_override("shadow_offset_y", 4)


func show_result(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _gear_button()
    _back_btn()
    var kind := String(d.get("kind", "win"))
    var win: bool = kind == "win" or kind == "timewin" or kind == "ringout"
    var title := Lang.t("win")
    var sub := Lang.t("by_ko")
    var col := ACCENT
    if kind == "ringout":
        sub = Lang.t("by_rope")
    elif kind == "ringoutlose":
        title = Lang.t("lose")
        sub = Lang.t("you_rope")
        col = RED
    elif kind == "lose":
        title = Lang.t("lose")
        sub = Lang.t("by_ko")
        col = RED
    elif kind == "timelose":
        title = Lang.t("lose")
        sub = Lang.t("time_over")
        col = RED
    elif kind == "draw":
        title = Lang.t("draw")
        sub = Lang.t("even")
        col = Color(0.62, 0.66, 0.72)
    elif kind == "timewin":
        sub = Lang.t("by_time")

    _overlay_label(sub.to_upper(), 0, 70, W, 13, MUTED)
    _overlay_label(title, 0, 92, W, 58, col)
    var bonus: int = int(d.get("bonus", 0))
    if win and bonus > 0:
        _overlay_label("+" + str(bonus) + " " + Lang.t("win_bonus"), 0, 164, W, 14, AMBER)
    _overlay_label("+" + str(int(d.get("coin_gain", 0))) + " " + Lang.t("coin_gain"),
            0, 188, W, 17, AMBER)
    var fg: int = int(d.get("form_gain", 0))
    if fg > 0:
        _overlay_label("+" + str(fg) + " " + Lang.t("form_gain"), 0, 212, W, 14, ACCENT)

    # карьера: где ты по поясам
    var belt: int = int(d.get("belt", 0))
    var belt_wins: int = int(d.get("belt_wins", 0))
    var belt_name: String = String(d.get("belt_name", ""))
    var belt_col: Color = d.get("belt_color", AMBER)
    var champion: bool = bool(d.get("champion", false))
    if bool(d.get("belt_won", false)) and not champion:
        _overlay_label(Lang.t("belt_won").to_upper() + " · " + belt_name.to_upper(),
                0, 240, W, 16, AMBER)
    elif champion:
        _overlay_label(Lang.t("champion"), 0, 240, W, 16, AMBER)
    else:
        _overlay_label(Lang.t("belt") + " " + str(belt + 1) + " · " + belt_name + " · "
                + str(belt_wins) + " / " + str(int(d.get("belt_fights", 10))),
                0, 240, W, 14, belt_col)

    var tour_txt := String(d.get("tour", ""))
    if tour_txt != "":
        _overlay_label(tour_txt, 0, 536, W, 13, Color(0.86, 0.90, 0.98))
    var coach := String(d.get("coach", ""))
    if coach != "":
        _overlay_rect(160, 588, 960, 52, Color(0.02, 0.03, 0.05, 0.82))
        _overlay_rect(160, 588, 4, 52, AMBER)
        _overlay_label(Lang.t("coach").to_upper() + ": «" + coach + "»", 184, 596, 912, 13,
                Color(0.92, 0.94, 0.99), HORIZONTAL_ALIGNMENT_LEFT, false)
    var rows := [
        [Lang.t("coins"), str(int(d.get("coins_total", 0))), AMBER],
        [Lang.t("form"), str(int(d.get("form_total", 0))), ACCENT],
        [Lang.t("wins"), str(int(d.get("wins", 0))), TEXT],
        [Lang.t("score"), str(int(d.get("score", 0))), TEXT],
        ["HITS" if Lang.is_en() else "ПОПАДАНИЙ", str(int(d.get("hits", 0))), TEXT],
        ["TAKEN" if Lang.is_en() else "ПРОПУЩЕНО", str(int(d.get("taken", 0))), TEXT],
        ["HP" if Lang.is_en() else "ЗДОРОВЬЕ", str(int(d.get("hp", 0))), TEXT],
        [Lang.t("record"), str(int(d.get("high", 0))), TEXT],
    ]
    var y := 276.0
    for r in rows:
        _overlay_label(str(r[0]), 320, y, 300, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
        _overlay_label(str(r[1]), 660, y, 300, 17, r[2], HORIZONTAL_ALIGNMENT_LEFT)
        y += 34.0

    _btn(Lang.t("next_fight"), Vector2(260, 650), Vector2(300, 54), "play", "cta")
    _btn(Lang.t("to_menu"), Vector2(580, 656), Vector2(180, 42), "tomenu")


func set_knockdown(active: bool) -> void:
    if knockdown_lbl:
        knockdown_lbl.visible = active


func set_training(active: bool, form: int) -> void:
    if training_lbl == null:
        return
    training_lbl.visible = active
    if active:
        training_lbl.text = Lang.t("training_hud") + " · " + Lang.t("form").to_upper() + " " + str(form) + " · " + Lang.t("exit_hint")


func set_chain(value: int, remain: float) -> void:
    var show := value >= 2
    chain_lbl.visible = show
    chain_bg.visible = show
    chain_bar.visible = show
    if show:
        chain_lbl.text = "ЦЕПОЧКА ×" + str(value)
        chain_bar.size.x = 160.0 * clampf(remain / 0.55, 0.0, 1.0)


func set_battle_visible(v: bool) -> void:
    if battle:
        battle.visible = v


func _overlay_rect(x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
    var r := ColorRect.new()
    r.position = Vector2(x, y)
    r.size = Vector2(w, h)
    r.color = col
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(r)
    return r


## Гардероб: слева разделы (фасоны и цвета), справа варианты, в центре живой боец.
func show_locker(d: Dictionary) -> void:
    _clear_overlay()
    var cats: Array = LookScript.CATALOG
    var ci: int = clampi(int(d.get("cat", 0)), 0, cats.size() - 1)
    var owned: Array = d.get("owned", [])
    var look: Dictionary = d.get("look", {})
    var coins: int = int(d.get("coins", 0))
    var wins: int = int(d.get("wins", 0))
    var matches: int = int(d.get("matches", 0))
    var msg: String = String(d.get("msg", ""))
    var msg_col: Color = d.get("msg_col", AMBER)

    # фон под панели и подписи
    _overlay_rect(0, 0, W, 58, Color(0.02, 0.025, 0.04, 0.72))
    _overlay_rect(0, 638, W, 82, Color(0.02, 0.025, 0.04, 0.78))
    _overlay_rect(40, 62, 340, 566, Color(0.03, 0.04, 0.06, 0.88))
    _overlay_rect(900, 62, 340, 566, Color(0.03, 0.04, 0.06, 0.88))
    _overlay_rect(40, 62, 340, 2, Color(1, 1, 1, 0.12))
    _overlay_rect(900, 62, 340, 2, Color(1, 1, 1, 0.12))

    _overlay_label("ГАРДЕРОБ", 0, 14, W, 24, ACCENT)
    _overlay_label("МОНЕТ " + str(coins), 60, 20, 320, 17, AMBER, HORIZONTAL_ALIGNMENT_LEFT)
    _overlay_label("ПОБЕД " + str(wins) + " / " + str(matches), 900, 20, 320, 15, MUTED,
            HORIZONTAL_ALIGNMENT_RIGHT)

    # разделы
    _overlay_label("РАЗДЕЛЫ", 64, 70, 300, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
    for i in cats.size():
        var cat: Dictionary = cats[i]
        var cid := String(cat["id"])
        var y := 98.0 + float(i) * 44.0
        if i == ci:
            _overlay_rect(52, y - 6, 316, 38, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16))
            _overlay_rect(52, y - 6, 4, 38, ACCENT)
        var got := 0
        for it in cat["items"]:
            if owned.has(cid + ":" + String(it["id"])):
                got += 1
        var col := TEXT if i == ci else Color(0.66, 0.71, 0.80)
        _overlay_label(String(cat["name"]), 70, y, 250, 15, col, HORIZONTAL_ALIGNMENT_LEFT, i == ci)
        _overlay_label(str(got) + "/" + str(cat["items"].size()), 300, y + 2, 60, 10, MUTED,
                HORIZONTAL_ALIGNMENT_RIGHT)
        _hit(52, y - 6, 316, 38, "lockercat%d" % i)

    # варианты выбранного раздела
    var cat_now: Dictionary = cats[ci]
    var cid_now := String(cat_now["id"])
    var arr: Array = cat_now["items"]
    var color_sec := LookScript.is_color_section(cid_now)
    var oi: int = clampi(int(d.get("idx", 0)), 0, arr.size() - 1)
    _overlay_label(String(cat_now["name"]), 924, 70, 292, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
    for i in arr.size():
        var it: Dictionary = arr[i]
        var y := 98.0 + float(i) * 44.0
        var key := cid_now + ":" + String(it["id"])
        var have := owned.has(key)
        var equipped := String(look.get(cid_now, "")) == String(it["id"])
        if i == oi:
            _overlay_rect(912, y - 6, 316, 38, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16))
            _overlay_rect(912, y - 6, 4, 38, ACCENT)
        if color_sec:
            _overlay_rect(928, y, 22, 22, Color(1, 1, 1, 0.20))
            _overlay_rect(930, y + 2, 18, 18, it["col"])
        var col := TEXT if i == oi else Color(0.66, 0.71, 0.80)
        var name_x := 962.0 if color_sec else 930.0
        _overlay_label(String(it["name"]), name_x, y, 180, 15, col, HORIZONTAL_ALIGNMENT_LEFT, i == oi)
        var tag := ""
        var tag_col := MUTED
        if equipped:
            tag = "НАДЕТО"
            tag_col = ACCENT
        elif have:
            tag = "КУПЛЕНО"
            tag_col = Color(0.45, 0.85, 0.55)
        elif int(it["price"]) == 0:
            tag = "БЕСПЛАТНО"
            tag_col = Color(0.45, 0.85, 0.55)
        else:
            tag = str(it["price"]) + " очк."
            tag_col = AMBER if coins >= int(it["price"]) else RED
        _overlay_label(tag, 1060, y + 2, 150, 10, tag_col, HORIZONTAL_ALIGNMENT_RIGHT)
        _hit(912, y - 6, 316, 38, "lockeritem%d" % i)

    _overlay_label("очки дают за матчи: победа, нокдаун и вылет за канаты — дороже",
            924, 570, 292, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)

    if msg != "":
        _overlay_label(msg, 0, 642, W, 15, msg_col)
    var lhint := "↑↓ раздел      ←→ вариант      ENTER — надеть / купить      ESC — назад"
    if bool(d.get("touch", false)):
        lhint = Lang.t("touch_locker_hint")
    _overlay_label(lhint, 0, 678, W, 14, Color(0.72, 0.78, 0.88))
    _btn(Lang.t("back_btn"), Vector2(18, 664), Vector2(148, 42), "back_all")


## Окно настроек: вкладки «управление» и «звук», вызывается шестерёнкой.
func show_settings(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var tab: int = int(d.get("tab", 0))
    _overlay_label(Lang.t("settings"), 0, 18, W, 26, ACCENT)
    _overlay_label(Lang.t("settings_sub"), 0, 50, W, 12, MUTED)
    _gear_button()
    _tab_button(0, Lang.t("tab_keys"), 300.0, 226.0, tab == 0)
    _tab_button(1, Lang.t("tab_sound"), 534.0, 226.0, tab == 1)
    _tab_button(2, Lang.t("tab_game"), 768.0, 212.0, tab == 2)
    if tab == 0:
        _settings_keys(d)
    elif tab == 1:
        _settings_sound(d)
    else:
        _settings_game(d)


## Вкладка-кнопка: активная подчёркнута акцентом.
func _tab_button(idx: int, text: String, x: float, w: float, active: bool) -> void:
    var b := Button.new()
    b.text = text
    b.position = Vector2(x, 80)
    b.size = Vector2(w, 42)
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_override("font", font_b if active else font_n)
    b.add_theme_font_size_override("font_size", 14)
    b.add_theme_color_override("font_color", TEXT if active else MUTED)
    b.add_theme_color_override("font_hover_color", TEXT)
    b.add_theme_color_override("font_pressed_color", TEXT)
    var bg := StyleBoxFlat.new()
    bg.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.15) if active else Color(1, 1, 1, 0.05)
    bg.border_width_bottom = 3 if active else 1
    bg.border_color = ACCENT if active else Color(1, 1, 1, 0.10)
    bg.corner_radius_top_left = 5
    bg.corner_radius_top_right = 5
    bg.corner_radius_bottom_left = 5
    bg.corner_radius_bottom_right = 5
    var hot: StyleBoxFlat = bg.duplicate()
    hot.bg_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.26) if active else Color(1, 1, 1, 0.11)
    b.add_theme_stylebox_override("normal", bg)
    b.add_theme_stylebox_override("hover", hot)
    b.add_theme_stylebox_override("pressed", hot)
    b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
    b.mouse_filter = Control.MOUSE_FILTER_STOP
    b.pressed.connect(func() -> void:
        if on_button.is_valid():
            on_button.call("tab%d" % idx))
    overlay.add_child(b)


## Вкладка «управление»: два столбца действий с текущими клавишами.
func _settings_keys(d: Dictionary) -> void:
    var rows: Array = d.get("rows", [])
    var sel: int = int(d.get("sel", 0))
    var wait: bool = bool(d.get("wait", false))
    var msg: String = String(d.get("msg", ""))
    var msg_col: Color = d.get("msg_col", ACCENT)

    _overlay_rect(238, 144, 340, 380, Color(0.03, 0.04, 0.06, 0.80))
    _overlay_rect(702, 144, 340, 380, Color(0.03, 0.04, 0.06, 0.80))
    _overlay_label(Lang.t("movement"), 254, 152, 300, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(Lang.t("punches"), 718, 152, 300, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)

    for i in rows.size():
        var r: Dictionary = rows[i]
        var left := i < 6
        var col := 254.0 if left else 718.0
        var row := i if left else i - 6
        var y := 182.0 + float(row) * 44.0
        if i == sel:
            _overlay_rect(col - 12, y - 8, 320, 38, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16))
            _overlay_rect(col - 12, y - 8, 4, 38, ACCENT)
        _overlay_label(String(r["label"]), col, y, 220, 15, TEXT,
                HORIZONTAL_ALIGNMENT_LEFT, i == sel)
        _overlay_label("[" + String(r["key"]) + "]", col + 180, y, 110, 15, ACCENT,
                HORIZONTAL_ALIGNMENT_RIGHT)

    if wait:
        _overlay_rect(340, 292, 600, 118, Color(0.05, 0.06, 0.09, 0.97))
        _overlay_rect(340, 292, 600, 3, ACCENT)
        _overlay_label("НАЖМИ НОВУЮ КЛАВИШУ" if not Lang.is_en() else "PRESS A NEW KEY",
                0, 318, W, 22, AMBER)
        _overlay_label("ESC — отмена" if not Lang.is_en() else "ESC — cancel", 0, 358, W, 13, MUTED)

    if msg != "":
        _overlay_label(msg, 0, 536, W, 15, msg_col)
    _overlay_label(Lang.t("keys_hint"), 0, 586, W, 14, Color(0.72, 0.78, 0.88))
    _overlay_label(Lang.t("keys_tab_hint"), 0, 614, W, 11, MUTED)


## Вкладка «звук»: громкость музыки и звуков боя, 0..10.
func _settings_sound(d: Dictionary) -> void:
    var music: int = int(d.get("music", 7))
    var sfx_v: int = int(d.get("sfx", 9))
    var sel: int = int(d.get("sel", 0))

    _overlay_rect(238, 144, 804, 380, Color(0.03, 0.04, 0.06, 0.80))
    var names := [Lang.t("music"), Lang.t("sfx")]
    var vals := [music, sfx_v]
    for i in 2:
        var y := 250.0 + float(i) * 96.0
        if i == sel:
            _overlay_rect(268, y - 30, 744, 82, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14))
            _overlay_rect(268, y - 30, 4, 82, ACCENT)
        _overlay_label(names[i], 300, y - 12, 220, 20, TEXT, HORIZONTAL_ALIGNMENT_LEFT, i == sel)
        for b in 10:
            var on: bool = b < int(vals[i])
            _overlay_rect(556 + float(b) * 38, y - 8, 30, 24,
                    ACCENT if on else Color(1, 1, 1, 0.12))
            # тап по делению сразу ставит громкость
            _hit(556 + float(b) * 38, y - 8, 30, 24, "snd:%d:%d" % [i, b + 1])
        _overlay_label(str(vals[i]) + "/10", 944, y - 12, 80, 18, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)

    var shint := Lang.t("sound_hint")
    if bool(d.get("touch", false)):
        shint = Lang.t("touch_sound_hint")
    _overlay_label(shint, 0, 500, W, 14, Color(0.72, 0.78, 0.88))
    _overlay_label(Lang.t("sound_alive"), 0, 530, W, 12, MUTED)
    _overlay_label(Lang.t("back"), 0, 586, W, 14, Color(0.72, 0.78, 0.88))


## Вкладка «игра»: язык, полный экран, выход.
func _settings_game(d: Dictionary) -> void:
    var sel: int = int(d.get("sel", 0))
    var lang: String = String(d.get("lang", "ru"))
    var full: bool = bool(d.get("fullscreen", false))
    _overlay_rect(238, 144, 804, 380, Color(0.03, 0.04, 0.06, 0.80))
    var armed := bool(d.get("reset_armed", false))
    var names := [Lang.t("language"), Lang.t("fullscreen"), Lang.t("reset_progress")]
    var vals := ["РУССКИЙ" if lang == "ru" else "ENGLISH",
            Lang.t("on") if full else Lang.t("off"),
            Lang.t("reset_armed") if armed else "—"]
    for i in 3:
        var y := 186.0 + float(i) * 96.0
        var row_col := TEXT if i < 2 else (RED if armed else Color(0.86, 0.62, 0.62))
        if i == sel:
            _overlay_rect(268, y - 24, 744, 70, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14))
            _overlay_rect(268, y - 24, 4, 70, ACCENT)
        _overlay_label(names[i], 300, y - 8, 300, 20, row_col, HORIZONTAL_ALIGNMENT_LEFT, i == sel)
        _overlay_label(vals[i], 760, y - 8, 220, 18, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
        var sub := ""
        if i == 0:
            sub = Lang.t("lang_hint")
        elif i == 1:
            sub = Lang.t("full_hint")
        else:
            sub = "нажми ещё раз, чтобы стереть всё" if not Lang.is_en() else "press again to wipe everything"
        _overlay_label(sub, 300, y + 26, 600, 11, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
        _hit(268, y - 24, 744, 70, "gamerow%d" % i)
    var ghint := Lang.t("game_hint")
    if bool(d.get("touch", false)):
        ghint = Lang.t("touch_game_hint")
    _overlay_label(ghint, 0, 470, W, 14, Color(0.72, 0.78, 0.88))

## Прокачка за «форму»: пять параметров, четыре уровня, цена растёт.
func show_upgrades(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var rows: Array = d.get("rows", [])
    var sel: int = int(d.get("sel", 0))
    var form_v: int = int(d.get("form", 0))
    var msg: String = String(d.get("msg", ""))
    var msg_col: Color = d.get("msg_col", AMBER)

    _overlay_label("ПРОКАЧКА", 0, 26, W, 26, ACCENT)
    _overlay_label("форма — отдельная валюта: её дают бои и тренировка (F)", 0, 58, W, 12, MUTED)
    _overlay_label("ФОРМА: " + str(form_v), 0, 84, W, 20, AMBER)

    _overlay_rect(184, 126, 912, 396, Color(0.03, 0.04, 0.06, 0.86))
    for i in rows.size():
        var r: Dictionary = rows[i]
        var y := 150.0 + float(i) * 72.0
        if i == sel:
            _overlay_rect(196, y - 10, 888, 62, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14))
            _overlay_rect(196, y - 10, 4, 62, ACCENT)
        _overlay_label(String(r["name"]), 216, y, 210, 18, TEXT, HORIZONTAL_ALIGNMENT_LEFT, i == sel)
        _overlay_label(String(r["desc"]), 430, y + 2, 380, 12, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
        # уровень: квадратики
        var lvl: int = int(r["lvl"])
        var lmax: int = int(r["max"])
        for b in lmax:
            _overlay_rect(216 + float(b) * 26, y + 26, 20, 10,
                    ACCENT if b < lvl else Color(1, 1, 1, 0.12))
        var cost: int = int(r["cost"])
        var tag := "МАКС"
        var tag_col := MUTED
        if lvl < lmax:
            tag = str(cost) + " формы"
            tag_col = AMBER if form_v >= cost else RED
        _overlay_label(tag, 940, y, 140, 15, tag_col, HORIZONTAL_ALIGNMENT_RIGHT)
        _overlay_label("ур. " + str(lvl) + "/" + str(lmax), 830, y + 24, 100, 10, MUTED,
                HORIZONTAL_ALIGNMENT_RIGHT)
        _hit(196, y - 10, 888, 62, "upgrow%d" % i)

    if msg != "":
        _overlay_label(msg, 0, 540, W, 15, msg_col)
    var uhint := "↑↓ — выбрать      ENTER — купить уровень      ESC — назад"
    if bool(d.get("touch", false)):
        uhint = Lang.t("touch_upg_hint")
    _overlay_label(uhint, 0, 580, W, 14, Color(0.72, 0.78, 0.88))
    _overlay_label("форму дают: попадания в тренировке (2 за удар, 4 в голову) и каждый бой",
            0, 612, W, 11, MUTED)


func hide_overlay() -> void:
    overlay.visible = false
    for c in overlay.get_children():
        c.queue_free()
