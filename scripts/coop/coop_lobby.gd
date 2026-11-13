class_name CoopLobby
extends Node
## Кооператив до 4 игроков, часть 1a: сетевое лобби на 4 слота.
## Обобщает лобби PvP 1v1 из scripts/net/net_fight.gd: полноэкранный UI на
## CanvasLayer (процедурные Control), данные — из autoload NetworkManager.
## Четыре слота P1..P4: ник, пинг, готовность, роль (если enable_roles), статус.
## Хост: «СОЗДАТЬ КООП», «НАЧАТЬ БОЙ», «КИКНУТЬ», «ЗАВЕРШИТЬ МАТЧ».
## Все: «Я ГОТОВ», «ПОКИНУТЬ», «ПОДКЛЮЧИТЬСЯ», «НАЙТИ В LAN».
## Бой в 4P здесь ещё не запускается — это задача task-18 (часть 2).

const Lang = preload("res://scripts/lang.gd")
const ROLES := ["TANK", "DPS", "SUPPORT", "SCOUT"]

signal nav(to: String)

## Роли в лобби (по умолчанию выключены: часть 1a — только слоты).
@export var enable_roles := false
## Если true — при выборе роли пропускаются уже занятые другими игроками.
@export var unique_roles := false
## Минимум игроков для «НАЧАТЬ БОЙ» (учитывая хоста).
@export var min_players := 2
## Максимум слотов лобби (не больше NetworkManager.max_players).
@export var max_players := 4
## Разрешить новым игрокам подключаться после старта матча (для части 2).
@export var allow_drop_in := true
## Разрешить игрокам покидать лобби/матч (хост завершает сессию всегда).
@export var allow_drop_out := true

var main: Node
var active := false
var sel_slot := 1

var _msg := ""
var _msg_t := 0.0
var _exit_t := -1.0
## Таймаут подключения: если за 8 с не соединились — сказать игроку, а не висеть.
var _join_t := 0.0

# --- UI
var ui: CanvasLayer
var _root: Control
var _backdrop: ColorRect
var _title: Label
var _status: Label
var _ping_lbl: Label
var _msg_lbl: Label
var _hint_lbl: Label
var _slot_btns: Array[Button] = []
var _host_btn: Button
var _join_btn: Button
var _lan_btn: Button
var _ready_btn: Button
var _start_btn: Button
var _role_btn: Button
var _kick_btn: Button
var _end_btn: Button
var _leave_btn: Button
var _ip_edit: LineEdit
var _port_edit: LineEdit
## v71: «адрес для друга» (интернет/UPnP/VPN), копирование/вставка и проверка адреса.
var _ext_lbl: Label
var _copy_btn: Button
var _paste_btn: Button
var _probe_btn: Button
var _lan_list: Array[Button] = []


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
    NetworkManager.match_ended.connect(_on_match_ended)
    NetworkManager.kicked.connect(_on_kicked)
    NetworkManager.role_changed.connect(_on_role_changed)
    NetworkManager.lan_found.connect(_on_lan_found)
    NetworkManager.upnp_updated.connect(_refresh_lobby)


# ---------------------------------------------------------------- открыть/закрыть

func open_lobby() -> void:
    active = true
    sel_slot = 1
    _msg = ""
    _msg_t = 0.0
    _exit_t = -1.0
    _join_t = 0.0
    # пересчитать LAN IP при каждом открытии: за время игры мог включиться VPN/смениться Wi-Fi
    NetworkManager.lan_ip = ""
    nm_cleanup()
    ui.visible = true
    _show_lobby()
    _status.text = Lang.t("coop_offline")


func close() -> void:
    active = false
    _exit_t = -1.0
    nm_cleanup()
    if ui != null:
        ui.visible = false


func show_lobby() -> void:
    active = true
    if ui != null:
        ui.visible = true
    _show_lobby()


func tick_lobby(delta: float) -> void:
    if _msg_t > 0.0:
        _msg_t = maxf(0.0, _msg_t - delta)
        if _msg_t <= 0.0:
            _msg_lbl.text = ""
    if _exit_t > 0.0:
        _exit_t -= delta
        if _exit_t <= 0.0:
            _exit_t = -1.0
            _leave_to_menu()
            return
    # T-coop: не висеть вечно в «подключаемся…», если IP/порт неверные или
    # соединение блокирует firewall. Таймер ставим и для join, начатого не через
    # кнопку (тесты/повтор), — по факту «режим выставлен, но связи нет».
    if _join_t <= 0.0 and NetworkManager.mode != "" \
            and NetworkManager.my_id == 0 and not NetworkManager.is_online():
        _join_t = NetworkManager.join_timeout_seconds
    if _join_t > 0.0:
        if NetworkManager.is_online():
            _join_t = 0.0
        else:
            _join_t -= delta
            if _join_t <= 0.0:
                _join_t = 0.0
                NetworkManager.leave_game()
                var secs := int(round(float(NetworkManager.join_timeout_seconds)))
                _say(("Не удалось подключиться за %d с: проверь IP/порт, что вы"
                        + " в одной Wi-Fi сети и разрешён доступ в брандмауэре") % secs
                        if not Lang.is_en() else
                        ("No connection in %d s: check IP/port, same Wi-Fi and firewall")
                        % secs)
                _refresh_lobby()
    if active:
        _refresh_lobby()


func nm_cleanup() -> void:
    if NetworkManager.is_online():
        NetworkManager.leave_game()


func _leave_to_menu() -> void:
    active = false
    ui.visible = false
    nm_cleanup()
    nav.emit("menu")


# ---------------------------------------------------------------- данные лобби

func _show_lobby() -> void:
    _backdrop.visible = true
    _title.visible = true
    _status.visible = true
    _ping_lbl.visible = true
    _msg_lbl.visible = true
    _hint_lbl.visible = true
    _host_btn.visible = true
    _join_btn.visible = true
    _lan_btn.visible = true
    _ip_edit.visible = true
    _port_edit.visible = true
    _ready_btn.visible = true
    _leave_btn.visible = true
    _start_btn.visible = NetworkManager.is_host
    _kick_btn.visible = NetworkManager.is_host
    _role_btn.visible = enable_roles
    _end_btn.visible = NetworkManager.is_host and NetworkManager.in_match
    for b in _slot_btns:
        b.visible = true
    _clear_lan_buttons()
    _refresh_lobby()


## Состояние слотов для UI и тестов: [{slot, id, name, ready, role, ping, alive,
## eliminated, empty}]. Использует только данные NetworkManager.
func debug_slots() -> Array:
    var out: Array = []
    var slots: Array = NetworkManager.lobby_slots()
    for i in slots.size():
        var p: Dictionary = slots[i]
        var row := {"slot": i + 1, "id": int(p.get("id", 0)),
                "name": String(p.get("name", "")),
                "ready": bool(p.get("ready", false)),
                "role": String(p.get("role", "DPS")),
                "ping": int(p.get("ping", 0)),
                "alive": bool(p.get("alive", true)),
                "eliminated": bool(p.get("eliminated", false)),
                "empty": p.is_empty()}
        out.append(row)
    return out


## Краткая сводка видимого UI — для автотестов (кнопки, 4 слота, тексты).
func debug_ui_summary() -> Dictionary:
    var btns: Array = []
    for c in _root.get_children():
        if c is Button and c.visible:
            btns.append(String((c as Button).text))
    var labels := 0
    for c in _root.get_children():
        if c is Label and c.visible:
            labels += 1
    return {"buttons": btns, "slots": _slot_btns.size(),
            "slot_texts": _slot_btns.map(func(b: Button) -> String: return b.text),
            "labels": labels, "visible": ui.visible,
            # T-coop: проверка, что поле IP пустое (не 127.0.0.1) и есть подсказка,
            # а в статусе хоста виден его LAN IP.
            "ip_text": _ip_edit.text, "ip_placeholder": _ip_edit.placeholder_text,
            "status_text": _status.text}


func _slot_line(n: int, p: Dictionary) -> String:
    if p.is_empty():
        return "P%d · %s" % [n, Lang.t("coop_slot_empty")]
    var rdy := Lang.t("coop_ready_word") if bool(p.get("ready", false)) \
            else Lang.t("coop_not_ready")
    var st := Lang.t("coop_slot_alive")
    if bool(p.get("eliminated", false)) or not bool(p.get("alive", true)):
        st = Lang.t("coop_slot_left")
    var host_mark := ""
    if int(p.get("id", 0)) == 1:
        host_mark = " · " + Lang.t("coop_host_word")
    var line := "P%d%s · %s · %s · ping %d мс · %s" % [n, host_mark,
            String(p.get("name", "")), rdy, int(p.get("ping", 0)), st]
    if enable_roles:
        line += " · " + String(p.get("role", "DPS"))
    return line


func _refresh_lobby() -> void:
    if not active or ui == null or not ui.visible:
        return
    var rows: Array = debug_slots()
    for i in _slot_btns.size():
        var row: Dictionary = rows[i] if i < rows.size() else {}
        _slot_btns[i].text = _slot_line(i + 1, row)
        var selected: bool = sel_slot == i + 1
        var col := Color(0.92, 0.94, 0.98)
        if bool(row.get("empty", true)):
            col = Color(0.55, 0.60, 0.70)
        if selected:
            col = Color(0.98, 0.86, 0.45)
        _slot_btns[i].add_theme_color_override("font_color", col)
    if not NetworkManager.is_online():
        _status.text = Lang.t("coop_offline")
    elif NetworkManager.is_host:
        # T-coop: хост видит все свои адреса (LAN и VPN-мосты) — их и диктует.
        _status.text = Lang.t("coop_hosting") % [NetworkManager.port,
                NetworkManager.player_count(), NetworkManager.session_max] \
                + "  ·  " + NetworkManager.addresses_text()
        # v40: для игры из разных сетей — внешний IP и статус проброса порта
        var ext := NetworkManager.internet_hint_text()
        if ext != "":
            _status.text += "  ·  " + ext
    else:
        _status.text = Lang.t("coop_connected") if NetworkManager.my_id != 0 \
                else Lang.t("coop_connecting")
    _ping_lbl.text = ("%s %d мс" % [Lang.t("net_ping"), int(NetworkManager.ping)]) \
            if NetworkManager.ping > 0 else ""
    # v71: хост видит «адрес для друга» (UPnP/интернет/VPN) и статус проброса;
    # гость — результат проверки адреса. Кнопки копирования/вставки — по роли.
    if _ext_lbl != null:
        if NetworkManager.is_host:
            _ext_lbl.text = NetworkManager.internet_hint_text()
        else:
            _ext_lbl.text = _probe_line()
    if _copy_btn != null:
        _copy_btn.visible = NetworkManager.is_host
        _copy_btn.disabled = not NetworkManager.is_online()
    if _paste_btn != null:
        _paste_btn.visible = not NetworkManager.is_host
        _paste_btn.disabled = NetworkManager.is_online()
    if _probe_btn != null:
        _probe_btn.visible = not NetworkManager.is_host
        _probe_btn.disabled = NetworkManager.is_online() or _ip_edit.text.strip_edges() == ""
    var me: Dictionary = NetworkManager.players.get(NetworkManager.my_id, {})
    _ready_btn.text = Lang.t("coop_unready") if bool(me.get("ready", false)) \
            else Lang.t("coop_ready")
    _ready_btn.visible = not NetworkManager.in_match
    _start_btn.visible = NetworkManager.is_host and not NetworkManager.in_match
    _start_btn.disabled = not NetworkManager.can_start()
    _kick_btn.visible = NetworkManager.is_host and not NetworkManager.in_match
    _end_btn.visible = NetworkManager.is_host and NetworkManager.in_match
    _role_btn.visible = enable_roles and not NetworkManager.in_match
    var sel_id: int = NetworkManager.id_at_slot(sel_slot)
    _kick_btn.disabled = sel_id == 0 or sel_id == 1
    _role_btn.disabled = sel_slot < 1 or (not NetworkManager.is_host
            and sel_slot != NetworkManager.slot_of(NetworkManager.my_id))
    _host_btn.disabled = NetworkManager.is_online()
    _join_btn.disabled = NetworkManager.is_online()
    _lan_btn.disabled = NetworkManager.is_online()
    _ip_edit.editable = not NetworkManager.is_online()
    _port_edit.editable = not NetworkManager.is_online()
    _leave_btn.visible = allow_drop_out or NetworkManager.is_host
    _hint_lbl.text = "%s %d..%d" % [Lang.t("coop_min_players"), min_players,
            NetworkManager.session_max]


func _clear_lan_buttons() -> void:
    for b in _lan_list:
        b.queue_free()
    _lan_list.clear()


func _on_lan_found(servers: Array) -> void:
    if not active or not ui.visible:
        return
    _clear_lan_buttons()
    if servers.is_empty():
        _say(Lang.t("coop_no_servers"))
        return
    _say(Lang.t("coop_lan_found") % servers.size())
    for i in servers.size():
        var s: Dictionary = servers[i]
        var b := _mk_button(Vector2(960, 150 + i * 40), Vector2(300, 34))
        b.text = "%s:%d — %s" % [String(s["ip"]), int(s["port"]), String(s["name"])]
        b.add_theme_font_size_override("font_size", 13)
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
    NetworkManager.set_min_players(min_players)
    if NetworkManager.host_coop(NetworkManager.port, clampi(max_players, 2,
            NetworkManager.max_players)):
        _say(Lang.t("coop_hosting") % [NetworkManager.port,
                NetworkManager.player_count(), NetworkManager.session_max])
    else:
        _say(Lang.t("net_host_fail"))
    _refresh_lobby()


func _on_join() -> void:
    if not _read_port():
        return
    var text := _ip_edit.text.strip_edges()
    if text == "":
        _say(Lang.t("net_need_ip"))
        return
    # v71: гость может вставить адрес целиком «1.2.3.4:27015» или имя хоста.
    var parsed := NetworkManager.split_address(text, NetworkManager.port)
    var host := String(parsed[0]).strip_edges()
    var p := int(parsed[1])
    if host == "":
        _say(Lang.t("net_need_ip"))
        return
    if p < 1024 or p > 65535:
        _say(Lang.t("net_bad_port"))
        return
    NetworkManager.port = p
    if _port_edit != null:
        _port_edit.text = str(p)
    if NetworkManager.join_coop(host, p):
        _join_t = NetworkManager.join_timeout_seconds
        _say(Lang.t("coop_connecting"))
    else:
        _say(Lang.t("net_join_fail"))
    _refresh_lobby()


## v71: скопировать адрес для друга (хост). Для интернета это UPnP-внешний
## адрес, если проброс удался; иначе подсказка, что именно нужно открыть.
func _on_copy_addr() -> void:
    if not NetworkManager.is_host:
        return
    var addr := NetworkManager.best_join_address()
    var hint := NetworkManager.internet_hint_text()
    if addr == "":
        _say(hint if hint != "" else Lang.t("net_ext_manual") % [
                NetworkManager.port, NetworkManager.lan_ip_text()])
        return
    if DisplayServer.get_name() != "headless":
        DisplayServer.clipboard_set(addr)
    _say(Lang.t("net_copied") % addr)


## v71: вставить адрес хоста из буфера и сразу подключиться.
func _on_paste_addr() -> void:
    var txt := ""
    if DisplayServer.get_name() != "headless":
        txt = DisplayServer.clipboard_get()
    if txt.strip_edges() == "":
        _say(Lang.t("net_paste_empty"))
        return
    var parsed := NetworkManager.split_address(txt, NetworkManager.port)
    var host := String(parsed[0]).strip_edges()
    if host == "":
        _say(Lang.t("net_paste_empty"))
        return
    _ip_edit.text = host
    var p := int(parsed[1])
    if p >= 1024 and p <= 65535 and _port_edit != null:
        _port_edit.text = str(p)
        NetworkManager.port = p
    _on_join()


## v71: проверить, отвечает ли адрес хоста (сеть vs порт/фаервол).
func _on_probe() -> void:
    var text := _ip_edit.text.strip_edges()
    if text == "":
        _say(Lang.t("net_probe_need_ip"))
        return
    var parsed := NetworkManager.split_address(text, NetworkManager.port)
    var host := String(parsed[0]).strip_edges()
    if host == "":
        _say(Lang.t("net_probe_need_ip"))
        return
    NetworkManager.probe_host(host)
    _say(Lang.t("net_probe_wait"))
    _refresh_lobby()


func _probe_line() -> String:
    match String(NetworkManager.probe_state):
        "searching":
            return Lang.t("net_probe_wait")
        "ok":
            return Lang.t("net_probe_ok") % NetworkManager.probe_ip
        "fail":
            return Lang.t("net_probe_fail") % NetworkManager.probe_ip
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
    _say(Lang.t("coop_scanning"))


func _on_ready() -> void:
    if not NetworkManager.is_online():
        return
    var me: Dictionary = NetworkManager.players.get(NetworkManager.my_id, {})
    NetworkManager.set_ready(not bool(me.get("ready", false)))


func _on_start() -> void:
    if not NetworkManager.is_host:
        return
    if not NetworkManager.can_start():
        _say(Lang.t("coop_need_ready") % clampi(min_players, 2,
                NetworkManager.session_max))
        return
    if not NetworkManager.start_match({"coop": true, "min": min_players,
            "enable_roles": enable_roles}):
        _say(Lang.t("coop_need_ready") % clampi(min_players, 2,
                NetworkManager.session_max))


func _on_kick() -> void:
    if not NetworkManager.is_host:
        return
    var id: int = NetworkManager.id_at_slot(sel_slot)
    if id == 0:
        _say(Lang.t("coop_no_slot"))
        return
    if id == 1:
        return
    if NetworkManager.kick_player(id):
        _say("P%d: %s" % [sel_slot, Lang.t("coop_kick")])
    _refresh_lobby()


func _on_end() -> void:
    if not NetworkManager.is_host:
        return
    NetworkManager.end_match("host_end")
    _say(Lang.t("coop_match_end"))
    _refresh_lobby()


func _on_leave() -> void:
    if not allow_drop_out and not NetworkManager.is_host:
        _say(Lang.t("coop_leave_denied"))
        return
    _leave_to_menu()


func _cycle_role(role: String) -> String:
    var idx := ROLES.find(role)
    if idx < 0:
        idx = ROLES.find("DPS")
    for step in range(1, ROLES.size() + 1):
        var cand: String = ROLES[(idx + step) % ROLES.size()]
        if unique_roles and _role_taken(cand, sel_slot):
            continue
        return cand
    return "DPS"


func _role_taken(role: String, except_slot: int) -> bool:
    for row in debug_slots():
        if bool(row["empty"]) or int(row["slot"]) == except_slot:
            continue
        if String(row["role"]) == role:
            return true
    return false


## Смена роли выбранного слота: хост — любого, клиент — только своего.
func _on_role() -> void:
    if not enable_roles:
        _say(Lang.t("coop_roles_off"))
        return
    var can := NetworkManager.is_host \
            or sel_slot == NetworkManager.slot_of(NetworkManager.my_id)
    if not can:
        _say(Lang.t("coop_no_slot"))
        return
    var row: Dictionary = {}
    for r in debug_slots():
        if int(r["slot"]) == sel_slot:
            row = r
    if row.is_empty() or bool(row.get("empty", true)):
        _say(Lang.t("coop_no_slot"))
        return
    var next_role := _cycle_role(String(row.get("role", "DPS")))
    NetworkManager.set_role(next_role, int(row["id"]))
    _say("P%d: %s %s" % [sel_slot, Lang.t("coop_role"), next_role])


func _on_slot(i: int) -> void:
    sel_slot = i + 1
    _say(Lang.t("coop_slot_selected") % sel_slot)
    _refresh_lobby()


func _say(text: String) -> void:
    _msg = text
    _msg_lbl.text = text
    _msg_t = 3.5


# ---------------------------------------------------------------- сигналы сети

func _on_peer_connected(_id: int) -> void:
    if not active or not ui.visible:
        return
    _refresh_lobby()
    _say(Lang.t("net_connected"))


func _on_peer_disconnected(_id: int) -> void:
    if not active or not ui.visible:
        return
    _refresh_lobby()
    _say(Lang.t("net_player_left"))


func _on_conn_failed() -> void:
    if not active or not ui.visible:
        return
    if NetworkManager.join_timed_out:
        # v71: отдельный текст для таймаута — «нет ответа за N с», а не общий fail
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
    if not active:
        return
    if NetworkManager.last_end_reason == "host_disconnect":
        if NetworkManager.handles_end_match():
            _say(Lang.t("coop_host_left"))
            _exit_t = 2.0
            return
    _refresh_lobby()


func _on_match_started(data: Dictionary) -> void:
    if not active:
        return
    _say(Lang.t("coop_match_started"))
    # кооп-матч: лобби прячется, бой ведёт CoopFight (часть 2)
    if main != null and main.has_method("_start_coop_fight"):
        ui.visible = false
        main._start_coop_fight(data)


func _on_match_ended(reason: String) -> void:
    if not active:
        return
    if reason == "host_disconnect":
        _say(Lang.t("coop_host_left"))
        _exit_t = 2.0
        return
    # конец кооп-матча: показывать нечего, CoopFight сам уводит в лобби/меню
    _refresh_lobby()


func _on_kicked(_reason: String) -> void:
    if not active:
        return
    _say(Lang.t("coop_kicked"))
    _exit_t = 2.0


func _on_role_changed(_id: int, _role: String) -> void:
    _refresh_lobby()


# ---------------------------------------------------------------- ввод (клавиши)

func handle_key(event: InputEvent) -> String:
    if not (event is InputEventKey) or not event.pressed or event.echo:
        return ""
    if event.keycode == KEY_ESCAPE:
        if NetworkManager.in_match:
            return ""
        _on_leave()
        return "menu"
    match event.keycode:
        KEY_R:
            _on_ready()
        KEY_S:
            if NetworkManager.is_host:
                _on_start()
        KEY_K:
            if NetworkManager.is_host:
                _on_kick()
        KEY_L:
            _on_role()
        KEY_E:
            if NetworkManager.is_host:
                _on_end()
    return ""


func handle_touch(_pos: Vector2) -> String:
    return ""


# ---------------------------------------------------------------- тесты

## Для --cooptest: поднять кооп-хост на порту (слоты 1..max_players).
func debug_host(port: int) -> bool:
    NetworkManager.port = port
    NetworkManager.set_min_players(min_players)
    var ok := NetworkManager.host_coop(port, clampi(max_players, 2,
            NetworkManager.max_players))
    _show_lobby()
    return ok


## Для --cooptest: подключиться к localhost.
func debug_join(ip: String, port: int) -> bool:
    NetworkManager.port = port
    return NetworkManager.join_coop(ip, port)


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
    _title = _mk_label(Vector2(0, 28), Vector2(1280, 52), 34,
            Color(0.98, 0.86, 0.45))
    _title.text = Lang.t("coop_title")
    _status = _mk_label(Vector2(0, 88), Vector2(1280, 26), 17,
            Color(0.80, 0.84, 0.92))
    for i in 4:
        var b := _mk_button(Vector2(330, 150 + i * 44), Vector2(620, 40))
        b.alignment = HORIZONTAL_ALIGNMENT_LEFT
        b.add_theme_font_size_override("font_size", 15)
        b.pressed.connect(_on_slot.bind(i))
        _slot_btns.append(b)
    _ping_lbl = _mk_label(Vector2(330, 330), Vector2(620, 22), 14,
            Color(0.72, 0.78, 0.88))
    _ping_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _msg_lbl = _mk_label(Vector2(330, 354), Vector2(620, 24), 15,
            Color(0.95, 0.80, 0.40))
    _msg_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _ip_edit = LineEdit.new()
    _ip_edit.position = Vector2(330, 386)
    _ip_edit.size = Vector2(420, 38)
    # Пустое поле + подсказка: раньше тут стоял 127.0.0.1, и игрок по ошибке
    # подключался к самому себе вместо ПК/телефона хоста.
    _ip_edit.text = ""
    _ip_edit.placeholder_text = "IP хоста, напр. 192.168.1.5"
    _ip_edit.add_theme_font_size_override("font_size", 16)
    _root.add_child(_ip_edit)
    _port_edit = LineEdit.new()
    _port_edit.position = Vector2(770, 386)
    _port_edit.size = Vector2(180, 38)
    _port_edit.text = str(NetworkManager.port)
    _port_edit.add_theme_font_size_override("font_size", 16)
    _root.add_child(_port_edit)
    # v71: адрес для друга (интернет/UPnP/VPN) и статус проброса — крупно и честно
    _ext_lbl = _mk_label(Vector2(330, 114), Vector2(620, 34), 13,
            Color(0.78, 0.84, 0.92))
    _ext_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
    _ext_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _ext_lbl.text = ""
    _host_btn = _mk_button(Vector2(330, 434), Vector2(300, 44))
    _host_btn.text = Lang.t("coop_host")
    _host_btn.pressed.connect(_on_host)
    _join_btn = _mk_button(Vector2(650, 434), Vector2(300, 44))
    _join_btn.text = Lang.t("coop_join")
    _join_btn.pressed.connect(_on_join)
    _lan_btn = _mk_button(Vector2(330, 482), Vector2(620, 36))
    _lan_btn.text = Lang.t("coop_lan")
    _lan_btn.pressed.connect(_on_lan)
    # v71: интернет-сценарий — скопировать адрес (хост) / вставить и проверить (гость)
    _copy_btn = _mk_button(Vector2(960, 386), Vector2(300, 38))
    _copy_btn.text = Lang.t("net_copy_addr")
    _copy_btn.add_theme_font_size_override("font_size", 14)
    _copy_btn.pressed.connect(_on_copy_addr)
    _paste_btn = _mk_button(Vector2(960, 434), Vector2(300, 44))
    _paste_btn.text = Lang.t("net_paste_addr")
    _paste_btn.add_theme_font_size_override("font_size", 14)
    _paste_btn.pressed.connect(_on_paste_addr)
    _probe_btn = _mk_button(Vector2(960, 482), Vector2(300, 32))
    _probe_btn.text = Lang.t("net_probe")
    _probe_btn.add_theme_font_size_override("font_size", 13)
    _probe_btn.pressed.connect(_on_probe)
    _ready_btn = _mk_button(Vector2(330, 526), Vector2(300, 42))
    _ready_btn.text = Lang.t("coop_ready")
    _ready_btn.pressed.connect(_on_ready)
    _start_btn = _mk_button(Vector2(650, 526), Vector2(300, 42))
    _start_btn.text = Lang.t("coop_start")
    _start_btn.pressed.connect(_on_start)
    _role_btn = _mk_button(Vector2(330, 576), Vector2(200, 40))
    _role_btn.text = Lang.t("coop_role")
    _role_btn.pressed.connect(_on_role)
    _kick_btn = _mk_button(Vector2(540, 576), Vector2(200, 40))
    _kick_btn.text = Lang.t("coop_kick")
    _kick_btn.pressed.connect(_on_kick)
    _end_btn = _mk_button(Vector2(750, 576), Vector2(200, 40))
    _end_btn.text = Lang.t("coop_end_match")
    _end_btn.pressed.connect(_on_end)
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
    _leave_btn.pressed.connect(_on_leave)
    _hint_lbl = _mk_label(Vector2(960, 660), Vector2(300, 24), 13,
            Color(0.56, 0.61, 0.70))
    _hint_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


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
    b.focus_mode = Control.FOCUS_NONE
    _root.add_child(b)
    return b
