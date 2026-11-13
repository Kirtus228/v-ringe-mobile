extends CanvasLayer
## HUD: полоски здоровья/выносливости, таймер, очки и экраны поверх сцены.

const W := 1280.0
const ACCENT := Color(0.22, 0.74, 0.97)
const TEXT := Color(0.91, 0.93, 0.99)
const MUTED := Color(0.49, 0.53, 0.59)
const RED := Color(0.97, 0.44, 0.44)
const AMBER := Color(0.98, 0.75, 0.14)
const DARK := Color(0.035, 0.04, 0.055, 0.92)

# ------------------------------------------------------------ адаптивная раскладка (v30)
# Меню и «История» раскладываются от фактической канвы и безопасной зоны, а не
# от жёсткой сетки 1280×720. На 16:9 координаты совпадают со старыми, на
# 18:9/19.5:9/20:9 кнопки получают больше места и не наезжают друг на друга.
const BASE_H := 720.0
## Правый край рядов меню: 1280 − 1168 (как было в v29).
const MENU_ROW_RIGHT := 112.0
## Левый край большого действия «ИГРАТЬ».
const MENU_LEFT := 46.0
const MENU_PLAY_W := 340.0
const MENU_PLAY_H := 78.0
## Щель между кнопками одного ряда.
const MENU_GAP := 6.0
## Запас внутри кнопки по ширине (кроме текста).
const BTN_TEXT_PAD := 16.0
## Во сколько раз можно растянуть кнопки меню на широкой канве.
const MENU_SCALE_MAX := 1.35
const BTN_FONT := 13
const CTA_FONT := 30
## T6: на телефоне кегли и зоны нажатия крупнее (иначе палец промахивается).
const BTN_FONT_TOUCH := 17
const CTA_FONT_TOUCH := 34
## T6: минимальная высота интерактивного элемента на тач-экране, единицы канвы.
## 96 единиц при content scale 1.5 на xhdpi-телефоне = 48 dp.
const TOUCH_MIN := 96.0
## Кнопка не должна становиться уже, чем её текст даже на минимальном кегле.
const BTN_FONT_MIN := 10
## История: ширина «листа» при 1280×720 и максимум на широкой канве.
const STORY_PANEL_MIN := 1040.0
const STORY_PANEL_MAX := 1240.0
const STORY_PANEL_MARGIN := 240.0
## Номера глав (чипы) внизу истории.
const STORY_CHIP_W := 44.0
const STORY_CHIP_H := 30.0
const STORY_CHIP_GAP := 8.0
## Стрелки-зоны листания слева и справа от листа.
const STORY_ARROW_W := 72.0
const STORY_ARROW_H := 120.0
## Сколько пикселей нужно протащить пальцем, чтобы перелистнуть главу.
const STORY_SWIPE_DIST := 58.0
## Скорость пальца (px/с), при которой листаем даже на коротком свайпе.
const STORY_SWIPE_VEL := 640.0
## Анимация смены главы.
const STORY_ANIM_TIME := 0.16
const STORY_DRAG_FOLLOW := 0.35
const STORY_DRAG_MAX := 70.0

const TouchScript = preload("res://scripts/touch.gd")
const LookScript = preload("res://scripts/look.gd")
const GearScript = preload("res://scripts/gear.gd")
const Lang = preload("res://scripts/lang.gd")

var root: Control
var battle: Control
## v71l: слой подъёма после нокдауна. В коопе battle скрыт (свой HUD), а панель
## «ВСТАТЬ» должна быть видна — поэтому она живёт отдельно и не гаснет вместе с battle.
var getup_root: Control
## v71m: какие кнопки реально попали в меню (для теста «в вебе/на телефоне нет
## сети и коопа»): {"row1": [...], "row2": [...], "net_ui": bool}.
var menu_rows_debug: Dictionary = {}
var overlay: Control

## T3: имя героя. Читается из SaveManager (секция profile/player_name),
## в бою показывается вместо «ТЫ», в настройках редактируется.
var you_lbl: Label
var name_edit: LineEdit
var name_msg_lbl: Label
var name_msg := ""
var name_msg_t := 0.0

## T6: тач-режим интерфейса. Определяется один раз по платформе, а экраны,
## куда main передаёт "touch" (меню/настройки/история/…), могут его включить
## при запуске с --touch на ПК (эмуляция телефона).
var touch_mode := false

## Заставка меню (кадр боя) и обработчики кнопок мыши.
var splash_tex: Texture2D
var on_button: Callable
var on_tab: Callable
var gear: Control

## Сдвиг 16:9-кадра на широкой канве (бой, старые экраны). При 1280×720 — ноль.
var stage_off := Vector2.ZERO
## true — экран рисуется на всю канву сам (меню и история), false — в 16:9-кадре.
var _wide := false
## Безопасные зоны в единицах канвы: x=слева, y=сверху, z=справа, w=снизу.
var _safe := Vector4.ZERO
## Контейнер текста главы: его двигаем пальцем и анимируем при листании.
var story_page: Control
var story_tween: Tween
var _story_base_y := 0.0
## Безопасные зоны, заданные флагом --safeinset=L,T,R,B (для кадров гейта).
var _safe_override := Vector4(-1, -1, -1, -1)

var p_hp_fill: ColorRect
var p_stam_fill: ColorRect
var e_hp_fill: ColorRect
var e_stam_fill: ColorRect
var timer_lbl: Label
var round_lbl: Label
var score_lbl: Label
var hs_lbl: Label
var combo_lbl: Label
var chain_lbl: Label
var chain_bar: ColorRect
var chain_bg: ColorRect
var knockdown_lbl: Label
var getup_lbl: Label
var getup_time_lbl: Label
var mash_bg: ColorRect
var mash_bar: ColorRect
var mash_lbl: Label
## v71p: индикатор окна неуязвимости после подъёма с нокдауна.
var invuln_lbl: Label
var rest_time_lbl: Label
var training_lbl: Label
var opp_lbl: Label

## Плавное восстановление полоски здоровья после подъёма: пока идёт tween,
## рисуем это значение, затем снова берём настоящий HP.
var p_hp_show := -1.0
var e_hp_show := -1.0
var hp_tween: Tween

var font_n: SystemFont
var font_b: SystemFont


func build() -> void:
    touch_mode = _detect_touch()
    # T6: аудит мобильного UI. Если запущен без --touch, на время теста создаём
    # тач-слой сами — иначе --mobiletest на ПК ничего не проверит.
    if OS.get_cmdline_user_args().has("--mobiletest") and not touch_mode \
            and not OS.get_cmdline_user_args().has("--touch"):
        touch_mode = true
        var ts := TouchScript.new()
        add_child(ts)
        ts.build()
    # task-47: аудит кнопок (прозвон всех экранов) — только по флагу
    if OS.get_cmdline_user_args().has("--btnaudit"):
        call_deferred("_run_btnaudit")
    for a in OS.get_cmdline_user_args():
        if a.begins_with("--safeinset="):
            var sp := a.substr(12).split(",")
            if sp.size() == 4:
                _safe_override = Vector4(float(sp[0]), float(sp[1]), float(sp[2]), float(sp[3]))
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
    battle.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(battle)

    # v71l: отдельный контейнер для панели «ВСТАТЬ» (иначе в коопе она скрыта
    # вместе с battle: заказчик на ПК не видел кнопки подъёма).
    getup_root = Control.new()
    getup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    getup_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    root.add_child(getup_root)

    you_lbl = _label(Lang.t("you"), 44, 26, 320, 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT, true)
    refresh_player_name()
    p_hp_fill = _bar(44, 44, 300, 16, ACCENT)
    p_stam_fill = _bar(44, 66, 300, 6, AMBER)

    opp_lbl = _label(Lang.t("opponent"), 936, 26, 300, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, true)
    e_hp_fill = _bar(936, 44, 300, 16, RED)
    e_stam_fill = _bar(936, 66, 300, 6, AMBER)

    round_lbl = _label(Lang.t("round"), 540, 14, 200, 12, MUTED, HORIZONTAL_ALIGNMENT_CENTER, true)
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

    knockdown_lbl = _label(Lang.t("knockdown"), 0, 168, W, 46, Color(0.98, 0.45, 0.35),
            HORIZONTAL_ALIGNMENT_CENTER, true)
    knockdown_lbl.visible = false

    # подсказка и обратный отсчёт на подъём: включаются только в состоянии downed
    getup_lbl = _label(Lang.t("get_up_hint"), 0, 236, W, 26, Color(0.98, 0.86, 0.45),
            HORIZONTAL_ALIGNMENT_CENTER, true)
    getup_lbl.visible = false
    getup_time_lbl = _label("", 0, 278, W, 36, TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
    getup_time_lbl.visible = false

    # прогресс «расжатия»: сколько нажатий Space уже есть
    mash_bg = ColorRect.new()
    mash_bg.position = Vector2(480, 340)
    mash_bg.size = Vector2(320, 10)
    mash_bg.color = Color(1, 1, 1, 0.14)
    mash_bg.visible = false
    mash_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(mash_bg)
    mash_bar = ColorRect.new()
    mash_bar.position = Vector2(480, 340)
    mash_bar.size = Vector2(0, 10)
    mash_bar.color = AMBER
    mash_bar.visible = false
    mash_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    battle.add_child(mash_bar)
    mash_lbl = _label("", 0, 352, W, 16, AMBER, HORIZONTAL_ALIGNMENT_CENTER, true)
    mash_lbl.visible = false
    # v71p: индикатор окна неуязвимости после подъёма («НЕУЯЗВИМ 1.8 с»)
    invuln_lbl = _label("", 0, 200, W, 20, Color(0.55, 0.78, 1.0),
            HORIZONTAL_ALIGNMENT_CENTER, true)
    invuln_lbl.visible = false
    # v71l: переносим панель подъёма в отдельный слой (видна и в коопе)
    for n in [getup_lbl, getup_time_lbl, mash_bg, mash_bar, mash_lbl, invuln_lbl]:
        (n as Node).reparent(getup_root)

    training_lbl = _label(Lang.t("training_hud") + " · " + Lang.t("form").to_upper() + " 0 · "
            + Lang.t("exit_hint"), 0, 540, W, 20, AMBER,
            HORIZONTAL_ALIGNMENT_CENTER, true)
    training_lbl.visible = false

    overlay = Control.new()
    overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    overlay.visible = false
    root.add_child(overlay)

    # канва может быть шире 16:9 (телефон): бой и старые экраны держим в
    # центральном 16:9-кадре, меню и история считают раскладку сами
    if not get_viewport().size_changed.is_connected(_refresh_layout):
        get_viewport().size_changed.connect(_refresh_layout)
    _refresh_layout()


# ---------------------------------------------------------------- helpers

# ---------------------------------------------------------------- раскладка

## Размер канвы в единицах интерфейса (1280×720 на 16:9, шире/выше на телефоне).
func _canvas() -> Vector2:
    var s := get_viewport().get_visible_rect().size
    if s.x <= 0.0 or s.y <= 0.0:
        return Vector2(W, BASE_H)
    return s


## Безопасные зоны (вырез, закругления, полоса жестов) в единицах канвы.
## Считаем их только на телефоне (APK): на десктопе окно может быть больше
## экрана и «безопасная зона» начала бы ложно сжимать интерфейс.
## Для кадров гейта зоны можно подставить вручную: --safeinset=L,T,R,B.
func _safe_insets(cs: Vector2) -> Vector4:
    if _safe_override.x >= 0.0:
        return _safe_override
    if DisplayServer.get_name() == "headless" or not OS.has_feature("mobile"):
        return Vector4.ZERO
    var win_size := Vector2(DisplayServer.window_get_size())
    var scr_size := Vector2(DisplayServer.screen_get_size())
    if win_size.x <= 0.0 or win_size.y <= 0.0:
        return Vector4.ZERO
    if win_size.x > scr_size.x + 1.0 or win_size.y > scr_size.y + 1.0:
        return Vector4.ZERO
    var scale := win_size.x / cs.x if cs.x > 0.0 else 1.0
    if scale <= 0.001:
        return Vector4.ZERO
    var win_pos := Vector2(DisplayServer.window_get_position())
    var safe := DisplayServer.get_display_safe_area()
    var left := maxf(0.0, float(safe.position.x) - win_pos.x)
    var top := maxf(0.0, float(safe.position.y) - win_pos.y)
    var right := maxf(0.0, (win_pos.x + win_size.x) - float(safe.position.x + safe.size.x))
    var bottom := maxf(0.0, (win_pos.y + win_size.y) - float(safe.position.y + safe.size.y))
    return Vector4(left / scale, top / scale, right / scale, bottom / scale)


## Пересчитать 16:9-кадр и безопасные зоны. Вызывается на старте и при ресайзе.
func _refresh_layout() -> void:
    var cs := _canvas()
    stage_off = Vector2(maxf(0.0, (cs.x - W) * 0.5), maxf(0.0, (cs.y - BASE_H) * 0.5))
    _safe = _safe_insets(cs)
    if battle != null:
        battle.set_anchors_preset(Control.PRESET_TOP_LEFT)
        battle.position = stage_off
        battle.size = Vector2(W, BASE_H)
    # v71l: слой панели «ВСТАТЬ» живёт вне battle, но должен держать тот же
    # 16:9-кадр — иначе на телефоне (канва шире кадра) панель уезжает в угол.
    if getup_root != null:
        getup_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
        getup_root.position = stage_off
        getup_root.size = Vector2(W, BASE_H)


## Позиция элемента старого 16:9-экрана (в меню/истории — как передали).
func _pos(x: float, y: float) -> Vector2:
    if _wide:
        return Vector2(x, y)
    # v71: по вертикали кадр не сдвигаем — на вертикальной канве (портрет)
    # stage_off.y огромный, и подписи/кнопки уезжали от панелей, которые рисуются
    # без сдвига. Горизонтальный сдвиг нужен только на широкой канве (20:9).
    return Vector2(x + stage_off.x, y)


## Ширина текста кнопки на нужном кегле.
func _text_w(text: String, size: int) -> float:
    return font_b.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## Кегль, при котором текст влезает в ширину кнопки (иначе кнопка «наезжает»).
func _fit_font(b: Button, text: String, base: int, width: float) -> void:
    var size := base
    var limit := maxf(width - BTN_TEXT_PAD, 8.0)
    while size > BTN_FONT_MIN and _text_w(text, size) > limit:
        size -= 1
    b.add_theme_font_size_override("font_size", size)


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
    var pr := clampf(php, 0.0, 1.0)
    if p_hp_show >= 0.0:
        pr = p_hp_show
    var er := clampf(ehp, 0.0, 1.0)
    if e_hp_show >= 0.0:
        er = e_hp_show
    p_hp_fill.size.x = 300.0 * pr
    p_stam_fill.size.x = 300.0 * clampf(pst, 0.0, 1.0)
    var ew := 300.0 * er
    e_hp_fill.size.x = maxf(0.0, ew)
    e_hp_fill.position.x = 936.0 + (300.0 - ew)
    e_stam_fill.size.x = 300.0 * clampf(est, 0.0, 1.0)


## Восстановление HP после подъёма: полоска доезжает плавно, без рывка.
func animate_hp(ratio: float, as_player: bool = true, dur: float = 0.5) -> void:
    if hp_tween != null and hp_tween.is_valid():
        hp_tween.kill()
    var target := clampf(ratio, 0.0, 1.0)
    hp_tween = create_tween()
    if as_player:
        if p_hp_show < 0.0:
            p_hp_show = p_hp_fill.size.x / 300.0
        hp_tween.tween_property(self, "p_hp_show", target, dur)
        hp_tween.tween_callback(func() -> void: p_hp_show = -1.0)
    else:
        if e_hp_show < 0.0:
            e_hp_show = e_hp_fill.size.x / 300.0
        hp_tween.tween_property(self, "e_hp_show", target, dur)
        hp_tween.tween_callback(func() -> void: e_hp_show = -1.0)


func reset_hp_anim() -> void:
    if hp_tween != null and hp_tween.is_valid():
        hp_tween.kill()
    hp_tween = null
    p_hp_show = -1.0
    e_hp_show = -1.0
    set_hp_dim(false)


## Затемнить полоску здоровья, пока боец лежит.
func set_hp_dim(on: bool) -> void:
    var a := 0.30 if on else 1.0
    if p_hp_fill:
        p_hp_fill.modulate = Color(1, 1, 1, a)
    if p_stam_fill:
        p_stam_fill.modulate = Color(1, 1, 1, a)


## Подсказка «Нажмите Space» и отсчёт: показываются только в состоянии downed.
func set_downed(active: bool, hint: String = "") -> void:
    if getup_lbl == null:
        return
    getup_lbl.visible = active
    getup_time_lbl.visible = active
    if active and hint != "":
        getup_lbl.text = hint
    if not active:
        if getup_time_lbl:
            getup_time_lbl.text = ""
        set_mash(false, 0.0, 0, 1)


## Прогресс активного подъёма: полоска и счётчик нажатий.
func set_mash(active: bool, progress: float, done: int = 0, need: int = 1) -> void:
    if mash_bg == null:
        return
    mash_bg.visible = active
    mash_bar.visible = active
    mash_lbl.visible = active
    if not active:
        return
    mash_bar.size.x = 320.0 * clampf(progress, 0.0, 1.0)
    mash_lbl.text = "%s  %d/%d" % [Lang.t("get_up_mash"), done, need]
    mash_lbl.add_theme_color_override("font_color", AMBER if progress < 1.0 else ACCENT)


## Текст вида «Встать: 7.3 с»; последние 3 секунды — красным.
func set_downed_time(seconds: float) -> void:
    if getup_time_lbl == null or not getup_time_lbl.visible:
        return
    var s := maxf(seconds, 0.0)
    getup_time_lbl.text = "%s: %.1f с" % [Lang.t("get_up_countdown"), s]
    getup_time_lbl.add_theme_color_override("font_color", RED if s <= 3.0 else TEXT)


## v71p: окно неуязвимости после подъёма. Показываем «НЕУЯЗВИМ 1.8 с»,
## чтобы игрок понимал, что 2 секунды его не могут ударить.
func set_invuln(seconds: float) -> void:
    if invuln_lbl == null:
        return
    var s := maxf(seconds, 0.0)
    invuln_lbl.visible = s > 0.05
    if invuln_lbl.visible:
        invuln_lbl.text = Lang.t("invuln") % s


func set_opponent_name(name: String) -> void:
    opp_lbl.text = name if name != "" else Lang.t("opponent")


# ---------------------------------------------------------------- имя героя (T3)

## Имя для интерфейса: пустое → «ТЫ»/«YOU» по языку (аварийный фолбэк;
## обычно SaveManager.player_name() уже отдаёт «Искра» или сохранённое имя).
func display_name(raw: String) -> String:
    var n := raw.strip_edges()
    return n if n != "" else Lang.t("you")


## Текущее имя из сейва (без подсказок из main.gd).
func current_player_name() -> String:
    var raw := ""
    if SaveManager != null:
        raw = String(SaveManager.player_name())
    return display_name(raw)


## Перечитать имя и обновить надпись в бою (вызывается при старте, смене языка
## и после сохранения в настройках).
func refresh_player_name() -> void:
    if you_lbl != null:
        you_lbl.text = current_player_name()


## Текст надписи игрока (для автотеста T3).
func player_label_text() -> String:
    return you_lbl.text if you_lbl != null else ""


## Сохранить имя из поля настроек: санитайз + сейв + обновление HUD.
func _save_player_name() -> void:
    if name_edit == null:
        return
    var saved := ""
    if SaveManager != null:
        saved = String(SaveManager.set_player_name(name_edit.text))
    name_edit.text = saved
    refresh_player_name()
    name_msg = Lang.t("name_saved") + ": " + saved
    name_msg_t = 2.5
    if name_msg_lbl != null:
        name_msg_lbl.text = name_msg
        name_msg_lbl.add_theme_color_override("font_color", Color(0.55, 0.86, 0.62))


func set_timer(seconds: float, rnd: int = 0, total: int = 0) -> void:
    var s := maxi(0, ceili(seconds))
    timer_lbl.text = "%d:%02d" % [int(s / 60), s % 60]
    timer_lbl.add_theme_color_override("font_color", RED if seconds <= 10.0 else TEXT)
    if round_lbl:
        if total > 1:
            round_lbl.text = "%s %d/%d" % [Lang.t("round"), rnd, total]
        else:
            round_lbl.text = Lang.t("round")


func set_score(value: int, combo: int, high: int) -> void:
    score_lbl.text = str(value)
    # v51: версия видна и в бою (мелко, справа снизу) — по скриншоту сразу понятно,
    # какая сборка стоит на устройстве
    hs_lbl.text = Lang.t("record").to_upper() + " " + str(high) + " · " \
            + Lang.t("version").get_slice("·", 1).strip_edges()
    if combo >= 2:
        combo_lbl.text = "СЕРИЯ ×" + str(combo)
    else:
        combo_lbl.text = ""


# ---------------------------------------------------------------- экраны

func _clear_overlay() -> void:
    for c in overlay.get_children():
        c.queue_free()
    overlay.visible = true
    _wide = false
    story_page = null
    name_edit = null
    name_msg_lbl = null


func _overlay_label(text: String, x: float, y: float, w: float, size: int, col: Color,
        align: int = HORIZONTAL_ALIGNMENT_CENTER, bold: bool = true) -> Label:
    var l := Label.new()
    l.text = text
    l.position = _pos(x, y)
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
    var cs := _canvas()
    if splash_tex != null:
        var art := TextureRect.new()
        art.texture = splash_tex
        art.position = Vector2.ZERO
        art.size = cs
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
        fade.size = cs
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
        fade2.size = cs
        fade2.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
        fade2.stretch_mode = TextureRect.STRETCH_SCALE
        fade2.mouse_filter = Control.MOUSE_FILTER_IGNORE
        overlay.add_child(fade2)
    else:
        _dim()


## Заставка приходит из main после рендера сцены боя.
func set_splash(t: Texture2D) -> void:
    splash_tex = t


## T6: платформа тач? (Android/iOS). Для эмуляции телефона на ПК есть --touch:
## main передаёт "touch" в данных экранов, show_menu включает touch_mode.
func _detect_touch() -> bool:
    # --touch на ПК — это стенд «как телефон»: раскладка/подписи как на Android
    return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available() \
            or OS.get_cmdline_user_args().has("--touch")


## T6: экран сейчас в тач-режиме? main передаёт "touch", плюс общий touch_mode
## (включён на телефоне или тестом --mobiletest на ПК).
func _is_touch(d: Dictionary) -> bool:
    return bool(d.get("touch", false)) or touch_mode


## T6: минимальная высота интерактивного элемента для тач-режима.
func _touch_h(default_h: float) -> float:
    return maxf(default_h, TOUCH_MIN) if touch_mode else default_h


## Кнопка HUD. style: "cta" — большая жёлтая, "ghost" — маленькая тёмная.
func _btn(text: String, pos: Vector2, sz: Vector2, id: String, style: String = "ghost") -> Button:
    var b := Button.new()
    b.text = text
    b.position = _pos(pos.x, pos.y)
    b.focus_mode = Control.FOCUS_NONE
    b.mouse_filter = Control.MOUSE_FILTER_STOP
    b.clip_text = true
    b.add_theme_font_override("font", font_b)
    # T6: на тач-экране кегль крупнее; _fit_font всё равно не даст тексту вылезти
    var base_font := (CTA_FONT_TOUCH if style == "cta" else BTN_FONT_TOUCH) \
            if touch_mode else (CTA_FONT if style == "cta" else BTN_FONT)
    var dark := Color(0.05, 0.045, 0.03)
    var normal := StyleBoxFlat.new()
    var hot := StyleBoxFlat.new()
    var press := StyleBoxFlat.new()
    if style == "cta":
        normal.bg_color = AMBER
        hot.bg_color = AMBER.lightened(0.14)
        press.bg_color = AMBER.darkened(0.10)
        b.add_theme_font_size_override("font_size", base_font)
        b.add_theme_color_override("font_color", dark)
        b.add_theme_color_override("font_hover_color", dark)
        b.add_theme_color_override("font_pressed_color", dark)
    else:
        normal.bg_color = Color(0.02, 0.03, 0.05, 0.66)
        hot.bg_color = Color(0.05, 0.08, 0.12, 0.88)
        press.bg_color = Color(0.08, 0.12, 0.18, 0.95)
        b.add_theme_font_size_override("font_size", base_font)
        b.add_theme_color_override("font_color", Color(0.86, 0.90, 0.97))
        b.add_theme_color_override("font_hover_color", TEXT)
        b.add_theme_color_override("font_pressed_color", TEXT)
    for sb in [normal, hot, press]:
        var s: StyleBoxFlat = sb
        s.corner_radius_top_left = 10 if style == "cta" else 6
        s.corner_radius_top_right = s.corner_radius_top_left
        s.corner_radius_bottom_left = s.corner_radius_top_left
        s.corner_radius_bottom_right = s.corner_radius_top_left
        # поля внутри кнопки фиксируем сами: иначе min-размер кнопки берёт их
        # из темы и кнопка вырастает шире слота (это и был «наезд» в меню)
        s.content_margin_left = BTN_TEXT_PAD * 0.5
        s.content_margin_right = BTN_TEXT_PAD * 0.5
        s.content_margin_top = 5.0
        s.content_margin_bottom = 5.0
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
    # длина текста проверяется по факту: раньше кнопка «БОЕВЫЕ ЛОКАЦИИ» вырастала
    # из слота 148 до 179 и залезала на соседнюю
    _fit_font(b, text, base_font, sz.x)
    # размер ставим последним: до своих stylebox min-ширина кнопки считается
    # по теме (текст+поля) и Control «раздувает» кнопку шире слота
    b.size = sz
    b.pressed.connect(func() -> void:
        if on_button.is_valid():
            on_button.call(id))
    overlay.add_child(b)
    # после входа в дерево min-размер пересчитывается уже по нашим stylebox —
    # ставим размер ещё раз, иначе кнопка остаётся раздутой
    b.size = sz
    return b


## Шестерёнка в правом верхнем углу: открывает окно настроек.
func _gear_button(x: float = 1214.0, y: float = 20.0) -> void:
    gear = GearScript.new()
    gear.position = _pos(x, y)
    gear.size = Vector2(46, 46)
    gear.mouse_filter = Control.MOUSE_FILTER_STOP
    overlay.add_child(gear)
    gear.pressed.connect(func() -> void:
        if on_button.is_valid():
            on_button.call("settings"))


## Кнопка «назад» в левом верхнем углу — общая для всех экранов, кроме меню и боя.
func _back_btn() -> Button:
    var p := back_button_pos()
    return _btn(Lang.t("back_btn"), p, back_button_size(), "back_all")


## v71: единый размер кнопки «назад» для HUD И для экранов со своим корнем
## (арены, сетевое лобби, кооп-лобби) — чтобы --overlaptest видел «назад_вариантов=1»,
## а на телефоне у всех экранов была одна и та же тач-цель 48 dp.
func back_button_size() -> Vector2:
    return Vector2(230, 96) if touch_mode else Vector2(148, 42)


## v71: позиция кнопки «назад» с учётом безопасной зоны (вырез/закругления).
## Сдвиг 16:9-кадра (_pos) здесь НЕ применяется: «назад» — кнопка уровня экрана,
## на широкой канве иначе уезжала вправо и наезжала на подписи/строки.
func back_button_pos() -> Vector2:
    return Vector2(18.0 + _safe.x, 12.0 + _safe.y)


## Прозрачная зона нажатия поверх строки списка: работает и мышью, и пальцем.
func _hit(x: float, y: float, w: float, h: float, id: String) -> Button:
    var b := Button.new()
    b.text = ""
    b.position = _pos(x, y)
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
            "hook_l": "K", "hook_r": "I", "upper": "U", "upper_l": "O",
            "cross": "E", "body": "Ctrl"}
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

    # --- раскладка меню от канвы и безопасной зоны -------------------------
    _wide = true
    # T6: тач-режим — из данных main ("touch") или по платформе
    touch_mode = bool(d.get("touch", touch_mode)) or touch_mode or _detect_touch()
    var tm := touch_mode
    var cs := _canvas()
    var sl := _safe.x
    var sr := _safe.z
    var sb := _safe.w
    var scale := clampf(cs.x / W, 1.0, MENU_SCALE_MAX)
    var right_edge := cs.x - MENU_ROW_RIGHT - sr
    var gap := MENU_GAP * scale
    var top_y := (16.0 if tm else 20.0) + _safe.y
    var y_hint := cs.y - (36.0 if tm else 30.0) - sb
    var row1_h := TOUCH_MIN if tm else 46.0
    var row2_h := TOUCH_MIN if tm else 30.0
    var play_h := 104.0 if tm else MENU_PLAY_H
    var suf := "" if tm else "  "
    var y1 := cs.y - 134.0 - sb
    var y2 := cs.y - 80.0 - sb
    var y_play := cs.y - 150.0 - sb
    var y_exit := cs.y - 46.0 - sb
    # два ряда кнопок: сначала ширина по самому длинному тексту, потом место ряда
    var row1: Array = [
        ["locker", Lang.t("locker") + suf + ("" if tm else "C")],
        ["upgrade", Lang.t("upgrade") + suf + ("" if tm else "P")],
        ["training", Lang.t("training") + suf + ("" if tm else "F")],
        ["tour", Lang.t("tour") + suf + ("" if tm else "G")],
        ["story", Lang.t("story") + suf + ("" if tm else "Y")],
    ]
    var row2: Array = [
        ["arenas", Lang.t("arenas") + suf + ("" if tm else "B")],
    ]
    # v71m: в веб-версии и на телефоне сети и кооператива нет (ENet в Web не
    # работает; на телефоне по просьбе заказчика оставлена только одиночная игра).
    var net_ui := bool(d.get("net_ui", true))
    if net_ui:
        row2.append(["net", Lang.t("net_title") + suf + ("" if tm else "N")])
        row2.append(["coop", Lang.t("coop_title") + suf + ("" if tm else "O")])
    var n2 := row2.size()
    var font_now := BTN_FONT_TOUCH if tm else BTN_FONT
    var w1 := 148.0 * scale
    var w2 := 148.0 * scale
    for item in row1:
        w1 = maxf(w1, _text_w(String(item[1]), font_now) + BTN_TEXT_PAD)
    for item in row2:
        w2 = maxf(w2, _text_w(String(item[1]), font_now) + BTN_TEXT_PAD)
    var play_w := MENU_PLAY_W * scale
    var row1_x := 0.0
    var row2_x := 0.0
    if tm:
        # T6: телефон — кнопки во всю ширину и высотой 48 dp; «ИГРАТЬ» — широкая
        # полоса внизу, над ней два ряда; клавишные хвосты в подписях убраны.
        var avail := right_edge - (MENU_LEFT + sl)
        w1 = clampf(maxf(w1, (avail - 4.0 * gap) / 5.0), 148.0 * scale, 260.0)
        w2 = clampf(maxf(w2, (avail - float(n2 - 1) * gap) / float(maxi(1, n2))),
                195.0 * scale, 320.0)
        # одна кнопка в ряду (веб/телефон: осталась только «Боевые локации») —
        # шириной как кнопки верхнего ряда, иначе она выглядит обрубком
        if n2 == 1:
            w2 = w1
        play_w = avail
        row1_x = right_edge - (5.0 * w1 + 4.0 * gap)
        row2_x = right_edge - (float(n2) * w2 + float(n2 - 1) * gap)
        y_play = y_hint - 10.0 - play_h
        y2 = y_play - 12.0 - row2_h
        y1 = y2 - 10.0 - row1_h
        y_exit = top_y
    else:
        # ряды занимают всю ширину до правого края: на широкой канве кнопки шире,
        # на 1280×720 выходит ровно прежний слот 148
        var row1_left := MENU_LEFT + sl + play_w + 18.0
        w1 = maxf(w1, (right_edge - row1_left - 4.0 * gap) / 5.0)
        w2 = maxf(w2, w1)
        # никогда не залезаем на «ИГРАТЬ»: сначала прижимаем ряд к правому краю,
        # и только если тексту тесно — уменьшаем кегль (см. _fit_font)
        row1_x = maxf(row1_left, right_edge - (5.0 * w1 + 4.0 * gap))
        row2_x = maxf(row1_left, right_edge - (float(n2) * w2 + float(n2 - 1) * gap))

    _splash_bg()
    _gear_button(cs.x - 20.0 - sr - 46.0, top_y)
    # T1: «Статистика» встаёт в верхний ряд слева от «Как играть» — ряды
    # основного меню не трогаем, поэтому раскладка не наезжает ни на чём.
    var howto_w := 196.0 * scale
    if tm:
        howto_w = 224.0 * scale
    var howto_h := TOUCH_MIN if tm else 40.0
    var howto_x := cs.x - 20.0 - sr - 46.0 - 12.0 - howto_w
    var stats_w := howto_w
    _btn(Lang.t("stats") + suf + ("" if tm else "K"), Vector2(howto_x - 12.0 - stats_w, top_y),
            Vector2(stats_w, howto_h), "stats")
    _btn(Lang.t("howto") + suf + ("" if tm else "H"), Vector2(howto_x, top_y),
            Vector2(howto_w, howto_h), "howto")
    if tm:
        # на телефоне «ВЫХОД» уходит в левый верхний угол, чтобы не делить
        # нижнюю зону с крупными кнопками
        _btn(Lang.t("exit"), Vector2(48.0 + sl, top_y), Vector2(176.0, 96.0), "exit")
        _overlay_label(Lang.t("version"), 48.0 + sl, 124.0 + _safe.y, 420, 10,
                Color(0.62, 0.66, 0.74), HORIZONTAL_ALIGNMENT_LEFT, false)
        # v48: строка «чем рендерится» — по ней видно, почему на телефоне
        # могут не строиться арены (рендерер/видеокарта)
        if String(d.get("gfx", "")) != "":
            _overlay_label(String(d.get("gfx", "")), 48.0 + sl, 140.0 + _safe.y, 620, 9,
                    Color(0.45, 0.50, 0.58), HORIZONTAL_ALIGNMENT_LEFT, false)
    else:
        _btn(Lang.t("exit"), Vector2(cs.x - 34.0 - sr - 104.0 * scale, y_exit),
                Vector2(104.0 * scale, 32), "exit")
        _overlay_label(Lang.t("version"), 48.0 + sl, 20.0 + _safe.y, 420, 10,
                Color(0.62, 0.66, 0.74), HORIZONTAL_ALIGNMENT_LEFT, false)
        if String(d.get("gfx", "")) != "":
            _overlay_label(String(d.get("gfx", "")), 48.0 + sl, 34.0 + _safe.y, 620, 9,
                    Color(0.45, 0.50, 0.58), HORIZONTAL_ALIGNMENT_LEFT, false)

    # название и обещание: на телефоне левый блок выше, чтобы освободить низ
    var t_title := 336.0 if not tm else 160.0
    var t_hook := 408.0 if not tm else 224.0
    var t_belt := 452.0 if not tm else 260.0
    var t_dots := 482.0 if not tm else 282.0
    var t_cnt := 506.0 if not tm else 302.0
    var t_wins := 526.0 if not tm else 322.0
    var t_tour := 544.0 if not tm else 340.0
    _overlay_label(Lang.t("title"), 46, t_title, 620, 60, TEXT, HORIZONTAL_ALIGNMENT_LEFT)
    _overlay_label(Lang.t("hook"), 50, t_hook, 660, 17, Color(0.88, 0.91, 0.97),
            HORIZONTAL_ALIGNMENT_LEFT, false)

    # карьера: пояс, десять соперников
    if champion:
        _overlay_label(Lang.t("champion"), 50, t_belt, 700, 15, AMBER,
                HORIZONTAL_ALIGNMENT_LEFT)
    else:
        _overlay_label(Lang.t("belt") + " " + str(belt + 1) + " " + Lang.t("of") + " "
                + str(belt_max) + " · " + belt_name, 50, t_belt, 700, 15, belt_col,
                HORIZONTAL_ALIGNMENT_LEFT)
    for i in belt_fights:
        var on := i < belt_wins or champion
        _overlay_rect(50 + i * 28, t_dots, 22, 10, belt_col if on else Color(1, 1, 1, 0.16))
    _overlay_label(str(mini(belt_wins, belt_fights)) + " / " + str(belt_fights), 50 + belt_fights * 28 + 4,
            t_dots - 8.0, 120, 13, Color(0.80, 0.84, 0.91), HORIZONTAL_ALIGNMENT_LEFT, false)

    _overlay_label(Lang.t("coins") + " " + str(coins) + " · " + Lang.t("form") + " "
            + str(form) + " · " + Lang.t("level") + " " + str(lv), 50, t_cnt, 620, 12,
            Color(0.74, 0.78, 0.86), HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(Lang.t("wins") + " " + str(wins) + " / " + str(matches) + " · "
            + Lang.t("record") + " " + str(high), 50, t_wins, 620, 11, MUTED,
            HORIZONTAL_ALIGNMENT_LEFT, false)
    var tour_name := String(d.get("tour_name", ""))
    if tour_name != "":
        _overlay_label(Lang.t("tour") + ": " + tour_name + " · "
                + str(int(d.get("tour_wins", 0))) + " / 3", 50, t_tour, 620, 11,
                Color(0.72, 0.84, 0.98), HORIZONTAL_ALIGNMENT_LEFT, false)
    elif int(d.get("tour_done", 0)) > 0:
        _overlay_label(Lang.t("tour") + ": " + str(int(d.get("tour_done", 0))) + " / "
                + str(int(d.get("tour_total", 3))), 50, t_tour, 620, 11,
                Color(0.55, 0.86, 0.62), HORIZONTAL_ALIGNMENT_LEFT, false)

    # одно большое действие и пять маленьких
    _btn(Lang.t("play"), Vector2(MENU_LEFT + sl, y_play), Vector2(play_w, play_h),
            "play", "cta")
    for i in row1.size():
        _btn(String(row1[i][1]), Vector2(row1_x + float(i) * (w1 + gap), y1),
                Vector2(w1, row1_h), String(row1[i][0]))
    # Этап 4: боевые локации (арены), сеть и кооп — отдельной строкой под меню
    for i in row2.size():
        _btn(String(row2[i][1]), Vector2(row2_x + float(i) * (w2 + gap), y2),
                Vector2(w2, row2_h), String(row2[i][0]))
    # v71m: запоминаем фактический состав меню для теста платформенных сборок
    var dbg1: Array = []
    for item in row1:
        dbg1.append(String(item[0]))
    var dbg2: Array = []
    for item in row2:
        dbg2.append(String(item[0]))
    menu_rows_debug = {"row1": dbg1, "row2": dbg2, "net_ui": net_ui}

    var notice := String(d.get("notice", ""))
    if notice != "":
        var nw := row2_x - 50.0 - sl - 16.0
        if nw > 120.0:
            _overlay_label(notice, 50.0 + sl, y2 + 2.0, nw, 13, AMBER,
                    HORIZONTAL_ALIGNMENT_RIGHT, false)

    # v67: подсказка на ПК собирается из реальной раскладки игрока — после
    # переназначения клавиш статичный текст «WASD — шаг · E — кросс…» врал
    var hint := Lang.t("controls_hint_touch")
    if not tm:
        hint = Lang.t("controls_hint_fmt") % [String(k.get("move", "WASD")),
                String(k.get("cross", "E")), String(k.get("jab", "J")),
                String(k.get("hook_l", "K")), String(k.get("hook_r", "I")),
                String(k.get("upper", "U")), String(k.get("body", "Ctrl")),
                String(k.get("dodge", "Shift")), String(k.get("block", "L"))]
    _overlay_label(hint, 0, y_hint, cs.x, 13 if tm else 11, Color(0.56, 0.61, 0.70),
            HORIZONTAL_ALIGNMENT_CENTER, false)
    if bool(d.get("saved", false)):
        # на таче — под версией слева сверху, на ПК — под версией в углу
        _overlay_label("✓ " + Lang.t("saved"), 48.0 + sl,
                132.0 if tm else 44.0, 620, 11, Color(0.55, 0.86, 0.62),
                HORIZONTAL_ALIGNMENT_LEFT, false)
    if OS.get_cmdline_user_args().has("--uidiag"):
        # Диагностика раскладки для гейта: только по флагу, в обычных прогонах молчит.
        print("UIDIAG канва=", cs, " stage=", stage_off, " safe=", _safe, " scale=", scale,
                " w1=", w1, " w2=", w2, " row1_x=", row1_x, " row2_x=", row2_x)
        for ch in overlay.get_children():
            if ch is Button:
                print("UIDIAG кнопка ", (ch as Button).text, " pos=", (ch as Button).position,
                        " size=", (ch as Button).size, " min=", (ch as Button).get_combined_minimum_size(),
                        " clip=", (ch as Button).clip_text)


## Карточка перед боем: кто соперник, чем он опасен и совет тренера.
func show_prefight(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var tip := String(d.get("tip", ""))
    var belt: int = int(d.get("belt", 0))
    var belt_name := String(d.get("belt_name", ""))
    var belt_col: Color = d.get("belt_color", AMBER)
    var tour_txt := String(d.get("tour", ""))
    var opp_name := String(d.get("opp_name", ""))
    var opp_style := String(d.get("opp_style", ""))
    var opp_desc := String(d.get("opp_desc", ""))
    var opp_stats := String(d.get("opp_stats", ""))
    var opp_dots := String(d.get("opp_dots", ""))
    var opp_tip := String(d.get("opp_tip", ""))
    _overlay_label(Lang.t("coach").to_upper(), 0, 96, W, 14, AMBER)
    _overlay_rect(180, 126, 920, 104, Color(0.02, 0.03, 0.05, 0.88))
    _overlay_rect(180, 126, 920, 3, AMBER)
    _overlay_label("«" + tip + "»", 214, 158, 852, 17, Color(0.94, 0.96, 1.0),
            HORIZONTAL_ALIGNMENT_LEFT, false)
    # соперник: имя, стиль и его повадки
    _overlay_rect(180, 242, 920, 234, Color(0.03, 0.035, 0.055, 0.88))
    _overlay_rect(180, 242, 4, 234, belt_col)
    _overlay_label(opp_name, 210, 252, 700, 26, Color(0.98, 0.96, 0.90),
            HORIZONTAL_ALIGNMENT_LEFT, true)
    _overlay_label(Lang.t("opp_style") + " " + opp_style, 210, 288, 700, 13, belt_col,
            HORIZONTAL_ALIGNMENT_LEFT, true)
    _overlay_label(opp_desc, 210, 308, 700, 13, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(opp_stats, 210, 332, 700, 13, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(Lang.t("difficulty") + " " + opp_dots, 900, 252, 180, 13, AMBER,
            HORIZONTAL_ALIGNMENT_RIGHT, true)
    _overlay_label(opp_tip, 210, 356, 860, 12, Color(0.72, 0.82, 0.92),
            HORIZONTAL_ALIGNMENT_LEFT, false)
    var line := Lang.t("belt") + " " + str(belt + 1) + " · " + belt_name + " · "
    line += str(int(d.get("belt_wins", 0))) + " / " + str(int(d.get("belt_fights", 10)))
    # подпись пояса и условия турнира — внутри той же карточки
    _overlay_label(line, 0, 400, W, 14, belt_col)
    if tour_txt != "":
        _overlay_label(tour_txt, 0, 424, W, 14, Color(0.86, 0.90, 0.98))
    if bool(d.get("champion", false)):
        _overlay_label(Lang.t("champion"), 0, 448, W, 13, AMBER)
    if touch_mode:
        _btn(Lang.t("fight"), Vector2(470, 470), Vector2(340, 96), "fight", "cta")
    else:
        _btn(Lang.t("fight"), Vector2(470, 486), Vector2(340, 66), "fight", "cta")
    var hint := Lang.t("prefight_hint_touch") if _is_touch(d) else Lang.t("prefight_hint")
    _overlay_label(hint, 0, 568, W, 12, MUTED)


## Сюжетные турниры: список с условиями, наградой и статусом.
func show_tournaments(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var rows: Array = d.get("rows", [])
    var sel: int = int(d.get("sel", 0))
    var msg := String(d.get("msg", ""))
    var tp := 40.0 if touch_mode else 0.0
    _overlay_label(Lang.t("tournaments"), 0, 44, W, 28, AMBER)
    _overlay_rect(150, 96.0 + tp, 980, 350, Color(0.02, 0.03, 0.05, 0.86))
    for i in rows.size():
        var r: Dictionary = rows[i]
        var y := 120.0 + tp + float(i) * 108.0
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
        _overlay_label(msg, 0, 476.0 + tp, W, 14, AMBER)
    if touch_mode:
        _btn(Lang.t("tour_start"), Vector2(470, 496), Vector2(340, 96), "tourstart", "cta")
    else:
        _btn(Lang.t("tour_start"), Vector2(470, 512), Vector2(340, 64), "tourstart", "cta")
    var thint := Lang.t("touch_tour_hint") if _is_touch(d) else Lang.t("tour_hint")
    _overlay_label(thint, 0, 596, W, 12, MUTED)


## T1: экран «Статистика» — цифры боёв, серия, урон и разбивка по аренам.
## Данные приходят из main._stats_data(); всё центрировано в 16:9-кадре,
## поэтому экран одинаково читается на любом окне.
func show_stats(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _back_btn()
    var fights: int = int(d.get("fights", 0))
    var wins: int = int(d.get("wins", 0))
    var losses: int = int(d.get("losses", 0))
    var draws: int = int(d.get("draws", 0))
    _overlay_label(Lang.t("stats"), 0, 34, W, 32, AMBER)
    _overlay_label(Lang.t("stats_sub"), 0, 78, W, 12, MUTED,
            HORIZONTAL_ALIGNMENT_CENTER, false)
    var left_rows: Array = [
        [Lang.t("stats_fights"), str(fights)],
        [Lang.t("stats_wins"), str(wins)],
        [Lang.t("stats_losses"), str(losses)],
        [Lang.t("stats_draws"), str(draws)],
        [Lang.t("stats_wins_ko"), str(int(d.get("wins_ko", 0)))],
        [Lang.t("stats_wins_dec"), str(int(d.get("wins_dec", 0)))],
        [Lang.t("stats_streak"), str(int(d.get("streak", 0)))],
    ]
    var right_rows: Array = [
        [Lang.t("stats_losses_ko"), str(int(d.get("losses_ko", 0)))],
        [Lang.t("stats_losses_dec"), str(int(d.get("losses_dec", 0)))],
        [Lang.t("stats_best_streak"), str(int(d.get("best_streak", 0)))],
        [Lang.t("stats_damage_dealt"), str(int(d.get("damage_dealt", 0)))],
        [Lang.t("stats_damage_taken"), str(int(d.get("damage_taken", 0)))],
        [Lang.t("stats_hits"), str(int(d.get("hits", 0)))],
        [Lang.t("stats_best_score"), str(int(d.get("best_score", 0)))],
    ]
    var tp := 32.0 if touch_mode else 0.0
    var y0 := 116.0 + tp
    var step := 40.0
    for i in left_rows.size():
        _stats_row(120.0, y0 + float(i) * step, 500.0,
                String(left_rows[i][0]), String(left_rows[i][1]))
    for i in right_rows.size():
        _stats_row(660.0, y0 + float(i) * step, 500.0,
                String(right_rows[i][0]), String(right_rows[i][1]))
    # арены: показываем только те, где уже были бои
    _overlay_rect(120, 404.0 + tp, 1040, 210, Color(0.02, 0.03, 0.05, 0.82))
    _overlay_rect(120, 404.0 + tp, 1040, 3, AMBER)
    _overlay_label(Lang.t("stats_arenas"), 150, 416.0 + tp, 600, 13, AMBER,
            HORIZONTAL_ALIGNMENT_LEFT)
    var arena_rows: Array = d.get("arena_rows", [])
    if arena_rows.is_empty():
        _overlay_label(Lang.t("stats_no_arenas"), 150, 452, 900, 13, MUTED,
                HORIZONTAL_ALIGNMENT_LEFT, false)
    else:
        for i in mini(arena_rows.size(), 6):
            var r: Dictionary = arena_rows[i]
            _overlay_label(String(r["name"]), 150, 450 + float(i) * 27, 560, 13,
                    TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
            _overlay_label("%d / %d  ·  %s %d" % [int(r["wins"]), int(r["losses"]),
                    Lang.t("stats_fights").to_lower(), int(r["fights"])],
                    700, 450.0 + tp + float(i) * 27, 430, 13, TEXT,
                    HORIZONTAL_ALIGNMENT_RIGHT, false)
    _overlay_label(Lang.t("stats_hint_touch") if touch_mode else Lang.t("stats_hint"),
            0, 660, W, 12, MUTED)


## Строка статистики: подпись слева, число справа.
func _stats_row(x: float, y: float, w: float, label: String, value: String) -> void:
    _overlay_label(label, x, y, w * 0.70, 14, Color(0.78, 0.82, 0.90),
            HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(value, x + w * 0.68, y, w * 0.32, 16, TEXT,
            HORIZONTAL_ALIGNMENT_RIGHT, true)

## История: пролог и главы. Листается клавишами ←/→, стрелками на экране,
## тапом по номеру главы и свайпом (вверх-вниз или влево-вправо).
## dir: −1/0/+1 — направление, откуда «въезжает» новая глава (анимация).
func show_story(d: Dictionary, dir: int = 0) -> void:
    _clear_overlay()
    if story_tween != null and story_tween.is_valid():
        story_tween.kill()
    _wide = true
    _dim()
    _back_btn()
    var pages: Array = d.get("pages", [])
    var sel: int = clampi(int(d.get("sel", 0)), 0, maxi(0, pages.size() - 1))
    var page: Dictionary = pages[sel] if pages.size() > 0 else {}
    var n: int = pages.size()
    var cs := _canvas()
    var sl := _safe.x
    var st := _safe.y
    var sr := _safe.z
    var sb := _safe.w
    var touch := _is_touch(d)

    _overlay_label(Lang.t("story"), 0, 40.0 + st, cs.x, 30, AMBER)
    var num := String(page.get("num", ""))
    var title := String(page.get("title", ""))
    var head: String = title
    if num != "":
        head = num + " · " + title
    _overlay_label(head, 0, 84.0 + st, cs.x, 16, Color(0.72, 0.78, 0.88))

    # лист с текстом: главы читаются как записка тренера
    var panel_y := 126.0 + st
    var panel_h := clampf(cs.y - panel_y - 198.0, 280.0, 560.0)
    var panel_w := clampf(cs.x - STORY_PANEL_MARGIN - sl - sr,
            STORY_PANEL_MIN, STORY_PANEL_MAX)
    var panel_x := (cs.x - panel_w) * 0.5 + (sl - sr) * 0.5
    _overlay_rect(panel_x, panel_y, panel_w, panel_h, Color(0.015, 0.02, 0.035, 0.90))
    _overlay_rect(panel_x, panel_y, panel_w, 3, AMBER)

    # всё содержимое листа — в отдельном контейнере: его двигаем пальцем
    story_page = Control.new()
    story_page.position = Vector2(panel_x, panel_y)
    story_page.size = Vector2(panel_w, panel_h)
    story_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(story_page)
    _story_base_y = panel_y
    if bool(page.get("open", true)):
        var body := Label.new()
        body.text = String(page.get("text", ""))
        # обёртку включаем до размера: иначе Label растягивается под всю строку
        body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        body.position = Vector2(48, 38)
        body.size = Vector2(panel_w - 96.0, panel_h - 66.0)
        body.vertical_alignment = VERTICAL_ALIGNMENT_TOP
        body.add_theme_font_override("font", font_n)
        body.add_theme_font_size_override("font_size", 17)
        body.add_theme_constant_override("line_spacing", 9)
        body.add_theme_color_override("font_color", Color(0.92, 0.94, 0.99))
        body.mouse_filter = Control.MOUSE_FILTER_IGNORE
        story_page.add_child(body)
    else:
        _story_locked_label(Lang.t("story_locked") + " " + str(int(page.get("need", 1)) + 1),
                0.44, 18, Color(0.82, 0.86, 0.94), panel_w, panel_h)
        _story_locked_label("«" + title + "»", 0.56, 15, MUTED, panel_w, panel_h)
        _story_locked_label(Lang.t("story_locked_hint"), 0.68, 12,
                Color(0.58, 0.63, 0.72), panel_w, panel_h)

    # номера глав: тап по номеру открывает главу, у закрытой — условие
    # T6: на тач-экране номера крупнее (≥48 dp по высоте не влезает в строку —
    # делаем 72×64 и расширяем зону нажатия до 96 по высоте).
    var chip_w := TOUCH_MIN * 0.75 if touch_mode else STORY_CHIP_W
    var chip_h := TOUCH_MIN * 0.66 if touch_mode else STORY_CHIP_H
    var chip_gap := 10.0 if touch_mode else STORY_CHIP_GAP
    var chip_step := chip_w + chip_gap
    var chips_w := float(n) * chip_w + float(maxi(0, n - 1)) * chip_gap
    var chips_x := (cs.x - chips_w) * 0.5 + (sl - sr) * 0.5
    var chips_y := panel_y + panel_h + 10.0
    for i in n:
        var open := bool(pages[i].get("open", true))
        var chip_x := chips_x + float(i) * chip_step
        var on := i == sel
        var bg := AMBER if on else (Color(1, 1, 1, 0.10) if open else Color(1, 1, 1, 0.04))
        _overlay_rect(chip_x, chips_y, chip_w, chip_h, bg)
        var num_txt := "П" if i == 0 else str(i)
        var txt_col := Color(0.06, 0.07, 0.10) if on else (
                Color(0.80, 0.84, 0.92) if open else Color(1, 1, 1, 0.35))
        _overlay_label(num_txt, chip_x, chips_y + (10.0 if touch_mode else 5.0), chip_w,
                17 if touch_mode else 13, txt_col, HORIZONTAL_ALIGNMENT_CENTER, true)
        # зона нажатия — не меньше 96 по высоте даже у невысокого чипа
        var hz := maxf(chip_h + 4.0, TOUCH_MIN) if touch_mode else chip_h + 4.0
        _hit(chip_x - 2.0, chips_y + chip_h * 0.5 - hz * 0.5, chip_w + 4.0, hz,
                "storych%d" % i)
    _overlay_label("%d / %d" % [sel + 1, n], panel_x + panel_w - 150.0, chips_y + 8.0,
            150.0, 12, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)

    var hint := Lang.t("story_hint_touch") if touch else Lang.t("story_hint")
    _overlay_label(hint, 0, chips_y + chip_h + 8.0, cs.x, 12, MUTED)
    if not touch_mode:
        _btn(Lang.t("back"), Vector2(cs.x * 0.5 - 62.0, cs.y - 114.0 - sb),
                Vector2(124, 44), "storyback")

    # стрелки-зоны слева и справа от листа: крупные, пальцем не промахнуться
    if n > 1:
        var arr_w := TOUCH_MIN if touch_mode else STORY_ARROW_W
        var arr_h := TOUCH_MIN * 1.25 if touch_mode else STORY_ARROW_H
        var arr_y := panel_y + panel_h * 0.5 - arr_h * 0.5
        var arr_lx := maxf(sl + 8.0, panel_x - arr_w - 16.0)
        var arr_rx := minf(cs.x - sr - 8.0 - arr_w,
                panel_x + panel_w + 16.0)
        for side in [[arr_lx, "<", "storyprev"], [arr_rx, ">", "storynext"]]:
            var ax: float = side[0]
            _overlay_rect(ax, arr_y, arr_w, arr_h,
                    Color(0.03, 0.035, 0.05, 0.72) if touch else Color(0, 0, 0, 0.0))
            _overlay_label(String(side[1]), ax, arr_y + arr_h * 0.5 - 37.0, arr_w,
                    54, Color(0.86, 0.90, 0.97, 0.85), HORIZONTAL_ALIGNMENT_CENTER, false)
            _hit(ax, arr_y, arr_w, arr_h, String(side[2]))

    # анимация смены главы: новый лист выезжает по направлению листания
    if story_page != null:
        if dir != 0:
            story_page.position = Vector2(panel_x, panel_y + float(dir) * 26.0)
            story_page.modulate.a = 0.0
            if story_tween != null and story_tween.is_valid():
                story_tween.kill()
            story_tween = create_tween().set_parallel(true)
            story_tween.tween_property(story_page, "position:y", panel_y, STORY_ANIM_TIME)
            story_tween.tween_property(story_page, "modulate:a", 1.0, STORY_ANIM_TIME)


## Строка на закрытой главе (внутри листа): позиция — доля высоты листа.
func _story_locked_label(text: String, frac: float, size: int, col: Color,
        panel_w: float, panel_h: float) -> void:
    var l := Label.new()
    l.text = text
    l.position = Vector2(0, panel_h * frac)
    l.size = Vector2(panel_w, float(size) * 1.5)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.add_theme_font_override("font", font_b)
    l.add_theme_font_size_override("font_size", size)
    l.add_theme_color_override("font_color", col)
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    if story_page != null:
        story_page.add_child(l)


## Палец тянет лист: лист едет за пальцем (с сопротивлением) и чуть бледнеет.
func story_drag(dy: float) -> void:
    if story_page == null:
        return
    if story_tween != null and story_tween.is_valid():
        story_tween.kill()
    story_page.position.y = _story_base_y + clampf(dy * STORY_DRAG_FOLLOW,
            -STORY_DRAG_MAX, STORY_DRAG_MAX)
    story_page.modulate.a = clampf(1.0 - absf(dy) / 420.0, 0.35, 1.0)


## Отпустили палец без перелистывания: лист плавно встаёт на место.
func story_drag_reset() -> void:
    if story_page == null:
        return
    if story_tween != null and story_tween.is_valid():
        story_tween.kill()
    story_tween = create_tween().set_parallel(true)
    story_tween.tween_property(story_page, "position:y", _story_base_y, 0.12)
    story_tween.tween_property(story_page, "modulate:a", 1.0, 0.12)


func show_pause() -> void:
    _clear_overlay()
    # v71: боевой HUD (полоски HP/раунд) убираем — иначе они просвечивают под «назад»
    set_battle_visible(false)
    _dim()
    _back_btn()
    _overlay_label(Lang.t("paused"), 0, 170 if touch_mode else 200, W, 44, TEXT)
    if touch_mode:
        # T6: крупные кнопки паузы на телефоне
        _btn(Lang.t("resume"), Vector2(510, 236), Vector2(260, 96), "resume")
        _btn(Lang.t("settings"), Vector2(510, 340), Vector2(260, 96), "settings")
        _btn(Lang.t("howto"), Vector2(510, 444), Vector2(260, 96), "howto")
        _btn(Lang.t("to_menu"), Vector2(510, 548), Vector2(260, 96), "tomenu")
        _overlay_label(Lang.t("pause_hint_touch"), 0, 660, W, 13, MUTED)
    else:
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
            "hook_l": "K", "hook_r": "I", "upper": "U", "upper_l": "O",
            "cross": "E", "body": "Ctrl"}
    _overlay_label(Lang.t("howto"), 0, 26, W, 28, AMBER)
    _overlay_label(Lang.t("howto_sub"), 0, 64, W, 12, MUTED)

    var tp := 28.0 if touch_mode else 0.0
    _overlay_rect(64, 104.0 + tp, 560, 232, Color(0.02, 0.03, 0.05, 0.86))
    _overlay_label(Lang.t("movement"), 88, 116.0 + tp, 300, 10, MUTED,
            HORIZONTAL_ALIGNMENT_LEFT, false)

    var tm := _is_touch(d) or touch_mode
    if tm:
        _overlay_label(Lang.t("touch_move"), 88, 146.0 + tp, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(Lang.t("touch_punch"), 88, 180.0 + tp, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(Lang.t("touch_guard"), 88, 214.0 + tp, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(Lang.t("howto_pause_touch"), 88, 256.0 + tp, 520, 12,
                Color(0.70, 0.75, 0.84), HORIZONTAL_ALIGNMENT_LEFT, false)
    else:
        _overlay_label(String(k["move"]) + " — шаг", 88, 146, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["dodge"]) + " — уклон", 88, 176, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["block"]) + " — блок (держать)", 88, 206, 500, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["jab"]) + " — джеб    " + String(k["cross"]) + " — кросс",
                88, 230, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["hook_l"]) + " — левый хук    " + String(k["hook_r"]) + " — правый хук",
                88, 258, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["upper"]) + " — апперкот    "
                + String(k.get("upper_l", "O")) + " — левый апперкот",
                88, 286, 520, 15, TEXT, HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(String(k["body"]) + "+удар — в корпус",
                88, 308, 520, 11, Color(0.70, 0.75, 0.84), HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label("Enter / Space — в бой      C — гардероб      P — прокачка      F — тренировка",
                88, 318, 520, 11, Color(0.70, 0.75, 0.84), HORIZONTAL_ALIGNMENT_LEFT, false)

    _overlay_rect(656, 104.0 + tp, 560, 232, Color(0.02, 0.03, 0.05, 0.86))
    var y := 120.0 + tp
    var body_line := Lang.t("touch_howto_body") if tm else Lang.t("howto_body")
    var kd_line := Lang.t("touch_howto_knockdown") if tm else Lang.t("howto_knockdown")
    for line in [Lang.t("howto_move"), Lang.t("howto_punch"), body_line,
            kd_line, Lang.t("howto_rounds"), Lang.t("howto_rope"),
            Lang.t("howto_career"), Lang.t("howto_form")]:
        _overlay_label("•  " + line, 680, y, 520, 13, Color(0.84, 0.88, 0.95),
                HORIZONTAL_ALIGNMENT_LEFT, false)
        y += 26.0

    if touch_mode:
        _btn(Lang.t("back_btn"), Vector2(520, 384), Vector2(240, 96), "back")
        _overlay_label(Lang.t("touch_back_hint"), 0, 500, W, 13, MUTED)
    else:
        _btn(Lang.t("back"), Vector2(540, 372), Vector2(200, 48), "back")
        _overlay_label(Lang.t("howto_back"), 0, 436, W, 12, MUTED)


func show_ko(text: String) -> void:
    _clear_overlay()
    var l := _overlay_label(text, 0, 250, W, 84 if text.length() <= 4 else 64, AMBER)
    l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
    l.add_theme_constant_override("shadow_offset_y", 4)


## Перерыв между раундами: следующий раунд, отсчёт отдыха и кнопка «продолжить».
func show_rest(d: Dictionary) -> void:
    _clear_overlay()
    _dim()
    _overlay_label(Lang.t("rest"), 0, 90, W, 54, AMBER)
    _overlay_label("%s %d/%d" % [Lang.t("rest_next"), int(d.get("round", 2)),
            int(d.get("total", 1))], 0, 158, W, 24, TEXT)
    rest_time_lbl = _overlay_label("", 0, 206, W, 66, TEXT)
    _overlay_label(Lang.t("rest_hint"), 0, 300, W, 14, MUTED, HORIZONTAL_ALIGNMENT_CENTER, false)
    _btn(Lang.t("rest_skip"), Vector2(520, 348), Vector2(240, 50), "skiprest")


func set_rest_time(seconds: float) -> void:
    if rest_time_lbl == null:
        return
    var s := maxi(0, ceili(seconds))
    rest_time_lbl.text = "%d:%02d" % [int(s / 60), s % 60]
    rest_time_lbl.add_theme_color_override("font_color", RED if seconds <= 5.0 else TEXT)


func show_result(d: Dictionary) -> void:
    _clear_overlay()
    # v71: боевой HUD убираем — под «назад» просвечивали полоски HP
    set_battle_visible(false)
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

    # T3: имя героя в экране результата — в той же строке, что и подзаголовок
    _overlay_label(current_player_name().to_upper() + " · " + sub.to_upper(),
            0, 70, W, 13, MUTED)
    # Пакет 2 / T2: имя соперника на экране результата — то же, что в HUD и в бою
    var opp_name := String(d.get("opp_name", ""))
    if opp_name != "":
        _overlay_label(Lang.t("opponent").to_upper() + ": " + opp_name, 0, 48, W, 13, MUTED)
    _overlay_label(title, 0, 92, W, 58, col)
    var bonus: int = int(d.get("bonus", 0))
    if win and bonus > 0:
        _overlay_label("+" + str(bonus) + " " + Lang.t("win_bonus"), 0, 164, W, 14, AMBER)
    _overlay_label("+" + str(int(d.get("coin_gain", 0))) + " " + Lang.t("coin_gain"),
            0, 188, W, 17, AMBER)
    var penalty: int = int(d.get("penalty", 0))
    if penalty > 0:
        _overlay_label("−" + str(penalty) + " " + Lang.t("defeat_penalty"),
                0, 214, W, 15, RED)
    var fg: int = int(d.get("form_gain", 0))
    if fg > 0:
        _overlay_label("+" + str(fg) + " " + Lang.t("form_gain"), 0, 236, W, 14, ACCENT)

    # карьера: где ты по поясам
    var belt: int = int(d.get("belt", 0))
    var belt_wins: int = int(d.get("belt_wins", 0))
    var belt_name: String = String(d.get("belt_name", ""))
    var belt_col: Color = d.get("belt_color", AMBER)
    var champion: bool = bool(d.get("champion", false))
    if bool(d.get("belt_won", false)) and not champion:
        _overlay_label(Lang.t("belt_won").to_upper() + " · " + belt_name.to_upper(),
                0, 264, W, 16, AMBER)
    elif champion:
        _overlay_label(Lang.t("champion"), 0, 264, W, 16, AMBER)
    else:
        _overlay_label(Lang.t("belt") + " " + str(belt + 1) + " · " + belt_name + " · "
                + str(belt_wins) + " / " + str(int(d.get("belt_fights", 10))),
                0, 264, W, 14, belt_col)

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
    var y := 300.0
    for r in rows:
        _overlay_label(str(r[0]), 320, y, 300, 13, MUTED, HORIZONTAL_ALIGNMENT_RIGHT, false)
        _overlay_label(str(r[1]), 660, y, 300, 17, r[2], HORIZONTAL_ALIGNMENT_LEFT)
        y += 34.0

    if touch_mode:
        _btn(Lang.t("next_fight"), Vector2(230, 612), Vector2(340, 96), "play", "cta")
        _btn(Lang.t("to_menu"), Vector2(590, 628), Vector2(240, 80), "tomenu")
    else:
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
    if v:
        refresh_player_name()


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

    # v71: на телефоне «назад» 230×96 — освобождаем ей верх и сдвигаем панели,
    # чтобы она не наезжала на подписи и строки (было: панели с y=62).
    var tp := 56.0 if touch_mode else 0.0
    var top_h := 112.0 if touch_mode else 58.0
    var pan_y := 62.0 + tp
    var pan_h := 628.0 - pan_y
    # фон под панели и подписи
    _overlay_rect(0, 0, W, top_h, Color(0.02, 0.025, 0.04, 0.72))
    _overlay_rect(0, 638, W, 82, Color(0.02, 0.025, 0.04, 0.78))
    _overlay_rect(40, pan_y, 340, pan_h, Color(0.03, 0.04, 0.06, 0.88))
    _overlay_rect(900, pan_y, 340, pan_h, Color(0.03, 0.04, 0.06, 0.88))
    _overlay_rect(40, pan_y, 340, 2, Color(1, 1, 1, 0.12))
    _overlay_rect(900, pan_y, 340, 2, Color(1, 1, 1, 0.12))

    _overlay_label("ГАРДЕРОБ", 0, 14, W, 24, ACCENT)
    if touch_mode:
        # монеты — в правую часть верхней строки, левее «ПОБЕД»
        _overlay_label("МОНЕТ " + str(coins), 620, 20, 260, 17, AMBER,
                HORIZONTAL_ALIGNMENT_RIGHT)
    else:
        _overlay_label("МОНЕТ " + str(coins), 186, 20, 320, 17, AMBER,
                HORIZONTAL_ALIGNMENT_LEFT)
    _overlay_label("ПОБЕД " + str(wins) + " / " + str(matches), 900, 20, 320, 15, MUTED,
            HORIZONTAL_ALIGNMENT_RIGHT)

    # разделы
    _overlay_label("РАЗДЕЛЫ", 64, 70.0 + tp, 300, 10, MUTED,
            HORIZONTAL_ALIGNMENT_LEFT, false)
    for i in cats.size():
        var cat: Dictionary = cats[i]
        var cid := String(cat["id"])
        var y := 98.0 + tp + float(i) * 44.0
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
    # v70: в каталоге стало больше фасонов (12 причёсок, 8 обуви) — шаг строк
    # сжимаем, иначе последние варианты налезали на нижнюю подсказку.
    var step := 44.0
    if arr.size() > 9:
        step = 34.0
    elif arr.size() > 7:
        step = 38.0
    var row_h := step - 4.0
    _overlay_label(String(cat_now["name"]), 924, 70.0 + tp, 292, 10, MUTED,
            HORIZONTAL_ALIGNMENT_LEFT, false)
    for i in arr.size():
        var it: Dictionary = arr[i]
        var y := 98.0 + tp + float(i) * step
        var key := cid_now + ":" + String(it["id"])
        var have := owned.has(key)
        var equipped := String(look.get(cid_now, "")) == String(it["id"])
        if i == oi:
            _overlay_rect(912, y - 4, 316, row_h, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16))
            _overlay_rect(912, y - 4, 4, row_h, ACCENT)
        if color_sec:
            _overlay_rect(928, y, 20, 20, Color(1, 1, 1, 0.20))
            _overlay_rect(930, y + 2, 16, 16, it["col"])
        var col := TEXT if i == oi else Color(0.66, 0.71, 0.80)
        var name_x := 958.0 if color_sec else 930.0
        _overlay_label(String(it["name"]), name_x, y - 2, 180, 14, col, HORIZONTAL_ALIGNMENT_LEFT, i == oi)
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
        _overlay_label(tag, 1060, y, 150, 10, tag_col, HORIZONTAL_ALIGNMENT_RIGHT)
        _hit(912, y - 4, 316, row_h, "lockeritem%d" % i)

    _overlay_label("очки дают за матчи: победа, нокдаун и вылет за канаты — дороже",
            924, 594, 292, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)

    if msg != "":
        _overlay_label(msg, 0, 642, W, 15, msg_col)
    var lhint := "↑↓ раздел      ←→ вариант      ENTER — надеть / купить      ESC — назад"
    if _is_touch(d):
        lhint = Lang.t("touch_locker_hint")
    _overlay_label(lhint, 0, 678, W, 14, Color(0.72, 0.78, 0.88))
    _back_btn()


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
    var ty := 120.0 if touch_mode else 80.0
    b.position = Vector2(x, ty)
    b.size = Vector2(w, 64.0 if touch_mode else 42.0)
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_override("font", font_b if active else font_n)
    b.add_theme_font_size_override("font_size", 18 if touch_mode else 14)
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

    # T6: на телефоне вкладка «управление» показывает тач-схему, а не клавиши
    if touch_mode:
        _overlay_rect(238, 200, 804, 400, Color(0.03, 0.04, 0.06, 0.80))
        _overlay_label(Lang.t("touch_settings_note"), 300, 242, 680, 18, TEXT,
                HORIZONTAL_ALIGNMENT_LEFT, false)
        # v58: своя раскладка — кнопки ударов и джойстик переставляются пальцем
        _overlay_label(Lang.t("touch_controls_note"), 300, 282, 680, 15, MUTED,
                HORIZONTAL_ALIGNMENT_LEFT, false)
        _btn(Lang.t("touch_controls_btn"), Vector2(300, 324), Vector2(680, TOUCH_MIN),
                "touchlayout", "cta")
        _overlay_label(Lang.t("touch_controls_hint"), 300, 442, 680, 13, MUTED,
                HORIZONTAL_ALIGNMENT_LEFT, false)
        _overlay_label(Lang.t("touch_back_hint"), 0, 520, W, 13,
                Color(0.72, 0.78, 0.88))
        return

    # T9: полноэкранный экран переназначения клавиш — крупные строки
    # «действие → клавиша» с группами, подсветкой выбора и прокруткой.
    keys_rows_cache = rows
    _overlay_rect(KEYS_PANEL_RECT.position.x, KEYS_PANEL_RECT.position.y,
            KEYS_PANEL_RECT.size.x, KEYS_PANEL_RECT.size.y, Color(0.03, 0.04, 0.06, 0.86))
    _overlay_rect(KEYS_PANEL_RECT.position.x, KEYS_PANEL_RECT.position.y,
            KEYS_PANEL_RECT.size.x, 2, Color(1, 1, 1, 0.12))

    var scroll := keys_clamp_scroll(float(d.get("scroll", 0.0)))
    var lay := _keys_layout(rows, sel)
    var box := Control.new()
    box.position = KEYS_PANEL_RECT.position
    box.size = KEYS_PANEL_RECT.size
    box.clip_contents = true
    box.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(box)
    for e in lay["items"]:
        var ry: float = float(e["y"]) - scroll + KEYS_PAD
        var eh: float = float(e["h"])
        if ry + eh < 0.0 or ry > KEYS_PANEL_RECT.size.y:
            continue
        if e.has("head"):
            var gname := String(e["head"]).to_upper()
            _keys_label(box, 24, ry, 420, eh, gname, 11, MUTED)
            box.add_child(_keys_rect(24, ry + eh * 0.5 + 8, KEYS_PANEL_RECT.size.x - 48, 1,
                    Color(1, 1, 1, 0.07)))
            continue
        var r: Dictionary = e["row"]
        var i: int = int(e["idx"])
        if i == sel:
            box.add_child(_keys_rect(6, ry + 2, KEYS_PANEL_RECT.size.x - 12, eh - 4,
                    Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.16)))
            box.add_child(_keys_rect(6, ry + 2, 4, eh - 4, ACCENT))
        _keys_label(box, 28, ry, 700, eh, String(r["label"]), 20,
                TEXT if i == sel else Color(0.84, 0.88, 0.95), HORIZONTAL_ALIGNMENT_LEFT, i == sel)
        # плашка клавиши: «действие → клавиша»
        var bx := KEYS_PANEL_RECT.size.x - 226.0
        var badge := StyleBoxFlat.new()
        badge.bg_color = Color(0.02, 0.03, 0.05, 0.9)
        badge.border_width_left = 1
        badge.border_width_right = 1
        badge.border_width_top = 1
        badge.border_width_bottom = 1
        badge.border_color = ACCENT if i == sel else Color(1, 1, 1, 0.18)
        badge.corner_radius_top_left = 6
        badge.corner_radius_top_right = 6
        badge.corner_radius_bottom_left = 6
        badge.corner_radius_bottom_right = 6
        var bpad := Panel.new()
        bpad.position = Vector2(bx, ry + 6)
        bpad.size = Vector2(186, eh - 12)
        bpad.mouse_filter = Control.MOUSE_FILTER_IGNORE
        bpad.add_theme_stylebox_override("panel", badge)
        box.add_child(bpad)
        _keys_label(box, bx, ry + 6, 186, eh - 12, String(r["key"]), 22,
                AMBER if i != sel else TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
        # вся строка — зона нажатия (плоская, в тест пересечений не попадает)
        # task-47: у нижней, частично видимой строки зона обрезается по границе
        # панели — иначе её центр уходит за clip_contents и тап/клик не доходит
        # (была «мёртвая» строка 7 на экране клавиш).
        var hit_y: float = maxf(ry, 0.0)
        var hit_h: float = minf(ry + eh, KEYS_PANEL_RECT.size.y) - hit_y
        if hit_h > 2.0:
            _keys_hit(box, 6, hit_y, KEYS_PANEL_RECT.size.x - 12, hit_h, "keyrow%d" % i)

    # полоса прокрутки
    var max_scroll: float = float(lay["max_scroll"])
    if max_scroll > 0.5:
        var track_h := KEYS_PANEL_RECT.size.y - 16.0
        box.add_child(_keys_rect(KEYS_PANEL_RECT.size.x - 9, 8, 4, track_h,
                Color(1, 1, 1, 0.08)))
        var th: float = maxf(40.0, track_h * float(KEYS_PANEL_RECT.size.y) / float(lay["total"]))
        var ty: float = 8.0 + (track_h - th) * (scroll / max_scroll)
        box.add_child(_keys_rect(KEYS_PANEL_RECT.size.x - 9, ty, 4, th,
                Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.65)))

    # прокрутка кнопками: колесо и клавиши тоже работают (main обрабатывает)
    _btn("▲", Vector2(1216, 140), Vector2(40, 52), "keysup")
    _btn("▼", Vector2(1216, 544), Vector2(40, 52), "keysdown")
    _btn(Lang.t("keys_reset"), Vector2(28, 604), Vector2(320, 52), "keysreset")

    if wait:
        _overlay_rect(340, 292, 600, 118, Color(0.05, 0.06, 0.09, 0.97))
        _overlay_rect(340, 292, 600, 3, ACCENT)
        _overlay_label("НАЖМИ НОВУЮ КЛАВИШУ" if not Lang.is_en() else "PRESS A NEW KEY",
                0, 318, W, 22, AMBER)
        _overlay_label("ESC — отмена" if not Lang.is_en() else "ESC — cancel", 0, 358, W, 13, MUTED)

    if msg != "":
        _overlay_label(msg, 0, 664, W, 14, msg_col)
    _overlay_label(Lang.t("keys_hint"), 360, 612, 900, 14,
            Color(0.72, 0.78, 0.88), HORIZONTAL_ALIGNMENT_LEFT, false)
    _overlay_label(Lang.t("keys_scroll_hint") + "      " + Lang.t("keys_tab_hint"),
            0, 688, W, 11, MUTED)


## Раскладка полного экрана клавиш (T9): строки с заголовками групп и высоты.
## v71: экран переназначения клавиш — на всю канву (без «окна» посередине).
const KEYS_PANEL_RECT := Rect2(28, 136, 1180, 456)
const KEYS_ROW_H := 52.0
const KEYS_HEAD_H := 30.0
const KEYS_PAD := 8.0
## Строки последнего показа — по ним main считает прокрутку при навигации.
var keys_rows_cache: Array = []


## Список для отрисовки: заголовок группы + строки действий.
func _keys_entries(rows: Array) -> Array:
    var out: Array = []
    var gi := ""
    for i in rows.size():
        var r: Dictionary = rows[i]
        var g := String(r.get("group", ""))
        if g != gi:
            gi = g
            out.append({"head": g})
        out.append({"row": r, "idx": i})
    return out


func _keys_layout(rows: Array, sel: int) -> Dictionary:
    var items: Array = []
    var y := 0.0
    var sel_y := 0.0
    var sel_h := 0.0
    for e in _keys_entries(rows):
        if e.has("head"):
            items.append({"y": y, "h": KEYS_HEAD_H, "head": String(e["head"])})
            y += KEYS_HEAD_H
        else:
            items.append({"y": y, "h": KEYS_ROW_H, "row": e["row"], "idx": int(e["idx"])})
            if int(e["idx"]) == sel:
                sel_y = y
                sel_h = KEYS_ROW_H
            y += KEYS_ROW_H
    var total := y + KEYS_PAD * 2.0
    var panel_h: float = KEYS_PANEL_RECT.size.y
    return {"items": items, "total": total,
            "max_scroll": maxf(0.0, total - panel_h), "panel_h": panel_h,
            "sel_y": sel_y, "sel_h": sel_h}


## Ограничить прокрутку полным экраном клавиш.
func keys_clamp_scroll(v: float) -> float:
    if keys_rows_cache.is_empty():
        return 0.0
    return clampf(v, 0.0, float(_keys_layout(keys_rows_cache, -1)["max_scroll"]))


## Прокрутка, при которой выбранная строка видна целиком (навигация ↑↓).
func keys_scroll_for(sel: int, cur: float) -> float:
    if keys_rows_cache.is_empty():
        return 0.0
    var lay := _keys_layout(keys_rows_cache, sel)
    var panel_h: float = float(lay["panel_h"])
    var top := float(lay["sel_y"]) - KEYS_PAD
    var bottom := float(lay["sel_y"]) + float(lay["sel_h"]) + KEYS_PAD
    var v := cur
    if top < v:
        v = top
    elif bottom > v + panel_h:
        v = bottom - panel_h
    return clampf(v, 0.0, float(lay["max_scroll"]))


func _keys_rect(x: float, y: float, w: float, h: float, col: Color) -> ColorRect:
    var r := ColorRect.new()
    r.position = Vector2(x, y)
    r.size = Vector2(w, h)
    r.color = col
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    return r


func _keys_label(box: Control, x: float, y: float, w: float, h: float, text: String,
        fs: int, col: Color, align: int = HORIZONTAL_ALIGNMENT_LEFT,
        bold: bool = false) -> Label:
    var l := Label.new()
    l.position = Vector2(x, y)
    l.size = Vector2(w, h)
    l.text = text
    l.add_theme_font_override("font", font_b if bold else font_n)
    l.add_theme_font_size_override("font_size", fs)
    l.add_theme_color_override("font_color", col)
    l.horizontal_alignment = align
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    box.add_child(l)
    return l


## Плоская зона нажатия на строку клавиши + колесо мыши (прокрутка).
func _keys_hit(box: Control, x: float, y: float, w: float, h: float, id: String) -> Button:
    var b := Button.new()
    b.text = ""
    b.name = "keys_" + id
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
    b.gui_input.connect(func(ev: InputEvent) -> void:
        if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
            var mb := ev as InputEventMouseButton
            if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
                if on_button.is_valid():
                    on_button.call("keysup")
            elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
                if on_button.is_valid():
                    on_button.call("keysdown"))
    box.add_child(b)
    return b


## Вкладка «звук»: громкость музыки и звуков боя, 0..10.
func _settings_sound(d: Dictionary) -> void:
    var music: int = int(d.get("music", 7))
    var sfx_v: int = int(d.get("sfx", 9))
    var sel: int = int(d.get("sel", 0))

    var top := 200.0 if touch_mode else 144.0
    _overlay_rect(238, top, 804, 380, Color(0.03, 0.04, 0.06, 0.80))
    var names := [Lang.t("music"), Lang.t("sfx")]
    var vals := [music, sfx_v]
    for i in 2:
        var y := (top + 106.0) + float(i) * 96.0
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
    if _is_touch(d):
        shint = Lang.t("touch_sound_hint")
    _overlay_label(shint, 0, 556.0 if touch_mode else 500, W, 14, Color(0.72, 0.78, 0.88))
    _overlay_label(Lang.t("sound_alive"), 0, 586.0 if touch_mode else 530, W, 12, MUTED)
    _overlay_label(Lang.t("touch_back_hint") if touch_mode else Lang.t("back"),
            0, 630.0 if touch_mode else 586, W, 14, Color(0.72, 0.78, 0.88))


## Вкладка «игра»: имя героя, язык, полный экран, выход.
func _settings_game(d: Dictionary) -> void:
    var sel: int = int(d.get("sel", 0))
    var lang: String = String(d.get("lang", "ru"))
    var full: bool = bool(d.get("fullscreen", false))
    var gtop := 200.0 if touch_mode else 144.0
    _overlay_rect(238, gtop, 804, 440 if touch_mode else 380, Color(0.03, 0.04, 0.06, 0.80))
    # T3: имя героя — поле ввода, кнопка сохранения и подсказка
    _overlay_label(Lang.t("name_label").to_upper(), 300, gtop + 12.0, 400, 11, MUTED,
            HORIZONTAL_ALIGNMENT_LEFT, false)
    name_edit = LineEdit.new()
    var fld_h := 84.0 if touch_mode else 42.0
    var fld_y := gtop + 24.0 if touch_mode else 178.0
    name_edit.position = Vector2(300, fld_y)
    name_edit.size = Vector2(400, fld_h)
    if SaveManager != null:
        name_edit.max_length = int(SaveManager.NAME_MAX)
        name_edit.text = String(SaveManager.player_name())
    else:
        name_edit.max_length = 16
    name_edit.placeholder_text = Lang.t("name_placeholder")
    name_edit.add_theme_font_override("font", font_n)
    name_edit.add_theme_font_size_override("font_size", 18)
    name_edit.add_theme_color_override("font_color", TEXT)
    name_edit.add_theme_color_override("font_placeholder_color", MUTED)
    var ne_n := StyleBoxFlat.new()
    ne_n.bg_color = Color(0.02, 0.03, 0.05, 0.92)
    ne_n.border_width_left = 1
    ne_n.border_width_right = 1
    ne_n.border_width_top = 1
    ne_n.border_width_bottom = 1
    ne_n.border_color = Color(1, 1, 1, 0.18)
    ne_n.corner_radius_top_left = 8
    ne_n.corner_radius_top_right = 8
    ne_n.corner_radius_bottom_left = 8
    ne_n.corner_radius_bottom_right = 8
    var ne_f: StyleBoxFlat = ne_n.duplicate()
    ne_f.border_color = ACCENT
    ne_f.border_width_left = 2
    ne_f.border_width_right = 2
    ne_f.border_width_top = 2
    ne_f.border_width_bottom = 2
    ne_n.content_margin_left = 12.0
    ne_n.content_margin_right = 12.0
    ne_f.content_margin_left = 12.0
    ne_f.content_margin_right = 12.0
    name_edit.add_theme_stylebox_override("normal", ne_n)
    name_edit.add_theme_stylebox_override("focus", ne_f)
    name_edit.add_theme_stylebox_override("read_only", ne_n)
    name_edit.mouse_filter = Control.MOUSE_FILTER_STOP
    # на Android тап по полю поднимает экранную клавиатуру
    name_edit.set("virtual_keyboard_enabled", true)
    name_edit.text_submitted.connect(func(_t: String) -> void: _save_player_name())
    overlay.add_child(name_edit)
    var save_b := _btn(Lang.t("name_save"), Vector2(716, fld_y), Vector2(184, fld_h), "namesave")
    # main.gd на время T3 закрыт: сохранение имени делает сам HUD
    save_b.pressed.connect(_save_player_name)
    _overlay_label(Lang.t("name_hint"), 300, gtop + 118.0 if touch_mode else 224.0, 600, 11,
            MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
    if name_msg != "":
        name_msg_lbl = _overlay_label(name_msg, 300, gtop + 138.0 if touch_mode else 242.0, 600, 11,
                Color(0.55, 0.86, 0.62), HORIZONTAL_ALIGNMENT_LEFT, false)
    var armed := bool(d.get("reset_armed", false))
    var blood_txt := String(d.get("blood_text", Lang.t("blood_off")))
    var names := [Lang.t("language"), Lang.t("fullscreen"), Lang.t("blood"),
            Lang.t("reset_progress")]
    var vals := ["РУССКИЙ" if lang == "ru" else "ENGLISH",
            Lang.t("on") if full else Lang.t("off"),
            blood_txt,
            Lang.t("reset_armed") if armed else "—"]
    for i in 4:
        var y := (300.0 + float(i) * 84.0) if touch_mode else (292.0 + float(i) * 66.0)
        var row_h := TOUCH_MIN * 0.8 if touch_mode else 54.0
        var row_col := TEXT if i < 3 else (RED if armed else Color(0.86, 0.62, 0.62))
        if i == sel:
            _overlay_rect(268, y - 22, 744, row_h, Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.14))
            _overlay_rect(268, y - 22, 4, row_h, ACCENT)
        _overlay_label(names[i], 300, y - 8, 300, 19, row_col, HORIZONTAL_ALIGNMENT_LEFT, i == sel)
        _overlay_label(vals[i], 760, y - 8, 220, 17, AMBER, HORIZONTAL_ALIGNMENT_RIGHT)
        var sub := ""
        if i == 0:
            sub = Lang.t("lang_hint")
        elif i == 1:
            sub = Lang.t("touch_full_hint") if touch_mode else Lang.t("full_hint")
        elif i == 2:
            sub = Lang.t("blood_hint")
        else:
            sub = "нажми ещё раз, чтобы стереть всё" if not Lang.is_en() else "press again to wipe everything"
        _overlay_label(sub, 300, y + 20, 600, 10, MUTED, HORIZONTAL_ALIGNMENT_LEFT, false)
        _hit(268, y - 22, 744, row_h, "gamerow%d" % i)
    var ghint := Lang.t("game_hint")
    if _is_touch(d):
        ghint = Lang.t("touch_game_hint")
    _overlay_label(ghint, 0, 620 if touch_mode else 596, W, 12, Color(0.72, 0.78, 0.88))

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
    if _is_touch(d):
        uhint = Lang.t("touch_upg_hint")
    _overlay_label(uhint, 0, 580, W, 14, Color(0.72, 0.78, 0.88))
    _overlay_label("форму дают: попадания в тренировке (2 за удар, 4 в голову) и каждый бой",
            0, 612, W, 11, MUTED)


func hide_overlay() -> void:
    overlay.visible = false
    for c in overlay.get_children():
        c.queue_free()


# ------------------------------------------------------- аудит кнопок (task-47)
## --btnaudit: прозвон всех экранов через штатные переключатели main.
## Ищет кнопки без обработчика pressed, перекрытые соседними STOP-контролами,
## с фильтром IGNORE, нулевого размера, вне канвы и вне safe-area.
## Печатает BTAUDIT <экран>: ... и итог BTAUDIT ок=true|false.
var _bt_ok := true
var _bt_rows: Array = []


func _run_btnaudit() -> void:
    get_tree().create_timer(90.0).timeout.connect(func() -> void:
        print("BTAUDIT ок=false (таймаут)")
        get_tree().quit())
    await get_tree().process_frame
    await get_tree().process_frame
    var main := get_tree().current_scene
    if main == null:
        print("BTAUDIT ок=false (нет main)")
        get_tree().quit()
        return
    var screens: Array = [
        ["menu", "_leave_to_menu", -1],
        ["settings_keys", "_open_settings", 0],
        ["settings_sound", "_open_settings", 1],
        ["settings_game", "_open_settings", 2],
        ["stats", "_open_stats", -1],
        ["story", "_open_story", -1],
        ["tour", "_open_tournaments", -1],
        ["upgrade", "_open_upgrades", -1],
        ["locker", "_open_locker", -1],
        ["howto", "_open_howto", -1],
        ["prefight", "_start_prefight", -1],
        ["pause", "_mt_pause", -1],
        ["result", "_mt_result", -1],
        ["training_hub", "_open_training_hub", -1],
        ["training", "_open_training", -1],
        ["arena_hub", "_open_arena_hub", -1],
        ["net", "_open_net_lobby", -1],
        ["coop", "_open_coop_lobby", -1],
    ]
    for row in screens:
        var name := String(row[0])
        var fn := String(row[1])
        var arg := int(row[2])
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
        var root: Control = overlay
        var rm = main.get("training_mode")
        if name.begins_with("training") and rm != null and rm.get("_root") != null:
            root = rm.get("_root")
        elif name == "arena_hub":
            var am = main.get("arena_manager")
            if am != null and am.get("_root") != null:
                root = am.get("_root")
        elif name == "net":
            var nf = main.get("net_fight")
            if nf != null and nf.get("_root") != null:
                root = nf.get("_root")
        elif name == "coop":
            var cl = main.get("coop_lobby")
            if cl != null and cl.get("_root") != null:
                root = cl.get("_root")
        await get_tree().process_frame
        await _bt_audit_screen(name, root)
        main.call("_leave_to_menu")
        await get_tree().process_frame
    for r in _bt_rows:
        print("BTAUDIT ", r)
    print("BTAUDIT ок=", str(_bt_ok))
    get_tree().quit()


func _bt_audit_screen(name: String, root: Control) -> void:
    if root == null:
        _bt_ok = false
        _bt_rows.append("%s: НЕТ КОРНЯ" % name)
        return
    var buttons: Array = []
    _bt_collect(root, buttons)
    var canvas := Vector2(W, 720.0)
    if root == overlay:
        canvas = _canvas()
    var safe := Vector4.ZERO
    if root == overlay:
        safe = _safe
    var no_handler := 0
    var blocked := 0
    var ignored := 0
    var zero := 0
    var outside := 0
    var safe_bad := 0
    var disabled := 0
    var hidden := 0
    var problems: Array = []
    for ctl in buttons:
        var c: Control = ctl
        if not c.is_visible_in_tree():
            hidden += 1
            continue
        if c.size.x < 2.0 or c.size.y < 2.0:
            zero += 1
            problems.append("нулевой:" + _bt_name(c))
            continue
        if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
            ignored += 1
            problems.append("IGNORE:" + _bt_name(c))
        if c is BaseButton and (c as BaseButton).disabled:
            disabled += 1
            problems.append("disabled:" + _bt_name(c))
        if not c.has_signal("pressed"):
            no_handler += 1
            problems.append("нет_сигнала:" + _bt_name(c))
        elif c.get_signal_connection_list("pressed").is_empty():
            no_handler += 1
            problems.append("нет_обработчика:" + _bt_name(c))
        var r := c.get_global_rect()
        if r.position.x < -1.0 or r.position.y < -1.0 \
                or r.end.x > canvas.x + 1.0 or r.end.y > canvas.y + 1.0:
            outside += 1
            problems.append("вне_канвы:%.0f,%.0f %.0fx%.0f" % [r.position.x,
                    r.position.y, r.size.x, r.size.y])
        if r.position.x < safe.x - 1.0 or r.position.y < safe.y - 1.0 \
                or r.end.x > canvas.x - safe.z + 1.0 \
                or r.end.y > canvas.y - safe.w + 1.0:
            safe_bad += 1
            problems.append("safe-area:" + _bt_name(c))
        var top := _bt_topmost_at(root, r.get_center())
        if top != null and top != c and not c.is_ancestor_of(top) \
                and not top.is_ancestor_of(c):
            blocked += 1
            problems.append("перекрыта(%s):%s" % [_bt_name(top), _bt_name(c)])
    # живая проверка: реальный клик мышью по центру каждой кнопки в оконном
    # прогоне (обработчики временно отключаем, чтобы ничего не нажать по-настоящему)
    var not_clickable := 0
    var live := DisplayServer.get_name() != "headless"
    if live:
        for ctl in buttons:
            var c: Control = ctl
            if not c.is_visible_in_tree() or c.size.x < 2.0 or c.size.y < 2.0:
                continue
            if c is BaseButton and (c as BaseButton).disabled:
                continue
            if c.mouse_filter == Control.MOUSE_FILTER_IGNORE:
                continue
            if not await _bt_live_press(c):
                not_clickable += 1
                problems.append("не_нажимается:" + _bt_name(c))
    # disabled — это штатные закрытые локации/арены, не ошибка
    var ok := no_handler == 0 and blocked == 0 and ignored == 0 \
            and zero == 0 and outside == 0 and safe_bad == 0 and not_clickable == 0
    if not ok:
        _bt_ok = false
    var line := "%s: кнопок=%d скрыто=%d без_обработчика=%d перекрыто=%d IGNORE=%d нулевых=%d вне_канвы=%d safe=%d disabled=%d не_нажимается=%d" \
            % [name, buttons.size(), hidden, no_handler, blocked, ignored, zero,
            outside, safe_bad, disabled, not_clickable]
    if not problems.is_empty():
        line += " | " + ", ".join(problems.slice(0, 6))
    _bt_rows.append(line)


## Живой клик: отключаем штатные обработчики, кликаем настоящей мышью через
## вьюпорт и смотрим, дошло ли событие до кнопки. Потом обработчики возвращаем.
func _bt_live_press(c: Control) -> bool:
    var conns: Array = c.get_signal_connection_list("pressed")
    for d in conns:
        c.disconnect("pressed", d["callable"])
    var got := [false]
    var probe := func() -> void: got[0] = true
    c.connect("pressed", probe)
    # координаты для push_input — в пикселях окна, а не канвы: при масштабе
    # канвы (телефон/большое окно) get_global_rect() даёт координаты канвы
    # канва-координаты + push_input(..., true): push_input сам переводит их
    # в координаты окна при растяжении (телефон/большое окно)
    var p: Vector2 = c.get_global_rect().get_center()
    # сначала движение мыши: GUI обновляет «под курсором» и enter/hover,
    # без этого на масштабированной канве кнопка иногда не получает press
    var mv := InputEventMouseMotion.new()
    mv.position = p
    mv.global_position = p
    get_viewport().push_input(mv, true)
    for down in [true, false]:
        var ev := InputEventMouseButton.new()
        ev.button_index = MOUSE_BUTTON_LEFT
        ev.pressed = down
        ev.position = p
        ev.global_position = p
        get_viewport().push_input(ev, true)
    await get_tree().process_frame
    c.disconnect("pressed", probe)
    for d in conns:
        c.connect("pressed", d["callable"])
    if not got[0]:
        print("BTDEBUG не_нажата: ", _bt_name(c), " rect=", c.get_global_rect(),
                " точка=", p, " окно=", get_viewport().get_visible_rect().size,
                " канва=", _canvas())
    return bool(got[0])


func _bt_name(c: Control) -> String:
    var t := ""
    if c is BaseButton:
        t = (c as BaseButton).text
    if t == "":
        t = String(c.name)
    if t == "":
        t = c.get_class()
    return t.replace("\n", " ").substr(0, 28)


func _bt_collect(node: Node, out: Array) -> void:
    for ch in node.get_children():
        if ch is BaseButton:
            out.append(ch)
        elif ch is Control and (ch as Control).has_signal("pressed"):
            out.append(ch)
        _bt_collect(ch, out)


## Верхний Control в точке — в порядке отрисовки Godot (поздние дети выше).
func _bt_topmost_at(node: Control, p: Vector2) -> Control:
    for i in range(node.get_child_count() - 1, -1, -1):
        var ch := node.get_child(i)
        if not (ch is Control):
            continue
        var c := ch as Control
        if not c.is_visible_in_tree() or not c.get_global_rect().has_point(p):
            continue
        var deep := _bt_topmost_at(c, p)
        if deep != null:
            return deep
        if c.mouse_filter != Control.MOUSE_FILTER_IGNORE:
            return c
    return null




























