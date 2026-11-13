class_name CoopFight
extends Node3D
## Кооп 4P, часть 2: серверный бой 4 игроков против AI-волн.
##
## Сервер (хост) авторитетен: HP/урон/нокдаун/таймеры/волны/воскрешение считает
## только он и рассылает снапшоты. Клиент шлёт интенты (движение/удары/блок/
## уклон/вставание/interact), предсказывает своё движение и интерполирует
## союзников и врагов по снапшотам.
##
## Модуль намеренно НЕ переиспользует 1v1-логику main.gd напрямую (там всё
## завязано на два глобальных бойца player/enemy): здесь свой компактный
## серверный тик и «мозг» волн на публичных методах fighter.gd
## (reset/start_punch/tick/take_hit/start_knockdown/begin_get_up/get_up_press/
## enter_ragdoll/glove_point). Косметика (искры/вспышки) — сервер локально +
## одноразовый RPC coop_spark.
##
## RPC-события (через существующий NetworkManager._rpc_event, авторитет = хост):
##   coop_down(slot)        нокдаун игрока
##   coop_elim(slot)        игрок выбыл до конца волны
##   coop_repair(slot,hp)   подъём/воскрешение
##   coop_wave(wave,total)  старт волны
##   coop_wave_clear(wave)  волна зачищена
##   coop_result(data)      таблица результата + награды
##   coop_spark(pos,kind)   косметическая искра (FF/попадание)
##   coop_join_match(data)  новому игроку: матч уже идёт (drop-in)

const Lang = preload("res://scripts/lang.gd")
const FighterScript = preload("res://scripts/fighter.gd")
const LookScript = preload("res://scripts/look.gd")
const EnemyDefScript = preload("res://scripts/configs/enemy_def.gd")
const WaveDefScript = preload("res://scripts/configs/wave_def.gd")
const InputProfileScript = preload("res://scripts/input_profile.gd")

signal nav(to: String)

enum WaveMode { WAVES, SINGLE_FIGHT, BOSS_RUSH }
enum AggroMode { NEAREST, MOST_DAMAGE, RANDOM, TANK_PRIORITY }
enum MatchState { IDLE, COUNTDOWN, WAVE, INTERMISSION, RESULT }

const PLAYER_BASE_HP := 100.0
## v71l: тот же масштаб базового урона, что в оффлайне (main.gd BASE_DMG_SCALE).
## Без него урон врагов в коопе был в 1/0.6 ≈ 1.67 раза выше обычного боя —
## отсюда «в кооперативе падают после одного удара».
const BASE_DMG_SCALE := 0.60
const PUNCH_KINDS := ["jab", "cross", "lhook", "rhook", "upper", "upper_l"]
const ROLE_TANK := "TANK"
const ROLE_DPS := "DPS"
const ROLE_SUPPORT := "SUPPORT"
const ROLE_SCOUT := "SCOUT"

# ---------------------------------------------------------------- настройки

## Урон по союзнику. false — friendly fire выключен: искра, 0 урона.
@export var friendly_fire := false
## Радиус воскрешения (метры, по горизонтали).
@export var revive_radius := 2.0
## Время удержания E для воскрешения.
@export var revive_time := 1.5
## Лимит подъёмов (воскрешений) за волну; -1 — без лимита.
@export var max_revives_per_wave := 3
## Штрафовать очки за поражение в коопе (нет).
@export var apply_ranked_penalty_in_coop := false
## Прогрессия общая, считает хост; клиенты применяют свою награду.
@export var shared_progression := true
## Выбывшие возвращаются после волны.
@export var respawn_between_waves := true
## Drop-in/drop-out посреди матча.
@export var allow_drop_in := true
@export var allow_drop_out := true

@export var waves_mode := WaveMode.WAVES
@export var waves_count := 5
@export var start_delay := 2.5
@export var intermission_time := 4.0
## Масштабирование от числа игроков: ключ — player_count (2/3/4).
@export var enemy_count_multiplier := {2: 1.0, 3: 1.5, 4: 2.0}
@export var enemy_hp_multiplier := {2: 1.0, 3: 1.25, 4: 1.5}
@export var spawn_interval_multiplier := {2: 1.0, 3: 0.9, 4: 0.8}
@export var boss_hp_multiplier := {2: 1.0, 3: 1.5, 4: 2.0}
## Не ближе этого расстояния к игрокам при спавне. На кооп-арене 20×20
## (spawn_radius=9.0) реально соблюдается при игроках ближе к центру.
@export var min_spawn_distance := 8.0
@export var spawn_point_count := 8
## Радиус спавн-точек кооп-арены (20×20 → 9.0 у края, но внутри канатов).
@export var spawn_radius := 9.0
## Полуразмер кооп-ринга: 10.0 → пол 20×20. Бойцов держим чуть внутри пола.
@export var ring_limit := 10.0
## Множители ролей (действуют только при enable_roles в лобби).
@export var role_hp_bonus := 1.3
@export var role_dmg_bonus := 1.25
@export var role_revive_bonus := 0.6
@export var role_move_bonus := 1.2
## Нокдаун: сколько лежит игрок до выбывания.
@export var knockout_time := 10.0
## Пауза между волнами, i-frames при drop-in.
@export var drop_in_iframes := 2.0
@export var downed_restore_ratio := 0.5
## v71p: неуязвимость после подъёма с нокдауна (сек) — как в одиночном бою.
@export var getup_invuln := 2.0
## Волны по умолчанию (пусто — соберутся кодом).
@export var waves: Array = []
## AI: как выбирать цель и как часто переоценивать.
@export var aggro_mode := AggroMode.NEAREST
@export var retarget_interval := 1.25
@export var enemy_attack_cooldown := 0.9
## Камера каждого игрока (v37): как в обычном бою — из-за спины своего бойца,
## ближний план. Дистанция и высота в метрах, вес точки взгляда на враге 0…1.
@export var cam_distance := 4.6
@export var cam_height := 2.55
@export var cam_fov := 60.0
@export var cam_foe_weight := 0.32
@export var cam_follow_speed := 6.0
## Нокдаун в коопе: минимальная пауза между нажатиями «ВСТАТЬ» (сек) и сколько
## нажатий нужно, чтобы встать. В офлайне 0.80/8 — на телефоне это слишком долго.
@export var mash_press_grace := 0.45
@export var player_get_up_presses := 5

# ---------------------------------------------------------------- состояние

var main: Node
var active := false
var match_active := false
var is_host := false
var my_slot := 0
var players := {}               # slot -> state dict
var player_count := 0
var match_time := 0.0
var state := MatchState.IDLE
var wave_idx := 0
var total_waves := 0
var countdown := 0.0
var intermission := 0.0
var enemies: Array = []
var next_enemy_id := 1
var spawn_queue: Array = []
var spawn_points: Array = []
var spawn_timer := 0.0
var revives_used := 0
var scaling: Dictionary = {}
var result: Dictionary = {}
var result_shown := false
var enable_roles := false
var _snap_t := 0.0
var _snapshots_sent := 0
var _snapshots_received := 0
var _spark_count := 0
var _profile := InputProfileScript.new()
## v71l: панель «ВСТАТЬ» (HUD одиночного боя) сейчас показана в коопе.
var _hud_downed := false
# --- мобильное управление и своя камера каждому игроку (v37) ---
var _touch_punch := ""          # удар с тач-кнопки, ждёт ближайшего чтения интента
var _touch_dodge := false
var _touch_getup := false
## Тестовый тач-ввод без настоящего TouchLayer: {"move": Vector2, "block": bool}.
var _test_touch := {}
var _cam_ready := false         # камера выставлена мгновенно на первом кадре
var _cam_pos := Vector3.ZERO
var _cam_look := Vector3.ZERO
var _enemy_defs := {}
var _result_sent := false
var _last_result_hp := 0
## Кооп-арена 20×20: корень геометрии и статистика спавна.
var _arena_root: Node3D
var last_spawn_min_distance := 0.0
var spawn_warnings := 0

# отладка/автотесты
var debug_paused := false
var debug_no_ai := false
var debug_no_player_damage := false
var debug_intents := {}
var debug_ff_damage := -1.0
var debug_ff_sparked := false

# ---------------------------------------------------------------- HUD
var hud_layer: CanvasLayer
var _root: Control
var _wave_lbl: Label
var _timer_lbl: Label
var _enemy_lbl: Label
var _own_name: Label
var _own_hp_bg: ColorRect
var _own_hp_fill: ColorRect
var _own_st_bg: ColorRect
var _own_st_fill: ColorRect
var _ally_rows: Array = []      # [{name, hp_bg, hp_fill, st_label}]
var _revive_lbl: Label
var _revive_bg: ColorRect
var _revive_fill: ColorRect
var _hint_lbl: Label
var _result_panel: Control
var _result_title: Label
var _result_body: Label
var _btn_rematch: Button
var _btn_lobby: Button
var _btn_menu: Button


func setup(main_ref: Node) -> void:
    main = main_ref
    _build_hud()
    _hud_visible(false)
    NetworkManager.intent_received.connect(_on_intent)
    NetworkManager.snapshot_received.connect(_on_snapshot)
    # v71: враги приходят отдельным unreliable_ordered-пакетом (без очереди reliable)
    NetworkManager.snapshot_extra.connect(_on_snapshot_extra)
    NetworkManager.net_event.connect(_on_net_event)
    NetworkManager.player_connected.connect(_on_peer_connected)
    NetworkManager.player_disconnected.connect(_on_peer_disconnected)
    NetworkManager.lobby_updated.connect(_on_lobby_updated)
    NetworkManager.match_ended.connect(_on_match_ended)
    NetworkManager.server_disconnected.connect(_on_server_lost)


# ---------------------------------------------------------------- старт/конец

## Начать кооп-матч. data — из NetworkManager.match_started (players/mode).
func begin(data: Dictionary) -> void:
    if active:
        close()
    active = true
    match_active = true
    is_host = NetworkManager.is_host
    result = {}
    result_shown = false
    _result_sent = false
    result_panel_hide()
    match_time = 0.0
    wave_idx = 0
    revives_used = 0
    enemies.clear()
    next_enemy_id = 1
    spawn_queue.clear()
    spawn_timer = 0.0
    debug_intents.clear()
    debug_ff_damage = -1.0
    debug_ff_sparked = false
    debug_paused = false
    debug_no_ai = false
    _snap_t = 0.0
    _snapshots_sent = 0
    _snapshots_received = 0
    _spark_count = 0
    _touch_punch = ""
    _touch_dodge = false
    _touch_getup = false
    _test_touch = {}
    _cam_ready = false
    _hud_downed = false
    if main != null and main.hud != null:
        main.hud.set_downed(false)

    var plist: Dictionary = data.get("players", NetworkManager.players)
    enable_roles = bool(data.get("enable_roles", false))
    _collect_players(plist)
    my_slot = 1 if is_host else NetworkManager.slot_of(NetworkManager.my_id)
    if not players.has(my_slot) and not players.is_empty():
        my_slot = int(players.keys()[0])

    # главный HUD/бойцы офлайна убираем: в коопе свой экран и свои тела
    if main != null:
        main.net_mode = false
        main.training = false
        main.demo = false
        main.no_ai = true
        main.no_cash = false
        if main.player != null:
            main.player.visible = false
        if main.enemy != null:
            main.enemy.visible = false
        if main.hud != null:
            main.hud.set_battle_visible(false)
            main.hud.hide_overlay()

    _make_spawn_points()
    _build_coop_arena()
    scaling = _compute_scaling(player_count)
    _enemy_defs = _make_enemy_defs()
    _build_waves()
    for slot in players:
        _create_player(int(slot))
    _apply_roles()
    state = MatchState.COUNTDOWN
    countdown = start_delay
    _wire_player_signals()
    _hud_visible(true)
    _update_hud()
    print("COOP бой старт: игроков=", player_count, " роль=", "host" if is_host else "client",
            " слот=", my_slot, " масштаб=", scaling)
    _sync_lobby_ui(false)
    _wire_touch()


func close() -> void:
    active = false
    match_active = false
    state = MatchState.IDLE
    debug_paused = false
    debug_intents.clear()
    for slot in players:
        var f: Node3D = players[slot].get("f")
        if f != null:
            f.queue_free()
    players.clear()
    for e in enemies:
        var ef: Node3D = e.get("f")
        if ef != null:
            ef.queue_free()
    enemies.clear()
    spawn_queue.clear()
    _free_coop_arena()
    # v50: вернуть основной ринг — иначе обычный бой после коопа шёл без ринга
    if main != null and main.get("arena") != null:
        (main.arena as Node3D).visible = true
    _hud_visible(false)
    result_panel_hide()
    _unwire_touch()
    _cam_ready = false
    if main != null:
        main.no_ai = false
        if main.player != null:
            main.player.visible = true
        if main.enemy != null:
            main.enemy.visible = true
        if main.arena != null:
            main.arena.visible = true


## Игрок вышел из матча/результата в лобби/меню — говорит main.
func request_nav(to: String) -> void:
    nav.emit(to)


func _sync_lobby_ui(visible_lobby: bool) -> void:
    if main == null or main.coop_lobby == null:
        return
    if visible_lobby:
        main.coop_lobby.show_lobby()
    else:
        main.coop_lobby.ui.visible = false


# ---------------------------------------------------------------- данные игроков

func _collect_players(plist: Dictionary) -> void:
    players.clear()
    for id in plist:
        var info: Dictionary = plist[id]
        var slot := int(info.get("slot", 0))
        if slot < 1 or slot > 4:
            continue
        players[slot] = {
            "slot": slot, "id": int(id),
            "name": String(info.get("name", "ИГРОК")),
            "role": String(info.get("role", ROLE_DPS)),
            "f": null, "alive": true, "downed": false, "eliminated": false,
            "down_t": 0.0, "revive_t": 0.0, "revive_target": -1,
            "mash_grace": 0.0, "iframes": 0.0, "intent": {},
            "prev_dodge": false, "pending_mash": false,
            "stats": {"damage": 0.0, "hits": 0, "revives": 0, "downs": 0,
                    "eliminated": 0},
        }
    player_count = maxi(1, players.size())


func _player_look(slot: int) -> Dictionary:
    var look: Dictionary = LookScript.default_look()
    if main != null and main.look is Dictionary and not (main.look as Dictionary).is_empty():
        look = (main.look as Dictionary).duplicate(true)
    var shorts_ids := ["blue", "red", "white", "black"]
    var glove_ids := ["blue", "red", "green", "gold"]
    var skin_ids := ["light", "tan", "olive", "dark"]
    var i := clampi(slot - 1, 0, 3)
    look["shorts_color"] = shorts_ids[i]
    look["gloves_color"] = glove_ids[i]
    look["skin"] = skin_ids[i]
    look["build"] = "normal" if slot != 1 else String(look.get("build", "normal"))
    # v71k: у остальных слотов (2-4) кроме цвета отличаются причёска и фасон
    # ботинок из каталога — иначе в коопе все четверо выглядели близнецами.
    if i > 0:
        var v: Dictionary = LookScript.varied_look(i * 7 + 2, {})
        look["hair"] = v["hair"]
        look["hair_color"] = v["hair_color"]
        look["boots"] = v["boots"]
        look["boots_color"] = v["boots_color"]
    return look


func _create_player(slot: int) -> void:
    var f := FighterScript.new()
    f.name = "CoopPlayer%d" % slot
    add_child(f)
    f.setup(true, _player_look(slot))
    if main != null and main.upg is Dictionary:
        f.set_upgrades(main.upg)
    if StatsManager != null:
        f.apply_stat_multipliers(StatsManager.damage_mult(), StatsManager.move_mult())
    var hp := PLAYER_BASE_HP * f.hp_mult
    if StatsManager != null:
        hp *= StatsManager.max_hp_mult()
    # на телефоне жмётся хуже, чем по клавише: 5 нажатий вместо 8
    f.get_up_presses = maxi(1, player_get_up_presses)
    f.reset(_player_spawn(slot), hp)
    # v71l: арена 20×20 — ragdoll может осесть далеко от центра. С оффлайн-границами
    # ±3.4 тело у края навсегда оставалось в FALLING (нельзя встать, таймер стоит).
    f.settle_radius = maxf(ring_limit + 2.0, 3.4)
    f.settle_max_y = 1.0
    f.settle_max_speed = 2.2
    players[slot]["f"] = f
    f.impact.connect(_on_fighter_impact.bind(f))
    if is_host:
        f.get_up_finished.connect(_on_player_get_up_finished.bind(slot))
        f.knocked_down.connect(_on_player_knocked_down.bind(slot))


func _apply_roles() -> void:
    if not enable_roles:
        return
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f == null:
            continue
        match String(pf["role"]):
            ROLE_TANK:
                f.max_hp *= role_hp_bonus
                f.hp = f.max_hp
            ROLE_DPS:
                f.dmg_mult *= role_dmg_bonus
            ROLE_SCOUT:
                f.move_mult *= role_move_bonus
            _:
                pass


func _player_spawn(slot: int) -> Vector3:
    var angle := -PI * 0.5 + float(slot - 1) * PI * 0.5
    # игроки стартуют ближе к центру 20×20: тогда дальние спавн-точки (радиус 9)
    # реально дают min_spawn_distance=8 м до ближайшего игрока
    return Vector3(cos(angle) * 1.2, 0.0, sin(angle) * 1.2)


func _make_spawn_points() -> void:
    spawn_points.clear()
    var n := maxi(4, spawn_point_count)
    for i in n:
        var a := TAU * float(i) / float(n) + PI * 0.25
        spawn_points.append(Vector3(cos(a) * spawn_radius, 0.0,
                sin(a) * spawn_radius))


# ---------------------------------------------------------------- кооп-арена 20×20

## Собственная арена кооп-боя: пол 20×20, канаты, 4 угловых столба, свет.
## Всё примитивами (BoxMesh/OmniLight3D), без внешних ассетов; офлайн-ринг
## на время матча прячется, чтобы не просвечивал сквозь пол.
func _build_coop_arena() -> void:
    _free_coop_arena()
    if main != null and main.arena != null:
        main.arena.visible = false
    _arena_root = Node3D.new()
    _arena_root.name = "CoopArena20"
    add_child(_arena_root)
    var half := ring_limit
    var size := half * 2.0

    # пол
    var floor := MeshInstance3D.new()
    var fm := BoxMesh.new()
    fm.size = Vector3(size, 0.3, size)
    floor.mesh = fm
    floor.position = Vector3(0.0, -0.15, 0.0)
    floor.material_override = _arena_mat(Color(0.22, 0.21, 0.20), 0.95)
    _arena_root.add_child(floor)
    # v71l: ФИЗИЧЕСКИЙ пол. Раньше здесь был только MeshInstance3D, и ragdoll
    # (RigidBody3D, collision_mask=1) при нокдауне падал сквозь настил в
    # бесконечность — отсюда «проваливаются в текстуры» и застрявший FALLING.
    # Коллизия чуть шире визуального пола (24×24), чтобы тело, вылетевшее за
    # канаты, всё равно приземлялось, а не падало мимо.
    var floor_body := StaticBody3D.new()
    floor_body.name = "CoopFloor"
    var fshape := CollisionShape3D.new()
    var fbox := BoxShape3D.new()
    fbox.size = Vector3(size + 4.0, 0.3, size + 4.0)
    fshape.shape = fbox
    floor_body.add_child(fshape)
    floor_body.position = Vector3(0.0, -0.15, 0.0)
    _arena_root.add_child(floor_body)
    # тёмная окантовка по краю пола
    var rim := MeshInstance3D.new()
    var rm := BoxMesh.new()
    rm.size = Vector3(size + 0.6, 0.14, size + 0.6)
    rim.mesh = rm
    rim.position = Vector3(0.0, -0.36, 0.0)
    rim.material_override = _arena_mat(Color(0.08, 0.09, 0.12), 0.8)
    _arena_root.add_child(rim)

    # настил-центр (светлее, чтобы читалась середина арены)
    var mat_center := MeshInstance3D.new()
    var cm := BoxMesh.new()
    cm.size = Vector3(size * 0.55, 0.02, size * 0.55)
    mat_center.mesh = cm
    mat_center.position = Vector3(0.0, 0.005, 0.0)
    mat_center.material_override = _arena_mat(Color(0.28, 0.26, 0.23), 0.9)
    _arena_root.add_child(mat_center)

    # канаты: 4 тонких бокса по периметру на высоте 1.05
    var rope_col := Color(0.78, 0.16, 0.18)
    for spec in [[Vector3(0, 0, half), Vector3(size, 0.05, 0.05)],
            [Vector3(0, 0, -half), Vector3(size, 0.05, 0.05)],
            [Vector3(half, 0, 0), Vector3(0.05, 0.05, size)],
            [Vector3(-half, 0, 0), Vector3(0.05, 0.05, size)]]:
        var rope := MeshInstance3D.new()
        var rmesh := BoxMesh.new()
        rmesh.size = spec[1]
        rope.mesh = rmesh
        rope.position = (spec[0] as Vector3) + Vector3(0.0, 1.05, 0.0)
        rope.material_override = _arena_mat(rope_col, 0.5)
        _arena_root.add_child(rope)
    # второй (нижний) канат — читается глубина
    for spec in [[Vector3(0, 0, half), Vector3(size, 0.04, 0.04)],
            [Vector3(0, 0, -half), Vector3(size, 0.04, 0.04)],
            [Vector3(half, 0, 0), Vector3(0.04, 0.04, size)],
            [Vector3(-half, 0, 0), Vector3(0.04, 0.04, size)]]:
        var rope := MeshInstance3D.new()
        var rmesh := BoxMesh.new()
        rmesh.size = spec[1]
        rope.mesh = rmesh
        rope.position = (spec[0] as Vector3) + Vector3(0.0, 0.62, 0.0)
        rope.material_override = _arena_mat(Color(0.55, 0.62, 0.72), 0.55)
        _arena_root.add_child(rope)

    # угловые столбы
    for sx in [-1.0, 1.0]:
        for sz in [-1.0, 1.0]:
            var post := MeshInstance3D.new()
            var pm := BoxMesh.new()
            pm.size = Vector3(0.16, 1.7, 0.16)
            post.mesh = pm
            post.position = Vector3(sx * half, 0.85, sz * half)
            post.material_override = _arena_mat(Color(0.12, 0.14, 0.18), 0.6)
            _arena_root.add_child(post)

    # свет: два тёплых прожектора по диагонали + холодная подсветка центра
    for spec in [[Vector3(-6.0, 6.0, -6.0), Color(1.0, 0.92, 0.80), 3.2, 24.0],
            [Vector3(6.0, 6.0, 6.0), Color(1.0, 0.92, 0.80), 3.2, 24.0],
            [Vector3(0.0, 8.0, 0.0), Color(0.80, 0.88, 1.0), 2.0, 26.0]]:
        var lamp := OmniLight3D.new()
        lamp.position = spec[0]
        lamp.light_color = spec[1]
        lamp.light_energy = float(spec[2])
        lamp.omni_range = float(spec[3])
        _arena_root.add_child(lamp)


func _arena_mat(col: Color, rough: float) -> StandardMaterial3D:
    var m := StandardMaterial3D.new()
    m.albedo_color = col
    m.roughness = rough
    return m


func _free_coop_arena() -> void:
    if _arena_root != null:
        _arena_root.queue_free()
        _arena_root = null


## Сводка кооп-арены для автотеста.
func debug_arena_info() -> Dictionary:
    var best := _best_spawn_distance()
    var fbody: Node = null
    if _arena_root != null:
        fbody = _arena_root.find_child("CoopFloor", true, false)
    var shape_ok := false
    if fbody != null:
        for c in fbody.get_children():
            if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
                shape_ok = true
    return {"built": _arena_root != null, "ring_limit": ring_limit,
            "floor_body": fbody != null, "floor_shape": shape_ok,
            "spawn_radius": spawn_radius, "spawn_points": spawn_points.size(),
            "floor_size": ring_limit * 2.0,
            "min_spawn_distance": min_spawn_distance,
            "best_spawn_min_distance": best,
            "spawn_warnings": spawn_warnings}


## Минимальная дистанция от лучшей спавн-точки до любого живого игрока.
func _best_spawn_distance() -> float:
    var best := -1.0
    for p in spawn_points:
        var d := 999.0
        for slot in players:
            var pf: Dictionary = players[slot]
            if bool(pf["eliminated"]):
                continue
            var f: Node3D = pf["f"]
            if f == null:
                continue
            d = minf(d, _flat_dist(p, f.position))
        best = maxf(best, d)
    return best


# ---------------------------------------------------------------- волны

func _mult(table: Dictionary, pc: int) -> float:
    if table.has(pc):
        return float(table[pc])
    # страховка: ближайший ключ
    var best := 1.0
    var best_d := 999
    for k in table:
        var d := absi(int(k) - pc)
        if d < best_d:
            best_d = d
            best = float(table[k])
    return best


func _compute_scaling(pc: int) -> Dictionary:
    var p := clampi(pc, 2, 4)
    return {
        "player_count": player_count,
        "count_mult": _mult(enemy_count_multiplier, p),
        "hp_mult": _mult(enemy_hp_multiplier, p),
        "interval_mult": _mult(spawn_interval_multiplier, p),
        "boss_mult": _mult(boss_hp_multiplier, p),
    }


func _enemy_def(id: String, archetype: String, hp: float, dmg: float, speed: float,
        aggr: float) -> EnemyDef:
    var d := EnemyDefScript.new()
    d.id = id
    d.title = id.to_upper()
    d.archetype = archetype
    d.max_hp = hp
    d.damage_mult = dmg
    d.speed_mult = speed
    d.aggression = aggr
    d.stamina = 100.0
    return d


func _make_enemy_defs() -> Dictionary:
    return {
        "grunt": _enemy_def("grunt", "aggressor", 70.0, 0.9, 1.0, 0.55),
        "puncher": _enemy_def("puncher", "puncher", 90.0, 1.15, 0.95, 0.5),
        "speedster": _enemy_def("speedster", "speedster", 55.0, 0.8, 1.25, 0.8),
        "tank": _enemy_def("tank", "tank", 150.0, 1.0, 0.8, 0.5),
        "boss": _enemy_def("boss", "puncher", 320.0, 1.35, 0.9, 0.65),
    }


func _enemy_def_for(kind: String, boss: bool) -> EnemyDef:
    if _enemy_defs.is_empty():
        _enemy_defs = _make_enemy_defs()
    if boss and kind == "boss":
        return _enemy_defs["boss"]
    return _enemy_defs.get(kind, _enemy_defs["grunt"])


func _wave_def(wave_title: String, entries: Array, boss: bool) -> WaveDef:
    var w := WaveDefScript.new()
    w.title = wave_title
    w.entries = entries
    w.boss = boss
    return w


func _entry(kind: String, count: int, interval: float) -> Dictionary:
    return {"def": _enemy_def_for(kind, kind == "boss"), "count": count,
            "interval": interval}


func _build_waves() -> void:
    var list: Array = []
    if waves.size() > 0:
        for w in waves:
            if w is WaveDef:
                list.append(w)
        if list.size() > 0:
            total_waves = list.size()
            waves = list
            return
    match waves_mode:
        WaveMode.SINGLE_FIGHT:
            list.append(_wave_def("ОДИН БОЙ", [
                _entry("grunt", 4, 1.0), _entry("puncher", 2, 1.2)], false))
        WaveMode.BOSS_RUSH:
            for i in 3:
                var boss := EnemyDefScript.new()
                boss.id = "boss"
                boss.title = "БОСС " + str(i + 1)
                boss.archetype = "puncher"
                boss.max_hp = 240.0 + 90.0 * float(i)
                boss.damage_mult = 1.25 + 0.1 * float(i)
                boss.speed_mult = 0.9
                boss.aggression = 0.6
                list.append(_wave_def("БОСС-РАШ " + str(i + 1),
                        [{"def": boss, "count": 1, "interval": 1.0}], true))
        _:
            list.append(_wave_def("ВОЛНА 1", [_entry("grunt", 3, 1.4)], false))
            list.append(_wave_def("ВОЛНА 2", [
                _entry("grunt", 2, 1.2), _entry("speedster", 2, 1.2)], false))
            list.append(_wave_def("ВОЛНА 3", [
                _entry("puncher", 2, 1.1), _entry("grunt", 2, 1.0),
                _entry("tank", 1, 1.3)], false))
            list.append(_wave_def("ВОЛНА 4", [
                _entry("speedster", 2, 0.9), _entry("puncher", 2, 0.9),
                _entry("tank", 2, 1.1)], false))
            list.append(_wave_def("ФИНАЛ", [
                _entry("boss", 1, 1.0), _entry("grunt", 2, 1.1)], true))
    if waves_mode == WaveMode.WAVES:
        total_waves = waves_count
        while list.size() < total_waves:
            list.append(_wave_def("ВОЛНА " + str(list.size() + 1), [
                _entry("grunt", 3 + list.size(), 1.1)], false))
    total_waves = list.size()
    waves = list


## Сколько врагов выйдет в волне wave_index (0-based) с учётом масштаба.
func wave_plan(wave_index: int) -> Dictionary:
    if wave_index < 0 or wave_index >= waves.size():
        return {}
    var w: WaveDef = waves[wave_index]
    var base := w.base_count()
    var scaled := maxi(1, int(round(float(base) * float(scaling.get("count_mult", 1.0)))))
    var hp_mult: float = float(scaling.get("hp_mult", 1.0))
    if w.boss:
        hp_mult *= float(scaling.get("boss_mult", 1.0))
    var entries: Array = []
    for e in w.entries:
        if not (e is Dictionary):
            continue
        var count := maxi(0, int(e.get("count", 0)))
        var def: EnemyDef = e.get("def")
        var def_id := String(def.id) if def != null else "grunt"
        var scaled_count := maxi(1, int(round(float(count)
                * float(scaling.get("count_mult", 1.0))))) if count > 0 else 0
        entries.append({"kind": def_id,
                "base": count, "scaled": scaled_count,
                "def_hp": float(def.max_hp if def != null else 70.0),
                "boss": w.boss and def != null and def_id == "boss",
                "interval": float(e.get("interval", 1.0))
                        * float(scaling.get("interval_mult", 1.0))})
    return {"wave": wave_index + 1, "base": base, "scaled": scaled,
            "hp_mult": hp_mult, "entries": entries,
            "count_mult": float(scaling.get("count_mult", 1.0)),
            "interval_mult": float(scaling.get("interval_mult", 1.0)),
            "boss_mult": float(scaling.get("boss_mult", 1.0))}


func _start_wave(index: int) -> void:
    if index < 0 or index >= waves.size():
        return
    wave_idx = index
    var w: WaveDef = waves[index]
    state = MatchState.WAVE
    spawn_queue.clear()
    spawn_timer = 0.0
    var plan := wave_plan(index)
    for e in w.entries:
        if not (e is Dictionary):
            continue
        var def: EnemyDef = e.get("def")
        var count := maxi(0, int(e.get("count", 0)))
        if def == null or count <= 0:
            continue
        var scaled := maxi(1, int(round(float(count)
                * float(scaling.get("count_mult", 1.0)))))
        var interval := maxf(0.15, float(e.get("interval", 1.0))
                * float(scaling.get("interval_mult", 1.0)))
        for i in scaled:
            spawn_queue.append({"def": def, "kind": def.id,
                    "boss": w.boss and def.id == "boss", "interval": interval,
                    "wave": index})
    NetworkManager.send_event("coop_wave", {"wave": index + 1, "total": total_waves,
            "count": spawn_queue.size()})
    print("COOP волна ", index + 1, "/", total_waves, ": врагов ", spawn_queue.size(),
            " base=", plan.get("base", 0), " count_mult=", scaling.get("count_mult"),
            " hp_mult=", plan.get("hp_mult"), " interval_mult=", scaling.get("interval_mult"))


func _spawn_tick(delta: float) -> void:
    if spawn_queue.is_empty():
        return
    spawn_timer -= delta
    while not spawn_queue.is_empty() and spawn_timer <= 0.0:
        var item: Dictionary = spawn_queue.pop_front()
        var pos := _pick_spawn_point()
        _spawn_enemy(item["def"], bool(item["boss"]), pos,
                float(wave_idx))
        spawn_timer = maxf(0.15, float(item.get("interval", 1.0)))


func _pick_spawn_point() -> Vector3:
    # выбрать точку максимально далеко от живых игроков
    var best: Vector3 = spawn_points[0] if not spawn_points.is_empty() else Vector3(9.0, 0, 0)
    var best_d := -1.0
    for p in spawn_points:
        var d := 999.0
        for slot in players:
            var pf: Dictionary = players[slot]
            if bool(pf["eliminated"]):
                continue
            var f: Node3D = pf["f"]
            if f == null:
                continue
            d = minf(d, _flat_dist(p, f.position))
        if d > best_d:
            best_d = d
            best = p
    last_spawn_min_distance = best_d
    if best_d < min_spawn_distance:
        spawn_warnings += 1
        push_warning("COOP спавн: ближайшая точка даёт %.2f м < %.2f м (игроки разошлись по арене)" % [
                best_d, min_spawn_distance])
    return best


func _spawn_enemy(def: EnemyDef, boss: bool, pos: Vector3, wave_index: int) -> void:
    var hp_mult: float = float(scaling.get("hp_mult", 1.0))
    var boss_mult: float = float(scaling.get("boss_mult", 1.0)) if boss else 1.0
    var hp := def.max_hp * hp_mult * boss_mult * (1.0 + 0.06 * float(wave_index))
    var f := _create_enemy_visual(next_enemy_id, def.id, boss, pos)
    f.max_hp = hp
    f.hp = hp
    f.dmg_mult = def.damage_mult
    f.dur_mult = 1.0 / maxf(0.6, def.speed_mult)
    f.move_mult = def.speed_mult
    # v71l: враги падают/оседают на 20×20 арене, а не только в оффлайн-ринге
    f.settle_radius = maxf(ring_limit + 2.0, 3.4)
    f.settle_max_y = 1.0
    enemies.append({
        "eid": next_enemy_id, "f": f, "def": def, "kind": def.id, "boss": boss,
        "dead": false, "remove_t": 0.0, "target_slot": 0, "retarget_t": 0.0,
        "attack_cd": randf_range(0.3, 1.0), "max_hp": hp,
    })
    next_enemy_id += 1


func _create_enemy_visual(eid: int, kind: String, boss: bool, pos: Vector3) -> Node3D:
    var f := FighterScript.new()
    f.name = "CoopEnemy%d" % eid
    add_child(f)
    f.setup(false, _enemy_look(kind, boss, eid))
    f.set_difficulty(0.45 if boss else 0.3)
    var def := _enemy_def_for(kind, boss)
    f.reset(pos, def.max_hp)
    f.impact.connect(_on_fighter_impact.bind(f))
    return f


func _enemy_look(kind: String, boss: bool, eid: int = 0) -> Dictionary:
    # v71k: враги тоже разные — причёска/кожа/фигура/ботинки из каталога по
    # номеру врага (раньше все были `hair=bald, skin=tan` и отличались только
    # цветом шорт/перчаток, то есть «одинаковые модельки»).
    var v: Dictionary = LookScript.varied_look(eid + 5, {})
    var look: Dictionary = LookScript.default_look()
    look["hair"] = v["hair"]
    look["hair_color"] = v["hair_color"]
    look["boots"] = v["boots"]
    look["boots_color"] = v["boots_color"]
    look["build"] = "heavy" if kind == "tank" or boss else String(v["build"])
    look["skin"] = "dark" if boss else String(v["skin"])
    look["shorts_color"] = "black"
    look["gloves_color"] = "red" if boss else "white"
    return look


# ---------------------------------------------------------------- цикл

func tick(delta: float) -> void:
    if not active:
        return
    if is_host:
        _tick_host(delta)
    else:
        _tick_client(delta)
    _update_hud()


func update_camera(delta: float) -> void:
    if main == null or main.cam == null:
        return
    var target := _local_fighter()
    if target == null:
        return
    # v37: своя камера каждому игроку — из-за спины своего бойца, ближний план
    # как в офлайн-бою, вместо прежнего общего обзорного ракурса всей арены.
    var pos := target.position
    var foe := _nearest_enemy(pos)
    # камера стоит с противоположной от угрозы стороны: враг всегда в кадре
    var away := Vector3.ZERO
    if foe != null:
        away = pos - foe.position
        away.y = 0.0
    if away.length() < 0.15:
        away = -target.global_transform.basis.z
        away.y = 0.0
    away = away.normalized()
    var desired := pos + away * cam_distance + Vector3(0.0, cam_height, 0.0)
    var focus := pos + Vector3(0.0, 1.15, 0.0)
    if foe != null:
        focus = focus.lerp(foe.position + Vector3(0.0, 1.05, 0.0), cam_foe_weight)
    if not _cam_ready:
        _cam_pos = desired
        _cam_look = focus
        _cam_ready = true
    var k := clampf(delta * cam_follow_speed, 0.0, 1.0)
    _cam_pos = _cam_pos.lerp(desired, k)
    _cam_look = _cam_look.lerp(focus, k)
    main.cam.fov = cam_fov
    main.cam.position = _cam_pos
    main.cam.look_at(_cam_look, Vector3.UP)


func _local_fighter() -> Node3D:
    var pf: Dictionary = players.get(my_slot, {})
    return pf.get("f")


# ---------------------------------------------------------------- сервер

func _tick_host(delta: float) -> void:
    if not match_active:
        return
    if debug_paused:
        return
    _server_step(delta)
    _snap_t += delta
    var interval := 1.0 / maxf(1.0, float(NetworkManager.snapshot_rate))
    if _snap_t >= interval:
        _snap_t = 0.0
        _send_snapshot()


func _server_step(dt: float) -> void:
    match_time += dt
    # v37: хост тоже игрок. Раньше его интент никто не заполнял, и боец хоста
    # стоял на месте, а управление уходило только клиентам.
    if players.has(my_slot):
        players[my_slot]["intent"] = _read_intent()
    if state == MatchState.COUNTDOWN:
        countdown = maxf(0.0, countdown - dt)
        if countdown <= 0.0:
            _start_wave(0)
        return
    if state == MatchState.INTERMISSION:
        intermission = maxf(0.0, intermission - dt)
        if intermission <= 0.0:
            _start_wave(wave_idx + 1)
        return
    if state == MatchState.RESULT:
        return
    _spawn_tick(dt)
    _apply_intents(dt)
    _revive_tick(dt)
    if not debug_no_ai:
        _ai_tick(dt)
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f != null:
            f.tick(dt)
            _clamp(f)
        _player_timers(pf, dt)
    for i in range(enemies.size() - 1, -1, -1):
        var e: Dictionary = enemies[i]
        if bool(e["dead"]):
            e["remove_t"] = float(e["remove_t"]) - dt
            if float(e["remove_t"]) <= 0.0:
                var f: Node3D = e["f"]
                if f != null:
                    f.queue_free()
                enemies.remove_at(i)
            continue
        var fe: Node3D = e["f"]
        if fe != null:
            fe.tick(dt)
            _clamp(fe)
    _separate(dt)
    if state == MatchState.WAVE:
        _check_wave_end()


func _clamp(f: Node3D) -> void:
    if f == null:
        return
    # 0.4 м запаса: тело не свисает с края 20×20 пола
    var lim := maxf(0.5, ring_limit - 0.4)
    f.position.x = clampf(f.position.x, -lim, lim)
    f.position.z = clampf(f.position.z, -lim, lim)
    f.position.y = 0.0


func _separate(_dt: float) -> void:
    var alive: Array = []
    for slot in players:
        var pf: Dictionary = players[slot]
        if not bool(pf["eliminated"]) and not bool(pf["downed"]):
            alive.append(pf["f"])
    for e in enemies:
        if not bool(e["dead"]):
            alive.append(e["f"])
    for i in alive.size():
        for j in range(i + 1, alive.size()):
            var a: Node3D = alive[i]
            var b: Node3D = alive[j]
            if a == null or b == null:
                continue
            var d: Vector3 = b.position - a.position
            d.y = 0.0
            var len := d.length()
            if len < 0.72 and len > 0.001:
                var push := d.normalized() * (0.72 - len) * 0.5
                a.position -= push
                b.position += push


# ---------------------------------------------------------------- интенты

func _on_intent(id: int, data: Dictionary) -> void:
    if not is_host or not active:
        return
    var slot := NetworkManager.slot_of(id)
    if players.has(slot):
        players[slot]["intent"] = data


func _intent_of(pf: Dictionary) -> Dictionary:
    var slot := int(pf["slot"])
    if debug_intents.has(slot):
        var di: Dictionary = debug_intents[slot]
        if bool(di.get("_once", false)):
            debug_intents.erase(slot)
        return di
    return pf.get("intent", {})


func _apply_intents(dt: float) -> void:
    for slot in players:
        var pf: Dictionary = players[slot]
        if bool(pf["eliminated"]):
            continue
        var intent := _intent_of(pf)
        _apply_player_intent(pf, intent, dt)


func _apply_player_intent(pf: Dictionary, intent: Dictionary, dt: float) -> void:
    var f: Node3D = pf["f"]
    if f == null:
        return
    if bool(pf["downed"]):
        var ks := int(f.knock_state)
        if ks == FighterScript.KnockState.NONE:
            # страховка от зависшего флага (старый баг/рассинхрон): боец уже встал —
            # возвращаем управление, а не держим его «лежачим» до выбывания
            if f.fallen:
                return
            pf["downed"] = false
        else:
            if ks == FighterScript.KnockState.FALLING:
                # v71l: пока тело летит/оседает, «ВСТАТЬ» ещё не работает, но
                # нажатие не теряем — иначе игрок жмёт Space и ничего не видит.
                if bool(intent.get("get_up", false)):
                    pf["pending_mash"] = true
                return
            if ks == FighterScript.KnockState.DOWNED:
                var pressed: bool = bool(intent.get("get_up", false)) \
                        or bool(pf.get("pending_mash", false))
                if pressed and float(pf["mash_grace"]) <= 0.0:
                    pf["pending_mash"] = false
                    pf["mash_grace"] = mash_press_grace
                    var prog: float = f.get_up_press()
                    if prog >= 0.999:
                        if f.begin_get_up():
                            pf["downed"] = false
                            NetworkManager.send_event("coop_repair", {"slot": int(pf["slot"]),
                                    "hp": 0.0, "kind": "self"})
                elif float(pf["mash_grace"]) > 0.0:
                    pf["mash_grace"] = maxf(0.0, float(pf["mash_grace"]) - dt)
                else:
                    f.get_up_cool(dt)
            return
    var mv: Array = intent.get("mv", [0.0, 0.0])
    var dir := Vector3(float(mv[0]) if mv.size() > 0 else 0.0, 0.0,
            float(mv[1]) if mv.size() > 1 else 0.0)
    f.blocking = bool(intent.get("block", false)) and f.stun <= 0.001
    if dir.length() > 0.01 and f.stun <= 0.001:
        f.drive(dir.normalized(), dt)
        if bool(intent.get("face_move", true)):
            f.look_at_target(f.position + dir.normalized())
    var dodge := bool(intent.get("dodge", false))
    if dodge and not bool(pf["prev_dodge"]):
        f.try_dodge()
    pf["prev_dodge"] = dodge
    var kind := String(intent.get("punch", ""))
    if kind != "":
        intent["punch"] = ""
        var target := _nearest_enemy(f.position)
        var aim: Vector3 = Vector3.ZERO if target == null else target.head.global_position
        if target != null:
            f.look_at_target(target.position)
            # корпусной удар (кнопка «КОРПУС» на телефоне) целится в корпус
            if kind.begins_with("body_"):
                aim = target.position + Vector3(0.0, 0.95, 0.0)
        f.start_punch(kind, aim)


# ---------------------------------------------------------------- бой: удары

func _on_fighter_impact(kind: String, att: Node3D) -> void:
    if not is_host or not match_active or state == MatchState.RESULT:
        return
    var is_enemy_att := _is_enemy_fighter(att)
    if is_enemy_att:
        _resolve_enemy_hit(att, kind)
    else:
        _resolve_player_hit(att, kind)


func _is_enemy_fighter(f: Node3D) -> bool:
    return String(f.name).begins_with("CoopEnemy")


func _resolve_enemy_hit(att: Node3D, kind: String) -> void:
    var e := _enemy_by_fighter(att)
    if e.is_empty() or bool(e["dead"]):
        return
    var slot := int(e["target_slot"])
    if not players.has(slot):
        return
    var pf: Dictionary = players[slot]
    if bool(pf["eliminated"]) or bool(pf["downed"]):
        return
    var def: Node3D = pf["f"]
    # v68: упавшего от усталости добивают, как в бою с ИИ; лежачего после
    # нокдауна не бьют (судья считает)
    if def == null or def.ko \
            or (def.fallen and not (def.exhaust_down or def.exhaust_getup)):
        return
    if float(pf["iframes"]) > 0.0 or def.is_invulnerable():
        return
    if debug_no_player_damage:
        return
    var info: Dictionary = att.punch_info(kind)
    var dist := _flat_dist(att.position, def.position)
    if dist > float(info["reach"]):
        return
    var anim_kind := String(info.get("anim", kind))
    var push_dir := def.position - att.position
    push_dir.y = 0.0
    push_dir = push_dir.normalized()
    var power := 1.0
    if att.get("punch_power") != null:
        power = float(att.get("punch_power"))
    # v71l: уклон работает как в оффлайне (main.gd::_resolve): окно слипа
    # 0.06–0.30 с уводит с линии, апперкот попадает на 80% урона.
    if def.evading:
        var slip_safe: bool = def.in_slip_window() if def.has_method("in_slip_window") else true
        if anim_kind != "upper" and slip_safe:
            _spark(def.head.global_position, "dodge")
            return
    if def.blocking and def.stun <= 0.001:
        # Блок гасит удар (×0.18), не отбрасывает и не станит — как в оффлайне.
        var bdmg: float = float(info["dmg"]) * BASE_DMG_SCALE * 0.18 \
                * float(att.dmg_mult) * power
        if anim_kind == "upper" and def.evading:
            bdmg *= 0.8
        def.hp = maxf(0.0, def.hp - bdmg)
        def.taken += bdmg
        def.flash = 0.07
        def.stamina = maxf(0.0, def.stamina - 8.0)
        def.position += push_dir * float(info["push"]) * 0.35
        def.push_impulse(push_dir, 1.6)
        _spark(def.head.global_position, "block")
        if def.hp <= 0.0:
            _down_player(slot, push_dir * 2.2 + Vector3(0.0, 1.6, 0.0))
        return
    var dmg: float = float(info["dmg"]) * BASE_DMG_SCALE * float(att.dmg_mult) * power
    if anim_kind == "upper" and def.evading:
        dmg *= 0.8
    def.take_hit(dmg, push_dir * float(info["push"]))
    # v71l: не дублируем пуш фиксированной силой — как в оффлайне, сила зависит
    # от удара (upper 5.0, rhook 4.2, lhook 3.6, прямой 2.6). Фиксированные
    # 2.4 поверх take_hit давали лишнее шатание «от одного удара».
    match anim_kind:
        "upper":
            def.push_impulse(push_dir, 5.0)
        "rhook":
            def.push_impulse(push_dir, 4.2)
        "lhook":
            def.push_impulse(push_dir, 3.6)
        _:
            def.push_impulse(push_dir, 2.6)
    _spark(def.head.global_position, "hit")
    if def.hp <= 0.0:
        _down_player(slot, push_dir * 2.2 + Vector3(0.0, 1.6, 0.0))


func _resolve_player_hit(att: Node3D, kind: String) -> void:
    var pf := _player_by_fighter(att)
    if pf.is_empty() or bool(pf["downed"]) or bool(pf["eliminated"]):
        return
    var info: Dictionary = att.punch_info(kind)
    var reach := float(info["reach"])
    # цель — ближайший враг в досягаемости; иначе проверяем союзников (FF)
    var target_e := {}
    var best := 999.0
    for e in enemies:
        if bool(e["dead"]):
            continue
        var ef: Node3D = e["f"]
        if ef == null:
            continue
        var d := _flat_dist(att.position, ef.position)
        if d <= reach and d < best:
            best = d
            target_e = e
    if not target_e.is_empty():
        _damage_enemy(pf, target_e, info)
        return
    # союзник в зоне удара — friendly fire
    var ally := {}
    var best_a := 999.0
    for slot in players:
        if int(slot) == int(pf["slot"]):
            continue
        var apf: Dictionary = players[slot]
        if bool(apf["eliminated"]) or bool(apf["downed"]):
            continue
        var af: Node3D = apf["f"]
        if af == null:
            continue
        var d := _flat_dist(att.position, af.position)
        if d <= reach and d < best_a:
            best_a = d
            ally = apf
    if not ally.is_empty():
        _friendly_hit(pf, ally, info)


func _damage_enemy(pf: Dictionary, e: Dictionary, info: Dictionary) -> void:
    var ef: Node3D = e["f"]
    if ef == null or bool(e["dead"]):
        return
    var dmg: float = float(info["dmg"]) * float((pf["f"] as Node3D).dmg_mult)
    if ef.blocking and ef.stun <= 0.001:
        dmg *= 0.18
    ef.take_hit(dmg, (ef.position - pf["f"].position).normalized() * float(info["push"]))
    ef.push_impulse((ef.position - pf["f"].position).normalized(), 3.0)
    var stats: Dictionary = pf["stats"]
    stats["damage"] = float(stats["damage"]) + dmg
    stats["hits"] = int(stats["hits"]) + 1
    if ef.hp <= 0.0:
        _kill_enemy(e)


func _friendly_hit(attacker: Dictionary, target: Dictionary, info: Dictionary) -> void:
    var tf: Node3D = target["f"]
    var af: Node3D = attacker["f"]
    _spark(tf.head.global_position, "ff")
    if not friendly_fire:
        debug_ff_damage = 0.0
        debug_ff_sparked = true
        return
    var dmg: float = float(info["dmg"]) * float(af.dmg_mult) * 0.5
    tf.take_hit(dmg, (tf.position - af.position).normalized() * float(info["push"]))
    if tf.hp <= 0.0:
        _down_player(int(target["slot"]), Vector3.UP * 1.4)


func _spark(pos: Vector3, kind: String) -> void:
    _spark_count += 1
    if main != null and main.has_method("_spawn_spark"):
        var col := Color(0.55, 0.75, 1.0) if kind == "ff" else Color(1.0, 0.82, 0.6)
        main._spawn_spark(pos, col)
    if is_host:
        NetworkManager.send_event("coop_spark", {"p": [pos.x, pos.y, pos.z], "k": kind})


func _kill_enemy(e: Dictionary) -> void:
    if bool(e["dead"]):
        return
    e["dead"] = true
    e["remove_t"] = 1.2
    var f: Node3D = e["f"]
    if f != null:
        f.ko = true
        f.hp = 0.0
        f.enter_ragdoll((f.position - _nearest_player_pos(f.position)).normalized()
                * 1.8 + Vector3(0.0, 1.2, 0.0))
    # если враг бил игрока — сбрасываем цель
    print("COOP враг убит eid=", int(e["eid"]), " осталось=", _alive_enemies())


func _alive_enemies() -> int:
    var n := 0
    for e in enemies:
        if not bool(e["dead"]):
            n += 1
    return n


# ---------------------------------------------------------------- игроки: нокдаун

func _down_player(slot: int, impulse: Vector3) -> void:
    if not players.has(slot):
        return
    var pf: Dictionary = players[slot]
    if bool(pf["eliminated"]) or bool(pf["downed"]):
        return
    var f: Node3D = pf["f"]
    if f == null:
        return
    pf["downed"] = true
    pf["down_t"] = knockout_time
    pf["revive_t"] = 0.0
    pf["revive_target"] = -1
    pf["mash_grace"] = 0.0
    pf["stats"]["downs"] = int(pf["stats"]["downs"]) + 1
    f.hp = 0.0
    f.start_knockdown(impulse)
    NetworkManager.send_event("coop_down", {"slot": slot})


func _on_player_knocked_down(slot: int) -> void:
    if not players.has(slot):
        return
    var pf: Dictionary = players[slot]
    var f: Node3D = pf.get("f")
    # ВАЖНО: knocked_down приходит и от потери баланса (knock_state = NONE), а не
    # только от нокдауна по HP. Такой боец встаёт сам через 1.9 с, и ставить ему
    # флаг downed нельзя: иначе управление отключается навсегда, кнопка подъёма
    # ничего не делает (knock_state != DOWNED), а через knockout_time игрока
    # выкидывает. Именно это ловил заказчик: «упал от первого удара и не встаёт».
    if f == null or int(f.knock_state) == FighterScript.KnockState.NONE:
        return
    pf["downed"] = true
    pf["down_t"] = knockout_time


func _on_player_get_up_finished(slot: int) -> void:
    if not players.has(slot):
        return
    var pf: Dictionary = players[slot]
    var f: Node3D = pf["f"]
    if f == null:
        return
    pf["downed"] = false
    pf["down_t"] = 0.0
    # v71p: 2 с неуязвимости после подъёма — как в одиночном бою. Раньше 1 с,
    # и бойца успевали уронить повторным ударом сразу после подъёма.
    pf["iframes"] = getup_invuln
    if f.has_method("start_invuln"):
        f.start_invuln(getup_invuln)
    f.hp = f.max_hp * downed_restore_ratio
    f.ko = false
    if slot == my_slot:
        _clear_downed_hud()
    NetworkManager.send_event("coop_repair", {"slot": slot, "hp": f.hp, "kind": "getup"})


func _player_timers(pf: Dictionary, dt: float) -> void:
    pf["iframes"] = maxf(0.0, float(pf["iframes"]) - dt)
    if not bool(pf["downed"]):
        return
    var f: Node3D = pf["f"]
    if f == null:
        return
    if int(f.knock_state) == FighterScript.KnockState.GETUP:
        return
    if int(f.knock_state) == FighterScript.KnockState.FALLING:
        return
    if int(f.knock_state) == FighterScript.KnockState.NONE:
        # потеря баланса, не нокдаун: боец встанет сам, таймер на выбывание не тикает
        return
    pf["down_t"] = float(pf["down_t"]) - dt
    if float(pf["down_t"]) <= 0.0:
        _eliminate_player(int(pf["slot"]))


func _eliminate_player(slot: int) -> void:
    if not players.has(slot):
        return
    var pf: Dictionary = players[slot]
    if bool(pf["eliminated"]):
        return
    pf["eliminated"] = true
    pf["downed"] = false
    pf["alive"] = false
    pf["stats"]["eliminated"] = int(pf["stats"]["eliminated"]) + 1
    var f: Node3D = pf["f"]
    if f != null:
        f.ko = true
        f.hp = 0.0
    if slot == my_slot:
        _clear_downed_hud()
    NetworkManager.send_event("coop_elim", {"slot": slot})
    print("COOP игрок выбыл: слот ", slot)
    if _alive_players() <= 0:
        _finish_match(false, "all_eliminated")


func _revive_tick(dt: float) -> void:
    for slot in players:
        var pf: Dictionary = players[slot]
        if bool(pf["eliminated"]) or bool(pf["downed"]):
            pf["revive_t"] = 0.0
            pf["revive_target"] = -1
            continue
        var intent := _intent_of(pf)
        if not bool(intent.get("interact", false)):
            pf["revive_t"] = 0.0
            pf["revive_target"] = -1
            continue
        var target := _find_downed_ally(pf)
        if target < 0:
            pf["revive_t"] = 0.0
            pf["revive_target"] = -1
            continue
        if int(pf["revive_target"]) != target:
            pf["revive_target"] = target
            pf["revive_t"] = 0.0
        var eff := revive_time
        if enable_roles and String(pf["role"]) == ROLE_SUPPORT:
            eff *= role_revive_bonus
        if max_revives_per_wave >= 0 and revives_used >= max_revives_per_wave:
            continue
        pf["revive_t"] = float(pf["revive_t"]) + dt / maxf(0.2, eff)
        if float(pf["revive_t"]) >= 1.0:
            _revive_player(pf, target)


func _find_downed_ally(pf: Dictionary) -> int:
    var f: Node3D = pf["f"]
    if f == null:
        return -1
    var best := -1
    var best_d := revive_radius
    for slot in players:
        if int(slot) == int(pf["slot"]):
            continue
        var other: Dictionary = players[slot]
        if not bool(other["downed"]) or bool(other["eliminated"]):
            continue
        var of: Node3D = other["f"]
        if of == null:
            continue
        var d := _flat_dist(f.position, of.position)
        if d <= best_d:
            best_d = d
            best = int(slot)
    return best


func _revive_player(reviver: Dictionary, target_slot: int) -> void:
    var target: Dictionary = players[target_slot]
    var tf: Node3D = target["f"]
    reviver["revive_t"] = 0.0
    reviver["revive_target"] = -1
    if tf == null or bool(target["eliminated"]):
        return
    if bool(tf.begin_get_up()):
        revives_used += 1
        reviver["stats"]["revives"] = int(reviver["stats"]["revives"]) + 1
        target["downed"] = false
        target["down_t"] = 0.0
        target["revived"] = true
        if int(target_slot) == my_slot:
            _clear_downed_hud()
        NetworkManager.send_event("coop_repair", {"slot": target_slot,
                "hp": tf.max_hp * downed_restore_ratio, "kind": "revive",
                "by": int(reviver["slot"])})
        print("COOP воскрешение: слот ", target_slot, " поднял ", int(reviver["slot"]),
                " всего за волну=", revives_used)


func _alive_players() -> int:
    var n := 0
    for slot in players:
        var pf: Dictionary = players[slot]
        if not bool(pf["eliminated"]):
            n += 1
    return n


# ---------------------------------------------------------------- AI

func _ai_tick(dt: float) -> void:
    for e in enemies:
        if bool(e["dead"]):
            continue
        var f: Node3D = e["f"]
        if f == null or f.fallen or f.ko:
            continue
        e["retarget_t"] = float(e["retarget_t"]) - dt
        e["attack_cd"] = maxf(0.0, float(e["attack_cd"]) - dt)
        var tslot := int(e["target_slot"])
        if not _target_valid(tslot) or float(e["retarget_t"]) <= 0.0:
            tslot = _choose_target(e)
            e["target_slot"] = tslot
            e["retarget_t"] = retarget_interval
        if tslot == 0 or not players.has(tslot):
            continue
        var tf: Node3D = players[tslot]["f"]
        if tf == null:
            continue
        var dist := _flat_dist(f.position, tf.position)
        f.look_at_target(tf.position)
        if dist > 1.15:
            var dir := (tf.position - f.position)
            dir.y = 0.0
            f.drive(dir.normalized(), dt)
        elif float(e["attack_cd"]) <= 0.0:
            var kind := _enemy_punch_kind(e)
            var def: EnemyDef = e["def"]
            if f.start_punch(kind, tf.head.global_position):
                e["attack_cd"] = enemy_attack_cooldown / maxf(0.35,
                        float(def.aggression) + 0.35) + randf_range(0.0, 0.35)


func _target_valid(slot: int) -> bool:
    if not players.has(slot):
        return false
    var pf: Dictionary = players[slot]
    return not bool(pf["eliminated"]) and not bool(pf["downed"])


func _choose_target(e: Dictionary) -> int:
    var alive: Array = []
    for slot in players:
        if _target_valid(int(slot)):
            alive.append(int(slot))
    if alive.is_empty():
        return 0
    match aggro_mode:
        AggroMode.MOST_DAMAGE:
            var best_slot := int(alive[0])
            var best_dmg := -1.0
            for slot in alive:
                var d := float(players[slot]["stats"]["damage"])
                if d > best_dmg:
                    best_dmg = d
                    best_slot = int(slot)
            return best_slot
        AggroMode.RANDOM:
            return int(alive[randi() % alive.size()])
        AggroMode.TANK_PRIORITY:
            for slot in alive:
                if enable_roles and String(players[slot]["role"]) == ROLE_TANK:
                    return int(slot)
            return _nearest_player_slot(e["f"].position)
        _:
            return _nearest_player_slot(e["f"].position)


func _nearest_player_slot(pos: Vector3) -> int:
    var best := 0
    var best_d := 999.0
    for slot in players:
        if not _target_valid(int(slot)):
            continue
        var f: Node3D = players[slot]["f"]
        if f == null:
            continue
        var d := _flat_dist(pos, f.position)
        if d < best_d:
            best_d = d
            best = int(slot)
    return best


func _enemy_punch_kind(e: Dictionary) -> String:
    var def: EnemyDef = e["def"]
    match String(def.archetype):
        "puncher":
            return ["rhook", "upper", "upper_l", "lhook"][randi() % 4]
        "speedster":
            return ["jab", "jab", "cross"][randi() % 3]
        "tank":
            return ["lhook", "body_jab", "rhook"][randi() % 3]
        "defender":
            return ["jab", "cross"][randi() % 2]
        _:
            return ["jab", "cross", "lhook", "rhook"][randi() % 4]


# ---------------------------------------------------------------- волны: завершение

func _check_wave_end() -> void:
    if _alive_enemies() > 0 or not spawn_queue.is_empty():
        return
    if state != MatchState.WAVE:
        return
    NetworkManager.send_event("coop_wave_clear", {"wave": wave_idx + 1})
    print("COOP волна ", wave_idx + 1, " зачищена; подъёмов за волну=", revives_used)
    if wave_idx + 1 >= total_waves:
        _finish_match(true, "waves_cleared")
        return
    state = MatchState.INTERMISSION
    intermission = intermission_time
    revives_used = 0
    if respawn_between_waves:
        _respawn_eliminated()
    _respawn_enemies_clear()


func _respawn_eliminated() -> void:
    for slot in players:
        var pf: Dictionary = players[slot]
        if not bool(pf["eliminated"]):
            continue
        var f: Node3D = pf["f"]
        if f == null:
            continue
        pf["eliminated"] = false
        pf["alive"] = true
        pf["downed"] = false
        pf["iframes"] = 1.5
        f.clear_ragdoll()
        f.reset(_player_spawn(int(slot)), f.max_hp)
        NetworkManager.send_event("coop_repair", {"slot": int(slot),
                "hp": f.max_hp, "kind": "respawn"})


func _respawn_enemies_clear() -> void:
    for e in enemies:
        var f: Node3D = e["f"]
        if f != null:
            f.queue_free()
    enemies.clear()


# ---------------------------------------------------------------- результат

func _finish_match(victory: bool, reason: String) -> void:
    if state == MatchState.RESULT:
        return
    state = MatchState.RESULT
    match_active = false
    spawn_queue.clear()
    var table: Array = []
    for slot in players:
        var pf: Dictionary = players[slot]
        var stats: Dictionary = pf["stats"]
        var coins := int(30 + 20 * (wave_idx + 1) + 2 * int(stats["hits"])
                + 10 * int(stats["revives"]) + (60 if victory else 0))
        var rep := 2 * (wave_idx + 1) + (3 if victory else 0)
        var stat_gain := 0.3 * float(wave_idx + 1) * (1.5 if victory else 1.0)
        table.append({
            "slot": int(slot), "name": String(pf["name"]), "role": String(pf["role"]),
            "damage": int(round(float(stats["damage"]))),
            "hits": int(stats["hits"]), "revives": int(stats["revives"]),
            "downs": int(stats["downs"]), "eliminated": int(stats["eliminated"]),
            "coins": coins, "rep": rep, "stat": stat_gain,
        })
    result = {"victory": victory, "reason": reason,
            "waves_cleared": wave_idx + 1 if victory else wave_idx,
            "waves_total": total_waves, "time": match_time,
            "players": table,
            "penalty": 0 if not apply_ranked_penalty_in_coop else 1}
    print("COOP матч завершён: победа=", victory, " причина=", reason,
            " волн=", result["waves_cleared"], "/", total_waves)
    if is_host:
        NetworkManager.send_event("coop_result", result)
        _apply_result_save()
        _apply_rewards_for_slot(my_slot)
    _show_result(result)


func _apply_result_save() -> void:
    var prev_matches := int(SaveManager.load_value("coop", "matches", 0.0))
    var prev_best := int(SaveManager.load_value("coop", "best_wave", 0.0))
    var prev_revives := int(SaveManager.load_value("coop", "revives", 0.0))
    SaveManager.save_value("coop", "matches", prev_matches + 1)
    SaveManager.save_value("coop", "waves_cleared",
            int(SaveManager.load_value("coop", "waves_cleared", 0.0))
            + int(result.get("waves_cleared", 0)))
    SaveManager.save_value("coop", "best_wave",
            maxi(prev_best, int(result.get("waves_cleared", 0))))
    var revives_total := 0
    for row in result.get("players", []):
        revives_total += int(row.get("revives", 0))
    SaveManager.save_value("coop", "revives", prev_revives + revives_total)
    SaveManager.save_value("coop", "last_result",
            "win" if bool(result.get("victory", false)) else "lose")
    SaveManager.save_value("coop", "last_wave",
            int(result.get("waves_cleared", 0)))
    SaveManager.save_value("coop", "arena", "ring")
    SaveManager.flush()
    print("COOP сейв [coop]: матчей=", prev_matches + 1, " лучшая волна=",
            maxi(prev_best, int(result.get("waves_cleared", 0))))


func _apply_rewards_for_slot(slot: int) -> void:
    if main == null or result.is_empty():
        return
    for row in result.get("players", []):
        if int(row.get("slot", 0)) != slot:
            continue
        var coins := int(row.get("coins", 0))
        var rep := int(row.get("rep", 0))
        var stat := float(row.get("stat", 0.0))
        main.coins = maxi(0, int(main.coins) + coins)
        if main.get("arena_rep") != null:
            main.arena_rep = int(main.arena_rep) + rep
        if StatsManager != null and stat > 0.0:
            StatsManager.add_stat("stamina", stat)
            StatsManager.add_stat("strength", stat * 0.5)
        if main.has_method("_save_profile"):
            main._save_profile()
        print("COOP награда слот ", slot, ": монет +", coins, " репутация +", rep,
                " стат +", snappedf(stat, 0.01))


# ---------------------------------------------------------------- клиент

func _tick_client(delta: float) -> void:
    match_time += delta
    if not NetworkManager.is_online():
        if active:
            nav.emit("lost")
        return
    var local := _local_fighter()
    if local != null and match_active and state != MatchState.RESULT:
        var intent := _read_intent()
        NetworkManager.send_intent(intent)
        _predict_local(local, intent, delta)
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f != null:
            f.tick(delta)
            if int(slot) != my_slot:
                var snap_interval := 1.0 / maxf(1.0,
                        float(NetworkManager.snapshot_rate))
                if pf.has("cur_pos"):
                    pf["interp_t"] = minf(float(pf.get("interp_t", 0.0)) + delta,
                            snap_interval * 2.0)
                    var alpha := clampf(float(pf["interp_t"]) / snap_interval, 0.0, 1.0)
                    f.position = (pf["prev_pos"] as Vector3).lerp(
                            pf["cur_pos"] as Vector3, alpha)
                else:
                    var target: Vector3 = pf.get("target_pos", f.position)
                    f.position = f.position.lerp(target,
                            clampf(delta * 10.0 * NetworkManager.interpolation_delay
                            / 0.1, 0.0, 1.0))
                f.position.y = 0.0
    for e in enemies:
        var ef: Node3D = e["f"]
        if ef == null:
            continue
        ef.tick(delta)
        var snap_i := 1.0 / maxf(1.0, float(NetworkManager.snapshot_rate))
        if e.has("cur_pos"):
            e["interp_t"] = minf(float(e.get("interp_t", 0.0)) + delta, snap_i * 2.0)
            var ea := clampf(float(e["interp_t"]) / snap_i, 0.0, 1.0)
            ef.position = (e["prev_pos"] as Vector3).lerp(e["cur_pos"] as Vector3, ea)
        else:
            var target: Vector3 = e.get("target_pos", ef.position)
            ef.position = ef.position.lerp(target, clampf(delta * 10.0, 0.0, 1.0))
        ef.position.y = 0.0


func _predict_local(f: Node3D, intent: Dictionary, dt: float) -> void:
    if f.fallen or f.ko:
        return
    var mv: Array = intent.get("mv", [0.0, 0.0])
    var dir := Vector3(float(mv[0]) if mv.size() > 0 else 0.0, 0.0,
            float(mv[1]) if mv.size() > 1 else 0.0)
    if dir.length() > 0.01 and f.stun <= 0.001:
        f.drive(dir.normalized(), dt)
        f.look_at_target(f.position + dir.normalized())
    f.blocking = bool(intent.get("block", false)) and f.stun <= 0.001


func _read_intent() -> Dictionary:
    var dir := Vector3.ZERO
    var fwd := Vector3(0.0, 0.0, -1.0)
    var right := Vector3(1.0, 0.0, 0.0)
    if main != null and main.cam != null:
        fwd = -main.cam.global_transform.basis.z
        fwd.y = 0.0
        fwd = fwd.normalized()
        right = main.cam.global_transform.basis.x
        right.y = 0.0
        right = right.normalized()
    if _profile.is_action_pressed("move_fwd"):
        dir += fwd
    if _profile.is_action_pressed("move_back"):
        dir -= fwd
    if _profile.is_action_pressed("move_left"):
        dir -= right
    if _profile.is_action_pressed("move_right"):
        dir += right
    # v37: на телефоне — виртуальный стик (движение относительно камеры)
    var touch_state := _touch_input()
    var tmove: Vector2 = touch_state.get("move", Vector2.ZERO)
    if tmove.length() > 0.01:
        dir += fwd * (-tmove.y) + right * tmove.x
    if dir.length() > 0.01:
        dir = dir.normalized()
    var punch := ""
    for pair in [["punch_jab", "jab"], ["punch_cross", "cross"],
            ["punch_hook_l", "lhook"], ["punch_hook_r", "rhook"],
            ["punch_upper", "upper"], ["punch_upper_l", "upper_l"]]:
        if _profile.is_action_just_pressed(String(pair[0])):
            punch = String(pair[1])
    # тап по тач-кнопке — разовый удар
    if _touch_punch != "":
        punch = _touch_punch
        _touch_punch = ""
    var block := _profile.is_action_pressed("block") or bool(touch_state.get("block", false))
    var dodge := _profile.is_action_just_pressed("dodge") or _touch_dodge
    if _touch_dodge:
        _touch_dodge = false
    var get_up := _profile.is_action_just_pressed("get_up") or _touch_getup
    if _touch_getup:
        _touch_getup = false
    return {"mv": [dir.x, dir.z], "punch": punch, "block": block,
            "dodge": dodge, "get_up": get_up,
            "interact": Input.is_action_pressed("interact")}


# ---------------------------------------------------------------- тач (v37)

## Текущее состояние тач-ввода: стик и блок. В тестах можно подменить
## через _test_touch и проверить интент без реального слоя кнопок.
func _touch_input() -> Dictionary:
    if not _test_touch.is_empty():
        return _test_touch
    if main == null or main.touch == null:
        return {}
    if not bool(main.touch.active):
        return {}
    return {"move": main.touch.move, "block": bool(main.touch.block)}


## Удар с тач-кнопки. body_mode — как в офлайне: удар по корпусу.
func touch_punch(kind: String) -> void:
    if not active:
        return
    var body := false
    if main != null and main.touch != null:
        body = bool(main.touch.body_mode)
    _touch_punch = ("body_" + kind) if body else kind


func touch_dodge() -> void:
    if active:
        _touch_dodge = true


func touch_getup() -> void:
    if active:
        _touch_getup = true


## Кнопка «II» в коопе: как ESC — выход из матча в лобби (пауза в сети нечестна).
func touch_pause() -> void:
    if active:
        nav.emit("leave")


func _wire_touch() -> void:
    if main == null or main.touch == null:
        return
    var t = main.touch
    if not t.punch.is_connected(_on_touch_punch):
        t.punch.connect(_on_touch_punch)
    if not t.dodge.is_connected(_on_touch_dodge):
        t.dodge.connect(_on_touch_dodge)
    if not t.getup.is_connected(_on_touch_getup):
        t.getup.connect(_on_touch_getup)
    if not t.pause_pressed.is_connected(_on_touch_pause):
        t.pause_pressed.connect(_on_touch_pause)


func _unwire_touch() -> void:
    if main == null or main.touch == null:
        return
    var t = main.touch
    if t.punch.is_connected(_on_touch_punch):
        t.punch.disconnect(_on_touch_punch)
    if t.dodge.is_connected(_on_touch_dodge):
        t.dodge.disconnect(_on_touch_dodge)
    if t.getup.is_connected(_on_touch_getup):
        t.getup.disconnect(_on_touch_getup)
    if t.pause_pressed.is_connected(_on_touch_pause):
        t.pause_pressed.disconnect(_on_touch_pause)


func _on_touch_punch(kind: String) -> void:
    touch_punch(kind)


func _on_touch_dodge() -> void:
    touch_dodge()


func _on_touch_getup() -> void:
    touch_getup()


func _on_touch_pause() -> void:
    touch_pause()


## Отладочный тач-ввод для автотестов: {"move": Vector2, "block": bool}
func debug_touch_input(move: Vector2, block: bool) -> void:
    if move.length() < 0.01 and not block:
        _test_touch = {}
    else:
        _test_touch = {"move": move, "block": block}


func _on_snapshot(data: Dictionary) -> void:
    if is_host or not active:
        return
    _snapshots_received += 1
    match_time = float(data.get("t", match_time))
    total_waves = int(data.get("waves", total_waves))
    wave_idx = int(data.get("wave", wave_idx))
    var new_state := String(data.get("state", "fight"))
    state = MatchState.WAVE if new_state == "fight" else (
            MatchState.INTERMISSION if new_state == "intermission" else
            (MatchState.RESULT if new_state == "result" else state))
    revives_used = int(data.get("revives", revives_used))
    enable_roles = bool(data.get("roles", enable_roles))
    # игроки — применяем строки из основного пакета (1-2 игрока) и из
    # дополнительного (3-4 игрока), чтобы каждый пакет оставался меньше MTU.
    _apply_player_rows(data.get("players", []), data.get("server_pos", null))
    var res = data.get("result")
    if res is Dictionary and not result_shown and not res.is_empty():
        result = res
        _show_result(res)


## v71: применить строки состояния игроков (основной снапшот или доп. пакет).
func _apply_player_rows(rows: Array, server_pos = null) -> void:
    for prow in rows:
        var slot := int(prow.get("slot", 0))
        if slot <= 0:
            continue
        if not players.has(slot):
            _add_player_from_snapshot(slot, prow)
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f == null:
            continue
        var pos: Array = prow.get("p", [0.0, 0.0, 0.0])
        var new_pos := Vector3(float(pos[0]), 0.0, float(pos[2]))
        # v71: два последних снапшота для плавной интерполяции (без «догоняния»)
        if not pf.has("prev_pos"):
            pf["prev_pos"] = f.position
            pf["cur_pos"] = new_pos
            pf["interp_t"] = 0.0
        else:
            pf["prev_pos"] = pf.get("cur_pos", new_pos)
            pf["cur_pos"] = new_pos
            pf["interp_t"] = 0.0
        pf["target_pos"] = new_pos
        pf["hp"] = float(prow.get("hp", 0.0))
        pf["max"] = float(prow.get("max", 100.0))
        pf["alive"] = bool(prow.get("alive", true))
        pf["downed"] = bool(prow.get("down", false))
        # v71l: клиенту нужен остаток таймера нокдауна — иначе HUD «Встать: 0.0 с»
        pf["down_t"] = float(prow.get("dt", pf.get("down_t", 0.0)))
        pf["eliminated"] = bool(prow.get("elim", false))
        pf["iframes"] = float(prow.get("iframes", 0.0))
        pf["role"] = String(prow.get("role", pf.get("role", ROLE_DPS)))
        pf["name"] = String(prow.get("name", pf.get("name", "ИГРОК")))
        f.hp = float(prow.get("hp", f.hp))
        f.max_hp = float(prow.get("max", f.max_hp))
        f.stamina = float(prow.get("st", f.stamina))
        f.blocking = bool(prow.get("blk", false))
        f.punch_kind = String(prow.get("pk", ""))
        f.punch_t = float(prow.get("pt", 0.0))
        var ks := int(prow.get("ks", 0))
        f.knock_state = ks
        f.ko = bool(prow.get("ko", false))
        f.fallen = ks != 0 or f.ko
        f.get_up_progress = float(prow.get("gu", f.get_up_progress))
        if slot == my_slot:
            _correct_local(f, pf, server_pos)


## v71: отдельный unreliable_ordered пакет снапшота (враги и 3-4-й игрок).
func _on_snapshot_extra(kind: String, data: Dictionary) -> void:
    if is_host or not active:
        return
    if kind == "coop_enemies":
        _apply_enemy_snapshots(data.get("e", []) as Array)
    elif kind == "coop_players2":
        _apply_player_rows(data.get("players", []), null)


## Враги приходят отдельным пакетом (см. _send_snapshot), чтобы снапшот игроков
## не вылезал за MTU ENet при 4 игроках и волне врагов.
func _apply_enemy_snapshots(elist: Array) -> void:
    var alive_eids := {}
    for erow in elist:
        var eid := int(erow.get("eid", 0))
        alive_eids[eid] = true
        var e := _enemy_by_id(eid)
        if e.is_empty():
            e = _add_enemy_from_snapshot(eid, erow)
        e["miss"] = 0
        var ef: Node3D = e.get("f")
        if ef == null:
            continue
        var epos: Array = erow.get("p", [0.0, 0.0, 0.0])
        var e_new := Vector3(float(epos[0]), 0.0, float(epos[2]))
        if not e.has("prev_pos"):
            e["prev_pos"] = ef.position
            e["cur_pos"] = e_new
            e["interp_t"] = 0.0
        else:
            e["prev_pos"] = e.get("cur_pos", e_new)
            e["cur_pos"] = e_new
            e["interp_t"] = 0.0
        e["target_pos"] = e_new
        ef.hp = float(erow.get("hp", ef.hp))
        ef.max_hp = float(erow.get("max", ef.max_hp))
        ef.punch_kind = String(erow.get("pk", ""))
        ef.punch_t = float(erow.get("pt", 0.0))
        ef.blocking = bool(erow.get("blk", false))
        if bool(erow.get("dead", false)) and not bool(e.get("dead", false)):
            e["dead"] = true
            ef.ko = true
            ef.enter_ragdoll(Vector3(0.0, 1.0, 0.0) + ef.position.normalized())
    # v71: пакет unreliable — один потерянный кадр не повод удалять врага.
    # Считаем промахи подряд: удаляем только если врага нет 3 снапшота подряд.
    for i in range(enemies.size() - 1, -1, -1):
        var e: Dictionary = enemies[i]
        if alive_eids.has(int(e["eid"])):
            continue
        e["miss"] = int(e.get("miss", 0)) + 1
        if int(e["miss"]) < 3:
            continue
        var ef: Node3D = e.get("f")
        if ef != null:
            ef.queue_free()
        enemies.remove_at(i)


func _correct_local(f: Node3D, pf: Dictionary, _server_pos: Variant) -> void:
    var target: Vector3 = pf.get("target_pos", f.position)
    if f.position.distance_to(target) > 0.45:
        f.position = target
    else:
        f.position = f.position.lerp(target, 0.5)
    f.position.y = 0.0


func _add_player_from_snapshot(slot: int, prow: Dictionary) -> void:
    players[slot] = {
        "slot": slot, "id": 0, "name": String(prow.get("name", "ИГРОК")),
        "role": String(prow.get("role", ROLE_DPS)), "f": null, "alive": true,
        "downed": false, "eliminated": false, "down_t": 0.0, "revive_t": 0.0,
        "revive_target": -1, "mash_grace": 0.0, "iframes": 0.0, "intent": {},
        "prev_dodge": false, "pending_mash": false,
        "stats": {"damage": 0.0, "hits": 0, "revives": 0, "downs": 0,
                "eliminated": 0},
    }
    _create_player(slot)
    player_count = maxi(player_count, players.size())


func _add_enemy_from_snapshot(eid: int, erow: Dictionary) -> Dictionary:
    var kind := String(erow.get("k", "grunt"))
    var boss := bool(erow.get("b", false))
    var pos: Array = erow.get("p", [2.6, 0.0, 0.0])
    var f := _create_enemy_visual(eid, kind, boss,
            Vector3(float(pos[0]), 0.0, float(pos[2])))
    var e := {"eid": eid, "f": f, "def": _enemy_def_for(kind, boss),
            "kind": kind, "boss": boss, "dead": false, "remove_t": 0.0,
            "target_slot": 0, "retarget_t": 0.0, "attack_cd": 0.0,
            "max_hp": float(erow.get("max", 100.0)), "miss": 0}
    enemies.append(e)
    return e


func _enemy_by_id(eid: int) -> Dictionary:
    for e in enemies:
        if int(e["eid"]) == eid:
            return e
    return {}


# ---------------------------------------------------------------- снапшоты

func _send_snapshot() -> void:
    if not is_host:
        return
    # снапшот разделён на два пакета: игроки (unreliable) и враги (reliable),
    # иначе при 4 игроках и 6+ врагах пакет выходит за MTU ENet.
    var data := _build_snapshot()
    var elist: Array = data.get("enemies", [])
    data.erase("enemies")
    # v71: 4 игрока не влезают в один MTU-пакет (2 игрока ≈1076 Б). Делим:
    # в основном снапшоте 1-2 игрока, 3-4 — в extra-пакете.
    var plist: Array = data.get("players", [])
    var players2: Array = []
    if plist.size() > 2:
        players2 = plist.slice(2)
        data["players"] = plist.slice(0, 2)
    NetworkManager.send_snapshot(data)
    if not players2.is_empty():
        NetworkManager.send_snapshot_extra("coop_players2", {"players": players2})
    # v71: врагов шлём unreliable_ordered, а не reliable: при потере пакета
    # reliable-канал копил очередь и бой «подвисал». Пропажу врага клиент
    # подтверждает несколькими подряд пустыми снапшотами (см. _apply_enemy_snapshots).
    NetworkManager.send_snapshot_extra("coop_enemies", {"e": elist})
    # Итоговая таблица — отдельным reliable-событием. В снапшоте она раздувала
    # unreliable-пакет за MTU (1852 байта против лимита 1392) и могла теряться.
    if state == MatchState.RESULT and not result.is_empty() and not _result_sent:
        _result_sent = true
        NetworkManager.send_event("coop_result", result.duplicate(true))
    _snapshots_sent += 1


func _build_snapshot() -> Dictionary:
    var plist: Array = []
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f == null:
            continue
        plist.append({"slot": int(slot), "name": String(pf["name"]),
                "role": String(pf["role"]),
                "p": [f.position.x, 0.0, f.position.z], "ry": f.rotation.y,
                "hp": f.hp, "max": f.max_hp, "st": f.stamina,
                "pk": String(f.punch_kind), "pt": float(f.punch_t),
                "ks": int(f.knock_state), "ko": bool(f.ko),
                "blk": bool(f.blocking),
                "down": bool(pf["downed"]), "elim": bool(pf["eliminated"]),
                "alive": bool(pf["alive"]), "iframes": float(pf["iframes"]),
                "dt": float(pf["down_t"]),
                # прогресс «вставания» — чтобы кольцо нажатий на телефоне
                # показывало реальный прогресс у клиентов
                "gu": float(f.get_up_progress)})
    var elist: Array = []
    for e in enemies:
        var f: Node3D = e["f"]
        if f == null:
            continue
        elist.append({"eid": int(e["eid"]), "k": String(e["kind"]),
                "b": bool(e["boss"]), "p": [f.position.x, 0.0, f.position.z],
                "ry": f.rotation.y, "hp": f.hp, "max": f.max_hp,
                "pk": String(f.punch_kind), "pt": float(f.punch_t),
                "blk": bool(f.blocking), "dead": bool(e["dead"])})
    var st := "fight"
    if state == MatchState.INTERMISSION:
        st = "intermission"
    elif state == MatchState.RESULT:
        st = "result"
    var data := {"t": match_time, "wave": wave_idx, "waves": total_waves,
            "state": st, "revives": revives_used, "roles": enable_roles,
            "players": plist, "enemies": elist}
    return data


func _on_net_event(kind: String, data: Dictionary) -> void:
    if is_host:
        return
    match kind:
        "coop_enemies":
            _apply_enemy_snapshots(data.get("e", []) as Array)
        "coop_down":
            _say_spark_hint("НОКДАУН")
        "coop_elim":
            var elim_slot := int(data.get("slot", 0))
            if players.has(elim_slot):
                players[elim_slot]["eliminated"] = true
                players[elim_slot]["downed"] = false
                players[elim_slot]["alive"] = false
            if elim_slot == my_slot:
                _clear_downed_hud()
        "coop_repair":
            var slot := int(data.get("slot", 0))
            if players.has(slot):
                var k := String(data.get("kind", ""))
                if k == "revive" or k == "respawn":
                    players[slot]["downed"] = false
                    players[slot]["eliminated"] = false
                if float(data.get("hp", 0.0)) > 0.0:
                    var rf: Node3D = players[slot]["f"]
                    if rf != null:
                        rf.hp = float(data.get("hp", rf.hp))
                    players[slot]["downed"] = false
                if slot == my_slot:
                    _clear_downed_hud()
        "coop_wave":
            _wave_banner(int(data.get("wave", 1)), int(data.get("total", total_waves)))
        "coop_spark":
            var p: Array = data.get("p", [0.0, 1.0, 0.0])
            var col := Color(0.55, 0.75, 1.0) if String(data.get("k", "")) == "ff" \
                    else Color(1.0, 0.82, 0.6)
            if main != null and main.has_method("_spawn_spark"):
                main._spawn_spark(Vector3(float(p[0]), float(p[1]), float(p[2])), col)
            _spark_count += 1
        "coop_result":
            if result_shown or data.is_empty():
                return
            result = data
            _apply_rewards_for_slot(my_slot)
            _show_result(data)
        "coop_join_match":
            if int(data.get("target", 0)) == NetworkManager.my_id:
                if main != null and main.has_method("_start_coop_fight"):
                    main._start_coop_fight(data)


func _on_peer_connected(id: int) -> void:
    if not is_host or not active or not match_active or not allow_drop_in:
        return
    # слот появляется только после _rpc_join_request, поэтому основная работа —
    # в _on_lobby_updated; здесь лишь сразу сообщаем новому клиенту о матче
    if players.has(NetworkManager.slot_of(id)):
        _send_join_match(id)


## Drop-in: слот игрока мог появиться уже после peer_connected (join request).
func _on_lobby_updated() -> void:
    if not is_host or not active or not match_active or not allow_drop_in:
        return
    for id in NetworkManager.players:
        var slot := NetworkManager.slot_of(int(id))
        if slot <= 0 or int(id) == 1:
            continue
        if players.has(slot):
            continue
        _collect_add_slot(slot, int(id))
        _create_player(slot)
        players[slot]["iframes"] = drop_in_iframes
        print("COOP drop-in: peer ", int(id), " занял слот ", slot)
        NetworkManager.send_event("coop_repair", {"slot": slot,
                "hp": players[slot]["f"].hp, "kind": "drop_in"})
        _send_join_match(int(id))


func _send_join_match(id: int) -> void:
    var info := {"target": id, "players": NetworkManager.players.duplicate(true),
            "enable_roles": enable_roles, "wave": wave_idx + 1,
            "waves": total_waves, "coop": true}
    NetworkManager.send_event("coop_join_match", info)


func _collect_add_slot(slot: int, id: int) -> void:
    var info: Dictionary = NetworkManager.players.get(id, {})
    players[slot] = {"slot": slot, "id": id,
            "name": String(info.get("name", "ИГРОК")),
            "role": String(info.get("role", ROLE_DPS)),
            "f": null, "alive": true, "downed": false, "eliminated": false,
            "down_t": 0.0, "revive_t": 0.0, "revive_target": -1,
            "mash_grace": 0.0, "iframes": 0.0, "intent": {}, "prev_dodge": false,
            "pending_mash": false,
            "stats": {"damage": 0.0, "hits": 0, "revives": 0, "downs": 0,
                    "eliminated": 0}}
    player_count = maxi(player_count, players.size())


func _on_peer_disconnected(id: int) -> void:
    if not is_host or not active:
        return
    var slot := 0
    for s in players:
        if int(players[s]["id"]) == id:
            slot = int(s)
    if slot == 0:
        return
    var pf: Dictionary = players[slot]
    var f: Node3D = pf.get("f")
    if f != null:
        f.queue_free()
    players.erase(slot)
    player_count = maxi(1, players.size())
    if match_active and _alive_players() <= 0:
        _finish_match(false, "all_left")
    NetworkManager.send_event("coop_leave", {"slot": slot})


func _on_match_ended(reason: String) -> void:
    if not active:
        return
    print("COOP матч закрыт сетью: ", reason)
    nav.emit("net_end")


func _on_server_lost() -> void:
    if not active:
        return
    nav.emit("lost")


# ---------------------------------------------------------------- ввод

func handle_key(event: InputEvent) -> String:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return ""
    if event.keycode == KEY_ESCAPE:
        if state == MatchState.RESULT:
            return "lobby"
        return "leave"
    return ""


func _wave_banner(wave: int, total: int) -> void:
    _hint_lbl.text = Lang.t("coop_wave_banner") % [wave, total]
    _hint_lbl.visible = not _use_touch_hints()


func _say_spark_hint(_text: String) -> void:
    pass


# ---------------------------------------------------------------- HUD

func _build_hud() -> void:
    hud_layer = CanvasLayer.new()
    hud_layer.layer = 8
    add_child(hud_layer)
    _root = Control.new()
    _root.set_anchors_preset(Control.PRESET_FULL_RECT)
    _root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    hud_layer.add_child(_root)
    _wave_lbl = _mk_label(Vector2(0, 12), Vector2(1280, 30), 22, Color(0.98, 0.86, 0.45))
    _enemy_lbl = _mk_label(Vector2(0, 42), Vector2(1280, 24), 16, Color(0.85, 0.90, 0.98))
    _timer_lbl = _mk_label(Vector2(0, 66), Vector2(1280, 22), 15, Color(0.72, 0.80, 0.92))
    _own_name = _mk_label(Vector2(20, 96), Vector2(360, 24), 16, Color(0.92, 0.95, 1.0))
    _own_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _own_hp_bg = _mk_bar(Vector2(20, 124), Vector2(240, 14))
    _own_hp_fill = _mk_fill(Vector2(22, 126), Vector2(236, 10), Color(0.35, 0.85, 0.45))
    _own_st_bg = _mk_bar(Vector2(20, 144), Vector2(240, 10))
    _own_st_fill = _mk_fill(Vector2(22, 146), Vector2(236, 6), Color(0.35, 0.65, 0.95))
    for i in 4:
        var y := 176.0 + float(i) * 34.0
        var nm := _mk_label(Vector2(20, y), Vector2(360, 20), 13, Color(0.82, 0.86, 0.94))
        nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        var bg := _mk_bar(Vector2(20, y + 20), Vector2(160, 9))
        var fill := _mk_fill(Vector2(21, y + 21), Vector2(158, 7), Color(0.4, 0.85, 0.5))
        var st := _mk_label(Vector2(190, y + 16), Vector2(120, 18), 12,
                Color(0.75, 0.8, 0.9))
        st.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
        _ally_rows.append({"name": nm, "bg": bg, "fill": fill, "st": st})
    # подсказку воскрешения держим выше тач-кнопок (низ экрана — под палец)
    _revive_lbl = _mk_label(Vector2(0, 452), Vector2(1280, 24), 17, Color(0.98, 0.86, 0.45))
    _revive_lbl.visible = false
    _revive_bg = _mk_bar(Vector2(0, 480), Vector2(1280, 10))
    _revive_bg.visible = false
    _revive_fill = _mk_fill(Vector2(0, 480), Vector2(0, 10), Color(0.98, 0.75, 0.14))
    _revive_fill.visible = false
    _hint_lbl = _mk_label(Vector2(0, 560), Vector2(1280, 24), 15, Color(0.75, 0.82, 0.92))
    _hint_lbl.text = _hint_text()
    # на телефоне подсказка про клавиши не нужна: кнопки подписаны сами,
    # а длинная строка лезет под тач-кнопки
    _hint_lbl.visible = not _use_touch_hints()
    _build_result_panel()


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


func _mk_bar(pos: Vector2, size: Vector2) -> ColorRect:
    var r := ColorRect.new()
    r.position = pos
    r.size = size
    r.color = Color(0.08, 0.09, 0.12, 0.85)
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(r)
    return r


func _mk_fill(pos: Vector2, size: Vector2, color: Color) -> ColorRect:
    var r := ColorRect.new()
    r.position = pos
    r.size = size
    r.color = color
    r.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _root.add_child(r)
    return r


func _hud_visible(v: bool) -> void:
    if hud_layer != null:
        hud_layer.visible = v
    if not v:
        _clear_downed_hud()


## v71l: убрать панель «ВСТАТЬ» (поднялись/выбыли/матч кончился).
func _clear_downed_hud() -> void:
    _hud_downed = false
    if main != null and main.hud != null:
        main.hud.set_downed(false)


func _update_hud() -> void:
    if not active or hud_layer == null or not hud_layer.visible:
        return
    if state == MatchState.COUNTDOWN:
        _wave_lbl.text = Lang.t("coop_get_ready") % int(ceil(countdown))
        _enemy_lbl.text = ""
    elif state == MatchState.INTERMISSION:
        _wave_lbl.text = Lang.t("coop_wave_clear") % (wave_idx + 1) + " · " \
                + Lang.t("coop_next") % int(ceil(intermission))
        _enemy_lbl.text = ""
    else:
        _wave_lbl.text = Lang.t("coop_wave") % [mini(wave_idx + 1, total_waves),
                maxi(total_waves, 1)]
        _enemy_lbl.text = Lang.t("coop_enemies_left") % _alive_enemies()
    _timer_lbl.text = _fmt_time(match_time) + " · " + Lang.t("coop_revives") \
            + " " + str(revives_used) + ("/" + str(max_revives_per_wave)
            if max_revives_per_wave >= 0 else "")
    var pf: Dictionary = players.get(my_slot, {})
    var f: Node3D = pf.get("f")
    if f != null:
        _own_name.text = "%s · %s" % [String(pf.get("name", "")),
                _role_label(String(pf.get("role", ROLE_DPS)))]
        _set_fill(_own_hp_fill, 236.0, f.hp / maxf(1.0, f.max_hp))
        _set_fill(_own_st_fill, 236.0, f.stamina / maxf(1.0, f.max_stamina))
    _sync_downed_hud(pf, f)
    # v71p: «НЕУЯЗВИМ N с» после подъёма — как в одиночном бою
    if main != null and main.hud != null:
        main.hud.set_invuln(f.invuln_left() if f != null else 0.0)
    for i in _ally_rows.size():
        var row: Dictionary = _ally_rows[i]
        var slot := i + 1
        if not players.has(slot):
            row["name"].text = "P%d · %s" % [slot, Lang.t("coop_slot_empty")]
            row["name"].add_theme_color_override("font_color", Color(0.5, 0.55, 0.65))
            row["fill"].size.x = 0
            row["st"].text = ""
            continue
        var apf: Dictionary = players[slot]
        var af: Node3D = apf.get("f")
        row["name"].text = "P%d · %s" % [slot, String(apf.get("name", ""))]
        var mark := ""
        if bool(apf.get("eliminated", false)):
            mark = Lang.t("coop_slot_left")
            row["name"].add_theme_color_override("font_color", Color(0.6, 0.55, 0.55))
        elif bool(apf.get("downed", false)):
            mark = Lang.t("coop_downed")
            row["name"].add_theme_color_override("font_color", Color(0.98, 0.6, 0.4))
        else:
            row["name"].add_theme_color_override("font_color", Color(0.82, 0.86, 0.94))
        if af != null:
            _set_fill(row["fill"], 158.0, af.hp / maxf(1.0, af.max_hp))
        row["st"].text = String(apf.get("role", ROLE_DPS)) + " " + mark
    # подсказка воскрешения: рядом лежит союзник
    var nearby := -1
    if f != null and not bool(pf.get("downed", false)):
        nearby = _find_downed_ally(pf) if not is_host else _find_downed_ally(pf)
    if nearby > 0:
        _revive_lbl.visible = true
        _revive_lbl.text = Lang.t("coop_revive_hint_touch" if _use_touch_hints()
                else "coop_revive_hint") % int(nearby)
        _revive_bg.visible = true
        _revive_fill.visible = true
        var prog := 0.0
        if is_host:
            prog = float(pf.get("revive_t", 0.0))
        else:
            prog = float(pf.get("revive_t", 0.0))
        _revive_fill.size.x = 1280.0 * clampf(prog, 0.0, 1.0)
    else:
        _revive_lbl.visible = false
        _revive_bg.visible = false
        _revive_fill.visible = false
    if state == MatchState.WAVE and not _use_touch_hints():
        _hint_lbl.text = _hint_text()
    _sync_touch_state(pf, f)


## Подсказка по управлению: на телефоне — про стик и кнопки, на ПК — про клавиши.
## v67: клавиши берём из реальной раскладки игрока (main._keys_text()), иначе
## после переназначения подсказка показывала заводские WASD/J K I U/E/L/Shift.
func _hint_text() -> String:
    if _use_touch_hints():
        return Lang.t("coop_hud_hint_touch")
    if main != null and main.has_method("_keys_text"):
        var k: Dictionary = main._keys_text()
        return Lang.t("coop_hud_hint_fmt") % [String(k.get("move", "WASD")),
                String(k.get("jab", "J")), String(k.get("hook_l", "K")),
                String(k.get("hook_r", "I")), String(k.get("upper", "U")),
                String(k.get("cross", "E")), String(k.get("block", "L")),
                String(k.get("dodge", "Shift"))]
    return Lang.t("coop_hud_hint")


## v71l: панель «ВСТАТЬ» на ПК. В коопе раньше показывался только тач-слой,
## поэтому заказчик на ПК не видел ни кнопки, ни полоски маша, ни отсчёта
## (главная жалоба «нету кнопки поднятия как в обычной игре»).
func _sync_downed_hud(pf: Dictionary, f: Node3D) -> void:
    if main == null or main.hud == null:
        return
    # На телефоне подъём показывает тач-слой (кнопка «ВСТАТЬ» и кольцо), как в
    # одиночке; панель HUD там не нужна и только перекрывает кнопки.
    if _use_touch_hints():
        if _hud_downed:
            _clear_downed_hud()
        return
    var downed := false
    if not bool(pf.get("eliminated", false)) and bool(pf.get("downed", false)) \
            and f != null and int(f.knock_state) == FighterScript.KnockState.DOWNED:
        downed = true
    if downed:
        if not _hud_downed:
            _hud_downed = true
            main.hud.set_downed(true, Lang.t("get_up_hint_touch"
                    if _use_touch_hints() else "get_up_hint"))
        if _use_touch_hints():
            # на телефоне прогресс рисует тач-кнопка (см. _sync_touch_state)
            main.hud.set_mash(false, 0.0, 0, 1)
        else:
            var need := maxi(1, int(f.get_up_presses))
            var prog := clampf(f.get_up_progress, 0.0, 1.0)
            main.hud.set_mash(true, prog, int(round(prog * float(need))), need)
        main.hud.set_downed_time(float(pf.get("down_t", 0.0)))
    elif _hud_downed:
        _hud_downed = false
        main.hud.set_downed(false)


func _use_touch_hints() -> bool:
    if main == null:
        return false
    if not ("touch_ui" in main):
        return false
    return bool(main.touch_ui)


## Мобилка (v37): кнопка «ВСТАТЬ» и кольцо нажатий, когда свой игрок лежит.
func _sync_touch_state(pf: Dictionary, f: Node3D) -> void:
    if main == null or main.touch == null:
        return
    if not bool(main.touch.active):
        return
    var down := bool(pf.get("downed", false))
    main.touch.set_downed(down)
    if not down:
        return
    var need := 1
    var prog := 0.0
    if f != null:
        need = maxi(1, int(f.get_up_presses))
        prog = float(f.get_up_progress)
    main.touch.set_mash(prog, int(floor(prog * float(need) + 0.5)), need)


func _set_fill(rect: ColorRect, full_width: float, ratio: float) -> void:
    if rect == null:
        return
    rect.size.x = full_width * clampf(ratio, 0.0, 1.0)


func _fmt_time(sec: float) -> String:
    var s := int(maxf(0.0, sec))
    return "%02d:%02d" % [s / 60, s % 60]


func _role_label(role: String) -> String:
    match role:
        ROLE_TANK:
            return Lang.t("coop_role_tank")
        ROLE_DPS:
            return Lang.t("coop_role_dps")
        ROLE_SUPPORT:
            return Lang.t("coop_role_support")
        ROLE_SCOUT:
            return Lang.t("coop_role_scout")
        _:
            return role


# ---------------------------------------------------------------- экран результата

func _build_result_panel() -> void:
    _result_panel = Control.new()
    _result_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
    _result_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _result_panel.visible = false
    _root.add_child(_result_panel)
    var bg := ColorRect.new()
    bg.color = Color(0.02, 0.03, 0.05, 0.94)
    bg.set_anchors_preset(Control.PRESET_FULL_RECT)
    bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _result_panel.add_child(bg)
    _result_title = _mk_panel_label(Vector2(0, 80), Vector2(1280, 60), 34,
            Color(0.98, 0.86, 0.45))
    _result_body = _mk_panel_label(Vector2(240, 160), Vector2(800, 340), 17,
            Color(0.90, 0.93, 0.98))
    _result_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _btn_rematch = _mk_panel_button(Vector2(300, 540), Vector2(210, 52))
    _btn_rematch.text = Lang.t("coop_rematch")
    _btn_rematch.pressed.connect(_on_result_rematch)
    _btn_lobby = _mk_panel_button(Vector2(535, 540), Vector2(210, 52))
    _btn_lobby.text = Lang.t("coop_to_lobby")
    _btn_lobby.pressed.connect(_on_result_lobby)
    _btn_menu = _mk_panel_button(Vector2(770, 540), Vector2(210, 52))
    _btn_menu.text = Lang.t("coop_to_menu")
    _btn_menu.pressed.connect(_on_result_menu)


func _mk_panel_label(pos: Vector2, size: Vector2, font_size: int,
        color: Color) -> Label:
    var l := Label.new()
    l.position = pos
    l.size = size
    l.add_theme_font_size_override("font_size", font_size)
    l.add_theme_color_override("font_color", color)
    l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    l.mouse_filter = Control.MOUSE_FILTER_IGNORE
    _result_panel.add_child(l)
    return l


func _mk_panel_button(pos: Vector2, size: Vector2) -> Button:
    var b := Button.new()
    b.position = pos
    b.size = size
    b.focus_mode = Control.FOCUS_NONE
    b.add_theme_font_size_override("font_size", 17)
    _result_panel.add_child(b)
    return b


func result_panel_hide() -> void:
    if _result_panel != null:
        _result_panel.visible = false
    result_shown = false


func _show_result(data: Dictionary) -> void:
    if _result_panel == null:
        return
    result = data
    result_shown = true
    _result_panel.visible = true
    # на телефоне убираем боевые кнопки, иначе они перехватывают тапы по панели
    if main != null and main.touch != null:
        main.touch.set_active(false)
    var win := bool(data.get("victory", false))
    _result_title.text = Lang.t("coop_result_win") if win else Lang.t("coop_result_lose")
    var lines: Array = []
    lines.append("%s %d/%d · %s %s" % [Lang.t("coop_waves_word"),
            int(data.get("waves_cleared", 0)), int(data.get("waves_total", 0)),
            Lang.t("coop_time_word"), _fmt_time(float(data.get("time", 0.0)))])
    lines.append("")
    lines.append(Lang.t("coop_result_header"))
    for row in data.get("players", []):
        lines.append("P%d %-10s %-8s %s %6d   %s %3d   %s %2d   %s %2d   %s %2d" % [
                int(row.get("slot", 0)), String(row.get("name", "")),
                String(row.get("role", "")),
                Lang.t("coop_dmg_word"), int(row.get("damage", 0)),
                Lang.t("coop_hits_word"), int(row.get("hits", 0)),
                Lang.t("coop_revives_word"), int(row.get("revives", 0)),
                Lang.t("coop_downs_word"), int(row.get("downs", 0)),
                Lang.t("coop_elim_word"), int(row.get("eliminated", 0))])
    _result_body.text = "\n".join(lines)
    _btn_rematch.visible = is_host


func _on_result_rematch() -> void:
    nav.emit("rematch")


func _on_result_lobby() -> void:
    nav.emit("lobby")


func _on_result_menu() -> void:
    nav.emit("menu")


# ---------------------------------------------------------------- утилиты

func _flat_dist(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()


func _player_by_fighter(f: Node3D) -> Dictionary:
    for slot in players:
        if players[slot]["f"] == f:
            return players[slot]
    return {}


func _enemy_by_fighter(f: Node3D) -> Dictionary:
    for e in enemies:
        if e["f"] == f:
            return e
    return {}


func _nearest_enemy(pos: Vector3) -> Node3D:
    var best: Node3D = null
    var best_d := 999.0
    for e in enemies:
        if bool(e["dead"]):
            continue
        var f: Node3D = e["f"]
        if f == null:
            continue
        var d := _flat_dist(pos, f.position)
        if d < best_d:
            best_d = d
            best = f
    return best


func _nearest_player_pos(pos: Vector3) -> Vector3:
    var best := Vector3.ZERO
    var best_d := 999.0
    for slot in players:
        var f: Node3D = players[slot]["f"]
        if f == null or bool(players[slot]["eliminated"]):
            continue
        var d := _flat_dist(pos, f.position)
        if d < best_d:
            best_d = d
            best = f.position
    return best


func _wire_player_signals() -> void:
    # сигналы уже подключаются в _create_player (impact и, на сервере, get_up)
    pass


# ---------------------------------------------------------------- отладочные API (тесты)

## Числа масштабирования волн для текущего числа игроков.
func debug_scaling() -> Dictionary:
    var plans: Array = []
    for i in waves.size():
        plans.append(wave_plan(i))
    return {"player_count": player_count, "count_mult": scaling.get("count_mult"),
            "hp_mult": scaling.get("hp_mult"),
            "interval_mult": scaling.get("interval_mult"),
            "boss_mult": scaling.get("boss_mult"),
            "total_waves": total_waves, "plans": plans}


## Проверка бонусов ролей: одноразово применяет роли, снимает множители,
## возвращает отношения к базовым значениям (для автотеста).
func debug_test_roles() -> Dictionary:
    var saved := {}
    var order: Array = []
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f == null:
            continue
        order.append(int(slot))
        saved[int(slot)] = {"hp": f.hp, "max": f.max_hp, "dmg": f.dmg_mult,
                "move": f.move_mult, "role": String(pf["role"])}
    order.sort()
    var roles := [ROLE_TANK, ROLE_DPS, ROLE_SUPPORT, ROLE_SCOUT]
    for i in order.size():
        players[int(order[i])]["role"] = String(roles[i % roles.size()])
    var old := enable_roles
    enable_roles = true
    _apply_roles()
    var out: Dictionary = {}
    for i in order.size():
        var slot := int(order[i])
        var f: Node3D = players[slot]["f"]
        var s: Dictionary = saved[slot]
        out[slot] = {"role": String(players[slot]["role"]),
                "hp_ratio": f.max_hp / maxf(0.001, float(s["max"])),
                "dmg_ratio": f.dmg_mult / maxf(0.001, float(s["dmg"])),
                "move_ratio": f.move_mult / maxf(0.001, float(s["move"]))}
    # откат: восстанавливаем значения и роли
    for i in order.size():
        var slot := int(order[i])
        var f: Node3D = players[slot]["f"]
        var s: Dictionary = saved[slot]
        f.max_hp = float(s["max"])
        f.hp = float(s["hp"])
        f.dmg_mult = float(s["dmg"])
        f.move_mult = float(s["move"])
        players[slot]["role"] = String(s["role"])
    enable_roles = old
    return {"roles": out, "hp_bonus": role_hp_bonus, "dmg_bonus": role_dmg_bonus,
            "move_bonus": role_move_bonus, "revive_bonus": role_revive_bonus}


## Эффективное время подъёма союзника для слота (SUPPORT короче).
func debug_revive_seconds(slot: int) -> float:
    if not players.has(slot):
        return revive_time
    var eff := revive_time
    if enable_roles and String(players[slot]["role"]) == ROLE_SUPPORT:
        eff *= role_revive_bonus
    return eff


## Спавн-точки: сколько их и реально достижимая дистанция на этой арене.
func debug_spawn_info() -> Dictionary:
    var best := _best_spawn_distance()
    return {"points": spawn_points.size(), "min_required": min_spawn_distance,
            "max_available": best, "ring_limit": ring_limit,
            "spawn_radius": spawn_radius}


func debug_state() -> Dictionary:
    var plist: Array = []
    for slot in players:
        var pf: Dictionary = players[slot]
        plist.append({"slot": int(slot), "role": String(pf["role"]),
                "alive": not bool(pf["eliminated"]), "downed": bool(pf["downed"]),
                "eliminated": bool(pf["eliminated"]),
                "hp": players[slot]["f"].hp if players[slot]["f"] != null else 0.0,
                "max": players[slot]["f"].max_hp if players[slot]["f"] != null else 0.0,
                "p": ([players[slot]["f"].position.x, 0.0,
                        players[slot]["f"].position.z]
                        if players[slot]["f"] != null else [0.0, 0.0, 0.0]),
                "iframes": float(pf["iframes"]),
                "damage": float(pf["stats"]["damage"]),
                "hits": int(pf["stats"]["hits"]),
                "revives": int(pf["stats"]["revives"]),
                "downs": int(pf["stats"]["downs"])})
    var etargets: Array = []
    for e in enemies:
        etargets.append({"eid": int(e["eid"]), "kind": String(e["kind"]),
                "target": int(e["target_slot"]), "dead": bool(e["dead"]),
                "hp": (e["f"].hp if e["f"] != null else 0.0),
                "max": (e["f"].max_hp if e["f"] != null else 0.0),
                "p": ([e["f"].position.x, 0.0, e["f"].position.z]
                        if e["f"] != null else [0.0, 0.0, 0.0])})
    return {"state": state, "match_active": match_active, "wave": wave_idx + 1,
            "total_waves": total_waves, "players": plist,
            "enemies": _alive_enemies(), "enemy_list": etargets,
            "revives_used": revives_used,
            "result": result.duplicate(true), "result_shown": result_shown,
            "snapshots_sent": _snapshots_sent, "sparks": _spark_count,
            "state_name": _state_name()}


func _state_name() -> String:
    match state:
        MatchState.IDLE:
            return "idle"
        MatchState.COUNTDOWN:
            return "countdown"
        MatchState.WAVE:
            return "wave"
        MatchState.INTERMISSION:
            return "intermission"
        MatchState.RESULT:
            return "result"
        _:
            return "?"


func debug_pause(v: bool) -> void:
    debug_paused = v


func debug_no_ai_set(v: bool) -> void:
    debug_no_ai = v


func debug_set_no_player_damage(v: bool) -> void:
    debug_no_player_damage = v


## v71l: самая низкая точка ragdoll/бойцов — тест «не провалились под пол».
func debug_min_solid_y() -> float:
    var lowest := 0.0
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf.get("f")
        if f == null:
            continue
        lowest = minf(lowest, f.position.y)
        for key in f.ragdoll_parts:
            var rb: RigidBody3D = f.ragdoll_parts[key]
            if rb != null:
                lowest = minf(lowest, rb.global_position.y)
    for e in enemies:
        var ef: Node3D = e.get("f")
        if ef == null:
            continue
        lowest = minf(lowest, ef.position.y)
        for key in ef.ragdoll_parts:
            var rb: RigidBody3D = ef.ragdoll_parts[key]
            if rb != null:
                lowest = minf(lowest, rb.global_position.y)
    return lowest


## v71l: ни один боец не «застрял» в FALLING (тогда подъём невозможен).
func debug_stuck_falling() -> int:
    var n := 0
    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf.get("f")
        if f != null and int(f.knock_state) == FighterScript.KnockState.FALLING \
                and float(f.knock_t) > 3.0:
            n += 1
    return n


## v71l: видна ли панель «ВСТАТЬ» в HUD одиночного боя.
func debug_hud_downed() -> Dictionary:
    var lbl_visible := false
    if main != null and main.hud != null and main.hud.getup_lbl != null:
        # важно именно «виден на экране»: в коопе battle скрыт, панель живёт
        # в отдельном слое getup_root (v71l)
        lbl_visible = main.hud.getup_lbl.is_visible_in_tree()
    return {"flag": _hud_downed, "label": lbl_visible}


## v71l: один удар врага по игроку (без AI) — проверка урона/нокдауна.
## Возвращает HP до/после и флаги, чтобы тест ловил «падает с одного удара».
func debug_enemy_hit_test(slot: int, kind: String = "upper") -> Dictionary:
    if not players.has(slot):
        return {"ok": false}
    var pf: Dictionary = players[slot]
    var def: Node3D = pf["f"]
    var target_e := {}
    for e in enemies:
        if not bool(e["dead"]) and e["f"] != null:
            target_e = e
            break
    if def == null or target_e.is_empty():
        return {"ok": false}
    var att: Node3D = target_e["f"]
    var hp_before: float = def.hp
    # ставим врага в досягаемость перед игроком и бьём тем же путём, что AI
    var fwd: Vector3 = -def.global_transform.basis.z
    fwd.y = 0.0
    fwd = fwd.normalized()
    att.position = def.position + fwd * 1.0
    # цель удара — именно запрошенный слот (иначе попадёт в того, на кого наведён AI)
    target_e["target_slot"] = slot
    def.blocking = false
    def.evading = false
    def.dodge_t = 0.0
    pf["downed"] = false
    pf["eliminated"] = false
    pf["iframes"] = 0.0
    # полный HP: проверяем именно «один удар с полного здоровья»
    def.hp = def.max_hp
    hp_before = def.hp
    _resolve_enemy_hit(att, kind)
    return {"ok": true, "hp_before": hp_before, "hp_after": def.hp,
            "damage": hp_before - def.hp, "downed": bool(pf["downed"]),
            "knock_state": int(def.knock_state),
            "max_hp": def.max_hp}


## Поднять всех игроков в полный HP на их точки спавна (тесты).
func debug_revive_all() -> void:    for slot in players:
        var pf: Dictionary = players[slot]
        var f: Node3D = pf["f"]
        if f == null:
            continue
        pf["downed"] = false
        pf["eliminated"] = false
        pf["alive"] = true
        pf["down_t"] = 0.0
        pf["revive_t"] = 0.0
        pf["revive_target"] = -1
        pf["iframes"] = 0.0
        f.clear_ragdoll()
        f.reset(_player_spawn(int(slot)), f.max_hp)
        f.ko = false


## Прокрутить серверную симуляцию на seconds секунд (без ожидания реального
## времени). Работает только у хоста. Асинхронно и кусками по 1 с: между
## кусками отдаём кадр, иначе ENet не успевает опрашивать сеть и клиенты
## отваливаются по таймауту, пока хост считает длинный отрезок.
func debug_advance(seconds: float) -> void:
    if not is_host:
        return
    var dt := 1.0 / 60.0
    var left := maxf(0.0, seconds)
    while left > 0.0001:
        var steps := mini(60, int(ceil(left / dt)))
        for i in steps:
            _server_step(dt)
            if state == MatchState.RESULT:
                left = 0.0
                break
        left -= float(steps) * dt
        await get_tree().process_frame
    _send_snapshot()


## Интент другому слоту (тесты): как будто игрок держит кнопки.
func debug_set_intent(slot: int, intent: Dictionary) -> void:
    debug_intents[slot] = intent.duplicate(true)


func debug_clear_intent(slot: int) -> void:
    debug_intents.erase(slot)


## Friendly fire: игрок 1 бьёт игрока 2 в упор. Возвращает 0 урона и искру.
func debug_ff_test() -> Dictionary:
    if not players.has(1) or not players.has(2):
        return {"ok": false, "reason": "нужно 2 игрока"}
    var a: Dictionary = players[1]
    var b: Dictionary = players[2]
    var af: Node3D = a["f"]
    var bf: Node3D = b["f"]
    if bool(a["downed"]) or bool(b["downed"]):
        return {"ok": false, "reason": "кто-то лежит"}
    bf.reset(af.position + af.global_transform.basis.x * 0.55 + Vector3(0, 0, 0.2),
            bf.max_hp)
    var hp0: float = bf.hp
    debug_ff_damage = -1.0
    debug_ff_sparked = false
    var info: Dictionary = af.punch_info("jab")
    _friendly_hit(a, b, info)
    return {"ok": true, "friendly_fire": friendly_fire,
            "damage": hp0 - bf.hp, "sparked": debug_ff_sparked,
            "reported": debug_ff_damage}


## Игрок 1 бьёт ближайшего врага; возвращает hp до/после.
func debug_hit_enemy_test() -> Dictionary:
    if not players.has(1):
        return {"ok": false}
    var e := {}
    for cand in enemies:
        if not bool(cand["dead"]):
            e = cand
            break
    if e.is_empty():
        return {"ok": false, "reason": "нет врагов"}
    var f: Node3D = players[1]["f"]
    var ef: Node3D = e["f"]
    ef.reset(f.position + Vector3(0.0, 0.0, -0.9), ef.max_hp)
    var hp0: float = ef.hp
    _damage_enemy(players[1], e, f.punch_info("jab"))
    return {"ok": true, "hp_before": hp0, "hp_after": ef.hp,
            "damage": hp0 - ef.hp}


## Принудительно уложить игрока в нокдаун.
func debug_down_player(slot: int) -> bool:
    if not players.has(slot):
        return false
    _down_player(slot, Vector3(0.0, 1.6, -1.0))
    return bool(players[slot]["downed"])


## Принудительно убить всех живых врагов (для проверки волн).
func debug_kill_all_enemies() -> int:
    var n := 0
    for e in enemies:
        if not bool(e["dead"]):
            _kill_enemy(e)
            n += 1
    return n


## Поставить игрока в точку.
func debug_place_player(slot: int, pos: Vector3) -> void:
    if players.has(slot) and players[slot]["f"] != null:
        players[slot]["f"].position = pos


## Применить награды/результат для всех (для проверки сейва).
func debug_apply_result(d: Dictionary) -> void:
    result = d
    if is_host:
        _apply_result_save()


func debug_revive_radius() -> float:
    return _find_downed_ally(players[my_slot]) if players.has(my_slot) else -1
