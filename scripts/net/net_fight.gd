class_name NetFight
extends Node3D
## Этап 5: лобби и сетевой бой. UI-лобби + склейка с существующим боем main.gd.
## Хост авторитетен: HP/урон/нокдаун/таймер тикает только у него. Клиент шлёт
## интенты (движение/удары/блок/уклон/вставание), предсказывает своё движение и
## интерполирует удалённого бойца по снапшотам. Никаких записей профиля/сейва
## в сетевом матче (main.net_mode = true).

const Lang = preload("res://scripts/lang.gd")
const STATE_MENU := 0
const STATE_FIGHT := 1
const STATE_NET_LOBBY := 17
const SNAP_INTERP := 0.35
const CORRECT_SNAP := 0.45
const REMOTE_DOWN_LIMIT := 10.0

var main: Node
var profile := InputProfile.new()
var active := false
var fight_active := false
var is_host := false
var latest_intent: Dictionary = {}
var _host_snap_t := 0.0
var _client_snap_t := 0.0
var _enemy_down_t := 0.0
var _last_downed := ""
var _remote_pos := Vector3.ZERO
## v71: плавная интерполяция удалённого бойца по ДВУМ последним снапшотам,
## а не «догоняние» последней позиции (на 20 Гц догоняние давало рывки).
var _rem_prev := Vector3.ZERO
var _rem_cur := Vector3.ZERO
var _rem_t := 0.0
var _rem_has := false
var _msg := ""
var _msg_t := 0.0
## Сколько секунд ещё ждём подключение к хосту, прежде чем сказать «нет связи».
var _join_t := 0.0
var _ending := false
var test_intent: Dictionary = {}
# --- мобильное управление в сетевом бою (v39) ---
var _touch_punch := ""
var _touch_dodge := false
var _touch_getup := false
## Тестовый тач-ввод без настоящего TouchLayer: {"move": Vector2, "block": bool}
var _test_touch := {}

# --- UI
var ui: CanvasLayer
var _root: Control
var _backdrop: ColorRect
var _title: Label
var _status: Label
var _players_lbl: Label
var _ping_lbl: Label
var _msg_lbl: Label
var _hint_lbl: Label
## Строка про интернет-игру: внешний IP + статус UPnP (v40).
var _ext_lbl: Label
var _host_btn: Button
var _join_btn: Button
var _lan_btn: Button
var _probe_btn: Button
## v46: «скопировать адрес» — для игры с ПК на ПК из другого города: адрес
## уходит в буфер, его остаётся только отправить другу в мессенджер.
var _copy_btn: Button
## v47: телефону проще вставить адрес из буфера одной кнопкой, чем набирать руками.
var _paste_btn: Button
## v47: строка «адрес для телефона/друга» — VPN-адрес хоста крупно в лобби.
var _addr_lbl: Label
var _ready_btn: Button
var _start_btn: Button
var _leave_btn: Button
## v45: отдельная кнопка «отключиться» (видна только когда соединение есть);
## «ВЫЙТИ» теперь честно выводит в меню — на телефоне Esc нет.
var _disc_btn: Button
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _lan_list: Array[Button] = []
var _result_title: Label
var _result_body: Label
var _result_menu: Button
var _result_rematch: Button


func setup(main_ref: Node) -> void:
    main = main_ref
    _build_ui()
    ui.visible = false
    NetworkManager.player_connected.connect(_on_peer_connected)
    NetworkManager.player_disconnected.connect(_on_peer_disconnected)
    NetworkManager.server_started.connect(_refresh_lobby)
    NetworkManager.joined_server.connect(_refresh_lobby)
    NetworkManager.connection_failed.connect(_on_conn_failed)
    NetworkManager.server_disconnected.connect(_on_server_lost)
    NetworkManager.lobby_updated.connect(_refresh_lobby)
    NetworkManager.match_started.connect(_on_match_started)
    NetworkManager.snapshot_received.connect(_on_snapshot)
    NetworkManager.intent_received.connect(_on_intent)
    NetworkManager.net_event.connect(_on_net_event)
    NetworkManager.lan_found.connect(_on_lan_found)
    NetworkManager.upnp_updated.connect(_refresh_lobby)


# ---------------------------------------------------------------- лобби

func open_lobby() -> void:
    active = true
    fight_active = false
    _join_t = 0.0
    # пересчитать LAN IP при каждом открытии: мог включиться VPN/смениться Wi-Fi
    NetworkManager.lan_ip = ""
    nm_cleanup()
    ui.visible = true
    _show_lobby()
    _status.text = Lang.t("net_offline")
    _players_lbl.text = ""
    _ping_lbl.text = ""
    if _ip_edit != null:
        _ip_edit.text = ""
        _ip_edit.placeholder_text = Lang.t("net_ip_hint")
    # сразу ищем хоста в LAN: на телефоне это избавляет от ввода IP руками
    call_deferred("_auto_scan")


func close() -> void:
    active = false
    fight_active = false
    nm_cleanup()
    if ui != null:
        ui.visible = false


func show_lobby() -> void:
    _show_lobby()


func tick_lobby(delta: float) -> void:
    if _msg_t > 0.0:
        _msg_t = maxf(0.0, _msg_t - delta)
        if _msg_t <= 0.0:
            _msg_lbl.text = ""
    # Не висеть вечно в «ПОДКЛЮЧЕНИЕ...», если IP/порт неверные или firewall
    # режет пакеты: через 8 с честно говорим, что связи нет (как в кооп-лобби).
    if _join_t > 0.0:
        if NetworkManager.is_online():
            _join_t = 0.0
        else:
            _join_t -= delta
            if _join_t <= 0.0:
                _join_t = 0.0
                NetworkManager.leave_game()
                NetworkManager.log_net("клиент: таймаут 8 с — хост не ответил")
                _say(Lang.t("net_join_timeout"))
                _refresh_lobby()
    if NetworkManager.player_count() > 0:
        _refresh_lobby()


func nm_cleanup() -> void:
    if NetworkManager.is_online():
        NetworkManager.leave_game()


func _show_lobby() -> void:
    _backdrop.visible = true
    _title.visible = true
    _status.visible = true
    _players_lbl.visible = true
    _ping_lbl.visible = true
    _host_btn.visible = true
    _join_btn.visible = true
    _lan_btn.visible = true
    _probe_btn.visible = true
    _copy_btn.visible = NetworkManager.is_host
    _paste_btn.visible = not NetworkManager.is_host
    _addr_lbl.visible = true
    _ip_edit.visible = true
    _port_edit.visible = true
    _ready_btn.visible = true
    _leave_btn.visible = true
    _disc_btn.visible = NetworkManager.is_online()
    _start_btn.visible = NetworkManager.is_host
    _result_title.visible = false
    _result_body.visible = false
    _result_menu.visible = false
    _result_rematch.visible = false
    _clear_lan_buttons()
    _refresh_lobby()


func _refresh_lobby() -> void:
    if not active or ui == null or not ui.visible:
        return
    if _disc_btn != null:
        _disc_btn.visible = NetworkManager.is_online()
    if _copy_btn != null:
        _copy_btn.visible = NetworkManager.is_host
    if _paste_btn != null:
        _paste_btn.visible = not NetworkManager.is_host
    # v47: «адрес для телефона/друга» — VPN-адрес, по которому телефон с
    # мобильным интернетом подключится к этому ПК-хосту
    _addr_lbl.text = ""
    if NetworkManager.is_host:
        var row: Dictionary = NetworkManager.best_join_row()
        var kind := String(row["kind"])
        var addr := "%s:%d" % [String(row["ip"]), int(row["port"])]
        var txt := Lang.t("net_phone_addr") % ("%s (%s)" % [addr,
                NetworkManager.kind_label(kind)])
        var lan := "%s:%d" % [NetworkManager.lan_ip_text(), NetworkManager.port]
        if kind != "lan" and lan != addr:
            txt += "  ·  " + NetworkManager.kind_label("lan") + ": " + lan
        _addr_lbl.text = txt
    var rows: Array[String] = []
    for id in NetworkManager.players:
        var p: Dictionary = NetworkManager.players[id]
        var role := "HOST" if int(id) == 1 else "CLIENT"
        var rdy := "OK" if bool(p.get("ready", false)) else "—"
        rows.append("ИГРОК %d (%s): %s · готов: %s · ping %d мс" % [
                int(id), role, String(p.get("name", "")), rdy, int(p.get("ping", 0))])
    _players_lbl.text = "\n".join(rows)
    if not NetworkManager.is_online():
        _status.text = Lang.t("net_offline")
    elif NetworkManager.is_host:
        # хост видит свой LAN IP: его и надо продиктовать второму игроку
        _status.text = Lang.t("net_hosting_ip") % [NetworkManager.lan_ip_text(),
                NetworkManager.port]
    else:
        _status.text = (Lang.t("net_connected") if NetworkManager.my_id != 0
                else Lang.t("net_connecting"))
        # v42: свой IP клиента — сразу видно, в одной ли подсети с хостом
        _status.text += "  ·  " + Lang.t("net_my_ip") % NetworkManager.lan_ip_text()
    _ping_lbl.text = ("%s %d мс" % [Lang.t("net_ping"), int(NetworkManager.ping)]) if NetworkManager.ping > 0 else ""
    _ext_lbl.text = NetworkManager.internet_hint_text() if NetworkManager.is_host \
            else _probe_line()
    # v44: клиент видит предупреждение ещё до пробы, если IP в другой подсети
    if not NetworkManager.is_host and _ext_lbl.text == "":
        var typed := _ip_edit.text.strip_edges()
        if typed != "" and _subnet_differs(typed):
            _ext_lbl.text = Lang.t("net_other_subnet")
    _probe_btn.disabled = NetworkManager.is_online()
    # v41: хост видит ВСЕ свои адреса (LAN, Tailscale, Radmin) — не надо гадать,
    # какой IP диктовать второму игроку из другой сети
    if NetworkManager.is_online() and NetworkManager.is_host:
        _hint_lbl.text = Lang.t("net_addrs_hint") % NetworkManager.addresses_text()
    else:
        _hint_lbl.text = Lang.t("net_lobby_hint")
    _start_btn.visible = NetworkManager.is_host
    _start_btn.disabled = not NetworkManager.can_start()
    _ready_btn.text = Lang.t("net_ready_on")
    if NetworkManager.is_host:
        _ready_btn.visible = false
        _start_btn.visible = true
    else:
        _ready_btn.visible = true
        _start_btn.visible = false
    _host_btn.disabled = NetworkManager.is_online()
    _join_btn.disabled = NetworkManager.is_online()
    _lan_btn.disabled = NetworkManager.is_online()


func _clear_lan_buttons() -> void:
    for b in _lan_list:
        b.queue_free()
    _lan_list.clear()


func _on_lan_found(servers: Array) -> void:
    _clear_lan_buttons()
    NetworkManager.log_net("LAN-поиск: найдено хостов=%d" % servers.size())
    if servers.is_empty():
        _say(Lang.t("net_no_servers"))
        return
    _say(Lang.t("net_lan_found") % servers.size())
    for i in servers.size():
        var s: Dictionary = servers[i]
        var b := _mk_button(Vector2(330, 470 + i * 44), Vector2(620, 38))
        b.text = "%s:%d — %s" % [String(s["ip"]), int(s["port"]), String(s["name"])]
        b.add_theme_font_size_override("font_size", 14)
        b.pressed.connect(_join_lan.bind(i))
        _lan_list.append(b)


func _join_lan(i: int) -> void:
    if i < 0 or i >= NetworkManager.found_servers.size():
        return
    var s: Dictionary = NetworkManager.found_servers[i]
    _ip_edit.text = String(s["ip"])
    _port_edit.text = str(int(s["port"]))
    _on_join()


# ---------------------------------------------------------------- кнопки

func _on_host() -> void:
    if not _read_port():
        return
    if NetworkManager.host_game(NetworkManager.port):
        _say(Lang.t("net_hosting") % NetworkManager.port)
    else:
        _say(Lang.t("net_host_fail"))
    _refresh_lobby()


func _on_join() -> void:
    if not _read_port():
        return
    var ip := _ip_edit.text.strip_edges()
    if ip == "":
        # Раньше пустой IP молча превращался в 127.0.0.1 — игрок подключался к
        # самому себе и видел «не удалось подключиться». Теперь говорим прямо.
        _say(Lang.t("net_need_ip"))
        return
    # v46: можно вставить адрес целиком — «100.1.2.3:27015» или имя хоста
    var parsed := NetworkManager.split_address(ip, NetworkManager.port)
    var host := String(parsed[0])
    var p := int(parsed[1])
    if p >= 1024 and p <= 65535:
        NetworkManager.port = p
        if _port_edit != null:
            _port_edit.text = str(p)
    if NetworkManager.join_game(host, NetworkManager.port):
        _say(Lang.t("net_connecting"))
        _join_t = NetworkManager.join_timeout_seconds
    else:
        _say(Lang.t("net_join_fail"))
    _refresh_lobby()


## v46: скопировать «мой адрес для друга» в буфер обмена.
func _on_copy_addr() -> void:
    var addr := NetworkManager.best_join_address()
    if DisplayServer.get_name() != "headless":
        DisplayServer.clipboard_set(addr)
    _say(Lang.t("net_copied") % addr)


## v47: вставить адрес хоста из буфера и сразу подключиться (телефону удобнее,
## чем набирать «100.123.202.1» пальцем).
func _on_paste_addr() -> void:
    var txt := ""
    if DisplayServer.get_name() != "headless":
        txt = DisplayServer.clipboard_get()
    if not _apply_pasted_address(txt):
        _say(Lang.t("net_paste_empty"))
        return
    _on_join()


## Разобрать текст из буфера и заполнить поля. Понимает и голый адрес, и строку
## вида «мой адрес: 100.1.2.3:27015 — заходи». true — адрес найден.
func _apply_pasted_address(txt: String) -> bool:
    var token := _pick_address_token(txt)
    if token == "":
        return false
    var parsed := NetworkManager.split_address(token, NetworkManager.port)
    var host := String(parsed[0]).strip_edges()
    if host == "":
        return false
    _ip_edit.text = host
    var p := int(parsed[1])
    if p >= 1024 and p <= 65535 and _port_edit != null:
        _port_edit.text = str(p)
        NetworkManager.port = p
    return true


## Найти в произвольном тексте адрес: «100.1.2.3», «100.1.2.3:27015», имя хоста.
func _pick_address_token(txt: String) -> String:
    var clean := txt.replace(",", " ").replace("\n", " ").replace("\t", " ")
    for raw in clean.split(" "):
        var t := String(raw).strip_edges()
        while t.begins_with("(") or t.begins_with("[") or t.begins_with("«"):
            t = t.substr(1)
        while t.ends_with(")") or t.ends_with("]") or t.ends_with("»") \
                or t.ends_with(".") or t.ends_with("!"):
            t = t.substr(0, t.length() - 1)
        if t.length() < 4:
            continue
        var host := String(NetworkManager.split_address(t, NetworkManager.port)[0])
        if host.is_valid_ip_address():
            return t
        # имя хоста: буква/цифра, точка, дефис; хотя бы одна точка, без «://»
        if host.contains(".") and not host.contains("://") and not host.begins_with(".") \
                and host.length() <= 253:
            var ok := true
            for ch in host:
                if not (ch.is_valid_identifier() or ch == "." or ch == "-"):
                    ok = false
                    break
            if ok:
                return t
    return ""


func _read_port() -> bool:
    var p := int(_port_edit.text.strip_edges())
    if p < 1024 or p > 65535:
        _say(Lang.t("net_bad_port"))
        return false
    NetworkManager.port = p
    return true


func _on_lan() -> void:
    if not _read_port():
        return
    NetworkManager.scan_lan()
    _say(Lang.t("net_scanning"))


## Проверка адреса хоста: отвечает ли он на UDP-запрос (v43).
func _on_probe() -> void:
    if not _read_port():
        return
    var ip := _ip_edit.text.strip_edges()
    if ip == "":
        _say(Lang.t("net_probe_need_ip"))
        return
    NetworkManager.probe_host(String(NetworkManager.split_address(ip, NetworkManager.port)[0]))
    _refresh_lobby()


func _probe_line() -> String:
    match String(NetworkManager.probe_state):
        "searching":
            return Lang.t("net_probe_wait")
        "ok":
            return Lang.t("net_probe_ok") % NetworkManager.probe_ip
        "fail":
            var txt := Lang.t("net_probe_fail") % NetworkManager.probe_ip
            # v44: частая причина — устройства в разных подсетях/на мобильном
            if _subnet_differs(NetworkManager.probe_ip):
                txt += " · " + Lang.t("net_other_subnet")
            return txt
    return ""


## Мой адрес и адрес хоста в разных подсетях? (192.168.1.x против 10.x и т.п.)
## v46: скобки/порт/имя хоста не мешают — берём только IP.
func _subnet_differs(ip: String) -> bool:
    var host := String(NetworkManager.split_address(ip, NetworkManager.port)[0])
    var mine := NetworkManager.lan_ip_text().split(".")
    var theirs := host.split(".")
    if mine.size() != 4 or theirs.size() != 4:
        return false
    return int(mine[0]) != int(theirs[0]) or int(mine[1]) != int(theirs[1]) \
            or int(mine[2]) != int(theirs[2])


## Автопоиск при открытии лобби. Не трогаем UDP, если уже хостим: scan_lan()
## перебиндивает сокет и сломал бы ответы на поиск у хоста.
func _auto_scan() -> void:
    if not active or NetworkManager.is_online():
        return
    _on_lan()


func _on_ready() -> void:
    NetworkManager.set_ready(true)


func _on_start() -> void:
    if not NetworkManager.can_start():
        _say(Lang.t("net_need_ready"))
        return
    var data := {"enemy_name": _remote_name(1), "hp": 120.0, "rounds": 1,
            "round_time": 90.0}
    if not NetworkManager.start_match(data):
        _say(Lang.t("net_need_ready"))


func _on_leave() -> void:
    nm_cleanup()
    _show_lobby()
    _status.text = Lang.t("net_offline")


## v45: «В МЕНЮ» из лобби. Раньше единственный выход был Esc — на телефоне его нет.
func _on_back_menu() -> void:
    _end_net("", true)


func _remote_name(host_id: int) -> String:
    for id in NetworkManager.players:
        if int(id) != host_id:
            return String(NetworkManager.players[id].get("name", "СОПЕРНИК"))
    return "СОПЕРНИК"


func _say(text: String) -> void:
    _msg_lbl.text = text
    _msg_t = 3.0


# ---------------------------------------------------------------- матч

func _on_match_started(data: Dictionary) -> void:
    # кооп-матч ведёт CoopLobby; PvP-модуль его не трогает
    if NetworkManager.mode_is_coop():
        return
    _begin_fight(data)


func _begin_fight(data: Dictionary) -> void:
    is_host = NetworkManager.is_host
    ui.visible = false
    active = true
    fight_active = true
    main.net_mode = true
    main.demo = true
    main.no_cash = true
    main.no_ai = true
    main._start_fight()
    main.rounds_total = maxi(1, int(data.get("rounds", 1)))
    main.round_num = 1
    main.round_time = float(data.get("round_time", 90.0))
    main.timer = main.round_time
    main.arena_active = false
    # одинаковый соперник у обеих сторон
    if not is_host:
        var hp := float(data.get("hp", 120.0))
        main.enemy.reset(Vector3(0.0, 0.0, -1.9), hp)
        main.enemy.max_hp = hp
        main.enemy.hp = hp
        main.hud.set_opponent_name(String(data.get("enemy_name", "СОПЕРНИК")))
    else:
        main.hud.set_opponent_name(_remote_name(1))
    main.enemy_get_up_delay = 999.0
    latest_intent = {}
    _touch_punch = ""
    _touch_dodge = false
    _touch_getup = false
    _test_touch = {}
    _host_snap_t = 0.0
    _client_snap_t = 0.0
    _enemy_down_t = 0.0
    _last_downed = ""
    _remote_pos = main.enemy.position
    _rem_prev = main.enemy.position
    _rem_cur = main.enemy.position
    _rem_t = 0.0
    _rem_has = false
    main._face_each_other()
    main._set_state(STATE_FIGHT)
    _say(Lang.t("net_match_start"))
    print("NET матч начался, роль=", "host" if is_host else "client")


func tick_fight(delta: float) -> void:
    if not fight_active:
        return
    if is_host:
        _tick_host(delta)
    else:
        _tick_client(delta)


func _tick_host(delta: float) -> void:
    _apply_remote_intent(delta)
    main._tick_fight(delta)
    _host_down_check(delta)
    var dn := "c" if main.downed_who == main.enemy else (
            "h" if main.downed_who == main.player else "")
    if dn != _last_downed:
        _last_downed = dn
        if dn != "":
            NetworkManager.send_event("knock", {"who": dn})
    _host_snap_t += delta
    if _host_snap_t >= 1.0 / float(NetworkManager.snapshot_rate):
        _host_snap_t = 0.0
        NetworkManager.send_snapshot(_build_snapshot())
    if main.pending != "":
        fight_active = false


func _tick_client(delta: float) -> void:
    var intent := _read_intent()
    NetworkManager.send_intent(intent)
    # предсказание своего движения (main.player — наш боец)
    var mv: Array = intent.get("mv", [0.0, 0.0])
    var dir := Vector3(float(mv[0]), 0.0, float(mv[1]))
    if dir.length() > 0.01 and not main.player.ko and not main.player.fallen \
            and main.player.stun <= 0.0:
        main.player.drive(dir.normalized(), delta)
        main.player.look_at_target(main.player.position + dir.normalized())
    var kind := String(intent.get("punch", ""))
    if kind != "" and main.player.punch_kind == "":
        main._punch(main.player, main.enemy, kind)
    main.player.tick(delta)
    # v71: удалённый боец — интерполяция между двумя последними снапшотами.
    # Даёт постоянную скорость вместо «догоняния» и рывков на 20 Гц.
    if _rem_has:
        var snap_interval := 1.0 / maxf(1.0, float(NetworkManager.snapshot_rate))
        _rem_t = minf(_rem_t + delta, snap_interval * 2.0)
        var alpha := clampf(_rem_t / snap_interval, 0.0, 1.0)
        main.enemy.position = _rem_prev.lerp(_rem_cur, alpha)
    else:
        main.enemy.position = main.enemy.position.lerp(_remote_pos,
                clampf(delta * SNAP_INTERP * 10.0, 0.0, 1.0))
    main.enemy.tick(delta)
    main.timer = maxf(0.0, main.timer - delta)
    main._update_hud()


func _read_intent() -> Dictionary:
    if not test_intent.is_empty():
        return test_intent.duplicate(true)
    var dir := Vector3.ZERO
    var fwd: Vector3 = -main.cam.global_transform.basis.z
    fwd.y = 0.0
    fwd = fwd.normalized()
    var right: Vector3 = main.cam.global_transform.basis.x
    right.y = 0.0
    right = right.normalized()
    if profile.is_action_pressed("move_fwd"):
        dir += fwd
    if profile.is_action_pressed("move_back"):
        dir -= fwd
    if profile.is_action_pressed("move_left"):
        dir -= right
    if profile.is_action_pressed("move_right"):
        dir += right
    # v39: на телефоне — стик (движение относительно камеры), как в офлайне
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
        if profile.is_action_just_pressed(String(pair[0])):
            punch = String(pair[1])
    if _touch_punch != "":
        punch = _touch_punch
        _touch_punch = ""
    var dodge := profile.is_action_just_pressed("dodge") or _touch_dodge
    if _touch_dodge:
        _touch_dodge = false
    var get_up := profile.is_action_just_pressed("get_up") or _touch_getup
    if _touch_getup:
        _touch_getup = false
    return {"mv": [dir.x, dir.z], "punch": punch,
            "block": profile.is_action_pressed("block") or bool(touch_state.get("block", false)),
            "dodge": dodge, "get_up": get_up}


# ---------------------------------------------------------------- тач (v39)

## Текущий тач-ввод: стик и блок. В тестах подменяется через _test_touch.
func _touch_input() -> Dictionary:
    if not _test_touch.is_empty():
        return _test_touch
    if main == null or main.touch == null:
        return {}
    if not bool(main.touch.active):
        return {}
    return {"move": main.touch.move, "block": bool(main.touch.block)}


## Удар с тач-кнопки на клиенте: уйдёт интентом хосту (он авторитетен).
func touch_punch(kind: String) -> void:
    if not fight_active or NetworkManager.is_host:
        return
    var body := false
    if main != null and main.touch != null:
        body = bool(main.touch.body_mode)
    _touch_punch = ("body_" + kind) if body else kind


func touch_dodge() -> void:
    if not fight_active or NetworkManager.is_host:
        return
    _touch_dodge = true
    # локальное предсказание, чтобы уклон был виден сразу, а не через пинг
    if main != null and main.player != null and not main.player.evading \
            and main.player.stun <= 0.001 and not main.player.ko \
            and not main.player.fallen and not main.player.is_down():
        main.player.try_dodge()


func touch_getup() -> void:
    if not fight_active or NetworkManager.is_host:
        return
    _touch_getup = true


## «II» в сетевом бою: у хоста — засчитать поражение и закрыть матч штатно,
## у клиента — выйти (хост увидит отключение и тоже закроет матч).
func touch_pause() -> void:
    if not fight_active:
        return
    if NetworkManager.is_host:
        main._end_fight("lose", false)
    else:
        _defer_end(Lang.t("net_lost"))


## Отладочный тач-ввод для автотестов: {"move": Vector2, "block": bool}
func debug_touch_input(move: Vector2, block: bool) -> void:
    if move.length() < 0.01 and not block:
        _test_touch = {}
    else:
        _test_touch = {"move": move, "block": block}


## Хост применяет интент клиента к main.enemy (фигура клиента).

func _apply_remote_intent(delta: float) -> void:
    if latest_intent.is_empty():
        return
    var f: Node3D = main.enemy
    if f.ko or f.fallen or main.pending != "":
        return
    var mv: Array = latest_intent.get("mv", [0.0, 0.0])
    var dir := Vector3(float(mv[0]), 0.0, float(mv[1]))
    if dir.length() > 0.01 and f.stun <= 0.0:
        f.drive(dir.normalized(), delta)
        f.look_at_target(f.position + dir.normalized())
    f.blocking = bool(latest_intent.get("block", false)) and f.stun <= 0.001
    if bool(latest_intent.get("dodge", false)):
        f.try_dodge()
    var kind := String(latest_intent.get("punch", ""))
    if kind != "":
        latest_intent["punch"] = ""
        main._punch(main.enemy, main.player, kind)
    # вставание: клиент жмёт Space, хост копит прогресс его фигуре
    if main.downed_active and main.downed_who == main.enemy:
        if bool(latest_intent.get("get_up", false)):
            latest_intent["get_up"] = false
            main.enemy.get_up_press()
            var prog: float = main.enemy.get_up_progress
            main.hud.set_mash(true, prog,
                    int(round(prog * float(main.enemy.get_up_presses))),
                    int(main.enemy.get_up_presses))
            if prog >= 0.999:
                main._start_get_up(main.enemy)
                _enemy_down_t = 0.0


func _host_down_check(delta: float) -> void:
    if main.downed_active and main.downed_who == main.enemy:
        _enemy_down_t += delta
        var left: float = maxf(0.0, REMOTE_DOWN_LIMIT - _enemy_down_t)
        main.hud.set_downed_time(left)
        if _enemy_down_t >= REMOTE_DOWN_LIMIT:
            main._end_fight("win", true)
        return


func _build_snapshot() -> Dictionary:
    return {"h": _fighter_state(main.player), "c": _fighter_state(main.enemy),
            "t": main.timer, "r": main.round_num,
            "downed": "c" if main.downed_who == main.enemy else (
                    "h" if main.downed_who == main.player else ""),
            "down_t": _enemy_down_t, "pending": main.pending}


func _fighter_state(f: Node3D) -> Dictionary:
    # v71: убрали "glv" — перчатка в снапшоте не использовалась клиентом,
    # это лишние ~60 байт на каждого бойца в каждом пакете.
    return {"p": [f.position.x, f.position.y, f.position.z],
            "ry": f.rotation.y, "hp": f.hp, "max": f.max_hp,
            "st": f.stamina, "pk": String(f.punch_kind), "pt": f.punch_t,
            "pd": f.punch_dur, "ks": int(f.knock_state), "kt": f.knock_t,
            "fal": f.fallen, "blk": f.blocking, "ko": f.ko,
            "kd": int(f.knockdown_count),
            # прогресс «вставания»: клиент рисует кольцо на кнопке «ВСТАТЬ»
            "gu": float(f.get_up_progress)}


func _on_snapshot(data: Dictionary) -> void:
    if is_host or not fight_active:
        return
    var own: Dictionary = data.get("c", {})
    var rem: Dictionary = data.get("h", {})
    # своё состояние — коррекция предсказания
    if not own.is_empty():
        var target := Vector3(float(own["p"][0]), float(own["p"][1]), float(own["p"][2]))
        if main.player.position.distance_to(target) > CORRECT_SNAP:
            main.player.position = target
        else:
            main.player.position = main.player.position.lerp(target, 0.5)
        main.player.hp = float(own["hp"])
        main.player.stamina = float(own["st"])
        main.player.ko = bool(own["ko"])
        main.player.fallen = bool(own["fal"])
        main.player.knock_state = int(own["ks"])
        main.player.knock_t = float(own["kt"])
        main.player.knockdown_count = int(own["kd"])
        main.player.get_up_progress = float(own.get("gu", main.player.get_up_progress))
    # удалённый — цель для интерполяции (две последние позиции, см. _tick_client)
    if not rem.is_empty():
        _remote_pos = Vector3(float(rem["p"][0]), float(rem["p"][1]), float(rem["p"][2]))
        if not _rem_has:
            _rem_prev = _remote_pos
            _rem_cur = _remote_pos
            _rem_has = true
        else:
            _rem_prev = _rem_cur
            _rem_cur = _remote_pos
        _rem_t = 0.0
        main.enemy.hp = float(rem["hp"])
        main.enemy.max_hp = float(rem["max"])
        main.enemy.stamina = float(rem["st"])
        main.enemy.ko = bool(rem["ko"])
        main.enemy.fallen = bool(rem["fal"])
        main.enemy.blocking = bool(rem["blk"])
        main.enemy.punch_kind = String(rem["pk"])
        main.enemy.punch_t = float(rem["pt"])
        main.enemy.punch_dur = float(rem["pd"])
        main.enemy.knock_state = int(rem["ks"])
        main.enemy.knock_t = float(rem["kt"])
        main.enemy.knockdown_count = int(rem["kd"])
        main.enemy.rotation.y = float(rem["ry"])
    main.timer = float(data.get("t", main.timer))
    main.round_num = int(data.get("r", main.round_num))
    # UI подсказок нокдауна
    var downed := String(data.get("downed", ""))
    if downed == "c":
        main.hud.set_downed(true, Lang.t("net_you_down"))
        main.hud.set_downed_time(maxf(0.0, REMOTE_DOWN_LIMIT - float(data.get("down_t", 0.0))))
        # v39: на телефоне своя кнопка «ВСТАТЬ» с живым прогрессом
        if main.touch_ui and main.touch != null:
            main.touch.set_downed(true)
            var need := maxi(1, int(main.player.get_up_presses))
            var prog := float(main.player.get_up_progress)
            main.touch.set_mash(prog, int(round(prog * float(need))), need)
    else:
        main.hud.set_downed(false)
        if main.touch_ui and main.touch != null:
            main.touch.set_downed(false)
    main._update_hud()


func _on_intent(id: int, data: Dictionary) -> void:
    latest_intent = data


func _on_net_event(kind: String, data: Dictionary) -> void:
    if is_host:
        return
    match kind:
        "end":
            if fight_active:
                _show_result(String(data.get("pending", "")))
        "disconnect":
            _defer_end(Lang.t("net_lost"))
        "knock":
            _say(Lang.t("net_knock"))


func on_match_end(pending: String) -> void:
    if not fight_active:
        return
    fight_active = false
    NetworkManager.send_event("end", {"pending": pending})
    _show_result(pending)


func _show_result(pending: String) -> void:
    active = true
    ui.visible = true
    _backdrop.visible = true
    _title.visible = false
    _status.visible = false
    _players_lbl.visible = false
    _ping_lbl.visible = false
    _host_btn.visible = false
    _join_btn.visible = false
    _lan_btn.visible = false
    _probe_btn.visible = false
    _copy_btn.visible = false
    _paste_btn.visible = false
    _addr_lbl.visible = false
    _ip_edit.visible = false
    _port_edit.visible = false
    _ready_btn.visible = false
    _start_btn.visible = false
    _leave_btn.visible = false
    _disc_btn.visible = false
    _clear_lan_buttons()
    var win := pending == "win" or pending == "timewin" or pending == "ringout"
    var lose := pending == "lose" or pending == "timelose" or pending == "ringoutlose"
    _result_title.visible = true
    _result_title.text = Lang.t("net_win") if win else (Lang.t("net_lose") if lose
            else Lang.t("net_draw"))
    _result_body.visible = true
    _result_body.text = Lang.t("net_no_save")
    _result_menu.visible = true
    _result_rematch.visible = is_host
    main.net_mode = true


func _end_net(message: String, to_menu: bool = true) -> void:
    fight_active = false
    active = false
    ui.visible = false
    nm_cleanup()
    if main != null:
        main.net_mode = false
        main.demo = false
        main.no_cash = false
        main.no_ai = false
        main.enemy_get_up_delay = 2.0
        main._reset_fight()
        main._set_state(STATE_MENU)
    if message != "":
        print("NET выход: ", message)
    if to_menu:
        pass


func _defer_end(message: String) -> void:
    if _ending:
        return
    _ending = true
    call_deferred("_deferred_end", message)


func _deferred_end(message: String) -> void:
    _ending = false
    _end_net(message, true)


func _on_result_menu() -> void:
    _end_net("", true)


func _on_result_rematch() -> void:
    if not NetworkManager.is_host:
        return
    _on_start()


# ---------------------------------------------------------------- сигналы сети

func _on_peer_connected(id: int) -> void:
    _refresh_lobby()
    _say(Lang.t("net_connected"))


func _on_peer_disconnected(id: int) -> void:
    if fight_active:
        _defer_end(Lang.t("net_lost"))
        return
    _refresh_lobby()
    _say(Lang.t("net_player_left"))


func _on_conn_failed() -> void:
    NetworkManager.log_net("клиент: connection_failed от лобби")
    if NetworkManager.join_timed_out:
        NetworkManager.join_timed_out = false
        _join_t = 0.0
        var secs := int(round(float(NetworkManager.join_timeout_seconds)))
        _say(("Нет ответа за %d с: проверь IP/порт, одну сеть, UPnP/проброс "
                + "порта и брандмауэр на ПК хоста") % secs
                if not Lang.is_en() else
                ("No reply in %d s: check IP/port, same network, UPnP/port "
                + "forwarding and host PC firewall") % secs)
    else:
        _say(Lang.t("net_join_fail"))
    _refresh_lobby()


func _on_server_lost() -> void:
    if fight_active or active:
        _defer_end(Lang.t("net_lost"))


# ---------------------------------------------------------------- ввод

func handle_key(event: InputEvent) -> String:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return ""
    if (event.keycode == KEY_ESCAPE):
        if fight_active:
            return ""
        _end_net("", true)
        return "menu"
    return ""


func handle_touch(_pos: Vector2) -> String:
    return ""


# ---------------------------------------------------------------- тесты

## Для --nettest: поднять хост на порту.
func debug_host(port: int) -> bool:
    NetworkManager.port = port
    if not NetworkManager.host_game(port):
        return false
    _show_lobby()
    return true


## Для --nettest: подключиться к localhost.
func debug_join(ip: String, port: int) -> bool:
    NetworkManager.port = port
    return NetworkManager.join_game(ip, port)


## Для --nettest: клиент шлёт синтетический интент.
func debug_send_intent(dx: float, dz: float, punch: String = "") -> void:
    test_intent = {"mv": [dx, dz], "punch": punch, "block": false,
            "dodge": false, "get_up": false}


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
    ui = CanvasLayer.new()
    ui.layer = 9
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
    _title = _mk_label(Vector2(0, 40), Vector2(1280, 54), 36, Color(0.98, 0.86, 0.45))
    _title.text = Lang.t("net_title")
    _status = _mk_label(Vector2(0, 104), Vector2(1280, 26), 17, Color(0.80, 0.84, 0.92))
    _players_lbl = _mk_label(Vector2(330, 188), Vector2(620, 90), 16, Color(0.92, 0.94, 0.98))
    _players_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _ping_lbl = _mk_label(Vector2(330, 284), Vector2(620, 24), 15, Color(0.72, 0.78, 0.88))
    _ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _msg_lbl = _mk_label(Vector2(330, 620), Vector2(620, 30), 16, Color(0.95, 0.80, 0.40))
    # подсказка «кто хост — тот диктует IP»: раньше её не было, и на телефоне
    # поле с 127.0.0.1 молча уводило подключение в никуда
    _hint_lbl = _mk_label(Vector2(0, 660), Vector2(1280, 26), 14, Color(0.62, 0.68, 0.78))
    _hint_lbl.text = Lang.t("net_lobby_hint")
    _ext_lbl = _mk_label(Vector2(0, 132), Vector2(1280, 26), 15, Color(0.62, 0.90, 0.72))
    _ext_lbl.text = ""
    # v47: крупная строка «адрес для телефона/друга» — VPN-адрес, по которому
    # телефон с мобильным интернетом подключится к ПК-хосту.
    _addr_lbl = _mk_label(Vector2(0, 158), Vector2(1280, 24), 16, Color(0.98, 0.86, 0.45))
    _addr_lbl.text = ""
    _ip_edit = LineEdit.new()
    _ip_edit.position = Vector2(330, 320)
    _ip_edit.size = Vector2(420, 40)
    _ip_edit.text = ""
    _ip_edit.placeholder_text = Lang.t("net_ip_hint")
    _ip_edit.add_theme_font_size_override("font_size", 16)
    _root.add_child(_ip_edit)
    _ip_edit.text_changed.connect(func(_t: String) -> void: _refresh_lobby())
    _port_edit = LineEdit.new()
    _port_edit.position = Vector2(770, 320)
    _port_edit.size = Vector2(180, 40)
    _port_edit.text = str(NetworkManager.port)
    _port_edit.add_theme_font_size_override("font_size", 16)
    _root.add_child(_port_edit)
    _host_btn = _mk_button(Vector2(330, 372), Vector2(300, 44))
    _host_btn.text = Lang.t("net_host")
    _host_btn.pressed.connect(_on_host)
    _join_btn = _mk_button(Vector2(650, 372), Vector2(300, 44))
    _join_btn.text = Lang.t("net_join")
    _join_btn.pressed.connect(_on_join)
    _lan_btn = _mk_button(Vector2(330, 424), Vector2(300, 40))
    _lan_btn.text = Lang.t("net_lan")
    _lan_btn.pressed.connect(_on_lan)
    # v43: проверить адрес хоста (ответит/не ответит) — отделить сеть от порта
    _probe_btn = _mk_button(Vector2(650, 424), Vector2(300, 40))
    _probe_btn.text = Lang.t("net_probe")
    _probe_btn.pressed.connect(_on_probe)
    _copy_btn = _mk_button(Vector2(330, 474), Vector2(620, 38))
    _copy_btn.text = Lang.t("net_copy_addr")
    _copy_btn.pressed.connect(_on_copy_addr)
    # v47: клиенту (телефону) проще вставить адрес из буфера одной кнопкой
    _paste_btn = _mk_button(Vector2(330, 474), Vector2(620, 38))
    _paste_btn.text = Lang.t("net_paste_addr")
    _paste_btn.pressed.connect(_on_paste_addr)
    _ready_btn = _mk_button(Vector2(330, 520), Vector2(300, 48))
    _ready_btn.text = Lang.t("net_ready_on")
    _ready_btn.pressed.connect(_on_ready)
    _start_btn = _mk_button(Vector2(650, 520), Vector2(300, 48))
    _start_btn.text = Lang.t("net_start")
    _start_btn.pressed.connect(_on_start)
    # T8: кнопка «назад» — слева сверху, как в HUD и остальных экранах.
    # v71/task-35: размер берём у HUD (тач-режим даёт 230×96), иначе --overlaptest
    # видит два разных размера «назад» на net/coop экранах.
    var back_size := Vector2(148, 42)
    if main != null and main.get("hud") != null \
            and main.hud.has_method("back_button_size"):
        back_size = main.hud.back_button_size()
    _leave_btn = _mk_button(Vector2(18, 12), back_size)
    _leave_btn.text = Lang.t("back_btn")
    _leave_btn.add_theme_font_size_override("font_size", 16)
    _leave_btn.pressed.connect(_on_back_menu)
    _disc_btn = _mk_button(Vector2(330, 578), Vector2(300, 40))
    _disc_btn.text = Lang.t("net_disconnect")
    _disc_btn.pressed.connect(_on_leave)
    _result_title = _mk_label(Vector2(0, 260), Vector2(1280, 60), 38, Color(0.98, 0.86, 0.45))
    _result_body = _mk_label(Vector2(0, 336), Vector2(1280, 30), 18, Color(0.86, 0.90, 0.98))
    _result_menu = _mk_button(Vector2(420, 420), Vector2(200, 52))
    _result_menu.text = Lang.t("net_to_menu")
    _result_menu.pressed.connect(_on_result_menu)
    _result_rematch = _mk_button(Vector2(660, 420), Vector2(200, 52))
    _result_rematch.text = Lang.t("net_rematch")
    _result_rematch.pressed.connect(_on_result_rematch)


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
    b.add_theme_font_size_override("font_size", 17)
    _root.add_child(b)
    return b
