extends Node
## Сеть «В РИНГЕ»: PvP 1v1 и кооператив до 4 игроков (общий слой, N слотов).
## Хост авторитетен, клиент шлёт интенты и получает снапшоты. Autoload, UI-лобби
## и боевая склейка — отдельные модули: scripts/net/net_fight.gd (PvP 1v1),
## scripts/coop/coop_lobby.gd (кооп-лобби на 4 слота).
##
## Игрок в players — словарь {slot:int 1..4, name, role, ready, ping, alive,
## eliminated}. Слот назначается по первому свободному при подключении.
##
## RPC-таблица (все на этом узле, путь /root/NetworkManager одинаков у сторон):
##   _rpc_join_request(name)    any_peer → host, reliable     регистрация клиента в лобби
##   _rpc_lobby(data)           authority → clients, reliable  полный снимок лобби (до 4 игроков)
##   _rpc_ready(v)              any_peer → host, reliable     готовность клиента
##   _rpc_set_role(role)        any_peer → host, reliable     своя роль в кооп-лобби
##   _rpc_kicked(reason)        authority → client, reliable  игрока исключил хост
##   _rpc_start(data)           authority → clients, reliable старт матча
##   _rpc_match_end(reason)     authority → clients, reliable конец матча/лобби (хост)
##   _rpc_intent(data)          any_peer → host, unreliable_ordered интент клиента
##   _rpc_snapshot(data)        authority → clients, unreliable_ordered снапшот мира
##   _rpc_event(kind, data)     authority → clients, reliable   нокдаун/КО/конец/дисконнект
##   _rpc_ping(t)               any_peer → host, unreliable_ordered
##   _rpc_pong(t)               authority → clients, unreliable_ordered
##   _rpc_report_ping(ms)       any_peer → host, reliable     клиент сообщает свой RTT

const Lang = preload("res://scripts/lang.gd")

signal player_connected(id: int)
signal player_disconnected(id: int)
signal server_started
signal joined_server
signal connection_failed
signal server_disconnected
signal lobby_updated
signal match_started(data: Dictionary)
signal snapshot_received(data: Dictionary)
signal intent_received(id: int, data: Dictionary)
signal net_event(kind: String, data: Dictionary)
## v71: необязательные данные снапшота (враги в коопе) — unreliable_ordered,
## чтобы reliable-поток не создавал очередь и лаг при потере пакетов.
signal snapshot_extra(kind: String, data: Dictionary)
signal lan_found(servers: Array)
## v40: статус интернет-проброса (UPnP) изменился — лобби перерисовывается.
signal upnp_updated
## Конец сетевой сессии по инициативе хоста или из-за его дисконнекта.
signal match_ended(reason: String)
## Клиента исключили из лобби.
signal kicked(reason: String)
signal role_changed(id: int, role: String)

## Что делать клиентам, если хост пропал. По умолчанию — завершить матч/лобби.
enum HostDisconnect { END_MATCH, MIGRATE_HOST }

const COOP_ROLES := ["TANK", "DPS", "SUPPORT", "SCOUT"]
const DEFAULT_ROLE := "DPS"

@export var port := 27015
@export var lan_port := 27016
## Верхний предел игроков у хоста (кооп до 4; PvP 1v1 использует 2 слота).
@export var max_players := 4
@export var tick_rate := 30
## v71: было 15 — для интернет-боя это рвано (заметный «шаг» удалённого бойца).
## 20 Гц + интерполяция по двум снапшотам дают плавнее при малом росте трафика.
@export var snapshot_rate := 20
@export var interpolation_delay := 0.1
## v71: таймаут входа (сеть/интернет). 8 с мало для мобильного интернета.
@export var join_timeout_seconds := 12.0
@export var on_host_disconnect: int = HostDisconnect.END_MATCH

## "" (офлайн), "pvp" или "coop" — текущая сессия.
var mode := ""
## Сколько слотов открыто в текущей сессии (2 для PvP, до max_players для коопа).
var session_max := 2
## Минимум игроков для старта (кооп-лобби выставляет своё значение).
var min_players := 2
## Причина последнего завершения сессии: host_disconnect / kicked / host_end / ...
var last_end_reason := ""
## v71: дедлайн входа и флаг «не успели подключиться» (UI показывает ошибку).
var _join_deadline_ms := 0
var join_timed_out := false

var is_host := false
var in_match := false
var players: Dictionary = {}      # id -> {slot, name, role, ready, ping, alive, eliminated}
var my_id := 0
var my_name := "БОКСЁР"
var ping := 0
var snapshots_sent := 0
var snapshots_received := 0
var intents_received := 0
## v71: размеры последних пакетов снапшота (байт) — для контроля MTU и отчёта.
var last_snapshot_bytes := 0
var last_snapshot_extra_bytes := 0
var found_servers: Array = []

var _ping_t := 0.0
var _udp := PacketPeerUDP.new()
var _udp_ready := false
var _scan_left := 0.0
var _scan_resend := 0.0
var _lan_replies: Array = []
## LAN-адрес этой машины для подсказки хосту («скажи другу этот IP»).
var lan_ip := ""

# --- интернет-игра (v40): автопроброс порта на роутере через UPnP ---
## Порт фактически проброшен на роутере (хост).
var upnp_mapped := false
## Внешний IP, который видит интернет (показываем хосту для второго игрока).
var upnp_external_ip := ""
## Человекочитаемый статус: «ищу…», «проброшен», «роутер не дал» и т.п.
var upnp_note := ""
## Код состояния UPnP: "" | "searching" | "ok" | "no_router" | "no_map"
var upnp_state := ""
var _upnp_thread: Thread
var _upnp_pending := false
var _upnp_mapped_port := 0
## v71: проброшенные порты (игра + служебный lan_port для probe/поиска).
var _upnp_mapped_ports: Array[int] = []
var _upnp_obj: UPNP
var _upnp_dev: UPNPDevice
## v71: публичный IP, полученный по HTTP (api.ipify.org), если UPnP не дал адрес.
## Нужен, чтобы показать хосту «адрес для друга» даже на роутере без UPnP —
## но без проброса порта такой адрес рабочим не станет (пишем это прямо).
var public_ip := ""
var _http_ip: HTTPRequest
var _http_pending := false

# --- проверка адреса хоста (v43) ---
## "" | "searching" | "ok" | "fail" — отвечает ли хост на UDP-запрос.
var probe_state := ""
var probe_ip := ""
var probe_t := 0.0
## v71: повтор запроса при проверке адреса (один UDP-пакет в интернете теряется).
var _probe_resend := 0.0


## Первый IPv4-адрес машины в локальной сети (не 127.*, не 169.254.*).
## Нужен, чтобы хост мог продиктовать IP клиенту: в лобби он теперь виден.
func lan_ip_text() -> String:
    if lan_ip != "":
        return lan_ip
    var found: Array[String] = []
    for a in IP.get_local_addresses():
        if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
            continue
        found.append(a)
    if found.is_empty():
        lan_ip = "127.0.0.1"
    else:
        # Приоритет домашним/офисным сетям: 192.168.* и 10.*, затем 172.16–31.*.
        # Иначе можно показать адрес VPN/виртуалки (например 100.x) — по нему
        # второй игрок не подключится.
        var best := found[0]
        var best_score := -1
        for a in found:
            var parts := a.split(".")
            var score := 0
            if parts.size() == 4:
                var o1 := int(parts[0])
                var o2 := int(parts[1])
                if o1 == 192 and o2 == 168:
                    score = 4
                elif o1 == 10:
                    score = 3
                elif o1 == 172 and o2 >= 16 and o2 <= 31:
                    score = 2
                elif o1 == 100 and o2 >= 64 and o2 <= 127:
                    score = 0
                else:
                    score = 1
            if score > best_score or (score == best_score and a < best):
                best_score = score
                best = a
        lan_ip = best
    return lan_ip


## Адреса для широковещательного поиска: общий broadcast + broadcast подсетей
## (255.255.255.255 не всегда доходит, если в машине несколько интерфейсов).
func _broadcast_targets() -> Array[String]:
    var out: Array[String] = ["255.255.255.255"]
    for a in IP.get_local_addresses():
        if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
            continue
        var parts := a.split(".")
        if parts.size() == 4:
            var b := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
            if not out.has(b):
                out.append(b)
    return out


func _ready() -> void:
    my_name = "БОКСЁР-" + str(OS.get_process_id() % 100)
    _connect_multiplayer()
    _open_net_log()


# ---------------------------------------------------------------- сетевой лог (v42)
## Пишем короткий лог сети в user://net-debug.log: по нему видно, дошёл ли
## пакет от телефона до ПК, когда «не подключается». Путь печатается в консоль.
var net_log_path := ""
var _net_log: FileAccess


func _open_net_log() -> void:
    # путь можно переопределить переменной окружения (тесты пишут в build/)
    var path := OS.get_environment("VRINGE_NET_LOG")
    if path == "":
        path = "user://net-debug.log"
    _net_log = FileAccess.open(path, FileAccess.WRITE)
    if _net_log == null:
        return
    net_log_path = path
    if path.begins_with("user://") or path.begins_with("res://"):
        net_log_path = ProjectSettings.globalize_path(path)
    print("NET лог: ", net_log_path)
    _log_net("старт; адреса=" + addresses_text())


func _log_net(msg: String) -> void:
    if _net_log == null:
        return
    _net_log.store_line("[%s] %s" % [Time.get_time_string_from_system(), msg])
    _net_log.flush()


## Публичная запись в сетевой лог (лобби пишет туда свои события).
func log_net(msg: String) -> void:
    _log_net(msg)


func _connect_multiplayer() -> void:
    if not multiplayer.peer_connected.is_connected(_on_peer_connected):
        multiplayer.peer_connected.connect(_on_peer_connected)
    if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
        multiplayer.peer_disconnected.connect(_on_peer_disconnected)
    if not multiplayer.connected_to_server.is_connected(_on_connected_to_server):
        multiplayer.connected_to_server.connect(_on_connected_to_server)
    if not multiplayer.connection_failed.is_connected(_on_connection_failed):
        multiplayer.connection_failed.connect(_on_connection_failed)
    if not multiplayer.server_disconnected.is_connected(_on_server_disconnected):
        multiplayer.server_disconnected.connect(_on_server_disconnected)


## Проверка адреса хоста без ENet: шлём UDP-запрос на служебный порт хоста
## (lan_port) и ждём ответ. Позволяет отличить «сеть не пускает» от «порт игры».
func probe_host(ip: String) -> void:
    var target := ip.strip_edges()
    if target == "":
        return
    if is_host:
        # у хоста этот же сокет занят ответами на поиск — не ломаем его
        return
    probe_ip = target
    probe_state = "searching"
    # 2.8 с: хватает и для интернета (RTT << 1 с), и влезает в автотест с ожиданием 4 с
    probe_t = 2.8
    _probe_resend = 0.8
    _lan_replies.clear()
    _udp_stop()
    if _udp.bind(0, "*") != OK:
        probe_state = "fail"
        probe_t = 0.0
        _log_net("проба %s: не смог открыть UDP" % target)
        lobby_updated.emit()
        return
    _udp.set_broadcast_enabled(true)
    _udp.set_dest_address(target, lan_port)
    _udp.put_packet("VRINGE?".to_utf8_buffer())
    _udp_ready = true
    _log_net("проба адреса %s:%d -> ждём ответ" % [target, lan_port])
    lobby_updated.emit()


func probe_reset() -> void:
    probe_state = ""
    probe_ip = ""
    probe_t = 0.0


# ---------------------------------------------------------------- UPnP (v40)
## Интернет-игра без своего сервера: хост просит роутер пробросить UDP-порт
## наружу (UPnP) и показывает внешний IP, клиент вводит этот IP.
## Работает, если на роутере включён UPnP; иначе — ручной проброс порта.

## Хост: в отдельном потоке ищем роутер и просим проброс — лобби не замирает.
func try_upnp(p: int) -> void:
    if _upnp_pending:
        return
    _upnp_pending = true
    _upnp_mapped_port = p
    upnp_mapped = false
    upnp_external_ip = ""
    upnp_state = "searching"
    upnp_note = "ищу роутер…"
    upnp_updated.emit()
    _upnp_thread = Thread.new()
    _upnp_thread.start(_upnp_work.bind(p))


func _upnp_work(p: int) -> void:
    var res := {"ok": false, "ip": "", "note": "", "obj": null, "dev": null,
            "port": p, "state": "no_router", "ports": []}
    var upnp := UPNP.new()
    var err: int = upnp.discover(1800, 2, "InternetGatewayDevice")
    if err != UPNP.UPNP_RESULT_SUCCESS:
        res["note"] = "роутер не найден"
        call_deferred("_upnp_done", res)
        return
    # Проброс можно просить только у ВАЛИДНОГО IGD — иначе движок сыплет
    # ERROR «The Internet Gateway Device must be valid» на каждый вызов.
    var count := int(upnp.get_device_count())
    var valid: Array = []
    var gw = upnp.get_gateway()
    if gw != null and gw.is_valid_gateway():
        valid.append(gw)
    for i in count:
        var d = upnp.get_device(i)
        if d != null and d.is_valid_gateway() and not valid.has(d):
            valid.append(d)
    # v71: пробрасываем и игровой порт, и lan_port (27016): по нему работает
    # проверка адреса probe_host и поиск хоста в LAN — без него гость из
    # интернета видел «хост не отвечает», хотя играбельный порт был открыт.
    var want_ports: Array[int] = [p]
    if lan_port != p and not want_ports.has(lan_port):
        want_ports.append(lan_port)
    var mapped_ports: Array[int] = []
    var ext := ""
    var used_dev = null
    for d in valid:
        var ok_seen := false
        for pp in want_ports:
            var m := int(d.add_port_mapping(pp, pp, "VRINGE", "UDP", 0))
            if m != int(UPNP.UPNP_RESULT_SUCCESS):
                # мог остаться проброс от прошлой сессии — пересоздаём
                d.delete_port_mapping(pp, "UDP")
                m = int(d.add_port_mapping(pp, pp, "VRINGE", "UDP", 0))
            if m == int(UPNP.UPNP_RESULT_SUCCESS):
                mapped_ports.append(pp)
                ok_seen = true
        if ok_seen:
            used_dev = d
            ext = String(d.query_external_address())
            break
    var mapped: bool = mapped_ports.has(p)
    if mapped:
        res["ok"] = true
        res["state"] = "ok"
        res["ip"] = ext
        res["obj"] = upnp
        res["dev"] = used_dev
        res["ports"] = mapped_ports
        res["note"] = "порты %s проброшены (UPnP)" % str(mapped_ports)
    else:
        res["state"] = "no_map" if count > 0 else "no_router"
        res["note"] = "UPnP не дал проброс (устройств: %d, IGD: %d)" % [
                count, valid.size()]
    call_deferred("_upnp_done", res)


func _upnp_done(res: Dictionary) -> void:
    _upnp_pending = false
    if _upnp_thread != null:
        _upnp_thread.wait_to_finish()
        _upnp_thread = null
    # сессию уже закрыли, пока шёл поиск роутера — результат не нужен
    if not is_host:
        return
    upnp_mapped = bool(res.get("ok", false))
    upnp_external_ip = String(res.get("ip", ""))
    upnp_state = String(res.get("state", ""))
    upnp_note = String(res.get("note", ""))
    _upnp_mapped_ports.clear()
    var ports_res = res.get("ports", [])
    if ports_res is Array:
        for pp in ports_res:
            _upnp_mapped_ports.append(int(pp))
    if _upnp_mapped_ports.is_empty() and _upnp_mapped_port > 0:
        _upnp_mapped_ports.append(_upnp_mapped_port)
    # v71: если роутер не отдал внешний адрес (или UPnP вообще нет) — добираем
    # публичный IP по HTTP, чтобы показать хосту реальный адрес и честный статус.
    if upnp_external_ip == "" or not upnp_mapped:
        _fetch_public_ip()
    var obj = res.get("obj")
    if obj is UPNP:
        _upnp_obj = obj
    var dev = res.get("dev")
    if dev != null:
        _upnp_dev = dev
    print("NET UPnP: ", upnp_state, " ", upnp_note, " внешний IP=", upnp_external_ip,
            " порты=", _upnp_mapped_ports)
    _log_net("UPnP: %s %s внешний=%s порты=%s" % [upnp_state, upnp_note,
            upnp_external_ip, str(_upnp_mapped_ports)])
    upnp_updated.emit()


## v71: публичный IP через api.ipify.org (запасной путь, если UPnP не дал адрес).
## Асинхронно, не блокирует лобби; в headless/без сети просто не сработает.
func _fetch_public_ip() -> void:
    if _http_pending:
        return
    if _http_ip == null:
        _http_ip = HTTPRequest.new()
        _http_ip.timeout = 6.0
        add_child(_http_ip)
    _http_pending = true
    var err := _http_ip.request("https://api.ipify.org")
    if err != OK:
        _http_pending = false
        _log_net("HTTP внешний IP: запрос не стартовал (err %d)" % err)
        return
    var resp: Array = await _http_ip.request_completed
    _http_pending = false
    var code := int(resp[1])
    var body: PackedByteArray = resp[3]
    if code != 200:
        _log_net("HTTP внешний IP: код %d" % code)
        return
    var txt := body.get_string_from_utf8().strip_edges()
    if txt.is_valid_ip_address():
        public_ip = txt
        if upnp_mapped and upnp_external_ip == "":
            upnp_external_ip = txt
        _log_net("HTTP внешний IP: %s" % public_ip)
        upnp_updated.emit()


func _upnp_release() -> void:
    if _upnp_thread != null:
        _upnp_thread.wait_to_finish()
        _upnp_thread = null
    _upnp_pending = false
    # v71: снимаем ВСЕ записи (игровой порт + lan_port), которые создали
    if not _upnp_mapped_ports.is_empty():
        for pp in _upnp_mapped_ports:
            if _upnp_dev != null and _upnp_dev.has_method("delete_port_mapping"):
                _upnp_dev.delete_port_mapping(int(pp), "UDP")
            elif _upnp_obj != null and _upnp_obj.has_method("delete_port_mapping"):
                _upnp_obj.delete_port_mapping(int(pp), "UDP")
    _upnp_mapped_ports.clear()
    _upnp_obj = null
    _upnp_dev = null
    _upnp_mapped_port = 0
    upnp_mapped = false
    upnp_external_ip = ""
    upnp_state = ""
    upnp_note = ""


## Все IPv4-адреса машины, по которым к ней можно подключиться.
## kind: "lan" | "tailscale" | "radmin" | "vpn". Нужно хосту, чтобы продиктовать
## второму игроку адрес: локалка — LAN, разные сети — Tailscale/Radmin.
func local_addresses() -> Array:
    var out: Array = []
    for a in IP.get_local_addresses():
        if a.contains(":") or a.begins_with("127.") or a.begins_with("169.254."):
            continue
        var kind := "vpn"
        var parts := a.split(".")
        if parts.size() == 4:
            var o1 := int(parts[0])
            var o2 := int(parts[1])
            if o1 == 192 and o2 == 168:
                kind = "lan"
            elif o1 == 10:
                kind = "lan"
            elif o1 == 172 and o2 >= 16 and o2 <= 31:
                kind = "lan"
            elif o1 == 100 and o2 >= 64 and o2 <= 127:
                kind = "tailscale"
            elif o1 == 26:
                kind = "radmin"
        var dup := false
        for row in out:
            if String(row["ip"]) == a:
                dup = true
        if not dup:
            out.append({"ip": a, "kind": kind})
    # сначала локалка, потом VPN-мосты
    var order := {"lan": 0, "tailscale": 1, "radmin": 2, "vpn": 3}
    out.sort_custom(func(x, y): return int(order.get(x["kind"], 9)) \
            < int(order.get(y["kind"], 9)))
    return out


## Строка «адрес:порт (тип)» по всем адресам — для лобби.
func addresses_text() -> String:
    var parts: Array = []
    for row in local_addresses():
        var kind := String(row["kind"])
        var label := Lang.t("net_kind_" + kind) if Lang.has("net_kind_" + kind) else kind
        parts.append("%s:%d (%s)" % [String(row["ip"]), port, label])
    return " · ".join(parts)


## Адрес VPN-моста (Tailscale/Radmin/другой VPN) — «ip:порт», или "" если моста нет.
## Именно он нужен для игры с ПК на ПК из другого города: LAN-адрес там не работает.
func vpn_address() -> String:
    for row in local_addresses():
        var kind := String(row["kind"])
        if kind == "tailscale" or kind == "radmin" or kind == "vpn":
            return "%s:%d" % [String(row["ip"]), port]
    return ""


## v71: внешний IP — сначала из UPnP, иначе публичный (HTTP), иначе "".
func external_ip_text() -> String:
    if upnp_external_ip != "":
        return upnp_external_ip
    return public_ip


## v71: «ip:порт» для друга через интернет, или "" если внешний адрес неизвестен.
func external_address() -> String:
    var ip := external_ip_text()
    if ip == "":
        return ""
    return "%s:%d" % [ip, port]


## Самый «дальний» рабочий адрес: интернет (если порт проброшен), VPN-мост, LAN.
func best_join_address() -> String:
    if upnp_mapped:
        var ext := external_address()
        if ext != "":
            return ext
    var vpn := vpn_address()
    if vpn != "":
        return vpn
    return "%s:%d" % [lan_ip_text(), port]


## То же с типом: {"ip","port","kind"} — для строки «адрес для друга» в лобби.
## kind: "internet" (порт проброшен), "internet_manual" (внешний IP есть, порт
## не проброшен — нужен ручной проброс), "tailscale"/"radmin"/"vpn", "lan".
func best_join_row() -> Dictionary:
    var ext_ip := external_ip_text()
    if ext_ip != "":
        return {"ip": ext_ip, "port": port,
                "kind": "internet" if upnp_mapped else "internet_manual"}
    for row in local_addresses():
        var kind := String(row["kind"])
        if kind == "tailscale" or kind == "radmin" or kind == "vpn":
            return {"ip": String(row["ip"]), "port": port, "kind": kind}
    return {"ip": lan_ip_text(), "port": port, "kind": "lan"}


## Подпись типа адреса: «Tailscale», «LAN» и т.п.
func kind_label(kind: String) -> String:
    var key := "net_kind_" + kind
    return Lang.t(key) if Lang.has(key) else kind


## Разбор строки адреса: «1.2.3.4:27015» → ["1.2.3.4", 27015].
## Если порта нет — берём default_port. Нужно, чтобы можно было вставить адрес,
## скопированный из лобби (или из чата), целиком, а не разбивать на два поля.
func split_address(text: String, default_port: int) -> Array:
    var s := text.strip_edges()
    if s == "":
        return ["", default_port]
    # IPv6 в квадратных скобках тоже поддерживаем, чтобы не ломать ввод
    if s.begins_with("["):
        var close := s.find("]")
        if close > 0:
            var host6 := s.substr(1, close - 1)
            var rest := s.substr(close + 1).strip_edges()
            var p6 := default_port
            if rest.begins_with(":"):
                p6 = int(rest.substr(1))
            return [host6, p6 if p6 > 0 else default_port]
    var colon := s.rfind(":")
    if colon > 0 and s.find(":") == colon:
        var p := int(s.substr(colon + 1))
        if p > 0 and p <= 65535:
            return [s.substr(0, colon).strip_edges(), p]
    return [s, default_port]


## v71: локальный перевод для новых строк, пока Lead не добавил ключи в lang.gd.
func _txt(key: String, ru: String, en: String) -> String:
    if Lang.has(key):
        return Lang.t(key)
    return en if Lang.is_en() else ru


## Строка для лобби: что показать хосту про игру из интернета. Честно: если
## проброса нет, так и пишем (а не «должно работать»).
func internet_hint_text() -> String:
    if not is_host:
        return ""
    if upnp_state == "searching":
        return Lang.t("net_ext_search")
    if upnp_state == "ok":
        var ext_ok := external_address()
        if ext_ok != "":
            return _txt("net_ext_addr", "адрес для друга (интернет): %s",
                    "friend address (internet): %s") % ext_ok
        return Lang.t("net_ext_search")
    # UPnP нет / не дал проброс.
    var vpn := vpn_address()
    if vpn != "":
        return (Lang.t("net_vpn_hint") % vpn) + " · " + _txt("net_ext_nomap_short",
                "внешний IP/проброс не нужен, если играете через VPN-мост",
                "no port forwarding needed over the VPN bridge")
    var ext_ip := external_ip_text()
    if ext_ip != "":
        return _txt("net_ext_nomap",
                "внешний IP %s:%d, но порт НЕ проброшен: включи UPnP на роутере, "
                + "проброс UDP %d (и %d) или DMZ/ZeroTier/Radmin",
                "public IP %s:%d, but the port is NOT forwarded: enable UPnP, "
                + "forward UDP %d (and %d) or use DMZ/ZeroTier/Radmin") % [
                ext_ip, port, port, lan_port]
    return Lang.t("net_ext_manual") % [port, lan_ip_text()]


## Тест: подставить статус UPnP без реального роутера. ports/public — для проверки
## строки «адрес для друга» и `best_join_*` без сети (используется --nettest/cooptest
## и ручной диагностикой; в игре не вызывается).
func debug_upnp_set(mapped: bool, ip: String, note: String,
        ports: Array = [], public: String = "") -> void:
    upnp_mapped = mapped
    upnp_external_ip = ip
    upnp_state = "ok" if mapped else "no_router"
    upnp_note = note
    _upnp_mapped_ports.clear()
    for pp in ports:
        _upnp_mapped_ports.append(int(pp))
    if _upnp_mapped_ports.is_empty() and mapped:
        _upnp_mapped_ports.append(port)
    if public != "":
        public_ip = public
    upnp_updated.emit()


# ---------------------------------------------------------------- сессии

## PvP 1v1: как раньше, два слота.
func host_game(p: int = -1) -> bool:
    return _host(p, 2, "pvp")


## Кооп: до max_players слотов (по умолчанию 4).
func host_coop(p: int = -1, slots: int = 4) -> bool:
    return _host(p, clampi(slots, 2, max_players), "coop")


func join_game(ip: String, p: int = -1) -> bool:
    return _join(ip, p, "pvp")


func join_coop(ip: String, p: int = -1) -> bool:
    return _join(ip, p, "coop")


func _host(p: int, slots: int, m: String) -> bool:
    if p > 0:
        port = p
    session_max = clampi(slots, 2, max_players)
    mode = m
    min_players = clampi(min_players, 2, session_max)
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_server(port, session_max - 1)
    if err != OK:
        push_warning("NetworkManager: не удалось открыть порт %d (err %d)" % [port, err])
        mode = ""
        return false
    multiplayer.multiplayer_peer = peer
    is_host = true
    in_match = false
    my_id = 1
    ping = 0
    last_end_reason = ""
    # в коопе хост тоже должен нажать «Я ГОТОВ»
    players = {1: _make_player(1, my_name, mode != "coop")}
    _udp_host_start()
    # v40: интернет-игра — просим роутер пробросить порт наружу (в потоке)
    try_upnp(port)
    # v71: тестовый хук — подменить результат UPnP без реального роутера
    # (VRINGE_UPNP_DEBUG=203.0.113.7). В обычной игре переменная пустая.
    var upnp_debug_ip := OS.get_environment("VRINGE_UPNP_DEBUG").strip_edges()
    if upnp_debug_ip != "":
        debug_upnp_set(true, upnp_debug_ip, "debug", [port, lan_port])
        print("NET UPnP debug: external=", upnp_debug_ip, ":", port,
                " best=", best_join_address(), " hint=", internet_hint_text())
        _log_net("UPnP debug: external=%s:%d best=%s hint=%s" % [upnp_debug_ip, port,
                best_join_address(), internet_hint_text()])
    _log_net("хост: порт %d режим %s адреса=%s" % [port, mode, addresses_text()])
    server_started.emit()
    lobby_updated.emit()
    print("NET хост: порт ", port, " режим ", mode, " слотов ", session_max,
            " игрок ", my_name)
    return true


func _join(ip: String, p: int, m: String) -> bool:
    # v46: в поле можно вставить адрес целиком «100.x.x.x:27015» или имя хоста
    # (Tailscale MagicDNS, Radmin, localhost) — не только голый IP.
    var parsed := split_address(ip, port if p <= 0 else p)
    var host := String(parsed[0])
    var use_port := int(parsed[1])
    if p > 0:
        use_port = p
    port = use_port
    if host == "":
        mode = ""
        return false
    var resolved := host
    if not host.is_valid_ip_address():
        resolved = IP.resolve_hostname(host, IP.TYPE_IPV4)
        if resolved == "" or resolved == "0.0.0.0":
            push_warning("NetworkManager: имя «%s» не разрешилось в IP" % host)
            _log_net("клиент: имя %s не разрешилось" % host)
            mode = ""
            return false
        _log_net("клиент: имя %s → %s" % [host, resolved])
    mode = m
    session_max = max_players if m == "coop" else 2
    if m != "coop":
        min_players = 2
    var peer := ENetMultiplayerPeer.new()
    var err := peer.create_client(resolved, port)
    if err != OK:
        push_warning("NetworkManager: не удалось подключиться к %s:%d (err %d)" % [resolved, port, err])
        mode = ""
        return false
    multiplayer.multiplayer_peer = peer
    is_host = false
    in_match = false
    my_id = 0
    last_end_reason = ""
    players = {}
    # v71: дедлайн подключения на уровне сети (не зависит от UI/сцены):
    # поздний ответ/чужой порт не оставят игрока в вечном «подключаюсь…».
    _join_deadline_ms = Time.get_ticks_msec() + int(join_timeout_seconds * 1000.0)
    join_timed_out = false
    print("NET клиент: подключаюсь к ", resolved, ":", port, " режим ", mode)
    _log_net("клиент: подключаюсь к %s:%d режим %s" % [resolved, port, mode])
    return true


func leave_game() -> void:
    _join_deadline_ms = 0
    if multiplayer.multiplayer_peer != null:
        multiplayer.multiplayer_peer.close()
    multiplayer.multiplayer_peer = null
    is_host = false
    in_match = false
    players = {}
    my_id = 0
    ping = 0
    mode = ""
    session_max = 2
    min_players = 2
    _udp_stop()
    # снять проброс порта, если делали
    _upnp_release()
    _log_net("сессия закрыта")
    lobby_updated.emit()


func is_online() -> bool:
    # в Godot 4 multiplayer_peer по умолчанию — OfflineMultiplayerPeer, поэтому
    # «онлайн» = именно ENet-сессия (иначе кнопки лобби блокировались бы всегда)
    var peer := multiplayer.multiplayer_peer
    return peer != null and peer is ENetMultiplayerPeer


func in_lobby() -> bool:
    return is_online() and not in_match


func mode_is_coop() -> bool:
    return mode == "coop"


## Клиенты при потере хоста должны завершить матч/лобби (а не ждать миграции).
func handles_end_match() -> bool:
    return on_host_disconnect == HostDisconnect.END_MATCH


func set_min_players(v: int) -> void:
    min_players = clampi(v, 2, max_players)


# ---------------------------------------------------------------- лобби

func player_count() -> int:
    return players.size()


func _make_player(slot: int, pname: String, ready: bool, role: String = DEFAULT_ROLE) -> Dictionary:
    return {"slot": slot, "name": pname, "role": role, "ready": ready,
            "ping": 0, "alive": true, "eliminated": false}


func _free_slot() -> int:
    var used := {}
    for id in players:
        used[int(players[id].get("slot", 0))] = true
    for s in range(1, session_max + 1):
        if not used.has(s):
            return s
    return 0


## Завести/обновить запись игрока. false — свободных слотов нет.
func _register(id: int, pname: String) -> bool:
    if players.has(id):
        players[id]["name"] = pname
        return true
    var slot := _free_slot()
    if slot == 0:
        return false
    players[id] = _make_player(slot, pname, false)
    return true


func slot_of(id: int) -> int:
    var p: Dictionary = players.get(int(id), {})
    return int(p.get("slot", 0))


func id_at_slot(slot: int) -> int:
    for id in players:
        if int(players[id].get("slot", 0)) == slot:
            return int(id)
    return 0


## Состояние всех слотов лобби (пустой слот — пустой словарь). Для UI и тестов.
func lobby_slots() -> Array:
    var out: Array = []
    for s in range(1, session_max + 1):
        out.append({})
    for id in players:
        var p: Dictionary = players[id]
        var slot := int(p.get("slot", 0))
        if slot >= 1 and slot <= out.size():
            var row: Dictionary = p.duplicate(true)
            row["id"] = int(id)
            out[slot - 1] = row
    return out


func ready_of(id: int) -> bool:
    return bool(players.get(int(id), {}).get("ready", false))


func can_start() -> bool:
    if not is_host:
        return false
    if players.size() < clampi(min_players, 2, session_max):
        return false
    for id in players:
        if mode == "coop":
            if not bool(players[id].get("ready", false)):
                return false
        elif int(id) != 1 and not bool(players[id].get("ready", false)):
            return false
    return true


func set_ready(v: bool) -> void:
    if is_host:
        if players.has(1):
            players[1]["ready"] = v
        _broadcast_lobby()
        return
    rpc_id(1, "_rpc_ready", v)


## Роль игрока. Хост может менять свою и чужие (target_id 0 = своя), клиент —
## только свою. Роли в коопе не уникальны: дубликаты разрешены.
func set_role(role: String, target_id: int = 0) -> void:
    if not role in COOP_ROLES:
        return
    if is_host:
        var id := target_id if target_id > 0 else 1
        if players.has(id):
            players[id]["role"] = role
            role_changed.emit(id, role)
            _broadcast_lobby()
        return
    if target_id != 0 and target_id != my_id:
        return
    if my_id != 0:
        rpc_id(1, "_rpc_set_role", role)


## Хост исключает игрока: слот освобождается, лобби продолжает жить.
func kick_player(id: int) -> bool:
    if not is_host or int(id) == 1 or not players.has(int(id)):
        return false
    rpc_id(int(id), "_rpc_kicked", "kick")
    players.erase(int(id))
    _disconnect_peer_later(int(id))
    _broadcast_lobby()
    return true


func _disconnect_peer_later(id: int) -> void:
    if is_inside_tree():
        get_tree().create_timer(0.3).timeout.connect(_disconnect_peer.bind(id))
    else:
        _disconnect_peer(id)


func _disconnect_peer(id: int) -> void:
    var peer := multiplayer.multiplayer_peer
    if peer == null or not (peer is ENetMultiplayerPeer):
        return
    # пир мог уже отключиться сам (например, кикнутый клиент вышел раньше таймера)
    if not (id in multiplayer.get_peers()):
        return
    var enet := peer as ENetMultiplayerPeer
    enet.disconnect_peer(id, true)


## Хост завершает матч/лобби — клиенты получают END_MATCH.
func end_match(reason: String = "host_end") -> void:
    if not is_host:
        return
    in_match = false
    last_end_reason = reason
    if multiplayer.multiplayer_peer != null:
        rpc("_rpc_match_end", reason)
    match_ended.emit(reason)
    _broadcast_lobby()


func start_match(data: Dictionary = {}) -> bool:
    if not can_start():
        return false
    in_match = true
    var payload := data.duplicate(true)
    payload["players"] = players.duplicate(true)
    payload["mode"] = mode
    payload["max"] = session_max
    rpc("_rpc_start", payload)
    match_started.emit(payload)
    return true


## v71: интенты клиента шлём не чаще tick_rate (по умолчанию 30/с). Раньше
## клиент отправлял их каждый кадр (60–120/с) — на мобильном интернете это
## лишний трафик и лаги из-за забитого канала.
var _last_intent_ms := 0

func send_intent(data: Dictionary) -> void:
    if is_host:
        return
    var now := Time.get_ticks_msec()
    var min_ms := int(1000.0 / maxf(1.0, float(tick_rate)))
    if now - _last_intent_ms < min_ms:
        return
    _last_intent_ms = now
    rpc_id(1, "_rpc_intent", data)


func send_snapshot(data: Dictionary) -> void:
    if not is_host:
        return
    snapshots_sent += 1
    # v71: размер снапшота пишем в сетевой лог — по нему видно, не вылезаем ли
    # за MTU ENet (1392 байта для unreliable) и не пора ли урезать поля.
    var bytes := var_to_bytes(data).size()
    last_snapshot_bytes = bytes
    if snapshots_sent <= 3:
        _log_net("снапшот #%d: %d байт" % [snapshots_sent, bytes])
    rpc("_rpc_snapshot", data)


## v71: необязательная часть снапшота (враги в коопе) — unreliable_ordered,
## чтобы reliable-канал не копил очередь и не давал рывки при потере пакетов.
func send_snapshot_extra(kind: String, data: Dictionary) -> void:
    if not is_host:
        return
    var bytes := var_to_bytes(data).size()
    last_snapshot_extra_bytes = bytes
    if snapshots_sent <= 3:
        _log_net("снапшот-extra #%d: %d байт" % [snapshots_sent, bytes])
    rpc("_rpc_snapshot_extra", kind, data)


func send_event(kind: String, data: Dictionary) -> void:
    if not is_host:
        return
    rpc("_rpc_event", kind, data)


func _broadcast_lobby() -> void:
    var data := {"players": players.duplicate(true), "max": session_max,
            "min": min_players, "mode": mode, "in_match": in_match}
    if is_host and multiplayer.multiplayer_peer != null:
        rpc("_rpc_lobby", data)
    lobby_updated.emit()


func _process(delta: float) -> void:
    _udp_tick(delta)
    # v71: таймаут входа на уровне сети — работает независимо от UI/сцены.
    if not is_host and _join_deadline_ms > 0 and my_id == 0 \
            and Time.get_ticks_msec() >= _join_deadline_ms:
        _join_deadline_ms = 0
        join_timed_out = true
        _log_net("ТАЙМАУТ ВХОДА: %d с, ответа нет" % int(join_timeout_seconds))
        print("NET таймаут подключения за ", join_timeout_seconds, " с")
        if multiplayer.multiplayer_peer != null:
            multiplayer.multiplayer_peer.close()
            multiplayer.multiplayer_peer = null
        mode = ""
        connection_failed.emit()
    if not is_host and multiplayer.multiplayer_peer != null and my_id != 0:
        _ping_t += delta
        if _ping_t >= 1.0:
            _ping_t = 0.0
            rpc_id(1, "_rpc_ping", Time.get_ticks_msec())


## Поток UPnP не должен пережить приложение (иначе падение на выходе).
func _exit_tree() -> void:
    if _upnp_thread != null:
        _upnp_thread.wait_to_finish()
        _upnp_thread = null


# ---------------------------------------------------------------- ENet-сигналы

func _on_peer_connected(id: int) -> void:
    player_connected.emit(id)
    _log_net("ВХОДЯЩИЙ peer %d — пакет от него дошёл" % id)
    if is_host:
        # клиент ещё не прислал имя; заводим запись на первом свободном слоте
        if _register(id, "ИГРОК-" + str(id)):
            _broadcast_lobby()
        else:
            # сессия уже заполнена — вежливо отключаем лишнего
            rpc_id(id, "_rpc_kicked", "full")
            _disconnect_peer_later(id)
    print("NET подключён peer ", id)


func _on_peer_disconnected(id: int) -> void:
    var was_slot := slot_of(id)
    _log_net("peer %d отключился (слот %d)" % [id, was_slot])
    players.erase(id)
    player_disconnected.emit(id)
    if is_host:
        if in_match:
            send_event("disconnect", {"id": id, "slot": was_slot})
            if mode != "coop":
                in_match = false
        _broadcast_lobby()
    print("NET отключён peer ", id, " (слот ", was_slot, " освобождён)")


func _on_connected_to_server() -> void:
    my_id = multiplayer.get_unique_id()
    rpc_id(1, "_rpc_join_request", my_name)
    _join_deadline_ms = 0
    _log_net("ПОДКЛЮЧИЛСЯ к хосту, мой id %d" % my_id)
    joined_server.emit()
    print("NET подключился к серверу, мой id ", my_id)


func _on_connection_failed() -> void:
    _join_deadline_ms = 0
    multiplayer.multiplayer_peer = null
    mode = ""
    _log_net("СОЕДИНЕНИЕ НЕ УДАЛОСЬ (хост не ответил)")
    connection_failed.emit()
    print("NET соединение не удалось")


func _on_server_disconnected() -> void:
    var reason := "host_disconnect"
    _log_net("хост отключился (%s)" % reason)
    multiplayer.multiplayer_peer = null
    is_host = false
    in_match = false
    players = {}
    ping = 0
    last_end_reason = reason
    # END_MATCH: клиент не продолжает матч/лобби без хоста
    match_ended.emit(reason)
    server_disconnected.emit()
    print("NET сервер отключился (", reason, ")")


# ---------------------------------------------------------------- RPC

@rpc("any_peer", "call_remote", "reliable")
func _rpc_join_request(pname: String) -> void:
    if not is_host:
        return
    var id := multiplayer.get_remote_sender_id()
    if not _register(id, pname):
        rpc_id(id, "_rpc_kicked", "full")
        _disconnect_peer_later(id)
        return
    _broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_lobby(data: Dictionary) -> void:
    players = data.get("players", {})
    session_max = int(data.get("max", session_max))
    min_players = int(data.get("min", min_players))
    mode = String(data.get("mode", mode))
    in_match = bool(data.get("in_match", in_match))
    if multiplayer.multiplayer_peer != null:
        my_id = multiplayer.get_unique_id()
    lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_ready(v: bool) -> void:
    if not is_host:
        return
    var id := multiplayer.get_remote_sender_id()
    if players.has(id):
        players[id]["ready"] = v
        _broadcast_lobby()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_set_role(role: String) -> void:
    if not is_host:
        return
    var id := multiplayer.get_remote_sender_id()
    if players.has(id) and role in COOP_ROLES:
        players[id]["role"] = role
        role_changed.emit(id, role)
        _broadcast_lobby()


@rpc("authority", "call_remote", "reliable")
func _rpc_kicked(reason: String) -> void:
    last_end_reason = "kicked"
    kicked.emit(reason)
    print("NET исключён из лобби: ", reason)


@rpc("authority", "call_remote", "reliable")
func _rpc_match_end(reason: String) -> void:
    in_match = false
    last_end_reason = reason
    match_ended.emit(reason)
    lobby_updated.emit()


@rpc("authority", "call_remote", "reliable")
func _rpc_start(data: Dictionary) -> void:
    in_match = true
    match_started.emit(data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_intent(data: Dictionary) -> void:
    if not is_host:
        return
    intents_received += 1
    intent_received.emit(multiplayer.get_remote_sender_id(), data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot(data: Dictionary) -> void:
    snapshots_received += 1
    snapshot_received.emit(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_snapshot_extra(kind: String, data: Dictionary) -> void:
    snapshot_extra.emit(kind, data)


@rpc("authority", "call_remote", "reliable")
func _rpc_event(kind: String, data: Dictionary) -> void:
    net_event.emit(kind, data)


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _rpc_ping(t: int) -> void:
    if is_host:
        rpc_id(multiplayer.get_remote_sender_id(), "_rpc_pong", t)


@rpc("authority", "call_remote", "unreliable_ordered")
func _rpc_pong(t: int) -> void:
    ping = Time.get_ticks_msec() - t
    if is_host:
        return
    rpc_id(1, "_rpc_report_ping", ping)
    lobby_updated.emit()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_report_ping(ms: int) -> void:
    if not is_host:
        return
    var id := multiplayer.get_remote_sender_id()
    if players.has(id):
        players[id]["ping"] = ms
        _broadcast_lobby()


# ---------------------------------------------------------------- LAN-поиск

## Хост слушает UDP на lan_port и отвечает на beacon "VRINGE?".
func _udp_host_start() -> void:
    _udp_stop()
    var err := _udp.bind(lan_port, "*")
    _udp_ready = err == OK


func _udp_stop() -> void:
    if _udp_ready:
        _udp.close()
    _udp_ready = false


## Клиент: широковещательный поиск хоста в LAN (~2 с).
func scan_lan() -> void:
    found_servers.clear()
    _lan_replies.clear()
    _udp_stop()
    var err := _udp.bind(0, "*")
    if err != OK:
        push_warning("NetworkManager: LAN-поиск не смог открыть UDP (err %d)" % err)
        return
    _udp.set_broadcast_enabled(true)
    _send_scan_packet()
    _udp_ready = true
    _scan_left = 2.0
    _scan_resend = 0.5


func _send_scan_packet() -> void:
    for ip in _broadcast_targets():
        _udp.set_dest_address(ip, lan_port)
        _udp.put_packet("VRINGE?".to_utf8_buffer())


func _udp_tick(delta: float) -> void:
    if not _udp_ready:
        return
    while _udp.get_available_packet_count() > 0:
        var pkt := _udp.get_packet()
        var txt := pkt.get_string_from_utf8()
        if is_host and txt.begins_with("VRINGE?"):
            var reply := "VRINGE|%d|%s" % [port, my_name]
            _udp.set_dest_address(_udp.get_packet_ip(), _udp.get_packet_port())
            _udp.put_packet(reply.to_utf8_buffer())
        elif not is_host and txt.begins_with("VRINGE|"):
            var parts := txt.split("|")
            if parts.size() >= 3:
                var entry := {"ip": _udp.get_packet_ip(), "port": int(parts[1]),
                        "name": parts[2]}
                # ответ именно от проверяемого адреса -> проба успешна
                if probe_state == "searching" \
                        and String(entry["ip"]) == probe_ip:
                    probe_state = "ok"
                    probe_t = 0.0
                    _log_net("проба %s: ОТВЕТ ПОЛУЧЕН" % probe_ip)
                    lobby_updated.emit()
                var dup := false
                for s in _lan_replies:
                    if s["ip"] == entry["ip"] and s["port"] == entry["port"]:
                        dup = true
                if not dup:
                    _lan_replies.append(entry)
        if not is_host and _lan_replies.size() > 0:
            found_servers = _lan_replies.duplicate(true)
            lan_found.emit(found_servers)
    # таймаут пробы: хост не ответил
    if not is_host and probe_state == "searching":
        probe_t -= delta
        _probe_resend -= delta
        if _probe_resend <= 0.0 and probe_t > 0.0:
            _probe_resend = 0.8
            _udp.set_dest_address(probe_ip, lan_port)
            _udp.put_packet("VRINGE?".to_utf8_buffer())
        if probe_t <= 0.0:
            probe_state = "fail"
            probe_t = 0.0
            _log_net("проба %s: ОТВЕТА НЕТ" % probe_ip)
            lobby_updated.emit()
    if not is_host and _scan_left > 0.0:
        _scan_left -= delta
        # повторяем broadcast каждые 0.5 с: один пакет теряется на Wi-Fi/фаерволе
        _scan_resend -= delta
        if _scan_resend <= 0.0 and _scan_left > 0.0:
            _scan_resend = 0.5
            _send_scan_packet()
        if _scan_left <= 0.0:
            found_servers = _lan_replies.duplicate(true)
            lan_found.emit(found_servers)
