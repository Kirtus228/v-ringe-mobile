class_name TrainingMode
extends Node3D
## Режим «Тренировка» Этапа 3: хаб с 5 локациями → локация → станции.
## Всё строится процедурно (в проекте нет сцен): хаб — UI-карточки, локация —
## комната со станциями (Area3D + Label3D), упражнения — по StationDef.kind.
## main.gd только создаёт модуль и переключает состояния/ввод; прогресс станций,
## прочность и визиты лежат в SaveManager ([training]), статы — в StatsManager.
##
## Публичный API для main.gd: open_hub(), open_location(id), close(), show_hub(),
## show_location(), tick(delta), update_camera(delta), handle_key(event).
## Для тестов — begin_station/press_action/tick_station/station_result и т.п.

const Lang = preload("res://scripts/lang.gd")
const SECTION := "training"
const StationScript := preload("res://scripts/training/station.gd")
## Этап 5 визуала: декор локаций (props/свет/звук/частицы/грейд).
var DecorScript: GDScript = null  # загружается лениво в _load_decor_script (fallback без файла)
const FactoryScript := preload("res://scripts/training/training_config_factory.gd")
## Этап 1 визуала: каркас процедурных ключей анимации станций (при OFF — no-op).
const TrainAnimScript := preload("res://scripts/training/anims/anim_base.gd")
## Этап 3, волна 1: BAG-клип (антиципация → удар → impact → follow → возврат).
const TrainAnimBagScript := preload("res://scripts/training/anims/anim_bag.gd")
## Этап 3, волна 2: QTE-клипы.
const TrainAnimStrikeScript := preload("res://scripts/training/anims/anim_strike.gd")
const TrainAnimLiftScript := preload("res://scripts/training/anims/anim_lift.gd")
const TrainAnimPullScript := preload("res://scripts/training/anims/anim_pull.gd")
## Этап 3, волны 3-4: бёрпи, прыжки, повторы, HOLD.
const TrainAnimBurpeeScript := preload("res://scripts/training/anims/anim_burpee.gd")
const TrainAnimJumpScript := preload("res://scripts/training/anims/anim_jump.gd")
const TrainAnimRepeatScript := preload("res://scripts/training/anims/anim_repeat.gd")
const TrainAnimSustainScript := preload("res://scripts/training/anims/anim_sustain.gd")
## v69: отжимания на брусьях (park/dips) — заменили бег в парке.
const TrainAnimDipsScript := preload("res://scripts/training/anims/anim_dips.gd")
const REPAIR_WINDOW := 0.30
## на каком расстоянии (м) станция считается «ближайшей» для E
const INTERACT_RADIUS := 2.0
## границы комнаты для ходьбы (WASD)
const WALK_MIN := Vector2(-4.2, -3.0)
const WALK_MAX := Vector2(4.2, 3.6)

var main: Node
## Этап 1 визуала: тот же VisualConfig, что в main (visual_level/train_anim_level).
var visual = null
## Каркас процедурных ключей анимации станций; при train_anim_level=OFF — no-op.
var anim = null
## Этап 3: BAG-клип (тайминг удара/impact/follow + промах).
var bag_anim = null
## Этап 3, волна 2: QTE-клипы (удар/жим/подтягивание).
var strike_anim = null
var lift_anim = null
var pull_anim = null
var burpee_anim = null
var jump_anim = null
var repeat_anim = null
var sustain_anim = null
## v69: отжимания на брусьях.
var dips_anim = null
var _beat_frame := -1
var _last_logged_phase := ""
## Текущий активный клип и id станции (диспетчеризация impact/промаха).
var _active_anim = null
var _active_station_id := ""
var _press_frame := 0
var _press_win_frac := 0.5
## Уровень аудио-анимации (0..2) — кэш из VisualConfig.train_anim_level.
var _anim_level := 0
var _anim_clock := 0.0
## Таймер «живого» отладочного клипа (--frames).
var _live_t := 0.0
## T-trainanim: демо-кадр — сразу начать станцию (env VRINGE_TRAIN_DEMO=1)
var _train_demo := false
## T-trainanim: режим камеры для кадров «до/после»: legacy | focus (env VRINGE_TRAIN_CAM)
var _train_cam_mode := ""
## Отладочный статичный кадр фазы для скриншотов (env VRINGE_ANIM_SHOT),
## в обычной игре пусто → код не выполняется.
var _debug_shot_phase := ""
## id станции для отладочных демо-кадров (env VRINGE_ANIM_STATION).
var _debug_station_id := ""
var _pending_hit_dir := Vector3.ZERO
var config: TrainingConfig
var locations: Array[TrainingLocationDef] = []
var profile := InputProfile.new()

var active := false
var screen := "hub"          # hub | loc
var current_location_id := ""
var sel := 0
var last_result: Dictionary = {}
var result_open := false
## id ближайшей станции (подсветка + запуск по E), "" — нет в радиусе
var _nearest_id := ""

var location_root: Node3D
var camera: Camera3D
## Этап 5: декор текущей локации (null при visual_level=OFF и в хабе).
var decor: Node3D = null
## Отладочный ракурс кадра локации: VRINGE_LOC_CAM = wide|hero|stations.
var _loc_shot_cam := ""
var stations: Dictionary = {}   # id -> Node3D (TrainingStation)
var station: Node3D = null
var order: Array[String] = []   # порядок станций текущей локации

var repair_on := false
var _repair_loc := ""
var _repair_id := ""
var _repair_prompt := -1.0
var _repair_next := 0.6
var repair_result := ""

# --- UI
var ui: CanvasLayer
var _root: Control
var _backdrop: ColorRect
var _panel: ColorRect
var _title: Label
var _sub: Label
var _hint: Label
var _status: Label
var _cards: Array[Button] = []
var _station_btns: Array[Button] = []
var _back_btn: Button
## v45: тач-кнопки упражнения. На телефоне нет Space/E — без них упражнение
## (штанга, груша, скакалка, бег, канат) не пройти: было «не получается качаться».
var _act_btn: Button
var _stop_btn: Button
## действие сейчас «держится» пальцем (станции HOLD — бег/канат)
var _touch_held := false
## остаток нажатия после тапа по 3D: короткий «держу», чтобы HOLD тоже реагировал
var _touch_hold_t := 0.0
## тач-кнопки включены принудительно (тесты на ПК без тач-экрана)
var _touch_force := false
var _overlay: ColorRect
var _ov_title: Label
var _ov_hint: Label
var _ov_line1: Label
var _ov_line2: Label
## v59: крупная подсказка «ЖМИ!» и полоса окна — чтобы момент нажатия был виден
## без приглядывания к мелкой строке внизу.
var _cue: Label
var _cue_bar: ColorRect
## v69: обозначитель действия на ПК — крупная строка «E — УДАР» над нижней панелью.
var _act_hint: Label
## v59: всплывающий результат нажатия («ЗАСЧИТАНО» / «ПРОМАХ» / «РАНО»).
var _flash: Label
var _flash_t := 0.0
## окно было открыто в прошлом кадре — по переходу играем звук-«тик»
var _prompt_prev := false
var _prompt_sound_prev := false


func setup(main_ref: Node) -> void:
    main = main_ref
    _load_decor_script()
    _setup_visual_anim()
    config = FactoryScript.create_default()
    locations = config.locations
    _build_camera()
    _build_ui()
    ui.visible = false


## Ленивая загрузка модуля декора: если файла нет (fallback-сборка без
## визуала), проект всё равно компилируется и работает — просто без декора.
func _load_decor_script() -> void:
    if DecorScript != null:
        return
    var path: String = "res://scripts/training/locations/location_decor.gd"
    if ResourceLoader.exists(path):
        var res: Resource = load(path)
        if res is GDScript:
            DecorScript = res as GDScript


## Этап 1/3 визуала: ЕДИНСТВЕННАЯ точка настройки train_anim_level в этом файле.
## visual приходит из main (VisualConfig); без него уровень OFF — как до правок.
func _setup_visual_anim() -> void:
    _anim_level = 0
    if visual != null:
        _anim_level = int(visual.train_anim_level)
    anim = TrainAnimScript.new()
    anim.set_level(_anim_level)
    bag_anim = TrainAnimBagScript.new()
    bag_anim.set_level(_anim_level)
    bag_anim.impact_reached.connect(_on_clip_impact)
    strike_anim = TrainAnimStrikeScript.new()
    strike_anim.set_level(_anim_level)
    strike_anim.impact_reached.connect(_on_clip_impact)
    lift_anim = TrainAnimLiftScript.new()
    lift_anim.set_level(_anim_level)
    lift_anim.impact_reached.connect(_on_clip_impact)
    burpee_anim = TrainAnimBurpeeScript.new()
    burpee_anim.set_level(_anim_level)
    burpee_anim.impact_reached.connect(_on_clip_impact)
    jump_anim = TrainAnimJumpScript.new()
    jump_anim.set_level(_anim_level)
    jump_anim.impact_reached.connect(_on_clip_impact)
    repeat_anim = TrainAnimRepeatScript.new()
    repeat_anim.set_level(_anim_level)
    repeat_anim.impact_reached.connect(_on_clip_impact)
    sustain_anim = TrainAnimSustainScript.new()
    sustain_anim.set_level(_anim_level)
    sustain_anim.impact_reached.connect(_on_clip_impact)
    pull_anim = TrainAnimPullScript.new()
    pull_anim.set_level(_anim_level)
    pull_anim.impact_reached.connect(_on_clip_impact)
    dips_anim = TrainAnimDipsScript.new()
    dips_anim.set_level(_anim_level)
    dips_anim.impact_reached.connect(_on_clip_impact)
    # отладочный кадр фазы (только для скриншотов; в игре env не задан)
    _debug_shot_phase = OS.get_environment("VRINGE_ANIM_SHOT").strip_edges()
    _debug_station_id = OS.get_environment("VRINGE_ANIM_STATION").strip_edges()
    _loc_shot_cam = OS.get_environment("VRINGE_LOC_CAM").strip_edges()
    _train_demo = OS.get_environment("VRINGE_TRAIN_DEMO").strip_edges() != ""
    _train_cam_mode = OS.get_environment("VRINGE_TRAIN_CAM").strip_edges().to_lower()


## Анимация включена? (одна проверка уровня для всех визуальных веток).
func _anim_on() -> bool:
    return _anim_level != 0


## Impact клипа: толчок снаряда/пыль/вибрация ровно в момент пика + лог кадра.
## Лог нужен для гейта: момент нажатия vs момент impact (разница кадров).
func _on_clip_impact() -> void:
    if station == null or not _anim_on():
        return
    var id := _active_station_id
    if station.has_method("animate_hit"):
        station.animate_hit(_pending_hit_dir)
    if id == "tires" and station.has_method("emit_dust"):
        station.emit_dust(_pending_hit_dir)
    if id == "bar" and station.has_method("animate_pull"):
        station.animate_pull(1.0)
    var now := Engine.get_frames_drawn()
    var d := now - _press_frame
    var clip := "bag"
    if _active_anim == pull_anim:
        clip = "pull"
    elif _active_anim == lift_anim:
        clip = "lift"
    elif _active_anim == strike_anim:
        clip = "strike"
    elif _active_anim == burpee_anim:
        clip = "burpee"
    elif _active_anim == jump_anim:
        clip = "jump"
    elif _active_anim == repeat_anim:
        clip = "repeat"
    elif _active_anim == sustain_anim:
        clip = "sustain"
    print("ANIMIMPACT станция=", id, " клип=", clip,
            " нажатие_кадр=", _press_frame, " impact_кадр=", now,
            " дельта_кадров=", d, " окно_доля=", snappedf(_press_win_frac, 0.01),
            " impact_в_окне=", str(d <= 6))


## Множитель энергии света локации из visual_level.
## OFF (по умолчанию) — ровно 1.0, свет локации не меняется ни на бит.
func _visual_light_mult() -> float:
    if visual == null:
        return 1.0
    return float(visual.light_mult())


# ---------------------------------------------------------------- публичный API

func open_hub() -> void:
    active = true
    screen = "hub"
    sel = 0
    result_open = false
    _clear_room()
    _hide_world(true)
    if _player() != null:
        _player().visible = false   # в хабе боец не нужен, только карточки
    ui.visible = true
    camera.position = Vector3(0.0, 2.0, 8.0)
    camera.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
    camera.make_current()
    show_hub()


func open_location(id: String) -> bool:
    var loc := config.find_location(id)
    if loc == null or not is_location_unlocked(id):
        return false
    active = true
    screen = "loc"
    current_location_id = id
    sel = 0
    result_open = false
    station = null
    repair_on = false
    _clear_room()
    _hide_world(true)
    _build_room(loc)
    _apply_anim_level_stations()
    _place_player(Vector3(0.0, 0.0, 3.2), Vector3(0.0, 0.0, -1.4))
    ui.visible = true
    camera.make_current()
    _mark_visited(id)
    _update_nearest()
    show_location()
    _debug_setup_shot()
    return true


func close() -> void:
    active = false
    station = null
    repair_on = false
    result_open = false
    _flash_t = 0.0
    _prompt_prev = false
    _prompt_sound_prev = false
    if _cue != null:
        _cue.visible = false
        _cue_bar.visible = false
        _flash.visible = false
    _clear_room()
    if ui != null:
        ui.visible = false
    _hide_world(false)
    if main != null and main.get("cam") != null:
        (main.cam as Camera3D).make_current()


func show_hub() -> void:
    screen = "hub"
    _render_hub()


func show_location() -> void:
    screen = "loc"
    _render_location()


func is_active() -> bool:
    return active


func current_screen() -> String:
    return screen


func location_ids() -> Array[String]:
    var ids: Array[String] = []
    for l in locations:
        ids.append(l.id)
    return ids


func station_ids(loc_id: String) -> Array[String]:
    var ids: Array[String] = []
    var loc := config.find_location(loc_id)
    if loc == null:
        return ids
    for s in loc.stations:
        ids.append(s.id)
    return ids


func location_of(loc_id: String) -> TrainingLocationDef:
    return config.find_location(loc_id)


func station_def(loc_id: String, st_id: String) -> StationDef:
    return config.find_station(loc_id, st_id)


## Разблокирована ли локация по её условию unlock (с учётом visited/статов).
func is_location_unlocked(loc_id: String) -> bool:
    var loc := config.find_location(loc_id)
    if loc == null:
        return false
    if not config.use_location_unlocks:
        return true
    # отладка кадров: VRINGE_UNLOCK_ALL=1 открывает все локации (в игре не задан)
    if OS.get_environment("VRINGE_UNLOCK_ALL") != "":
        return true
    var u: Dictionary = loc.unlock
    if u.is_empty():
        return true
    if u.has("visited"):
        for v in u["visited"]:
            if not _load_bool("visited/" + String(v)):
                return false
        return true
    if u.has("stat"):
        var name := String(u["stat"])
        var minimum := float(u.get("min", 0.0))
        return StatsManager.get_stat(name) >= minimum if StatsManager != null else false
    if u.has("any_stat"):
        var arr: Array = u["any_stat"]
        if arr.size() >= 2:
            return StatsManager.get_stat(String(arr[0])) >= float(arr[1]) \
                    if StatsManager != null else false
    return true


func unlock_text(loc_id: String) -> String:
    var loc := config.find_location(loc_id)
    if loc == null:
        return ""
    var u: Dictionary = loc.unlock
    if u.has("visited"):
        var names: Array[String] = []
        for v in u["visited"]:
            var vl := config.find_location(String(v))
            names.append(vl.title if vl != null else String(v))
        return Lang.t("train_need_visit") % ", ".join(names)
    if u.has("stat"):
        return Lang.t("train_need_stat") % [
                _stat_name(String(u["stat"])), int(float(u.get("min", 0.0)))]
    return ""


# ---------------------------------------------------------------- станции

func begin_station(st_id: String) -> bool:
    if screen != "loc" or current_location_id == "":
        return false
    var st: Node3D = _station_by_id(st_id)
    if st == null:
        return false
    result_open = false
    repair_on = false
    last_result = {}
    station = st
    var begun: bool = st.begin()
    # v71s: «покрышки» бьют кувалдой — станция забирает молот в руки бойца на
    # время подхода и возвращает на место после (метод есть только у неё).
    if begun and st.has_method("set_holder"):
        st.set_holder(_player())
    return begun


func station_active() -> bool:
    return station != null and station.active


func station_finished() -> bool:
    return station != null and station.finished


func station_kind() -> int:
    return station.kind() if station != null else -1


func station_prompt_open() -> bool:
    return station != null and station.prompt_open()


func station_hold_progress() -> float:
    return station.hold_progress() if station != null else 0.0


func get_station() -> Node3D:
    return station


## v59: отладочный кадр — открыть окно нажатия и держать его для скриншота.
func debug_hold_prompt(on: bool) -> void:
    if station != null:
        station.debug_hold_prompt = on


## v59: «тап» по активной станции извне (клавиша удара в зале на ПК, кнопка на
## телефоне). Для HOLD оставляем короткое «держу», чтобы удержание тоже шло.
func tap_press() -> String:
    # v60: если упражнение не идёт — это нажатие подходит к ближайшей станции или
    # закрывает окно результата. Иначе клавиша E в зале перестала бы работать:
    # её теперь забирает обработчик ударов (любая клавиша удара = нажатие).
    if result_open:
        confirm_result()
        return "confirm"
    if station != null and station.active:
        _touch_hold_t = maxf(_touch_hold_t, 0.45)
        return press_action()
    if screen == "loc" and _nearest_id != "":
        begin_station(_nearest_id)
        return "start_station"
    return "ignored"


## Одно нажатие действия в активной станции.
func press_action() -> String:
    if station == null or not station.active:
        return "ignored"
    var r: String = station.press()
    match r:
        "hit":
            _play(station.def.sfx_hit)
            _anim_hit()
            _flash_text("ЗАСЧИТАНО" if not Lang.is_en() else "HIT", Color(0.55, 0.86, 0.62))
        "miss":
            _play(station.def.sfx_fail)
            _anim_miss()
            _flash_text("ПРОМАХ" if not Lang.is_en() else "MISS", Color(0.92, 0.42, 0.38))
        "early":
            # v59: рано нажал — не промах, просто подсказка (никаких штрафов)
            _play("block")
            _flash_text("РАНО — ЖДИ ПОДСКАЗКУ" if not Lang.is_en() else "TOO EARLY — WAIT",
                    Color(0.80, 0.84, 0.95))
        "wait":
            _play("block")
            _flash_text("ЖДИ" if not Lang.is_en() else "WAIT", Color(0.80, 0.84, 0.95))
        "start":
            # 3.8 HOLD: нажали и держим — запускаем циклический клип удержания
            _anim_start_hold()
    return r


## v59: короткая всплывающая строка результата нажатия (гаснет в tick).
func _flash_text(text: String, col: Color) -> void:
    if _flash == null:
        return
    _flash.text = text
    _flash.add_theme_color_override("font_color", col)
    _flash.visible = true
    _flash_t = 0.7


## Этап 3: старт клипа на попадании. Выбор клипа — по id станции:
## speedbag/tires → удар (3.2), barbell/homemade_bar → жим (3.3), bar → подтягивание (3.4),
## остальные BAG-станции → мешок (волна 1). OFF → ничего не делает.
func _anim_hit() -> void:
    if not _anim_on() or station == null:
        return
    var loc_id := current_location_id
    var st: Node3D = station
    var id := String(st.def.id)
    var p := _player()
    _pending_hit_dir = Vector3(0.0, 0.0, -1.0)
    if p != null:
        var d: Vector3 = st.global_position - p.global_position
        d.y = 0.0
        if d.length() > 0.001:
            _pending_hit_dir = d.normalized()
    _active_station_id = id
    _press_frame = Engine.get_frames_drawn()
    _press_win_frac = float(st.prompt_frac()) if st.has_method("prompt_frac") else 0.5
    var ok := false
    if id == "speedbag" or id == "tires":
        ok = strike_anim.play_hit(loc_id, id, _press_win_frac)
        _active_anim = strike_anim if ok else null
    elif id == "barbell" or id == "homemade_bar":
        ok = lift_anim.play_hit(loc_id, id, _press_win_frac)
        _active_anim = lift_anim if ok else null
    elif id == "bar":
        ok = pull_anim.play_hit(loc_id, id, _press_win_frac)
        _active_anim = pull_anim
        # лог гейта: частые нажатия не должны обрывать цикл (pending/chain)
        print("ANIMPULL нажатие=", Engine.get_frames_drawn(),
                " уже_играл=", str(not ok), " chain=", pull_anim.chain,
                " pending=", str(pull_anim.pending))
    elif id == "burpee":
        ok = burpee_anim.play_hit(loc_id, id, _press_win_frac, _st_interval(st))
        _active_anim = burpee_anim if ok else null
    elif id == "rope" or id == "speedrope":
        ok = jump_anim.play_jump(loc_id, id, _st_interval(st))
        _active_anim = jump_anim if ok else null
        if ok:
            _log_beat(id)
    elif id == "pushups" or id == "shadow":
        ok = repeat_anim.play_hit(loc_id, id, _st_interval(st))
        _active_anim = repeat_anim if ok else null
        if ok:
            _log_beat(id)
    elif id == "dips":
        ok = dips_anim.play_hit(loc_id, id, _st_interval(st))
        _active_anim = dips_anim if ok else null
        if ok:
            _log_beat(id)
    else:
        ok = bag_anim.play_hit(loc_id, id)
        _active_anim = bag_anim if ok else null


## T-trainanim: темп анимации = фактическая пауза между окнами (3–5 с), а не
## старый interval. Клипы сами клампят длительность, поэтому движение плавное.
func _st_interval(st: Node3D) -> float:
    if st != null and st.has_method("interval_now"):
        return float(st.interval_now())
    return float(st.def.interval) if st != null else 3.5


## 3.8 HOLD: старт циклического клипа удержания (run/climb).
func _anim_start_hold() -> void:
    if not _anim_on() or station == null:
        return
    var id := String(station.def.id)
    if id != "run" and id != "climb" and id != "treadmill":
        return
    _active_station_id = id
    _press_frame = Engine.get_frames_drawn()
    _active_anim = sustain_anim
    sustain_anim.start_hold(current_location_id, id, 1.0)


## 3.6/3.7: лог такта — дельта в кадрах между подсказками (гейт: не растёт).
func _log_beat(id: String) -> void:
    var now := Engine.get_frames_drawn()
    if _beat_frame >= 0:
        print("ANIMBEAT станция=", id, " такт_кадров=", now - _beat_frame,
                " кадр=", now)
    _beat_frame = now


## Этап 3: клип промаха (удар — без пыли, жим — штанга падает, подтягивание — срыв).
func _anim_miss() -> void:
    if not _anim_on() or station == null:
        return
    var loc_id := current_location_id
    var id := String(station.def.id)
    _press_win_frac = float(station.prompt_frac()) if station.has_method("prompt_frac") else 0.5
    if id == "speedbag" or id == "tires":
        strike_anim.play_miss_hit(loc_id, id)
        _active_anim = strike_anim
    elif id == "barbell" or id == "homemade_bar":
        lift_anim.play_miss_hit(loc_id, id)
        _active_anim = lift_anim
        if station.has_method("animate_drop"):
            station.animate_drop()
    elif id == "bar":
        pull_anim.play_miss_hit(loc_id, id)
        _active_anim = pull_anim
    elif id == "dips":
        dips_anim.play_miss_hit(loc_id, id)
        _active_anim = dips_anim
    else:
        bag_anim.play_miss_hit(loc_id, id)
        _active_anim = bag_anim


## Раздать уровень анимации всем станциям локации (при OFF остаётся false).
func _apply_anim_level_stations() -> void:
    var on := _anim_on()
    var budget := 300
    if visual != null:
        budget = int(visual.particle_budget())
    for id in order:
        var st: Node3D = stations[id]
        if st == null:
            continue
        st.anim_on = on
        st.particle_budget = budget
        if not on and st.has_method("reset_anim"):
            st.reset_anim()
    var pl := _player()
    if pl != null and pl.has_method("set_train_pose_enabled"):
        pl.set_train_pose_enabled(on)


## Покадровое обновление станции (held — удержание действия для HOLD).
func tick_station(delta: float, held: bool = false) -> void:
    if station == null:
        return
    station.tick(delta, held)
    _update_overlay()


func abort_station() -> void:
    if station != null and station.active:
        station.abort()
    if station != null and station.has_method("set_holder"):
        station.set_holder(null)
    result_open = false


func station_result() -> Dictionary:
    if station == null:
        return last_result.duplicate(true)
    return {"station": station.def.id, "ok": station.ok, "reps": station.reps_done,
            "mistakes": station.mistakes, "gain": station.gain.duplicate(true),
            "durability": station.durability}


func confirm_result() -> void:
    result_open = false
    _update_ui()


## Починка сломанной станции: QTE-окно 0.3 с, успех восстанавливает прочность.
func begin_repair(st_id: String) -> bool:
    if screen != "loc":
        return false
    var st: Node3D = _station_by_id(st_id)
    if st == null or not st.is_broken():
        return false
    repair_on = true
    _repair_loc = current_location_id
    _repair_id = st_id
    _repair_prompt = -1.0
    _repair_next = 0.6
    repair_result = ""
    result_open = false
    last_result = {}
    station = null
    return true


func repair_active() -> bool:
    return repair_on


func repair_prompt_open() -> bool:
    return repair_on and _repair_prompt >= 0.0


func tick_repair(delta: float) -> void:
    if not repair_on:
        return
    if _repair_prompt >= 0.0:
        _repair_prompt += delta
        if _repair_prompt > REPAIR_WINDOW:
            _repair_prompt = -1.0
            repair_result = "miss"
            _repair_next = 0.6
    _repair_next -= delta
    if _repair_prompt < 0.0 and _repair_next <= 0.0:
        _repair_prompt = 0.0
        _repair_next = 0.6
    _update_overlay()


func press_repair() -> String:
    if not repair_on:
        return "ignored"
    if _repair_prompt < 0.0 or _repair_prompt > REPAIR_WINDOW:
        repair_result = "miss"
        _repair_prompt = -1.0
        _repair_next = 0.6
        return "miss"
    var st: Node3D = _station_by_id(_repair_id)
    if st != null:
        st.durability = minf(config.durability_max, st.durability + config.repair_restore)
        st.update_label()
        _save_float("durability/%s/%s" % [_repair_loc, _repair_id], st.durability)
    _flush()
    repair_on = false
    repair_result = "ok"
    last_result = {"station": _repair_id, "ok": true, "repair": true,
            "durability": st.durability if st != null else 0.0}
    result_open = true
    _play("shove")
    _update_ui()
    return "ok"


func cancel_repair() -> void:
    repair_on = false
    repair_result = ""
    _update_ui()


# ---------------------------------------------------------------- прогресс

func mastery(loc_id: String, st_id: String) -> float:
    return _load_float("mastery/%s/%s" % [loc_id, st_id], 0.0)


func durability(loc_id: String, st_id: String) -> float:
    return _load_float("durability/%s/%s" % [loc_id, st_id], config.durability_max)


func is_station_broken(loc_id: String, st_id: String) -> bool:
    return durability(loc_id, st_id) <= 0.0


func visits(loc_id: String) -> bool:
    return _load_bool("visited/" + loc_id)


## Звук промаха станции (станция зовёт при miss).
func play_fail(st: Node3D) -> void:
    _play(String(st.def.sfx_fail))


## Станция успешно отработала повтор: статы с бонусом локации + мастерство.
func station_gain(st: Node3D) -> void:
    var applied := {}
    for k in st.def.stat_bonus:
        var amount: float = float(st.def.stat_bonus[k]) * float(st.location.bonus_mult(String(k)))
        var got := StatsManager.add_stat(String(k), amount) if StatsManager != null else 0.0
        applied[String(k)] = got
        if got > 0.0:
            st.gain[String(k)] = float(st.gain.get(String(k), 0.0)) + got
    var key := "mastery/%s/%s" % [st.location.id, st.def.id]
    _save_float(key, minf(100.0, mastery(st.location.id, st.def.id) + 1.0))
    _flush()


## Износ оборудования: одна успешная единица работы = wear_per_use прочности.
func consume_wear(st: Node3D) -> void:
    if float(st.def.wear_per_use) <= 0.0:
        return
    st.durability = maxf(0.0, st.durability - float(st.def.wear_per_use))
    _save_float("durability/%s/%s" % [st.location.id, st.def.id], st.durability)
    st.update_label()
    _flush()


func on_station_finished(st: Node3D) -> void:
    result_open = true
    last_result = station_result()
    # v71s: подход закончен — кувалда возвращается на место (если станция её давала).
    if st != null and st.has_method("set_holder"):
        st.set_holder(null)
    _update_ui()
    _flush()


# ---------------------------------------------------------------- кадр и ввод

func tick(delta: float) -> void:
    if not active:
        return
    if _flash_t > 0.0:
        _flash_t = maxf(0.0, _flash_t - delta)
    # Этап 1 визуала: единственная точка вызова каркаса анимации станций.
    # При train_anim_level=OFF anim.tick() сразу возвращает 0.0 и ничего не меняет.
    if anim != null:
        anim.tick(delta)
    var pressed := profile.is_action_just_pressed("train_qte") \
            or profile.is_action_just_pressed("interact")
    # v45: на телефоне действие приходит кнопкой/тапом (см. _on_act_down/handle_touch)
    if _touch_hold_t > 0.0:
        _touch_hold_t = maxf(0.0, _touch_hold_t - delta)
    var held := profile.is_action_pressed("interact") or _touch_held or _touch_hold_t > 0.0
    var player: Node3D = _player()
    # ходьба и анимация бойца в комнате (бой в тренировке не тикает)
    if screen == "loc" and player != null:
        if not repair_on and not result_open \
                and (station == null or not station.active):
            _walk(delta, player)
        player.tick(delta)
        _update_nearest()
    if repair_on:
        tick_repair(delta)
        if pressed and repair_prompt_open():
            press_repair()
    elif station != null and station.active:
        if station.kind() == StationDef.Kind.HOLD:
            if pressed:
                press_action()
            tick_station(delta, held)
        else:
            tick_station(delta, false)
            if pressed:
                press_action()
    elif screen == "loc" and pressed and _nearest_id != "":
        # главный путь: подошёл к станции и нажал E
        begin_station(_nearest_id)
    # Этап 3: визуал анимаций (поза бойца по фазе клипа, качание снаряда,
    # дыхание в простое). При train_anim_level=OFF функция сразу выходит.
    _tick_anim_visuals(delta)
    if decor != null and screen == "loc":
        # подсветка активной станции + уникальный эффект локации
        var fpos := Vector3.ZERO
        var fon := false
        if _nearest_id != "" and stations.has(_nearest_id):
            var stn: Node3D = stations[_nearest_id]
            if stn != null:
                fpos = stn.global_position
                fon = true
        decor.update_focus(fpos, fon)
        decor.tick(delta)
    _update_overlay()


## Этап 3: единственная точка покадрового применения анимаций тренировки.
## При OFF (_anim_level=0) не трогает ни позы, ни трансформы станций.
func _tick_anim_visuals(delta: float) -> void:
    if not _anim_on():
        return
    _anim_clock += delta
    var player: Node3D = _player()
    if _debug_shot_phase != "":
        if _debug_shot_phase == "live" or _debug_shot_phase == "rapid":
            # отладка «живой» анимации для серии кадров (--frames): гоняем клип
            # по кругу и продолжаем обычную обработку клипа ниже
            _debug_live(delta)
        else:
            _debug_anim_tick(player)
            return
    if _active_anim != null and _active_anim.is_playing():
        _active_anim.tick(delta)
        _apply_clip_pose(player)
        _log_pose_changes()
        _drive_prop_from_clip()
        if not _active_anim.is_playing():
            # v69: сначала запускаем продолжение (цикл HOLD/подтягивания может
            # перезапуститься сразу), и только если его нет — сбрасываем позу.
            # Иначе каждый цикл бега мигал нейтральной стойкой на один кадр.
            _on_clip_finished()
            if _active_anim != null and _active_anim.is_playing():
                _apply_clip_pose(player)
            elif player != null:
                player.freeze_pose("", 0.0, false)
                if player.has_method("reset_train_pose"):
                    player.reset_train_pose()
    elif bag_anim != null and bag_anim.is_playing():
        bag_anim.tick(delta)
        if player != null:
            player.freeze_pose(bag_anim.pose_kind(), bag_anim.pose_phase(), false)
        if not bag_anim.is_playing() and player != null:
            player.freeze_pose("", 0.0, false)
    elif player != null and _anim_level >= 2:
        # дыхание в простое (FULL): лёгкий кивок головы/корпуса
        var b: float = float(anim.breath(_anim_clock)) if anim != null else 0.0
        player.head.rotation.x += 0.012 * b
        player.torso.rotation.x += 0.005 * b
    # Этап 4: реакции снарядов тикают у ВСЕХ станций локации (качание догорает
    # и у неактивных; поломка/починка тоже видны без подхода к станции)
    for sid in order:
        var sst: Node3D = stations[sid]
        if sst != null and sst.has_method("anim_tick"):
            sst.anim_tick(delta)


## Применить позу текущего клипа: если у клипа есть тренировочные ключи —
## слой apply_train_pose (присед/наклон/упор), иначе — обычные punch-позы.
func _apply_clip_pose(player: Node3D) -> void:
    if player == null or _active_anim == null:
        return
    var tp: Dictionary = {}
    if _active_anim.has_method("train_pose"):
        tp = _active_anim.train_pose()
    if not tp.is_empty() and player.has_method("apply_train_pose"):
        player.apply_train_pose(tp)
    else:
        player.freeze_pose(_active_anim.pose_kind(), _active_anim.pose_phase(), false)


## Лог ключей позы при смене фазы (гейт: hip_height/torso_pitch/локти по фазам).
func _log_pose_changes() -> void:
    if _active_anim == null:
        return
    var ph: String = _active_anim.phase_name()
    if ph == _last_logged_phase:
        return
    _last_logged_phase = ph
    var p := _player()
    var vals: Dictionary = {}
    if p != null and p.has_method("train_pose_values"):
        vals = p.train_pose_values()
    print("ANIMPOSE станция=", _active_station_id, " фаза=", ph, " ключи=", vals)


## 3.3/3.4: снаряд следует за фазой клипа (штанга поднимается, перекладина проседает).
func _drive_prop_from_clip() -> void:
    if station == null or _active_anim == null:
        return
    if _active_anim == lift_anim:
        if station.has_method("animate_lift"):
            station.animate_lift(float(lift_anim.lift_progress()),
                    float(lift_anim.vibration()))
    elif _active_anim == pull_anim:
        if station.has_method("animate_pull"):
            station.animate_pull(float(pull_anim.pull_progress()))
    elif _active_anim == jump_anim:
        if station.has_method("animate_rope"):
            station.animate_rope(float(jump_anim.rope_angle()))
    elif _active_anim == sustain_anim:
        if sustain_anim.is_climb() and station.has_method("animate_pull"):
            station.animate_pull(float(sustain_anim.climb_progress()))


## Клип доиграл: у подтягивания подхватываем отложенное нажатие (частые нажатия
## не рвут цикл), у остальных — просто возврат в idle.
func _on_clip_finished() -> void:
    if _active_anim == pull_anim and pull_anim.pending and station != null and station.active:
        pull_anim.pending = false
        pull_anim.play_hit(current_location_id, _active_station_id, _press_win_frac)
        return
    if _active_anim == jump_anim and station != null:
        if station.has_method("animate_rope_stop"):
            station.animate_rope_stop(9.0)
    if _active_anim == sustain_anim and station != null and station.active:
        # HOLD: пока удержание идёт — клип зацикливается без разрыва
        sustain_anim.start_hold(current_location_id, _active_station_id, 1.0)
        return
    _active_anim = null


## «Живой» отладочный режим: держим бойца у станции и повторяем удары, чтобы
## снять последовательность кадров (--frames) и проверить плавность/цикл.
func _debug_live(delta: float) -> void:
    if station == null or _player() == null:
        return
    var want: Vector3 = station.global_position + _stand_offset(station)
    _player().global_position = want
    _player().look_at_target(_aim_point(station))
    _live_t += delta
    var playing: bool = _active_anim != null and _active_anim.is_playing()
    if _debug_shot_phase == "rapid":
        # гейт 3.4: 10 частых нажатий подряд — цикл не должен рваться/перезапускаться
        if _live_t > 0.06:
            _live_t = 0.0
            _anim_hit()
            var n: int = pull_anim.chain if _active_anim == pull_anim else 0
            if n >= 10:
                print("ANIMPULL rapid итог: нажатий в очередь=", n, " цикл_жив=",
                        str(pull_anim.is_playing()))
        return
    if not playing and _live_t > 0.22:
        _live_t = 0.0
        # v71o: у станций HOLD (дорожка, канат) живой клип — цикл бега/лазания,
        # а не удар по мешку; иначе отладочные кадры врали.
        if station.kind() == StationDef.Kind.HOLD:
            _anim_start_hold()
        else:
            _anim_hit()


## Отладочный статичный кадр фазы (env VRINGE_ANIM_SHOT; в игре пусто).
## Фазы задаются по типу клипа станции:
##  удар: idle/anticipation/active/impact/follow/recover/miss/series
##  жим: idle/approach/grip/lift/lockout/lower/miss/vibration
##  подтягивание: idle/hang/pull/chin/lower/miss/repeat/settle
func _debug_anim_tick(player: Node3D) -> void:
    if station == null or player == null:
        return
    var loc_id := current_location_id
    var st: Node3D = station
    var id := String(st.def.id)
    # фиксируем позицию/разворот бойца у станции: кадр должен быть повторяемым
    var want: Vector3 = st.global_position + _stand_offset(st)
    player.global_position = want
    player.look_at_target(_aim_point(st))
    # Этап 4: отладочные кадры поломки и починки
    if _debug_shot_phase == "break" or _debug_shot_phase == "repair":
        if st.has_method("debug_set_broken"):
            st.debug_set_broken(_debug_shot_phase == "break")
        print("ANIMPOSE станция=", id, " фаза=", _debug_shot_phase)
        return
    var bundle := _debug_bundle_for(id)
    # Этап 3, волна 5: для моторных клипов — слой тренировочных ключей (присед/наклон/
    # упор/шаг), а не punch-позы; лог ключей для гейта.
    if bundle == "burpee" or bundle == "jump" or bundle == "repeat" \
            or bundle == "sustain" or bundle == "dips":
        if _debug_shot_phase == "miss":
            player.freeze_pose("rhook", 0.5, false)
            print("ANIMPOSE станция=", id, " фаза=miss (punch-поза)")
            return
        if bundle == "repeat" and (_debug_shot_phase == "shadow" or _debug_shot_phase == "cross"):
            player.freeze_pose("jab" if _debug_shot_phase == "shadow" else "cross", 0.45, false)
            print("ANIMPOSE станция=", id, " фаза=", _debug_shot_phase, " (punch-поза)")
            return
        var t := _debug_pose_t(bundle, _debug_shot_phase, id)
        if t >= 0.0:
            var clip = _clip_for_bundle(bundle)
            if clip != null:
                if bundle == "sustain" and clip.has_method("debug_climb"):
                    clip.debug_climb(id == "climb")
                player.apply_train_pose(clip.train_pose_at(t))
            if bundle == "jump" and st.has_method("animate_rope"):
                st.animate_rope(TAU * clampf(t / 0.5, 0.0, 1.0))
            if bundle == "sustain" and id == "climb" and st.has_method("animate_pull"):
                st.animate_pull(clampf(t, 0.0, 1.0))
            print("ANIMPOSE станция=", id, " фаза=", _debug_shot_phase, " t=", t,
                    " ключи=", player.train_pose_values())
        else:
            player.reset_train_pose()
            print("ANIMPOSE станция=", id, " фаза=", _debug_shot_phase, " t=none")
        return
    # v71q: для силовых клипов/кувалды кадр должен показывать моторные ключи
    # (жим лёжа, подтягивание, замах кувалдой), а не punch-позу.
    if bundle == "pull" or bundle == "lift" or bundle == "strike":
        var kp: Dictionary = {}
        # v71s2: клипы выбирают позу по station_id/_heavy (кувалда у покрышек),
        # а в отладочном кадре play_hit не вызывается — сообщаем станцию вручную.
        var clip_for_st: Object = _clip_for_bundle(bundle)
        if clip_for_st != null and clip_for_st.has_method("debug_station"):
            clip_for_st.debug_station(id)
        match bundle:
            "pull":
                kp = pull_anim.train_pose_at(0.50)
            "lift":
                kp = lift_anim.train_pose_at(0.36)
            "strike":
                kp = strike_anim.train_pose_at(0.50)
        if not kp.is_empty():
            player.apply_train_pose(kp)
            print("ANIMPOSE станция=", id, " фаза=", _debug_shot_phase, " моторные ключи")
            return
    var kind := "jab"
    var pose_phase := 0.0
    var show_pose := true
    match bundle:
        "lift":
            kind = TrainAnimLiftScript.POSE_LIFT
            match _debug_shot_phase:
                "idle":
                    show_pose = false
                "approach":
                    kind = TrainAnimLiftScript.POSE_APPROACH
                    pose_phase = 0.20
                "grip":
                    kind = TrainAnimLiftScript.POSE_APPROACH
                    pose_phase = 0.38
                "lift":
                    pose_phase = 0.42
                    st.animate_lift(0.55, 0.3)
                "lockout":
                    pose_phase = 0.58
                    st.animate_lift(1.0, 1.0)
                "lower":
                    pose_phase = 0.82
                    st.animate_lift(0.30, 0.2)
                "vibration":
                    pose_phase = 0.58
                    st.animate_lift(1.0, 1.0)
                "miss":
                    kind = TrainAnimLiftScript.POSE_APPROACH
                    pose_phase = 0.92
                    st.animate_drop()
                _:
                    show_pose = false
        "pull":
            kind = TrainAnimPullScript.POSE_PULL
            match _debug_shot_phase:
                "idle":
                    show_pose = false
                "hang":
                    pose_phase = 0.10
                    st.animate_pull(0.0)
                "pull":
                    pose_phase = 0.34
                    st.animate_pull(0.55)
                "chin":
                    pose_phase = 0.50
                    st.animate_pull(1.0)
                "lower":
                    pose_phase = 0.72
                    st.animate_pull(0.45)
                "repeat":
                    pose_phase = 0.50
                    st.animate_pull(1.0)
                "settle":
                    pose_phase = 0.12
                    st.animate_pull(0.0)
                "miss":
                    kind = "rhook"
                    pose_phase = 0.50
                _:
                    show_pose = false
        "burpee":
            kind = TrainAnimBurpeeScript.POSE_CROUCH
            match _debug_shot_phase:
                "jump":
                    kind = TrainAnimBurpeeScript.POSE_JUMP
                    pose_phase = 0.45
                "pushup":
                    pose_phase = 0.50
                "land":
                    pose_phase = 0.15
                "miss":
                    kind = "rhook"
                    pose_phase = 0.50
                _:
                    show_pose = false
        "jump":
            match _debug_shot_phase:
                "up":
                    st.animate_rope(0.0)
                    show_pose = false
                "air":
                    st.animate_rope(PI * 0.5)
                    show_pose = false
                "land":
                    st.animate_rope(PI)
                    show_pose = false
                "spin":
                    st.animate_rope(PI * 1.25)
                    show_pose = false
                "miss":
                    kind = "rhook"
                    pose_phase = 0.50
                _:
                    show_pose = false
        "repeat":
            kind = "body_upper"
            match _debug_shot_phase:
                "up":
                    pose_phase = 0.05
                "down":
                    pose_phase = 0.50
                "shadow":
                    kind = "jab"
                    pose_phase = 0.30
                "cross":
                    kind = "cross"
                    pose_phase = 0.45
                "miss":
                    kind = "rhook"
                    pose_phase = 0.50
                _:
                    show_pose = false
        "sustain":
            match _debug_shot_phase:
                "grip":
                    kind = "upper"
                    pose_phase = 0.10
                    st.animate_pull(0.10)
                "pull":
                    kind = "upper"
                    pose_phase = 0.35
                    st.animate_pull(0.55)
                "hold":
                    kind = "upper"
                    pose_phase = 0.50
                    st.animate_pull(1.0)
                "miss":
                    kind = "rhook"
                    pose_phase = 0.50
                _:
                    show_pose = false
        _:
            # удар (speedbag/tires) и мешок — фазы волны 1
            kind = strike_anim.punch_for(loc_id, id) if strike_anim != null else "jab"
            var bag_phase := ""
            match _debug_shot_phase:
                "idle":
                    show_pose = false
                "anticipation":
                    pose_phase = 0.10
                "active":
                    pose_phase = 0.30
                "impact":
                    pose_phase = 0.44
                    bag_phase = "impact"
                "follow":
                    pose_phase = 0.62
                    bag_phase = "follow"
                "recover":
                    pose_phase = 0.88
                "miss":
                    kind = "rhook"
                    pose_phase = 0.55
                "series":
                    pose_phase = 0.62
                    bag_phase = "series"
                _:
                    show_pose = false
            if bag_phase != "" and st.has_method("debug_hold"):
                var d: Vector3 = st.global_position - player.global_position
                st.debug_hold(bag_phase, d)
            elif st.has_method("debug_hold"):
                st.debug_hold("idle", Vector3(0.0, 0.0, -1.0))
    if show_pose:
        player.freeze_pose(kind, pose_phase, false)


## Клип по типу (для отладочных ключей позы).
func _clip_for_bundle(bundle: String):
    match bundle:
        "burpee":
            return burpee_anim
        "jump":
            return jump_anim
        "repeat":
            return repeat_anim
        "sustain":
            return sustain_anim
        "dips":
            return dips_anim
    return null


## Доля клипа t (0..1) для отладочной фазы (-1 — фазы нет в ключах).
func _debug_pose_t(bundle: String, phase: String, id: String) -> float:
    match bundle:
        "burpee":
            # v71s: клип переписан (visual-dev) — фазы привязаны к НОВЫМ ключам:
            # 0.05 стойка, 0.12 присед с ладонями, 0.30 планка, 0.42 отжимание внизу,
            # 0.56 планка, 0.70 ноги к рукам, 0.84 прыжок вверх, 0.94 приземление.
            match phase:
                "start":
                    return 0.05
                "jump":
                    return 0.84
                "pushup":
                    return 0.42
                "land":
                    return 0.94
                "feet":
                    return 0.70
                "breath":
                    return 0.30
                "anticipation":
                    return 0.12
                _:
                    return -1.0
        "jump":
            match phase:
                "up":
                    return 0.25
                "air":
                    return 0.50
                "land":
                    return 0.75
                "spin":
                    return 0.50
                "fast":
                    return 0.25
                "air2":
                    return 0.60
                "idle":
                    return 0.0
                _:
                    return -1.0
        "repeat":
            match phase:
                "up":
                    return 0.0
                "down":
                    return 0.50
                "up2":
                    return 1.0
                "down2":
                    return 0.50
                "breath":
                    return 0.0
                _:
                    return -1.0
        "dips":
            match phase:
                "up":
                    return 0.0
                "down":
                    return 0.50
                "up2":
                    return 1.0
                "down2":
                    return 0.50
                _:
                    return -1.0
        "sustain":
            if id == "climb":
                match phase:
                    "grip":
                        return 0.0
                    "pull":
                        return 0.33
                    "hold":
                        return 0.66
                    "lower":
                        return 1.0
                    "pull2":
                        return 0.50
                    "hold2":
                        return 0.80
                    _:
                        return -1.0
            match phase:
                "run":
                    return 0.0
                "run2":
                    return 0.50
                "fast":
                    return 0.25
                "slow":
                    return 0.75
                "stop":
                    return 0.0
                _:
                    return -1.0
    return -1.0


## Тип клипа по id станции (для отладочных фаз).
func _debug_bundle_for(id: String) -> String:
    if id == "speedbag" or id == "tires":
        return "strike"
    if id == "barbell" or id == "homemade_bar":
        return "lift"
    if id == "bar":
        return "pull"
    if id == "burpee":
        return "burpee"
    if id == "rope" or id == "speedrope":
        return "jump"
    if id == "pushups" or id == "shadow":
        return "repeat"
    if id == "dips":
        return "dips"
    if id == "run" or id == "climb" or id == "treadmill":
        return "sustain"
    return "bag"


## Отладочная подготовка кадра: выбрать станцию (env VRINGE_ANIM_STATION или первую
## подходящую) и поставить бойца рядом.
func _debug_setup_shot() -> void:
    if _debug_shot_phase == "" or screen != "loc":
        return
    var target: Node3D = null
    if _debug_station_id != "" and stations.has(_debug_station_id):
        target = stations[_debug_station_id]
    if target == null:
        var want_kind: int = StationDef.Kind.BAG
        for id in order:
            var st: Node3D = stations[id]
            if st == null:
                continue
            if _debug_station_id == "" and st.kind() == want_kind:
                target = st
                break
        if target == null:
            # fallback: первая станция локации
            if order.size() > 0:
                target = stations[String(order[0])]
    if target == null:
        return
    station = target
    if _player() != null:
        var pos: Vector3 = target.global_position + _stand_offset(target)
        _player().global_position = pos
        _player().look_at_target(_aim_point(target))
    if _train_demo:
        begin_station(String(target.def.id))


## Движение игрока WASD относительно камеры (как в основном бою) + границы комнаты.
func _walk(delta: float, player: Node3D) -> void:
    var mv := profile.get_move_vector()
    if mv.length() < 0.05:
        return
    var fwd: Vector3 = -camera.global_transform.basis.z
    fwd.y = 0.0
    fwd = fwd.normalized()
    var right: Vector3 = camera.global_transform.basis.x
    right.y = 0.0
    right = right.normalized()
    var dir := fwd * (-mv.y) + right * mv.x
    if dir.length() < 0.01:
        return
    dir = dir.normalized()
    player.drive(dir, delta)
    player.position.x = clampf(player.position.x, WALK_MIN.x, WALK_MAX.x)
    player.position.z = clampf(player.position.z, WALK_MIN.y, WALK_MAX.y)
    # не проходим сквозь станции
    for id in order:
        var st: Node3D = stations[id]
        var d := Vector2(player.position.x - st.position.x,
                player.position.z - st.position.z)
        if d.length() < 1.05 and d.length() > 0.001:
            player.position += Vector3(d.normalized().x, 0.0, d.normalized().y) \
                    * (1.05 - d.length())
    player.look_at_target(player.position + dir)


## Ближайшая станция в радиусе: подсветка + запуск по E.
func _update_nearest() -> void:
    _nearest_id = ""
    var player: Node3D = _player()
    if player == null or screen != "loc":
        return
    var best := INTERACT_RADIUS
    for id in order:
        var st: Node3D = stations[id]
        var d := Vector2(player.position.x - st.position.x,
                player.position.z - st.position.z).length()
        if d < best:
            best = d
            _nearest_id = id
    # T7: подпись показывает только станция в фокусе, размер — по дистанции до камеры
    var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
    # v71o: во время упражнения подписи станций убираем — камера стоит близко,
    # и крупный Label3D («ОТЖИМАНИЯ», «БЁРПИ») висел поперёк кадра/геометрии.
    var busy: bool = station != null and station.active
    for id in order:
        var st2: Node3D = stations[id]
        st2.set_highlight(false if busy else (id == _nearest_id))
        if st2.has_method("tick_label"):
            st2.tick_label(cam)
    _refresh_near_hint()


func nearest_station_id() -> String:
    return _nearest_id


func _player() -> Node3D:
    if main == null or main.get("player") == null:
        return null
    return main.player as Node3D


func _place_player(spawn: Vector3, look_at_p: Vector3) -> void:
    var player: Node3D = _player()
    if player == null:
        return
    player.reset(spawn, 100.0)
    player.visible = true
    player.look_at_target(Vector3(look_at_p.x, spawn.y, look_at_p.z))
    player.tick(0.001)


func get_player_pos() -> Vector3:
    var player: Node3D = _player()
    return player.position if player != null else Vector3.ZERO


## Для тестов: поставить игрока в точку (без сброса статов/позы).
func place_player_for_test(pos: Vector3) -> void:
    var player: Node3D = _player()
    if player != null:
        player.position = pos
        player.vel = Vector3.ZERO
    _update_nearest()


## Для тестов: пройти в направлении dir `seconds` секунд тем же путём, что и WASD.
func walk_for_test(dir: Vector3, seconds: float) -> void:
    var player: Node3D = _player()
    if player == null:
        return
    var dt := 1.0 / 60.0
    var n := int(maxf(1.0, seconds * 60.0))
    for i in n:
        player.drive(dir.normalized(), dt)
        player.position.x = clampf(player.position.x, WALK_MIN.x, WALK_MAX.x)
        player.position.z = clampf(player.position.z, WALK_MIN.y, WALK_MAX.y)
        player.tick(dt)
    _update_nearest()


## Для тестов/тача: нажать E по ближайшей станции. true — упражнение началось.
func interact_nearest() -> bool:
    if _nearest_id == "":
        return false
    return begin_station(_nearest_id)


## Экранная позиция станции (для тач-тапа по 3D-станции).
func station_screen_pos(st_id: String) -> Vector2:
    var st: Node3D = stations.get(st_id)
    if st == null or camera == null:
        return Vector2(-1000.0, -1000.0)
    return camera.unproject_position(st.global_position + Vector3(0.0, 1.0, 0.0))


## Тап по экрану: по 3D-станции — «подойти и нажать E», по оверлею — продолжить.
func handle_touch(pos: Vector2) -> String:
    if not active:
        return ""
    if repair_on:
        if repair_prompt_open():
            press_repair()
        return ""
    if result_open:
        confirm_result()
        return ""
    if screen != "loc":
        return ""
    # v45: упражнение уже идёт — тап по экрану = одно нажатие (на телефоне нет E).
    # Кнопка действия справа делает то же, но тап «куда удобно» тоже работает.
    if station != null and station.active:
        _touch_hold_t = 0.45
        press_action()
        return ""
    var best := ""
    var best_d := 120.0
    for id in order:
        var sp := station_screen_pos(id)
        var d := pos.distance_to(sp)
        if d < best_d:
            best_d = d
            best = id
    if best == "":
        return ""
    # тап по станции = interact: подводим бойца и запускаем упражнение
    var st: Node3D = stations[best]
    var player: Node3D = _player()
    if player != null:
        var so := _stand_offset(st)
        player.position = Vector3(st.position.x + so.x, so.y, st.position.z + so.z)
        player.look_at_target(_aim_point(st))
    _update_nearest()
    begin_station(best)
    return ""


## Тап по карточке хаба (для тач-режима и тестов). Возвращает "loc"/"".
func tap_hub_card(i: int) -> String:
    if screen != "hub" or i < 0 or i >= locations.size():
        return ""
    if not is_location_unlocked(locations[i].id):
        return ""
    _on_card_pressed(i)
    return "loc"


func current_location() -> String:
    return current_location_id


func update_camera(delta: float) -> void:
    if not active or camera == null:
        return
    # Этап 5: отладочные ракурсы локации для кадров (wide/hero/stations).
    if _loc_shot_cam != "" and screen == "loc" and decor != null:
        var pose: Dictionary = decor.debug_camera(_loc_shot_cam)
        if not pose.is_empty():
            camera.position = pose["pos"]
            camera.fov = float(pose.get("fov", 55.0))
            camera.look_at(pose["look"], Vector3.UP)
            camera.make_current()
            return
    # T-trainanim: отладочный режим камеры для кадров «до/после» (в игре env не задан).
    if _train_cam_mode == "legacy":
        _legacy_camera(delta)
        return
    if _train_cam_mode == "focus":
        if station != null and station.active:
            _exercise_camera(delta)
        else:
            _legacy_camera(delta)
        return
    # Отладка демо-кадров: ставим камеру в три четверти так, чтобы боец и станция
    # были целиком в кадре (одинаковый ракурс для всех кадров волны).
    if _debug_shot_phase != "" and screen == "loc" and station != null:
        _debug_camera()
        return
    if screen != "loc":
        camera.position = camera.position.lerp(Vector3(0.0, 2.0, 8.0),
                clampf(delta * 4.0, 0.0, 1.0))
        camera.look_at(Vector3(0.0, 1.1, 0.0), Vector3.UP)
        return
    # T-trainanim: во время упражнения — фокус на паре «игрок + снаряд».
    if station != null and station.active:
        _exercise_camera(delta)
    else:
        _legacy_camera(delta)


## Общий вид локации (как было до T-trainanim).
func _legacy_camera(delta: float) -> void:
    _cam_ex_prev = false
    var focus := get_player_pos()
    var base := Vector3(3.0 + focus.x * 0.3, 3.1, 4.5 + focus.z * 0.4)
    camera.position = camera.position.lerp(base, clampf(delta * 5.0, 0.0, 1.0))
    camera.look_at(Vector3(focus.x * 0.35, 0.95, focus.z * 0.25), Vector3.UP)
    # вернуть общий план после упражнения: fov/сдвиг плавно в исходные
    camera.fov = lerpf(camera.fov, 46.0, clampf(delta * 6.0, 0.0, 1.0))
    camera.h_offset = lerpf(camera.h_offset, 0.0, clampf(delta * 6.0, 0.0, 1.0))


## T-trainanim: камера «игрок + снаряд» — три четверти сбоку-спереди, плавный
## переход ~0.4 с; пара кадрируется правее центра, чтобы её не закрывала левая панель.
var _cam_look_cur := Vector3(0.0, 1.0, 0.0)
var _cam_ex_prev := false


## v71q: явные ракурсы для упражнений на полу: камера в стороне от соседних
## станций, дистанция подобрана под высоту снаряда и положение тела.
func _fixed_exercise_cam(st_id: String, b: Vector3) -> Dictionary:
    # v71q: отладочный подбор ракурса без пересборки — VRINGE_FIXCAM="dx,dy,dz,lx,ly,lz,fov"
    var over := OS.get_environment("VRINGE_FIXCAM").strip_edges()
    if over != "":
        var p := over.split(",")
        if p.size() >= 7:
            return {"pos": b + Vector3(float(p[0]), float(p[1]), float(p[2])),
                    "look": b + Vector3(float(p[3]), float(p[4]), float(p[5])),
                    "fov": float(p[6])}
    var res: Dictionary = {}
    match st_id:
        "barbell", "homemade_bar":
            # лежачий жим: тело вытянуто вдоль Z, поэтому ракурс — сбоку-спереди
            # (~55° от оси снаряда), иначе камера смотрит вдоль тела и видит
            # только крупный затылок/грудь.
            res = {"pos": b + Vector3(1.90, 2.20, 3.00),
                    "look": b + Vector3(0.0, 0.60, 0.0), "fov": 52.0}
        "bar":
            # турник: боец висит спиной к +Z, поэтому 3/4 сбоку-спереди
            res = {"pos": b + Vector3(1.80, 2.75, 3.35),
                    "look": b + Vector3(0.0, 1.85, 0.0), "fov": 58.0}
        "dips":
            res = {"pos": b + Vector3(1.80, 1.70, 3.25),
                    "look": b + Vector3(0.0, 1.00, 0.0), "fov": 58.0}
        "speedbag":
            res = {"pos": b + Vector3(1.70, 1.75, 3.20),
                    "look": b + Vector3(0.0, 1.30, 0.0), "fov": 55.0}
        "climb":
            res = {"pos": b + Vector3(1.90, 2.85, 3.40),
                    "look": b + Vector3(0.0, 2.05, 0.0), "fov": 58.0}
        "pushups":
            # планка/отжимания на мате: строго сбоку, низкая точка взгляда —
            # тело вытянуто на ~1.7 м, камера сверху-сбоку его не читала.
            res = {"pos": b + Vector3(2.75, 1.25, 1.35),
                    "look": b + Vector3(0.0, 0.32, 0.0), "fov": 52.0}
        "burpee":
            # бёрпи: стойка/присед/планка/прыжок — кадр с запасом по высоте
            res = {"pos": b + Vector3(2.85, 1.70, 1.70),
                    "look": b + Vector3(0.0, 0.70, 0.0), "fov": 58.0}
    if res.is_empty():
        return res
    # v71q: третья станция ряда стоит у правой стены (x≈3.4) — сдвиг по +X
    # упирается в стену, поэтому боковой сдвиг зеркалим на свободную сторону.
    var cp: Vector3 = res["pos"]
    if absf(cp.x) > 4.6:
        res["pos"] = Vector3(b.x - (cp.x - b.x), cp.y, cp.z)
    return res


func _fixed_camera(delta: float, cam_pos: Vector3, look: Vector3, fov: float,
        hoff: float = 0.0) -> void:
    if not _cam_ex_prev:
        _cam_ex_prev = true
        _cam_look_cur = camera.position - camera.global_transform.basis.z * 5.0
    # v71q: даже явный ракурс зажимаем в габариты комнаты — иначе камера за
    # стеной даёт чёрный кадр (ровно этот баг был на дорожке в v71o).
    var target := Vector3(clampf(cam_pos.x, -5.0, 5.0), cam_pos.y,
            clampf(cam_pos.z, -3.9, 3.9))
    var k := clampf(delta * 8.0, 0.0, 1.0)
    camera.position = camera.position.lerp(target, k)
    _cam_look_cur = _cam_look_cur.lerp(look, clampf(delta * 10.0, 0.0, 1.0))
    camera.look_at(_cam_look_cur, Vector3.UP)
    camera.fov = lerpf(camera.fov, fov, k)
    camera.h_offset = lerpf(camera.h_offset, hoff, k)


func _exercise_camera(delta: float) -> void:
    var p := _player()
    if p == null or station == null:
        _legacy_camera(delta)
        return
    var a: Vector3 = p.global_position
    var b: Vector3 = station.global_position
    var st_id := String(station.def.id) if station.get("def") != null else ""
    # v71q: у «снарядов на полу» (турник, брусья, жим лёжа, груша, канат) ракурс
    # задаём явно: автоматический перебор утыкается в соседние станции и декор.
    var fixed := _fixed_exercise_cam(st_id, b)
    if not fixed.is_empty():
        _fixed_camera(delta, fixed["pos"], fixed["look"], float(fixed["fov"]),
                float(fixed.get("hoff", 0.0)))
        return
    # v71o: если боец стоит НА станции (дорожка), обычная «камера сбоку»
    # утыкается в стойки/пульт и режет ноги. Для этого случая — ракурс
    # от свободной стороны комнаты, где помещается весь боец и полотно.
    if Vector2(a.x - b.x, a.z - b.z).length() < 0.9:
        _on_station_camera(delta, a, station)
        return
    # v71o: отжимания/бёрпи — боец лежит, тело вытянуто почти на 2 м; обычный
    # боковой ракурс резал голову/ноги краем кадра. Для них — свободный ракурс
    # с увеличенной дистанцией и низкой точкой взгляда.
    if st_id == "pushups" or st_id == "burpee":
        _on_station_camera(delta, a, station)
        return
    var focus_y := _focus_look_y(station)
    var mid: Vector3 = (a + b) * 0.5 + Vector3(0.0, focus_y, 0.0)
    var axis := b - a
    axis.y = 0.0
    if axis.length() < 0.01:
        axis = Vector3(0.0, 0.0, -1.0)
    axis = axis.normalized()
    var side := axis.cross(Vector3.UP)
    side.y = 0.0
    if side.length() < 0.01:
        side = Vector3.RIGHT
    side = side.normalized()
    # камера сбоку и чуть со стороны снаряда; знак выбран, чтобы боец был справа
    var base_pt: Vector3 = a - axis * 1.95 + Vector3(0.0, focus_y + 0.85, 0.0)
    var cand_a: Vector3 = base_pt + side * 2.65
    var cand_b: Vector3 = base_pt - side * 2.65
    # v71o: камера обязана остаться ВНУТРИ комнаты (пол 11×9, боковые стены ±5.5,
    # задняя −4.2). Третья станция в ряду стоит у правой стены (x≈3.4), и сдвиг
    # +2.65 по боку уводил камеру за стену (x≈6.05) — экран становился чёрным
    # квадратом, анимация упражнения не видна («чёрный квадрат» на дорожке).
    var half_x := 5.0
    var half_z := 3.9
    var inside_a: bool = absf(cand_a.x) <= half_x and absf(cand_a.z) <= half_z
    var inside_b: bool = absf(cand_b.x) <= half_x and absf(cand_b.z) <= half_z
    var desired: Vector3
    if inside_a:
        desired = cand_a
    elif inside_b:
        desired = cand_b          # зеркальный ракурс: боец слева, но всё видно
    else:
        var clamp_a := Vector3(clampf(cand_a.x, -half_x, half_x), cand_a.y,
                clampf(cand_a.z, -half_z, half_z))
        var clamp_b := Vector3(clampf(cand_b.x, -half_x, half_x), cand_b.y,
                clampf(cand_b.z, -half_z, half_z))
        desired = clamp_a if cand_a.distance_to(clamp_a) <= cand_b.distance_to(clamp_b) \
                else clamp_b
    desired.x = clampf(desired.x, -half_x, half_x)
    desired.z = clampf(desired.z, -half_z, half_z)
    # v71o: если у стены камеру прижало слишком близко (боец занимает весь кадр),
    # переключаемся на свободный ракурс с гарантированной дистанцией.
    if desired.distance_to(a) < 2.7:
        _on_station_camera(delta, a, station)
        return
    var look: Vector3 = Vector3(mid.x, focus_y, mid.z)
    if not _cam_ex_prev:
        # вход в упражнение: фиксируем текущий взгляд для плавного перехода
        _cam_ex_prev = true
        _cam_look_cur = camera.position - camera.global_transform.basis.z * 5.0
    var k := clampf(delta * 8.0, 0.0, 1.0)      # ~0.4 с при 60 fps
    camera.position = camera.position.lerp(desired, k)
    _cam_look_cur = _cam_look_cur.lerp(look, clampf(delta * 10.0, 0.0, 1.0))
    camera.look_at(_cam_look_cur, Vector3.UP)
    camera.fov = lerpf(camera.fov, _fit_fov(desired.distance_to(look), 2.5), k)
    camera.h_offset = lerpf(camera.h_offset, -0.45, k)


## v71o: камера для станций, на которых боец стоит (дорожка). Выбираем направление
## в комнате, где больше запаса до стены и до габаритов снаряда, — чтобы в кадр
## целиком попадали боец и полотно, а камера не оказалась внутри геометрии.
func _on_station_camera(delta: float, a: Vector3, st: Node3D) -> void:
    var half_x := 5.0
    var half_z := 3.9
    var best := a + Vector3(0.0, 1.5, 3.2)
    var best_score := -1e9
    var dirs: Array = [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0),
            Vector3(-1, 0, 0), Vector3(1, 0, 1), Vector3(-1, 0, 1),
            Vector3(1, 0, -1), Vector3(-1, 0, -1)]
    var cam_dist := _focus_dist(st)
    for d in dirs:
        var dir: Vector3 = (d as Vector3).normalized()
        var raw: Vector3 = a + dir * cam_dist + Vector3(0.0,
                _focus_look_y(st) + 0.75, 0.0)
        var pos := Vector3(clampf(raw.x, -half_x, half_x), raw.y,
                clampf(raw.z, -half_z, half_z))
        var dist := Vector2(pos.x - a.x, pos.z - a.z).length()
        var wall := minf(half_x - absf(pos.x), half_z - absf(pos.z))
        var clear_prop := Vector2(pos.x - st.global_position.x,
                pos.z - st.global_position.z).length()
        # главное — полная дистанция и запас до стены; снаряд не должен быть в упор
        var score: float = minf(dist - 2.8, wall) + clampf(clear_prop - 0.9, 0.0, 1.0) * 0.3
        if score > best_score:
            best_score = score
            best = pos
    var desired := best
    var look_y := _focus_look_y(st)
    var look: Vector3 = a + Vector3(0.0, look_y, 0.0) \
            + (st.global_position - a) * 0.15
    if not _cam_ex_prev:
        _cam_ex_prev = true
        _cam_look_cur = camera.position - camera.global_transform.basis.z * 5.0
    var k := clampf(delta * 7.0, 0.0, 1.0)
    camera.position = camera.position.lerp(desired, k)
    _cam_look_cur = _cam_look_cur.lerp(look, clampf(delta * 9.0, 0.0, 1.0))
    camera.look_at(_cam_look_cur, Vector3.UP)
    camera.fov = lerpf(camera.fov, _fit_fov(desired.distance_to(look), 2.5), k)
    camera.h_offset = lerpf(camera.h_offset, -0.25, k)


## v71q: fov под дистанцию и требуемую высоту кадра. В проекте кадр 16:9 и fov
## работает по ГОРИЗОНТАЛИ, поэтому высоту переводим в горизонтальный угол:
## tan(fov/2) = (h · aspect) / (2 · d). Иначе тело 1.8–2.0 м резалось краями.
func _fit_fov(dist: float, height: float, aspect: float = 16.0 / 9.0) -> float:
    var d := maxf(dist, 0.5)
    var h := clampf(height, 0.7, 5.0)
    return clampf(rad_to_deg(2.0 * atan((h * aspect) / (2.0 * d))), 35.0, 88.0)


## v71o: дистанция камеры под упражнение (лежачие — дальше, чтобы тело влезло).
func _focus_dist(st: Node3D) -> float:
    var id := ""
    if st != null and st.get("def") != null:
        id = String((st.get("def") as StationDef).id)
    match id:
        "pushups":
            return 4.2
        "burpee":
            return 3.9
        "bar", "climb":
            return 4.7
        "dips":
            return 4.3
        "barbell", "homemade_bar":
            return 4.2
    return 3.4


## v71o: высота точки взгляда под упражнение (присед/отжимания ниже, канат выше).
func _focus_look_y(st: Node3D) -> float:
    var id := ""
    if st != null and st.get("def") != null:
        id = String((st.get("def") as StationDef).id)
    match id:
        "pushups", "burpee":
            return 0.65
        "tires":
            return 0.85
        "climb":
            return 2.75
        "bar":
            return 2.75
        "dips":
            return 1.95
        "barbell", "homemade_bar":
            return 0.72
        "treadmill", "run":
            return 1.0
    return 1.05


## Единый ракурс демо-кадров: три четверти, боец целиком, станция видна.
func _debug_camera() -> void:
    var p := _player()
    if p == null or station == null:
        return
    # Широкий кадр от бойца (по замечанию Lead'а): ~3.7 м до бойца, fov 47,
    # станция за бойцом в кадре, ничего не обрезано. Одинаково для всех станций.
    var mid: Vector3 = (p.global_position + station.global_position) * 0.5
    camera.position = p.global_position + Vector3(1.7, 1.6, 3.3)
    camera.fov = 47.0
    camera.look_at(mid + Vector3(0.0, 0.85, 0.0), Vector3.UP)
    camera.make_current()


## Клавиатурная навигация. Возвращает "menu"/"hub"/"loc" — куда перейти main.gd.
func handle_key(event: InputEvent) -> String:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return ""
    var key := (event as InputEventKey).keycode
    match key:
        KEY_ESCAPE:
            if repair_on:
                cancel_repair()
                return ""
            if station != null and station.active:
                abort_station()
                _update_ui()
                return ""
            if result_open:
                confirm_result()
                return ""
            if screen == "hub":
                return "menu"
            open_hub()
            return "hub"
        KEY_UP:
            _move_sel(-1)
            return ""
        KEY_DOWN:
            _move_sel(1)
            return ""
        KEY_ENTER, KEY_KP_ENTER, KEY_E:
            if screen == "hub":
                return _activate_hub()
            if screen == "loc":
                if result_open:
                    confirm_result()
                    return ""
                if station != null and station.active:
                    return ""
                # главный путь: E у ближайшей станции; список — запасной
                if _nearest_id != "":
                    begin_station(_nearest_id)
                    return ""
                return _activate_station()
    return ""


func _move_sel(d: int) -> void:
    var n := locations.size() if screen == "hub" else order.size()
    if n <= 0:
        return
    sel = wrapi(sel + d, 0, n)
    if screen == "hub":
        _render_hub()
    else:
        _render_location()


func _activate_hub() -> String:
    if sel < 0 or sel >= locations.size():
        return ""
    var loc := locations[sel]
    if not is_location_unlocked(loc.id):
        return ""
    open_location(loc.id)
    return "loc"


func _activate_station() -> String:
    if sel < 0 or sel >= order.size():
        return ""
    var st: Node3D = _station_by_id(order[sel])
    if st == null:
        return ""
    var player: Node3D = _player()
    if player != null:
        var so := _stand_offset(st)
        player.position = Vector3(st.position.x + so.x, so.y, st.position.z + so.z)
        player.look_at_target(_aim_point(st))
    if st.is_broken():
        begin_repair(order[sel])
        return ""
    begin_station(order[sel])
    _update_nearest()
    return ""


func _on_card_pressed(i: int) -> void:
    sel = i
    if is_location_unlocked(locations[i].id):
        open_location(locations[i].id)
        _notify_main("loc")


func _on_station_pressed(i: int) -> void:
    sel = i
    _activate_station()
    _update_ui()


func _notify_main(to: String) -> void:
    if main != null and main.has_method("_on_training_nav"):
        main._on_training_nav(to)


# ---------------------------------------------------------------- сцена

func _build_camera() -> void:
    camera = Camera3D.new()
    camera.name = "TrainingCamera"
    camera.fov = 52.0
    add_child(camera)
    camera.position = Vector3(0.0, 2.0, 8.0)


func _build_room(loc: TrainingLocationDef) -> void:
    location_root = Node3D.new()
    location_root.name = "Room_" + loc.id
    add_child(location_root)
    # пол
    var floor := MeshInstance3D.new()
    var fm := BoxMesh.new()
    fm.size = Vector3(11.0, 0.2, 9.0)
    floor.mesh = fm
    var fmat := StandardMaterial3D.new()
    fmat.albedo_color = loc.floor_color
    fmat.roughness = 0.92
    fmat.emission_enabled = true
    fmat.emission = loc.floor_color * 0.35
    floor.material_override = fmat
    floor.position = Vector3(0.0, -0.1, 0.0)
    location_root.add_child(floor)
    # Этап 5: на крыше и в парке «коробка» заменяется парапетом/открытым краем
    # (только при visual_level != OFF; при OFF стены строятся как раньше).
    var shell: int = int(DecorScript.shell_mode(visual, loc.id)) if DecorScript != null else 0
    if shell == 0:
        # задняя стена
        var wall := MeshInstance3D.new()
        var wm := BoxMesh.new()
        wm.size = Vector3(11.0, 3.4, 0.2)
        wall.mesh = wm
        var wmat := StandardMaterial3D.new()
        wmat.albedo_color = loc.floor_color.darkened(0.35)
        wmat.roughness = 0.95
        wmat.emission_enabled = true
        wmat.emission = loc.floor_color.darkened(0.35) * 0.3
        wall.material_override = wmat
        wall.position = Vector3(0.0, 1.7, -4.2)
        location_root.add_child(wall)
        # боковые стены: чтобы комната не висела в пустоте
        for sx in [-5.5, 5.5]:
            var side := MeshInstance3D.new()
            var sm := BoxMesh.new()
            sm.size = Vector3(0.2, 3.4, 9.0)
            side.mesh = sm
            var smat := StandardMaterial3D.new()
            smat.albedo_color = loc.floor_color.darkened(0.45)
            smat.roughness = 0.95
            smat.emission_enabled = true
            smat.emission = loc.floor_color.darkened(0.45) * 0.25
            side.material_override = smat
            side.position = Vector3(sx, 1.7, 0.0)
            location_root.add_child(side)
    # свет локации: направленный «солнечный» + заполняющий, иначе комната тёмная
    var sun := DirectionalLight3D.new()
    sun.light_color = loc.light_color
    # Этап 1 визуала: единственная точка применения visual_level к свету локации.
    # При OFF множитель ровно 1.0 — энергия света байт-в-байт как в baseline.
    # v71s: свет тренировки суммарно пересвечивал белое тело бойца (солнце без
    # теней + мощная лампа) — в кадре поза превращалась в белое пятно. Снизили
    # оба источника и дали лампе затухание ближе к физическому.
    sun.light_energy = loc.light_energy * 1.0 * _visual_light_mult()
    sun.shadow_enabled = false
    sun.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
    location_root.add_child(sun)
    var light := OmniLight3D.new()
    light.light_color = loc.light_color
    light.light_energy = loc.light_energy * 1.0 * _visual_light_mult()
    light.omni_range = 16.0
    light.omni_attenuation = 1.4
    light.position = Vector3(0.0, 3.6, 2.4)
    location_root.add_child(light)
    # станции в ряд справа от панели локации (панель занимает левые 440 px)
    stations.clear()
    order.clear()
    var n := loc.stations.size()
    for i in n:
        var def: StationDef = loc.stations[i]
        var st: Node3D = StationScript.new()
        location_root.add_child(st)
        var x := 0.4 + 1.5 * float(i) if n > 1 else 1.6
        st.position = Vector3(x, 0.0, -1.4)
        st.setup(def, loc, self)
        st.durability = durability(loc.id, def.id)
        st.durability_max = config.durability_max
        st.update_label()
        st.set_label_text(_st_title(loc.id, def))
        stations[def.id] = st
        order.append(def.id)
    # Этап 5: декор локации поверх базовой комнаты (при OFF не создаётся вовсе)
    if visual != null and visual.visual_on() and DecorScript != null:
        decor = DecorScript.new()
        decor.name = "LocationDecor"
        location_root.add_child(decor)
        decor.build(main, visual, loc)
    camera.position = Vector3(0.0, 2.4, 6.4)
    camera.look_at(Vector3(1.4, 1.05, -1.4), Vector3.UP)


func _clear_room() -> void:
    if decor != null:
        # вернуть WorldEnvironment к состоянию до локации (при OFF не трогался)
        decor.restore()
        decor = null
    if location_root != null:
        remove_child(location_root)
        location_root.queue_free()
        location_root = null
    stations.clear()
    order.clear()


## v71o: где бойцу стоять у станции. У беговой дорожки — НА полотне (иначе «бег»
## изображается в метре перед машиной, по полу), у остальных станций — 1.35 м
## перед снарядом.
func _stand_offset(st: Node3D) -> Vector3:
    var id := ""
    if st != null and st.get("def") != null:
        id = String((st.get("def") as StationDef).id)
    if id == "treadmill":
        return Vector3(0.0, 0.08, 0.10)
    # v71o: к канату встаём вплотную (было 1.35 м — боец «лазал» по воздуху)
    if id == "climb":
        return Vector3(0.0, 0.0, 0.55)
    # v71q: снаряды-«на полу» — боец стоит/лежит/висит ПОД снарядом, а не в
    # 1.35 м перед тумбой: турник, брусья, жим лёжа (скамья).
    if id == "bar" or id == "dips" or id == "barbell" or id == "homemade_bar":
        return Vector3(0.0, 0.0, 0.0)
    # v71s: отжимания и бёрпи — тело лежит/планка НА мате, значит боец стоит
    # ровно на станции (раньше он вставал в 1.35 м и планка висела в воздухе
    # перед матом). Тело вытягивается назад, к центру снаряда.
    if id == "pushups" or id == "burpee":
        return Vector3(0.0, 0.0, 0.0)
    # скоростная груша: вплотную, иначе перчатки не достают до груши
    if id == "speedbag":
        return Vector3(0.0, 0.0, 0.85)
    return Vector3(0.0, 0.0, 1.35)


## v71o: куда боец смотрит у станции — в центр снаряда, а не в пол под ним.
func _aim_point(st: Node3D) -> Vector3:
    if st == null:
        return Vector3.ZERO
    var id := ""
    if st.get("def") != null:
        id = String((st.get("def") as StationDef).id)
    var up := 0.95
    match id:
        "climb":
            up = 2.90          # руки на канате на 2.9 м
        "bar":
            up = 2.30          # перекладина турника
        "dips":
            up = 1.15          # жерди брусьев
        "speedbag":
            up = 1.44          # груша
        "barbell", "homemade_bar":
            up = 0.95          # гриф над грудью лежащего
        "speedrope":
            up = 1.35
        "bag", "dummy", "tires":
            up = 1.0
        "treadmill", "run":
            # бегущий смотрит вдоль полотна на пульт (консоль стоит за полотном)
            return st.global_position + Vector3(0.0, 1.05, -0.9)
    return st.global_position + Vector3(0.0, up, 0.0)


func _station_by_id(st_id: String) -> Node3D:
    var st: Node3D = stations.get(st_id)
    return st


func _hide_world(hidden: bool) -> void:
    if main == null:
        return
    # арена и соперник в тренировке не нужны, а игрок стоит в комнате и ходит
    if main.get("arena") != null:
        (main.arena as Node3D).visible = not hidden
    if main.get("enemy") != null:
        (main.enemy as Node3D).visible = not hidden
    if main.get("player") != null and not hidden:
        var player: Node3D = main.player
        player.visible = true
        player.position = Vector3(0, 0, 1.9)


# ---------------------------------------------------------------- сохранение

func _load_float(key: String, def: float) -> float:
    if SaveManager == null:
        return def
    return float(SaveManager.load_value(SECTION, key, def))


func _load_bool(key: String, def: bool = false) -> bool:
    if SaveManager == null:
        return def
    return bool(SaveManager.load_value(SECTION, key, def))


func _save_float(key: String, value: float) -> void:
    if SaveManager != null:
        SaveManager.save_value(SECTION, key, value)


func _mark_visited(loc_id: String) -> void:
    if SaveManager == null:
        return
    SaveManager.save_value(SECTION, "visited/" + loc_id, true)
    _flush()


func _flush() -> void:
    if SaveManager != null:
        SaveManager.flush()


## Только для тестов: очистить прогресс тренировки в сейве.
func reset_training_save() -> void:
    if SaveManager == null:
        return
    SaveManager.data[SECTION] = {}
    SaveManager.flush()


# ---------------------------------------------------------------- тексты RU/EN

## Английский текст локации/станции (RU берётся из конфига).
func _en(key: String, field: String, fallback: String) -> String:
    if Lang.code != "en":
        return fallback
    return FactoryScript.en_text(key, field, fallback)


func _loc_title(loc: TrainingLocationDef) -> String:
    return _en("loc/" + loc.id, "title", loc.title)


func _loc_desc(loc: TrainingLocationDef) -> String:
    return _en("loc/" + loc.id, "desc", loc.description)


func _st_title(loc_id: String, st: StationDef) -> String:
    return _en("station/%s/%s" % [loc_id, st.id], "title", st.title)


func _st_desc(loc_id: String, st: StationDef) -> String:
    return _en("station/%s/%s" % [loc_id, st.id], "desc", st.description)


func _stations_text(loc: TrainingLocationDef) -> String:
    var parts: Array[String] = []
    for st in loc.stations:
        parts.append(_st_title(loc.id, st))
    return ", ".join(parts)


## Суммарное мастерство локации (0..100 на каждую станцию).
func _loc_mastery_total(loc: TrainingLocationDef) -> int:
    var total := 0
    for st in loc.stations:
        total += int(mastery(loc.id, st.id))
    return total


func _loc_mastery_max(loc: TrainingLocationDef) -> int:
    return maxi(1, loc.stations.size()) * 100


func _back_to_hub() -> void:
    open_hub()
    _notify_main("hub")


func _go_menu() -> void:
    _notify_main("menu")


# ---------------------------------------------------------------- тач-кнопки (v45)

## Тач-режим включён? (на телефоне всегда; на ПК — флаг --touch или тач-экран)
func touch_mode_on() -> bool:
    if _touch_force:
        return true
    if main != null:
        var t = main.get("touch_ui")
        if t != null:
            return bool(t)
    return OS.has_feature("mobile") or DisplayServer.is_touchscreen_available()


## v67: подсказка ходьбы из реальной раскладки игрока. «E» — фиксированная
## клавиша взаимодействия, её не переназначить, поэтому она константой.
func _walk_hint_text() -> String:
    if main != null and main.has_method("_keys_text"):
        var k: Dictionary = main._keys_text()
        return Lang.t("train_walk_hint_fmt") % [String(k.get("move", "WASD"))]
    return Lang.t("train_walk_hint")


## T8: кнопка «назад» одна и та же на всех экранах — слева сверху, как в HUD
## (18,12; на тач-экране крупнее). Смысл зависит от экрана: хаб → меню,
## локация → хаб (см. _on_back_pressed).
func _sync_back_btn() -> void:
    if _back_btn == null:
        return
    _back_btn.text = Lang.t("back_btn")
    _back_btn.position = Vector2(18, 12)
    _back_btn.size = Vector2(230, 96) if touch_mode_on() else Vector2(148, 42)


## Кнопка «назад» одна на два экрана: в хабе — в меню, в локации — в хаб.
func _on_back_pressed() -> void:
    if screen == "hub":
        _go_menu()
    else:
        _back_to_hub()


## Метка кнопки действия под текущее упражнение. Пустая строка — действие не нужно.
func action_label() -> String:
    if repair_on:
        return Lang.t("train_act_repair")
    if result_open:
        return Lang.t("train_act_continue")
    if station == null or not station.active:
        return ""
    var id := String(station.def.id)
    if station.kind() == StationDef.Kind.HOLD:
        return Lang.t("train_act_hold")
    match id:
        "barbell", "homemade_bar":
            return Lang.t("train_act_lift")
        "bar":
            return Lang.t("train_act_pull")
        "rope", "speedrope":
            return Lang.t("train_act_jump")
        "burpee", "pushups", "shadow", "dips":
            return Lang.t("train_act_rep")
    return Lang.t("train_act_hit")


func _on_act_down() -> void:
    if result_open:
        confirm_result()
        return
    if repair_on:
        if repair_prompt_open():
            press_repair()
        return
    _touch_held = true
    if station != null and station.active:
        press_action()


func _on_act_up() -> void:
    _touch_held = false


func _on_stop_pressed() -> void:
    if station != null and station.active:
        abort_station()
    elif repair_on:
        cancel_repair()
    result_open = false
    _update_ui()


## Показать/спрятать и подписать тач-кнопки под текущее состояние.
func _sync_touch_buttons() -> void:
    if _act_btn == null or _stop_btn == null:
        return
    var on := touch_mode_on()
    if not on:
        _act_btn.visible = false
        _stop_btn.visible = false
        return
    var label := action_label()
    _act_btn.visible = label != ""
    if label != "":
        _act_btn.text = label
    var can_stop: bool = (station != null and station.active) or repair_on
    _stop_btn.visible = can_stop
    # кнопка действия не должна налезать на панель со списком станций
    if screen == "hub":
        _act_btn.visible = false
        _stop_btn.visible = false


## Тесты: нажать кнопку действия (как палец), отпустить, СТОП, «назад»/«в меню».
func debug_tap_action() -> String:
    var before := ""
    if station != null and station.active:
        before = String(station.def.id)
    _on_act_down()
    _on_act_up()
    return before


func debug_tap_stop() -> void:
    _on_stop_pressed()


func debug_tap_back() -> void:
    _on_back_pressed()


## Тесты: включить тач-кнопки без телефона (на ПК touch_ui обычно выключен).
func debug_touch_force(on: bool) -> void:
    _touch_force = on
    _sync_touch_buttons()


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
    ui = CanvasLayer.new()
    ui.layer = 6
    add_child(ui)
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(_root)
    _backdrop = ColorRect.new()
    _backdrop.color = Color(0.02, 0.03, 0.05, 0.985)
    _backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
    _backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_backdrop)
    _panel = ColorRect.new()
    _panel.color = Color(0.6, 0.6, 0.7, 0.0)
    _panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_panel)
    _title = _mk_label(Vector2(0, 46), Vector2(1280, 60), 40, Color(0.98, 0.86, 0.45))
    _sub = _mk_label(Vector2(0, 108), Vector2(1280, 30), 18, Color(0.80, 0.84, 0.92))
    _hint = _mk_label(Vector2(0, 660), Vector2(1280, 26), 16, Color(0.62, 0.68, 0.78))
    _status = _mk_label(Vector2(0, 624), Vector2(1280, 26), 18, Color(0.95, 0.75, 0.35))
    for i in 5:
        var b := _mk_button(Vector2(210, 146 + i * 104), Vector2(860, 96))
        b.add_theme_font_size_override("font_size", 15)
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        b.pressed.connect(_on_card_pressed.bind(i))
        _cards.append(b)
    for i in 4:
        var b := _mk_button(Vector2(18, 180 + i * 72), Vector2(434, 64))
        b.add_theme_font_size_override("font_size", 16)
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        b.pressed.connect(_on_station_pressed.bind(i))
        _station_btns.append(b)
    _back_btn = _mk_button(Vector2(18, 12), Vector2(148, 42))
    _back_btn.text = Lang.t("back_btn")
    _back_btn.add_theme_font_size_override("font_size", 18)
    _back_btn.pressed.connect(_on_back_pressed)
    _back_btn.visible = false
    # v45: кнопка действия упражнения — большая, справа снизу, под палец
    _act_btn = _mk_button(Vector2(970, 486), Vector2(292, 142))
    _act_btn.text = Lang.t("train_act_hit")
    _act_btn.add_theme_font_size_override("font_size", 30)
    _act_btn.visible = false
    _act_btn.button_down.connect(_on_act_down)
    _act_btn.button_up.connect(_on_act_up)
    _stop_btn = _mk_button(Vector2(1132, 430), Vector2(130, 48))
    _stop_btn.text = Lang.t("train_stop_btn")
    _stop_btn.add_theme_font_size_override("font_size", 18)
    _stop_btn.visible = false
    _stop_btn.pressed.connect(_on_stop_pressed)
    # T-trainanim: вместо большого квадрата в центре — компактная полоса снизу
    # в одну строку: упражнение · счётчик повторов · подсказка «жми».
    _overlay = ColorRect.new()
    _overlay.color = Color(0.03, 0.04, 0.07, 0.78)
    _overlay.position = Vector2(0, 648)
    _overlay.size = Vector2(1280, 72)
    _overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_overlay)
    _ov_title = _mk_label(Vector2(24, 654), Vector2(420, 26), 22, Color(0.98, 0.86, 0.45))
    _ov_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _ov_hint = _mk_label(Vector2(24, 680), Vector2(420, 20), 13, Color(0.70, 0.76, 0.86))
    _ov_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _ov_hint.visible = false
    _ov_line1 = _mk_label(Vector2(462, 656), Vector2(330, 24), 19, Color(0.96, 0.96, 1.0))
    _ov_line1.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _ov_line2 = _mk_label(Vector2(800, 656), Vector2(456, 24), 18, Color(0.72, 0.78, 0.88))
    _ov_line2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    _overlay.visible = false
    # v59: крупная подсказка момента нажатия — справа от панели локации
    _cue = _mk_label(Vector2(470, 132), Vector2(810, 96), 54, Color(0.98, 0.86, 0.45))
    _cue.text = ""
    _cue.visible = false
    _cue_bar = ColorRect.new()
    _cue_bar.color = Color(0.98, 0.75, 0.14, 0.9)
    _cue_bar.position = Vector2(695, 236)
    _cue_bar.size = Vector2(360, 10)
    _cue_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _cue_bar.visible = false
    _root.add_child(_cue_bar)
    _flash = _mk_label(Vector2(470, 252), Vector2(810, 42), 28, Color(0.55, 0.86, 0.62))
    _flash.text = ""
    _flash.visible = false
    # v69: обозначитель действия — крупная строка над нижней панелью, чтобы при
    # упражнении всегда было видно, ЧТО нажимать (E — УДАР / ДЕРЖИ E и т.п.).
    _act_hint = _mk_label(Vector2(0, 604), Vector2(1280, 36), 26, Color(0.98, 0.86, 0.45))
    _act_hint.text = ""
    _act_hint.visible = false


func _mk_label(pos: Vector2, size: Vector2, font_size: int, color: Color) -> Label:
    var l := Label.new()
    l.position = pos
    l.size = size
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(l)
    return l


func _mk_button(pos: Vector2, size: Vector2) -> Button:
    var b := Button.new()
    b.position = pos
    b.size = size
    b.add_theme_font_size_override("font_size", 20)
    b.text = ""
    _root.add_child(b)
    return b


func _render_hub() -> void:
    _backdrop.visible = true
    # v45: в хабе тоже нужна видимая кнопка выхода — на телефоне нет Esc
    _back_btn.visible = true
    _sync_back_btn()
    _panel.color = Color(0.6, 0.6, 0.7, 0.0)
    _overlay.visible = false
    # v59: подсказка «ЖМИ» и всплывающий результат — только в локации
    if _cue != null:
        _cue.visible = false
        _cue_bar.visible = false
        _flash.visible = false
        _flash_t = 0.0
    _title.text = Lang.t("train_title")
    _title.position = Vector2(0, 22)
    _title.size = Vector2(1280, 50)
    _sub.text = Lang.t("train_sub")
    _sub.position = Vector2(0, 72)
    _sub.size = Vector2(1280, 24)
    _hint.text = Lang.t("train_hub_hint_touch") if touch_mode_on() else Lang.t("train_hub_hint")
    _hint.position = Vector2(0, 676)
    _hint.size = Vector2(1280, 26)
    _status.text = ""
    for i in _cards.size():
        var b := _cards[i]
        var loc := locations[i]
        var unlocked := is_location_unlocked(loc.id)
        var total := _loc_mastery_total(loc)
        var max_total := _loc_mastery_max(loc)
        var head: String
        if unlocked:
            head = "%s · %s" % [_loc_title(loc), Lang.t("train_open")]
        else:
            head = "%s · %s: %s" % [_loc_title(loc), Lang.t("train_locked"), unlock_text(loc.id)]
        var bonus_line: String = Lang.t("train_bonus") % _bonus_text(loc)
        b.text = "%s\n%s\n%s: %s\n%s · %s %d/%d" % [
                head, _loc_desc(loc), Lang.t("train_stations"), _stations_text(loc),
                bonus_line, Lang.t("train_mastery_short"), total, max_total]
        b.visible = true
        b.position = Vector2(210, 146 + i * 104)
        b.disabled = not unlocked
        if not unlocked:
            b.add_theme_color_override("font_color", Color(0.58, 0.60, 0.66))
        else:
            b.add_theme_color_override("font_color",
                    Color(0.98, 0.86, 0.45) if i == sel else Color(0.92, 0.94, 0.98))
    for b in _station_btns:
        b.visible = false
    _sync_touch_buttons()


func _render_location() -> void:
    var loc := config.find_location(current_location_id)
    if loc == null:
        return
    # комнату показываем напрямую: затемнение хаба здесь не нужно
    _backdrop.visible = false
    _back_btn.visible = true
    _sync_back_btn()
    _panel.color = Color(0.03, 0.04, 0.06, 0.82)
    _panel.position = Vector2(0, 0)
    _panel.size = Vector2(470, 720)
    _title.text = _loc_title(loc)
    _title.position = Vector2(0, 60)
    _title.size = Vector2(470, 40)
    # описание: перенос по словам и ширина панели, чтобы текст не уезжал в 3D
    _sub.text = _loc_desc(loc)
    _sub.position = Vector2(18, 104)
    _sub.size = Vector2(434, 64)
    _sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _sub.add_theme_font_size_override("font_size", 15)
    # v67: подсказка из реальной раскладки игрока (после переназначения клавиш
    # «WASD — идти» врала). E — фиксированная клавиша «взаимодействия».
    _hint.text = "" if touch_mode_on() else _walk_hint_text()
    _hint.position = Vector2(18, 652)
    _hint.size = Vector2(434, 44)
    _hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _status.text = ""
    _status.position = Vector2(18, 540)
    _status.size = Vector2(434, 42)
    _status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    if _nearest_id != "":
        var near_st: Node3D = _station_by_id(_nearest_id)
        if near_st != null:
            _status.text = (Lang.t("train_near_touch") if touch_mode_on()
                    else Lang.t("train_near")) % _st_title(current_location_id, near_st.def)
    for b in _cards:
        b.visible = false
    _overlay.visible = false
    for i in _station_btns.size():
        var b := _station_btns[i]
        if i >= order.size():
            b.visible = false
            continue
        var st: Node3D = _station_by_id(order[i])
        b.visible = true
        b.position = Vector2(18, 180 + i * 72)
        b.disabled = false
        var m := int(mastery(current_location_id, st.def.id))
        var st_title := _st_title(current_location_id, st.def)
        if st.is_broken():
            b.text = "%s · %s" % [st_title, Lang.t("train_broken")]
            b.add_theme_color_override("font_color", Color(0.92, 0.45, 0.38))
        else:
            b.text = "%s · %s %d · %s %d" % [st_title, Lang.t("train_mastery_short"), m,
                    Lang.t("train_durability_short"), int(round(st.durability))]
            var lit: bool = i == sel or order[i] == _nearest_id
            b.add_theme_color_override("font_color",
                    Color(0.98, 0.86, 0.45) if lit else Color(0.90, 0.92, 0.98))
    _update_overlay()


## v69: обозначитель действия. На ПК крупная строка над нижней панелью
## («E — УДАР», «держи E»), на телефоне роль обозначителя играет кнопка действия.
## Плюс мелкая подсказка по типу станции под названием упражнения.
func _update_action_hint(show: bool, touch: bool) -> void:
    var act := action_label()
    var hint_text := ""
    if station != null and station.active:
        match station.kind():
            StationDef.Kind.HOLD:
                hint_text = Lang.t("train_hold_hint")
            StationDef.Kind.QTE:
                hint_text = Lang.t("train_qte_hint")
            StationDef.Kind.RHYTHM:
                hint_text = Lang.t("train_rhythm_hint")
            _:
                hint_text = Lang.t("train_bag_hint")
    if _ov_hint != null:
        _ov_hint.text = hint_text
        _ov_hint.visible = show and hint_text != "" and not result_open
    if _act_hint == null:
        return
    var on_pc: bool = show and not touch and act != ""
    _act_hint.visible = on_pc
    if not on_pc:
        return
    if station != null and station.active and station.kind() == StationDef.Kind.HOLD:
        _act_hint.text = Lang.t("train_hold_hint")
    elif result_open:
        _act_hint.text = "" if touch else Lang.t("train_continue")
    else:
        _act_hint.text = "E — %s" % act


func _update_overlay() -> void:
    if not active or ui == null:
        return
    var show := false
    var title := ""
    var mid := ""
    var right := ""
    var urgent := false
    var touch := touch_mode_on()
    if repair_on:
        show = true
        title = Lang.t("train_repair_title")
        if repair_prompt_open():
            mid = Lang.t("train_repair_hint_touch") if touch else Lang.t("train_press_now")
            right = "окно %.2f с" % REPAIR_WINDOW
            urgent = true
        else:
            mid = Lang.t("train_wait_prompt")
    elif result_open:
        show = true
        var ok := bool(last_result.get("ok", false))
        title = Lang.t("train_done") if ok else Lang.t("train_fail")
        var gain: Dictionary = last_result.get("gain", {})
        if bool(last_result.get("repair", false)):
            title = Lang.t("train_repaired")
            mid = "%s %d" % [Lang.t("train_durability_word"),
                    int(round(float(last_result.get("durability", 0.0))))]
        else:
            mid = "%s %d · %s %d" % [Lang.t("train_reps"), int(last_result.get("reps", 0)),
                    Lang.t("train_mistakes"), int(last_result.get("mistakes", 0))]
        right = _gain_text(gain)
        if right == "":
            right = Lang.t("train_act_continue") if touch else Lang.t("train_continue")
    elif station != null and station.active:
        show = true
        title = _st_title(current_location_id, station.def)
        var kind: int = station.kind()
        if kind == StationDef.Kind.BAG:
            mid = "%s %d" % [Lang.t("train_reps"), station.reps_done]
            right = Lang.t("train_bag_hint_touch") if touch else Lang.t("train_bag_hint")
        elif kind == StationDef.Kind.HOLD:
            mid = "%d%%" % int(round(station.hold_progress() * 100.0))
            right = "%s %d / %d" % [Lang.t("train_reps"), station.reps_done,
                    int(station.def.reps)]
        else:
            mid = "%s %d / %d" % [Lang.t("train_reps"), station.reps_done,
                    int(station.def.reps)]
            if station.prompt_open():
                right = (Lang.t("train_press_now_touch") if touch
                        else Lang.t("train_press_now")) + " (%.2f с)" % station.prompt_left()
                urgent = true
            else:
                # между повторами — маленькая подсказка, экран не залеплен цифрами
                var wait_left: float = 0.0
                if station.has_method("time_to_prompt"):
                    wait_left = float(station.time_to_prompt())
                right = "%s %.1f с" % [Lang.t("train_wait_prompt"), wait_left]
    _overlay.visible = show
    # v59: момент нажатия видно без приглядывания — крупное «ЖМИ!» и полоса,
    # которая сжимается по мере закрытия окна; звук-«тик» в момент открытия.
    var qte_kind: bool = station != null and station.active \
            and (station.kind() == StationDef.Kind.QTE or station.kind() == StationDef.Kind.RHYTHM)
    var qte_open: bool = qte_kind and station.prompt_open()
    if qte_open and not _prompt_sound_prev:
        _play("block")
    _prompt_sound_prev = qte_open
    _prompt_prev = qte_open
    if _cue != null:
        _cue.visible = qte_open
        _cue.text = ("ЖМИ!" if not Lang.is_en() else "NOW!")
        _cue_bar.visible = qte_open
        if qte_open:
            var win := maxf(0.01, float(station.def.perfect_window))
            var left: float = clampf(station.prompt_left() / win, 0.0, 1.0)
            _cue_bar.size = Vector2(360.0 * left, 10.0)
            _cue_bar.color = Color(0.98, 0.75, 0.14, 0.9) if left > 0.3 \
                    else Color(1.0, 0.35, 0.28, 0.95)
    if _flash != null:
        _flash.visible = _flash_t > 0.0
    # v59: пока идёт упражнение, нижняя подсказка «подойди и нажми E» не нужна
    # (она налезала на строку упражнения)
    if _hint != null:
        _hint.visible = not show
    # v69: обозначитель действия — что нажимать прямо сейчас
    _update_action_hint(show, touch)
    # v45: кнопки «действие/стоп» живут вместе с оверлеем упражнения
    _sync_touch_buttons()
    if not show:
        return
    _ov_title.text = title
    _ov_line1.text = mid
    _ov_line2.text = right
    _ov_line2.add_theme_color_override("font_color",
            Color(1.0, 0.86, 0.45) if urgent else Color(0.72, 0.78, 0.88))


func _update_ui() -> void:
    if screen == "hub":
        _render_hub()
    else:
        _render_location()


## Обновить подсказку «рядом станция» и подсветку (зовётся из tick).
func _refresh_near_hint() -> void:
    if screen != "loc" or ui == null:
        return
    if _nearest_id != "":
        var st: Node3D = _station_by_id(_nearest_id)
        if st != null:
            _status.text = (Lang.t("train_near_touch") if touch_mode_on()
                    else Lang.t("train_near")) % _st_title(current_location_id, st.def)
    else:
        _status.text = ""


func _bonus_text(loc: TrainingLocationDef) -> String:
    var parts: Array[String] = []
    for k in loc.stat_bonus:
        parts.append("%s ×%.1f" % [_stat_name(String(k)), float(loc.stat_bonus[k])])
    return ", ".join(parts)


func _gain_text(gain: Dictionary) -> String:
    if gain.is_empty():
        return ""
    var parts: Array[String] = []
    for k in gain:
        parts.append("+%.2f %s" % [float(gain[k]), _stat_name(String(k))])
    return ", ".join(parts)


func _stat_name(stat: String) -> String:
    match stat:
        "strength":
            return Lang.t("stat_strength")
        "stamina":
            return Lang.t("stat_stamina")
        "speed":
            return Lang.t("stat_speed")
    return stat


func _play(key: String) -> void:
    if main != null and main.get("sfx") != null:
        (main.sfx as Node).play(key, randf_range(0.95, 1.05), -12.0)



