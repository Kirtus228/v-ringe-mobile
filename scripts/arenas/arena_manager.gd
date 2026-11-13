class_name ArenaManager
extends Node3D
## Этап 4: боевые локации (арены). Хаб с карточками → бой на существующем
## движке main.gd с модификаторами из ArenaDef, награды/рекорды в save.dat.
## Архитектура как у тренировки: модуль-Node внутри main, main только даёт
## кадр и применяет флаги/коэффициенты. Боевую стейт-машину не переписываем.

const Lang = preload("res://scripts/lang.gd")
const FactoryScript := preload("res://scripts/arenas/arena_config_factory.gd")
## Этап 6: визуал арен (окружение по scene_kind + видимые модификаторы среды).
var ArenaVisualScript: GDScript = null  # ленивая загрузка: без файла проект компилируется (fallback)
## значения main.St: FIGHT=1, ARENA_HUB=16 (enum в main.gd не виден из модуля)
const STATE_FIGHT := 1
const STATE_ARENA_HUB := 16
const SECTION := "arenas"
const BET := 50
const ARENA_EDGE := 3.0

var main: Node
var arenas: Array[ArenaDef] = []
var by_id: Dictionary = {}
var current: ArenaDef
var hub_visible := false
var fight_running := false
var screen := "hub"           # hub | result
var sel := 0
var last_result: Dictionary = {}
var bet := 0
var _fight_start_ms := 0
var _rock_t := 0.0
## v71m: --arenadiag — раз в 0.5 с печатаем позицию/HP бойцов и расстояния до
## опасных зон, чтобы видеть причину «самого по себе» урона и «падения за край».
var _diag_t := 0.0
var _diag_haz_dmg := 0.0
var _room: Node3D
## Этап 6: визуальный модуль комнаты (создаётся только при visual_level != OFF).
var _arena_visual: Node3D

# --- UI
var ui: CanvasLayer
var _root: Control
var _backdrop: ColorRect
var _title: Label
var _sub: Label
var _hint: Label
var _cards: Array[Button] = []
var _back_btn: Button
var _result_panel: ColorRect
var _result_title: Label
var _result_body: Label
var _result_rematch: Button
var _result_hub: Button
var _fight_bar: ColorRect
var _fight_label: Label
var _surrender_btn: Button
## v55: строка версии/рендера в хабе арен — по ней со скриншота телефона сразу
## видно, какая сборка стоит и каким рендерером она рисует.
var _ver_lbl: Label


func setup(main_ref: Node) -> void:
    main = main_ref
    arenas = FactoryScript.create_default()
    for a in arenas:
        by_id[a.id] = a
    _build_ui()
    ui.visible = false


# ---------------------------------------------------------------- хаб

func open_hub() -> void:
    fight_running = false
    hub_visible = true
    screen = "hub"
    sel = 0
    _clear_room()
    _hide_world(false)
    ui.visible = true
    _show_screen("hub")


func close() -> void:
    fight_running = false
    hub_visible = false
    screen = "hub"
    _clear_room()
    if ui != null:
        ui.visible = false
    # v50: при выходе из модуля вернуть основной ринг — иначе следующий обычный
    # бой шёл без ринга (пустая комната и на ПК, и на телефоне)
    _hide_world(true)
    if main != null:
        main.arena_active = false


func show_hub() -> void:
    hub_visible = true
    screen = "hub"
    _show_screen("hub")


func get_available_arenas() -> Array[ArenaDef]:
    return arenas


func arena_by_id(id: String) -> ArenaDef:
    return by_id.get(id)


func current_arena() -> ArenaDef:
    return current


## T2: единая точка локализованного названия арены. Не зависит от того,
## когда создан бой: язык берётся из Lang в момент показа.
func display_title(a: ArenaDef) -> String:
    if a == null:
        return ""
    if Lang.is_en():
        var en := String(a.title_en).strip_edges()
        if en != "":
            return en
    var ru := String(a.title).strip_edges()
    return ru if ru != "" else "ARENA"


## T2: единая точка локализованного имени противника арены.
func display_enemy(e: EnemyDef) -> String:
    if e == null:
        return "OPPONENT"
    if Lang.is_en():
        var en := String(e.title_en).strip_edges()
        if en != "":
            return en
    var ru := String(e.title).strip_edges()
    if ru == "":
        return "OPPONENT"
    var out := ru
    if out.length() > 40:
        out = out.substr(0, 40)
    return out


func is_arena_unlocked(a: ArenaDef) -> bool:
    if a == null:
        return false
    if bool(_load_bool("unlocked/" + a.id)):
        return true
    var cond: Dictionary = a.unlock_condition
    if cond.is_empty():
        return true
    if cond.has("arena"):
        return int(_load_float("wins/" + String(cond["arena"]), 0.0)) > 0.0
    if cond.has("wins"):
        return total_arena_wins() >= int(cond["wins"])
    if cond.has("visited_training"):
        if SaveManager != null:
            return bool(SaveManager.load_value("training", "visited/"
                    + String(cond["visited_training"]), false))
        return false
    return true


func unlock_arena(id: String) -> void:
    _save_bool("unlocked/" + id, true)
    _flush()


func total_arena_wins() -> int:
    var total := 0
    for a in arenas:
        total += int(_load_float("wins/" + a.id, 0.0))
    return total


func best_time(id: String) -> float:
    return _load_float("best_time/" + id, 0.0)


func best_series(id: String) -> int:
    return int(_load_float("best_series/" + id, 0.0))


func record_result(id: String, won: bool, elapsed: float, series: int) -> Dictionary:
    var key := "wins/" if won else "losses/"
    _save_float(key + id, _load_float(key + id, 0.0) + 1.0)
    if won:
        var prev := best_time(id)
        if prev <= 0.0 or elapsed < prev:
            _save_float("best_time/" + id, elapsed)
        if series > best_series(id):
            _save_float("best_series/" + id, series)
        unlock_arena(id)
        _unlock_satisfied()
    _flush()
    return {"wins": int(_load_float("wins/" + id, 0.0)),
            "losses": int(_load_float("losses/" + id, 0.0)),
            "best_time": best_time(id), "best_series": best_series(id)}


func _unlock_satisfied() -> void:
    for a in arenas:
        if is_arena_unlocked(a):
            _save_bool("unlocked/" + a.id, true)


# ---------------------------------------------------------------- бой

func start_arena_force(id: String) -> bool:
    unlock_arena(id)
    return start_arena(id)


func start_arena(id: String) -> bool:
    var def := arena_by_id(id)
    if def == null or not is_arena_unlocked(def) or fight_running:
        return false
    if main == null or not main.has_method("_start_fight"):
        return false
    current = def
    screen = "fight"
    last_result = {}
    bet = 0
    hub_visible = false
    ui.visible = true
    _show_screen("fight")
    if main.touch_ui and main.touch != null:
        main.touch.set_active(false)
    main._start_fight()
    fight_running = true
    _fight_start_ms = Time.get_ticks_msec()
    _apply_rules(def)
    _apply_enemy(def)
    _apply_environment(def)
    _build_room(def)
    _face_opponents()
    hud_show_fight(def)
    main._set_state(STATE_FIGHT)
    # v53: диагностика видимости ринга на аренах
    if main.get("arena") != null:
        print("ARENASTART ", def.id, " ring_visible=", (main.arena as Node3D).visible,
                " arena_active=", bool(main.get("arena_active")),
                " room_children=", _room.get_child_count() if _room != null else -1)
    sfx_bell()
    return true


## Применить правила арены к main (main читает эти поля в бою).
func _apply_rules(def: ArenaDef) -> void:
    var rules: Dictionary = def.rules_modifiers
    main.arena_active = true
    main.arena_def = def
    main.arena_penalty = def.apply_ranked_penalty
    main.arena_no_knockdown = bool(rules.get("no_knockdown", false))
    main.arena_no_healing = bool(rules.get("no_healing", false))
    main.arena_rounds_to_win = int(rules.get("rounds_to_win", 0))
    main.arena_fall_defeat = bool(def.environment_modifiers.get("fall_defeat", false))
    main.arena_confined = float(def.environment_modifiers.get("confined", 0.0))
    main.arena_edge_hazard = float(def.environment_modifiers.get("edge_hazard", 0.0))
    main.arena_ring_limit = (main.arena_confined if main.arena_confined > 0.0 else 3.0)
    if main.arena_fall_defeat:
        main.arena_ring_limit = 99.0       # не режем канатами: край = падение
    main.rounds_total = maxi(1, def.rounds)
    main.round_num = 1
    main.round_time = def.round_time
    main.timer = def.round_time
    main.rounds_won_p = 0
    main.rounds_won_e = 0
    main.bell_hold = false
    if rules.has("time_limit"):
        main.round_time = float(rules["time_limit"])
        main.timer = main.round_time
    # ставка в клубе: снимаем со счёта, ×2 при победе
    if bool(rules.get("betting", false)) and main.coins >= BET:
        bet = BET
        main.coins -= BET
        main._save_profile()


## Противник из EnemyDef: HP/урон/скорость/агрессия поверх существующего AI.
func _apply_enemy(def: ArenaDef) -> void:
    var pool := def.opponent_pool
    if pool.is_empty():
        return
    var pick: EnemyDef = pool[total_arena_wins() % pool.size()]
    var spawn := Vector3(0.0, 0.0, -1.9)
    main.enemy.reset(spawn, pick.max_hp)
    main.enemy.max_hp = pick.max_hp
    main.enemy.hp = pick.max_hp
    main.enemy.dmg_mult = pick.damage_mult
    main.enemy.dur_mult = 1.0 / maxf(0.6, pick.speed_mult)
    main.enemy.max_stamina = pick.stamina
    main.enemy.stamina = pick.stamina
    main.enemy.taken_mult = 1.0 - 0.3 * float(def.difficulty) / 5.0
    main.opp["name"] = display_enemy(pick)
    main.opp["level"] = clampf(float(def.difficulty - 1) / 4.0, 0.0, 1.0)
    main.enemy.set_difficulty(clampf(float(def.difficulty - 1) / 4.0, 0.0, 1.0))
    main.enemy.dmg_mult = pick.damage_mult
    main.enemy.dur_mult = 1.0 / maxf(0.6, pick.speed_mult)
    main.ai_skill = clampi(def.difficulty - 1, 0, 5)
    main.player.position = Vector3(0.0, 0.0, 1.9)
    main.hud.set_opponent_name(display_enemy(pick))


func _face_opponents() -> void:
    main.player.look_at_target(main.enemy.position)
    main.enemy.look_at_target(main.player.position)
    main.player.vel = Vector3.ZERO
    main.enemy.vel = Vector3.ZERO


## Модификаторы среды → поля бойцов (fighter читает их в движении/уроне).
func _apply_environment(def: ArenaDef) -> void:
    var env: Dictionary = def.environment_modifiers
    var wind := Vector3.ZERO
    if env.has("wind"):
        var w = env["wind"]
        if w is Vector3:
            wind = w
    for f in [main.player, main.enemy]:
        f.surface_friction = def.friction()
        f.stamina_drain = float(env.get("stamina_drain", 0.0))
        f.gravity_mult = float(env.get("gravity", 1.0))
        f.wind = wind


## Кадр боя: опасные зоны, край/падение, качка, ограничение площадки.
func tick_fight(delta: float) -> void:
    if not fight_running or current == null or main == null:
        return
    if bool(main.get("arena_diag")):
        _diag_t += delta
        if _diag_t >= 0.5:
            _diag_t = 0.0
            var pp: Vector3 = main.player.position
            var pe: Vector3 = main.enemy.position
            var hz: Array = current.environment_modifiers.get("hazards", [])
            var hz_txt: Array = []
            for h in hz:
                var hp: Vector3 = h.get("pos", Vector3.ZERO)
                var hr := float(h.get("radius", 1.0))
                hz_txt.append("%.2f/%.2f" % [
                        Vector2(pp.x - hp.x, pp.z - hp.z).length(), hr])
            var t_sec := float(Time.get_ticks_msec() - _fight_start_ms) / 1000.0
            print("ARENADBG ", current.id, " t=", snappedf(t_sec, 0.1),
                    " P=(", snappedf(pp.x, 0.01), ",", snappedf(pp.z, 0.01),
                    ") dP=", snappedf(Vector2(pp.x, pp.z).length(), 0.01),
                    " hpP=", snappedf(main.player.hp, 0.1),
                    " E=(", snappedf(pe.x, 0.01), ",", snappedf(pe.z, 0.01),
                    ") hpE=", snappedf(main.enemy.hp, 0.1),
                    " edge=", snappedf(float(current.environment_modifiers.get(
                            "fall_radius", ARENA_EDGE + 0.45)), 0.01),
                    " lim=", snappedf(main.arena_ring_limit, 0.01),
                    " hazard(player)",
                    "=", str(hz_txt),
                    " fall=", main.arena_fall_defeat,
                    " hz_dmg=", snappedf(_diag_haz_dmg, 0.01))
    # Этап 6: анимация визуала арены (мерцание/аудио/пульс аур)
    if _arena_visual != null:
        _arena_visual.tick(delta)
    var env: Dictionary = current.environment_modifiers
    var hazards: Array = env.get("hazards", [])
    for h in hazards:
        var pos: Vector3 = h.get("pos", Vector3.ZERO)
        var rad := float(h.get("radius", 1.0))
        var dps := float(h.get("dps", 2.0))
        for f in [main.player, main.enemy]:
            if f.fallen or f.ko or f.hp <= 0.0:
                continue
            if Vector2(f.position.x - pos.x, f.position.z - pos.z).length() <= rad:
                f.hp = maxf(0.0, f.hp - dps * delta)
                # v71m: ожог виден — красно-оранжевая вспышка сильнее обычной,
                # чтобы урон «сам по себе» не выглядел багом
                f.flash = maxf(f.flash, 0.18)
                f.taken += dps * delta
                if bool(main.get("arena_diag")):
                    _diag_haz_dmg += dps * delta
                if f.hp <= 0.0:
                    var other = main.enemy if f == main.player else main.player
                    main._hp_zero(f, other, f.position - other.position, "jab")
                    return
    # край: урон у края и/или падение
    var fall := float(env.get("fall_defeat", 0.0))
    # v71m: радиус «края» для арен с падением. По умолчанию — граница ринга,
    # но у «Крыши» край — это парапет (стены на радиусе 7), поэтому радиус
    # задаётся данными арены (fall_radius). Раньше падение срабатывало на 3.45 м
    # от центра, то есть посреди видимой крыши: бой кончался через 2 секунды.
    var fall_rad := float(env.get("fall_radius", ARENA_EDGE + 0.45))
    for f in [main.player, main.enemy]:
        if f.fallen or f.ko:
            continue
        var d := Vector2(f.position.x, f.position.z).length()
        if fall > 0.0 and d > fall_rad:
            if bool(main.get("arena_diag")):
                print("ARENADBG край: ", f.name, " d=", snappedf(d, 0.01),
                        " vel=", f.vel, " → поражение")
            main._end_fight("lose" if f == main.player else "ringout", true)
            return
        # v71m: на аренах с падением «опасный край» отсчитывается от того же
        # радиуса, что и падение (у «Крыши» — парапет), и предупреждает уроном
        # ДО падения, а не молча: раньше edge_hazard был мёртв (ring_limit=99).
        var edge_lim: float = fall_rad if fall > 0.0 else float(main.arena_ring_limit)
        if main.arena_edge_hazard > 0.0 and d > edge_lim - 0.9:
            f.hp = maxf(0.0, f.hp - main.arena_edge_hazard * delta)
            f.flash = 0.08
            f.taken += main.arena_edge_hazard * delta
            if f.hp <= 0.0:
                var other2 = main.enemy if f == main.player else main.player
                main._hp_zero(f, other2, f.position - other2.position, "jab")
                return
    # качка палубы: дрейф обоих бойцов + наклон комнаты
    var rock := float(env.get("rocking", 0.0))
    if rock > 0.0:
        _rock_t += delta
        var push := Vector3(sin(_rock_t * 1.1) * 0.8, 0.0, cos(_rock_t * 0.7) * 0.5) * rock * delta
        main.player.position += push
        main.enemy.position += push
        if _room != null:
            _room.rotation.z = sin(_rock_t * 1.1) * 0.02 * rock
            _room.rotation.x = cos(_rock_t * 0.7) * 0.015 * rock
    # ограниченная площадка: не выпускаем за арену
    if main.arena_confined > 0.0:
        for f in [main.player, main.enemy]:
            var lim: float = main.arena_confined
            f.position.x = clampf(f.position.x, -lim, lim)
            f.position.z = clampf(f.position.z, -lim, lim)


## Вызывается из main._finalize после конца боя.
func on_fight_finished(kind: String) -> void:
    if current == null:
        return
    fight_running = false
    _clear_room()
    var won: bool = kind == "win" or kind == "ringout" or kind == "timewin"
    var elapsed: float = maxf(0.001, float(Time.get_ticks_msec() - _fight_start_ms) / 1000.0)
    var series: int = int(main.rounds_won_p)
    var rec := record_result(current.id, won, elapsed, series)
    var gains := {"coins": 0, "rep": 0, "stats": {}}
    if won:
        gains["coins"] = current.money_reward
        gains["rep"] = current.reputation_reward
        main.coins += current.money_reward
        main.arena_rep += current.reputation_reward
        for k in current.stat_bonus_on_win:
            var got := StatsManager.add_stat(String(k), float(current.stat_bonus_on_win[k])) \
                    if StatsManager != null else 0.0
            gains["stats"][String(k)] = got
        if bet > 0:
            main.coins += bet * 2
            gains["coins"] += bet * 2
    elif bet > 0:
        gains["coins"] = -bet
    if main.has_method("_save_profile"):
        main._save_profile()
    if StatsManager != null:
        StatsManager.save_stats()
    last_result = {"arena": current.id, "title": display_title(current), "won": won,
            "kind": kind, "elapsed": elapsed, "series": series, "gains": gains,
            "record": rec, "bet": bet}
    bet = 0
    screen = "result"
    main._set_state(STATE_ARENA_HUB)
    _show_screen("result")
    print("ARENA результат ", current.id, " won=", won, " время=", snappedf(elapsed, 0.1),
            " серия=", series, " монеты+", gains["coins"], " репутация+", gains["rep"],
            " рекорд=", rec)


## Сдаться: поражение без штрафа (main завершает бой, экран результата — как обычно).
func request_surrender() -> void:
    if not fight_running or main == null:
        return
    main._end_fight("lose", true)


func rematch() -> bool:
    if current == null:
        return false
    _result_panel.visible = false
    return start_arena(current.id)


func back_to_hub() -> void:
    _clear_room()
    _hide_world(false)
    main._reset_fight()
    main._set_state(STATE_ARENA_HUB)
    open_hub()


## Для тестов: завершить бой заданным исходом (без реального боя).
func debug_finish(won: bool) -> void:
    on_fight_finished("win" if won else "lose")


# ---------------------------------------------------------------- ввод

func handle_key(event: InputEvent) -> String:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return ""
    var key := (event as InputEventKey).keycode
    if screen == "result":
        match key:
            KEY_ENTER, KEY_KP_ENTER, KEY_E:
                rematch()
                return ""
            KEY_ESCAPE:
                back_to_hub()
                return "hub"
        return ""
    match key:
        KEY_ESCAPE:
            return "menu"
        KEY_UP:
            _move_sel(-1)
            return ""
        KEY_DOWN:
            _move_sel(1)
            return ""
        KEY_ENTER, KEY_KP_ENTER, KEY_E:
            _click_selected()
    return ""


func _move_sel(d: int) -> void:
    if arenas.is_empty():
        return
    sel = wrapi(sel + d, 0, arenas.size())
    _show_screen("hub")


func _click_selected() -> void:
    if sel < 0 or sel >= arenas.size():
        return
    var a := arenas[sel]
    if is_arena_unlocked(a):
        start_arena(a.id)


func handle_touch(pos: Vector2) -> String:
    # карточки/кнопки — обычные Control, сюда доходят только клики по сцене
    return ""


## Для тестов/тача: тап по карточке хаба.
func tap_card(i: int) -> bool:
    if screen != "hub" or i < 0 or i >= arenas.size():
        return false
    sel = i
    var a := arenas[i]
    if not is_arena_unlocked(a):
        return false
    return start_arena(a.id)


# ---------------------------------------------------------------- сохранение

func _load_float(key: String, def: float = 0.0) -> float:
    if SaveManager == null:
        return def
    return float(SaveManager.load_value(SECTION, key, def))


func _load_bool(key: String, def: bool = false) -> bool:
    if SaveManager == null:
        return def
    return bool(SaveManager.load_value(SECTION, key, def))


func _save_float(key: String, v: float) -> void:
    if SaveManager != null:
        SaveManager.save_value(SECTION, key, v)


func _save_bool(key: String, v: bool) -> void:
    if SaveManager != null:
        SaveManager.save_value(SECTION, key, v)


func _flush() -> void:
    if SaveManager != null:
        SaveManager.flush()


## Для тестов: очистить прогресс арен.
func reset_arena_save() -> void:
    if SaveManager == null:
        return
    SaveManager.data[SECTION] = {}
    SaveManager.flush()


# ---------------------------------------------------------------- окружение

func _hide_world(show_ring: bool) -> void:
    if main == null:
        return
    if main.get("arena") != null:
        main.arena.visible = show_ring
    if main.get("player") != null:
        main.player.visible = true
    if main.get("enemy") != null:
        main.enemy.visible = true


func _build_room(def: ArenaDef) -> void:
    _clear_room()
    if main.get("arena") != null:
        main.arena.visible = false
    _room = Node3D.new()
    _room.name = "ArenaRoom_" + def.id
    main.add_child(_room)
    # Этап 6: при включённом визуале комнату целиком строит ArenaVisual
    # (уникальный scene_kind, свет, толпа, модификаторы). При OFF — ровно
    # прежняя legacy-комната, байт-в-байт как до правок.
    var vc = main.get("visual")
    if vc != null and vc.visual_on():
        if ArenaVisualScript == null:
            var av_path := "res://scripts/arenas/arena_visual.gd"
            if ResourceLoader.exists(av_path):
                var av_res: Resource = load(av_path)
                if av_res is GDScript:
                    ArenaVisualScript = av_res as GDScript
    if vc != null and vc.visual_on() and ArenaVisualScript != null:
        _arena_visual = ArenaVisualScript.new()
        _arena_visual.name = "ArenaVisual"
        _room.add_child(_arena_visual)
        _arena_visual.build(main, vc, def)
        # v48: на телефоне комната иногда получалась пустой/чёрной. Проверяем, что
        # визуал реально что-то построил (меши + свет); если нет — падаем на
        # простую комнату, она работает на любом железе.
        var built_ok: bool = _arena_visual != null and bool(_arena_visual.get("built")) \
                and _count_visible(_room, "mesh") > 0 and _count_visible(_room, "light") > 0
        if built_ok:
            print("ARENAROOM ", def.id, " visual ok meshes=", _count_visible(_room, "mesh"),
                    " lights=", _count_visible(_room, "light"))
            return
        print("ARENAROOM ", def.id, " визуал не собрался (меши=",
                _count_visible(_room, "mesh"), " свет=", _count_visible(_room, "light"),
                ") → простая комната")
        _clear_room()
        if main.get("arena") != null:
            main.arena.visible = false
        _room = Node3D.new()
        _room.name = "ArenaRoom_" + def.id
        main.add_child(_room)
        _build_legacy_room(def)
        return
    _build_legacy_room(def)


## Сколько видимых мешей/света реально есть в комнате (для проверки визуала).
func _count_visible(root: Node, kind: String) -> int:
    var n := 0
    for ch in root.get_children():
        if kind == "mesh" and ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
            n += 1
        elif kind == "light" and ch is Light3D:
            n += 1
        if ch.get_child_count() > 0:
            n += _count_visible(ch, kind)
    return n


## Простая комната арены (работает на любом рендерере и на телефоне).
func _build_legacy_room(def: ArenaDef) -> void:
    var floor := MeshInstance3D.new()
    var fm := BoxMesh.new()
    fm.size = Vector3(14.0, 0.2, 14.0)
    floor.mesh = fm
    var fmat := StandardMaterial3D.new()
    fmat.albedo_color = def.floor_color
    fmat.roughness = 0.9
    fmat.emission_enabled = true
    fmat.emission = def.floor_color * 0.3
    floor.material_override = fmat
    floor.position = Vector3(0.0, -0.1, 0.0)
    _room.add_child(floor)
    for sx in [-7.0, 7.0]:
        var wall := MeshInstance3D.new()
        var wm := BoxMesh.new()
        wm.size = Vector3(0.3, 5.0, 14.0)
        wall.mesh = wm
        var wmat := StandardMaterial3D.new()
        wmat.albedo_color = def.floor_color.darkened(0.4)
        wmat.roughness = 0.95
        wmat.emission_enabled = true
        wmat.emission = def.floor_color.darkened(0.4) * 0.25
        wall.material_override = wmat
        wall.position = Vector3(sx, 2.4, 0.0)
        _room.add_child(wall)
    var light := DirectionalLight3D.new()
    light.light_color = def.light_color
    light.light_energy = def.light_energy * 1.2
    light.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
    _room.add_child(light)
    var lamp := OmniLight3D.new()
    lamp.light_color = def.light_color
    lamp.light_energy = def.light_energy * 1.8
    lamp.omni_range = 18.0
    lamp.position = Vector3(0.0, 4.2, 2.0)
    _room.add_child(lamp)
    if def.crowd:
        for i in 10:
            var c := MeshInstance3D.new()
            var cm := BoxMesh.new()
            cm.size = Vector3(0.6, 0.9 + 0.2 * float(i % 3), 0.6)
            c.mesh = cm
            var cmat := StandardMaterial3D.new()
            cmat.albedo_color = Color(0.25 + 0.03 * float(i % 4), 0.22, 0.28)
            cmat.emission_enabled = true
            cmat.emission = cmat.albedo_color * 0.4
            c.material_override = cmat
            var side := -1.0 if i % 2 == 0 else 1.0
            c.position = Vector3(side * (6.1 + 0.15 * float(i % 2)),
                    0.45 + 0.2 * float(i % 3), -5.0 + 1.1 * float(i / 2))
            _room.add_child(c)
    if def.obstacles:
        for i in 3:
            var ob := MeshInstance3D.new()
            var om := BoxMesh.new()
            om.size = Vector3(0.8, 0.8, 0.8)
            ob.mesh = om
            var omat := StandardMaterial3D.new()
            omat.albedo_color = Color(0.35, 0.30, 0.24)
            omat.emission_enabled = true
            omat.emission = Color(0.35, 0.30, 0.24) * 0.3
            ob.material_override = omat
            ob.position = Vector3(-4.0 + 2.4 * float(i), 0.4, -2.8 + 1.3 * float(i))
            _room.add_child(ob)


## Этап 6: сводка визуала арены (для отчёта/тестов).
func visual_stats() -> Dictionary:
    if _arena_visual != null and _arena_visual.has_method("stats"):
        return _arena_visual.stats()
    return {"built": false}


## v55: комната арены реально построена? Пока она существует, основной ринг обязан
## быть скрыт — независимо от того, что успело выставить поле main.arena_active.
## На телефоне (другой порядок кадров/загрузки) флаг мог остаться false, и вместо
## арены показывался красный ринг.
func room_ready() -> bool:
    return _room != null and is_instance_valid(_room) and _room.get_child_count() > 0



func _clear_room() -> void:
    if _arena_visual != null:
        if _arena_visual.has_method("restore"):
            _arena_visual.restore()
        _arena_visual = null
    if _room != null:
        main.remove_child(_room)
        _room.queue_free()
        _room = null
    if main != null and main.get("arena") != null:
        main.arena.visible = false


## Короткая версия сборки («v55») из строки Lang.t("version").
func version_short() -> String:
    var v := Lang.t("version")
    var n := v.get_slice_count("·")
    return v.get_slice("·", n - 1).strip_edges()


func hud_show_fight(def: ArenaDef) -> void:
    _fight_bar.visible = true
    # v55: версия в строке арены — доказательство со скриншота телефона, что бой
    # идёт на арене именно этой сборки (как «РЕКОРД … · vNN» в обычном бою).
    _fight_label.text = "%s · сложность %d/5 · правил: %d · ставка: %d · %s" % [
            display_title(def), def.difficulty, def.rules_modifiers.size(), bet,
            version_short()]
    _surrender_btn.visible = true


func sfx_bell() -> void:
    if main != null and main.get("sfx") != null:
        main.sfx.play("bell", 1.0, -6.0)


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
    ui = CanvasLayer.new()
    ui.layer = 7
    add_child(ui)
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    ui.add_child(_root)
    _backdrop = ColorRect.new()
    _backdrop.color = Color(0.02, 0.03, 0.05, 0.97)
    _backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
    _backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(_backdrop)
    _title = _mk_label(Vector2(0, 20), Vector2(1280, 48), 36, Color(0.98, 0.86, 0.45))
    _sub = _mk_label(Vector2(0, 68), Vector2(1280, 24), 17, Color(0.80, 0.84, 0.92))
    _hint = _mk_label(Vector2(0, 690), Vector2(1280, 24), 15, Color(0.62, 0.68, 0.78))
    _ver_lbl = _mk_label(Vector2(236, 656), Vector2(740, 22), 11,
            Color(0.52, 0.58, 0.66))
    _ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    for i in 10:
        var col := i % 2
        var row := i / 2
        var b := _mk_button(Vector2(20 + col * 630, 110 + row * 112),
                Vector2(610, 102))
        b.add_theme_font_size_override("font_size", 13)
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
        b.pressed.connect(_on_card_pressed.bind(i))
        _cards.append(b)
    # T8: кнопка «назад» — там же, где в HUD и остальных экранах: слева сверху.
    # v71: размер/позиция берутся из HUD, чтобы на ПК и в тач-режиме «назад»
    # была одинаковой на всех экранах (--overlaptest: назад_вариантов=1).
    var back_size := Vector2(148, 42)
    var back_pos := Vector2(18, 12)
    if main != null and main.get("hud") != null and main.hud.has_method("back_button_size"):
        back_size = main.hud.back_button_size()
        if main.hud.has_method("back_button_pos"):
            back_pos = main.hud.back_button_pos()
    _back_btn = _mk_button(back_pos, back_size)
    _back_btn.text = Lang.t("back_btn")
    _back_btn.add_theme_font_size_override("font_size", 16)
    _back_btn.pressed.connect(_back_to_menu)
    _fight_bar = ColorRect.new()
    _fight_bar.color = Color(0.03, 0.04, 0.06, 0.75)
    _fight_bar.position = Vector2(0, 652)
    _fight_bar.size = Vector2(1280, 60)
    _fight_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _fight_bar.visible = false
    _root.add_child(_fight_bar)
    _fight_label = _mk_label(Vector2(16, 664), Vector2(980, 34), 16, Color(0.95, 0.88, 0.70))
    _fight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _surrender_btn = _mk_button(Vector2(1080, 664), Vector2(184, 34))
    _surrender_btn.text = Lang.t("arena_surrender")
    _surrender_btn.add_theme_font_size_override("font_size", 15)
    _surrender_btn.pressed.connect(request_surrender)
    _surrender_btn.visible = false
    _result_panel = ColorRect.new()
    _result_panel.color = Color(0.05, 0.06, 0.09, 0.97)
    _result_panel.position = Vector2(290, 130)
    _result_panel.size = Vector2(700, 470)
    _root.add_child(_result_panel)
    _result_title = _mk_label(Vector2(310, 150), Vector2(660, 56), 34, Color(0.98, 0.86, 0.45))
    _result_body = _mk_label(Vector2(320, 220), Vector2(640, 200), 18, Color(0.90, 0.92, 0.98))
    _result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _result_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _result_rematch = _mk_button(Vector2(360, 480), Vector2(250, 54))
    _result_rematch.text = Lang.t("arena_rematch")
    _result_rematch.add_theme_font_size_override("font_size", 18)
    _result_rematch.pressed.connect(_on_rematch)
    _result_hub = _mk_button(Vector2(670, 480), Vector2(250, 54))
    _result_hub.text = Lang.t("arena_back_hub")
    _result_hub.add_theme_font_size_override("font_size", 18)
    _result_hub.pressed.connect(back_to_hub)
    _result_panel.visible = false


func _show_screen(which: String) -> void:
    var hub := which == "hub"
    var res := which == "result"
    var fight := which == "fight"
    _backdrop.visible = hub or res
    _title.visible = hub
    _sub.visible = hub
    _hint.visible = hub
    if _ver_lbl != null:
        _ver_lbl.visible = hub
    _back_btn.visible = hub
    _result_panel.visible = res
    _result_title.visible = res
    _result_body.visible = res
    _result_rematch.visible = res
    _result_hub.visible = res
    _fight_bar.visible = fight
    _fight_label.visible = fight
    _surrender_btn.visible = fight
    for c in _cards:
        c.visible = hub
    if hub:
        _title.text = Lang.t("arena_title")
        _sub.text = Lang.t("arena_sub")
        _hint.text = Lang.t("arena_hub_hint")
        if _ver_lbl != null:
            _ver_lbl.visible = true
            _ver_lbl.text = "%s · %s" % [version_short(),
                    String(main.get("gfx_info")) if main != null else ""]
        for i in _cards.size():
            var a := arenas[i]
            var unlocked := is_arena_unlocked(a)
            var rec := ""
            if int(_load_float("wins/" + a.id, 0.0)) > 0:
                rec = "%s %.1f с · %s %d" % [Lang.t("arena_best_time"),
                        best_time(a.id), Lang.t("arena_best_series"), best_series(a.id)]
            var head := "%s · %s %d/5 · %s" % [display_title(a), Lang.t("arena_difficulty"),
                    a.difficulty, Lang.t("arena_open") if unlocked
                    else Lang.t("arena_locked")]
            if not unlocked:
                head += ": " + _unlock_text(a)
            var rules := _rules_text(a)
            var tail := "%s %d · %s %d · %s%s" % [Lang.t("coins"), a.money_reward,
                    Lang.t("arena_rep"), a.reputation_reward,
                    rules, (" · " + rec) if rec != "" else ""]
            var btn := _cards[i]
            btn.text = "%s\n%s\n%s" % [head, a.description, tail]
            btn.position = Vector2(20 + (i % 2) * 630, 110 + (i / 2) * 112)
            btn.disabled = not unlocked
            btn.add_theme_color_override("font_color",
                    Color(0.90, 0.92, 0.98) if i != sel else Color(0.98, 0.86, 0.45))
    if which == "result":
        _fill_result()


func _fill_result() -> void:
    var won := bool(last_result.get("won", false))
    _result_title.text = Lang.t("arena_win") if won else Lang.t("arena_lose")
    var g: Dictionary = last_result.get("gains", {})
    var rec: Dictionary = last_result.get("record", {})
    var stats_txt := ""
    var stats: Dictionary = g.get("stats", {})
    for k in stats:
        stats_txt += " · %s +%.2f" % [String(k), float(stats[k])]
    var lines: Array[String] = []
    lines.append(display_title(current) if current != null
            else String(last_result.get("title", "")))
    lines.append("%s %.1f с" % [Lang.t("arena_time"),
            float(last_result.get("elapsed", 0.0))])
    lines.append("%s %d · %s %d%s" % [Lang.t("arena_reward_coins"),
            int(g.get("coins", 0)), Lang.t("arena_rep"), int(g.get("rep", 0)), stats_txt])
    lines.append("%s %d · %s %.1f с · %s %d" % [Lang.t("arena_win"),
            int(rec.get("wins", 0)), Lang.t("arena_best_time"),
            float(rec.get("best_time", 0.0)), Lang.t("arena_best_series"),
            int(rec.get("best_series", 0))])
    var bet_shown := int(last_result.get("bet", 0))
    if bet_shown > 0:
        lines.append("%s %d" % [Lang.t("arena_bet"), bet_shown])
    _result_body.text = "\n".join(lines)


func _rules_text(a: ArenaDef) -> String:
    var parts: Array[String] = []
    for k in a.rules_modifiers:
        parts.append(_rule_name(String(k)))
    for k in a.environment_modifiers:
        if k in ["hazards", "wind", "surface_friction", "gravity", "rocking",
                "stamina_drain", "edge_hazard", "fall_defeat", "confined"]:
            parts.append(_rule_name(String(k)))
    return ", ".join(parts) if not parts.is_empty() else Lang.t("arena_no_rules")


const RULE_NAMES := {
    "surface_friction": ["трение", "friction"],
    "gravity": ["гравитация", "gravity"],
    "stamina_drain": ["расход сил", "stamina drain"],
    "wind": ["ветер", "wind"],
    "hazards": ["опасные зоны", "hazard zones"],
    "rocking": ["качка", "rocking"],
    "edge_hazard": ["опасный край", "edge hazard"],
    "fall_defeat": ["падение с края", "fall = defeat"],
    "confined": ["тесная площадка", "confined"],
    "no_knockdown": ["без нокдауна", "no knockdown"],
    "no_healing": ["без лечения", "no healing"],
    "rounds_to_win": ["раунды до победы", "rounds to win"],
    "time_limit": ["лимит времени", "time limit"],
    "betting": ["ставки", "betting"],
    "referee": ["рефери", "referee"],
    "boss_fight": ["босс", "boss fight"],
}


func _rule_name(key: String) -> String:
    var pair: Array = RULE_NAMES.get(key, [])
    if pair.is_empty():
        return key
    return String(pair[1] if Lang.code == "en" else pair[0])


func _unlock_text(a: ArenaDef) -> String:
    var c: Dictionary = a.unlock_condition
    if c.has("wins"):
        return "%s %d" % [Lang.t("arena_need_wins"), int(c["wins"])]
    if c.has("arena"):
        var prev := arena_by_id(String(c["arena"]))
        return "%s: %s" % [Lang.t("arena_need_arena"),
                display_title(prev) if prev != null else String(c["arena"])]
    if c.has("visited_training"):
        return Lang.t("arena_need_training")
    return ""


func _on_card_pressed(i: int) -> void:
    sel = i
    # v54: ФИКС. Раньше после нажатия карточки вызывался ещё и _show_screen("hub")
    # — и хаб снова показывался ПОВЕРХ уже начавшегося боя. Игрок нажимал арену,
    # боя не видел и попадал в обычный бой («заходишь в боевые локации — видишь
    # ринг»). Теперь экран хаба возвращаем только если арена НЕ стартовала
    # (например, закрыта по прогрессу).
    if not tap_card(i):
        _show_screen("hub")


func _on_rematch() -> void:
    rematch()


func _back_to_menu() -> void:
    if main != null and main.has_method("_on_arena_nav"):
        main._on_arena_nav("menu")


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
    b.add_theme_font_size_override("font_size", 16)
    _root.add_child(b)
    return b
