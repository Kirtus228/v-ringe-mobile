class_name AdsManager
extends Node
## v71s: монетизация (реклама).
##
## Два пути, ничего не ломается, если площадка/аккаунт ещё не подключены:
##   * web  — Yandex Games SDK (`ads_sdk`): SDK подгружается со страницы игры,
##            если игра открыта внутри площадки Яндекс Игр. Тогда межстраничная
##            реклама идёт через `sdk.adv.showFullscreenAdv`.
##   * android — AdMob-плагин: активируется только если в сборку добавлен
##            нативный синглтон с нашими ad unit id (см. docs/ads.md).
##
## Частотный кап: не чаще одного показа в COOLDOWN_SEC и не чаще, чем раз в
## AD_EVERY_FIGHTS завершённых боёв. Реклама НИКОГДА не показывается во время боя
## или тренировки — только на экранах результата/меню.

const AD_EVERY_FIGHTS := 3
const COOLDOWN_SEC := 60.0
const HOLD_MIN := 120.0

## Провайдер: "none" | "yandex" | "admob"
var provider := "none"
## Включена ли реклама вообще (можно выключить в настройках игры).
var enabled := true
## Сколько боёв прошло после последнего показа.
var fights_since_ad := 0
## Отладочный лог (env VRINGE_ADS_LOG=1).
var _log := false

var _js_ready := false
var _js_checked := false
var _js_fail := ""
## Ссылка на JS-колбэк звука (держать, иначе GC уберёт объект).
var _mute_cb: JavaScriptObject = null
var _cooldown := 0.0
var _shown := 0
var _tried := 0
var _started_msec := 0
## AdMob: синглтон плагина (если подключён в сборке) и id блоков.
var _admob: Object = null
var admob_interstitial_id := ""
var admob_banner_id := ""


func _ready() -> void:
	name = "AdsManager"
	_log = OS.get_environment("VRINGE_ADS_LOG").strip_edges() != ""
	_started_msec = Time.get_ticks_msec()
	_setup()


func _setup() -> void:
	if OS.has_feature("web"):
		_setup_web()
	elif OS.has_feature("android"):
		_setup_android()
	if _log:
		print("ADS провайдер=", provider, " включено=", enabled)


## --- web / Yandex Games ------------------------------------------------------

## v71s: SDK Яндекс Игр подключает bootstrap в самой странице
## (web/yandex_bootstrap.js, вставляется в index.html при сборке): он грузит
## официальный /sdk.js, вызывает YaGames.init(), отдаёт язык и сообщает платформе
## о готовности игры (LoadingAPI.ready). Здесь мы только читаем статус и
## регистрируем колбэки звука.
func _setup_web() -> void:
	_js_fail = ""
	if not OS.has_feature("web"):
		return
	# Колбэк «включить/выключить звук»: страница зовёт его при потере фокуса,
	# паузе площадки и показе рекламы (требования 1.3 и 4.7). Ссылку на объект
	# держим в поле, иначе его соберёт GC и вызовы из JS отвалятся.
	_mute_cb = JavaScriptBridge.create_callback(_on_page_mute)
	var win := JavaScriptBridge.get_interface("window")
	if win != null:
		win.set("__vringeMuteGd", _mute_cb)
		JavaScriptBridge.eval("""
		(function () {
			window.__vringeMute = function (on) {
				try { if (window.__vringeMuteGd) { window.__vringeMuteGd(on === true); } } catch (e) {}
			};
		})();
		""", true)
	provider = "yandex"


## Колбэк из страницы: нужно заглушить/вернуть звук игры.
func _on_page_mute(args: Array) -> void:
	var on: bool = bool(args[0]) if args.size() > 0 else false
	_set_master_mute(on)


## Глушим мастер-шину. Отдельно запоминаем, что звук выключен именно нами,
## чтобы не перебить пользовательские настройки громкости.
var _page_muted := false


func _set_master_mute(on: bool) -> void:
	if _page_muted == on:
		return
	_page_muted = on
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_mute(idx, on)


func is_page_muted() -> bool:
	return _page_muted


## Игра загрузилась и показывает меню — можно сообщить платформе, что готово
## (иначе «экран загрузки» у Яндекса висит и модерация ругается, п. 1.14).
func notify_game_ready() -> void:
	if provider != "yandex":
		return
	JavaScriptBridge.eval("if (window.__vringeSignalReady) { window.__vringeSignalReady(); }", true)


## v71s: игра открыта внутри площадки Яндекс Игр? Только на web и только если
## страница (web/yandex_bootstrap.js) подтвердила: iframe + домен/referrer Яндекса
## или успешно поднятый SDK (window.__vringeHosted === true).
##
## Важно: одного «мы в iframe» недостаточно — itch.io и GitHub Pages тоже грузят
## игру в iframe. Там признак остаётся false, и кнопка «ПОДДЕРЖАТЬ» (boosty.to,
## внешняя ссылка) должна показываться. Внутри Яндекса внешние ссылки запрещены
## правилами площадки — кнопку убираем, ссылку не открываем.
func is_hosted() -> bool:
	if not OS.has_feature("web"):
		return false
	return bool(JavaScriptBridge.eval("window.__vringeHosted === true", true))


## Чем площадка подтвердилась: "frame+host" (домен/referrer Яндекса) или "sdk"
## (YaGames.init ответил). Пусто — не площадка. Для лога и отладки.
func hosted_reason() -> String:
	if not OS.has_feature("web"):
		return ""
	return str(JavaScriptBridge.eval("window.__vringeHostedBy || ''", true))


## v71t: разметка геймплея для площадки (п. 1.19.3) — сообщаем Яндексу, когда
## идёт игра, а когда меню/результат. Вызовы безопасны: нет SDK/API — тишина.
func gameplay_start() -> void:
	if provider != "yandex":
		return
	JavaScriptBridge.eval("if (window.__vringeGameplay) { window.__vringeGameplay(true); }", true)


func gameplay_stop() -> void:
	if provider != "yandex":
		return
	JavaScriptBridge.eval("if (window.__vringeGameplay) { window.__vringeGameplay(false); }", true)


## Язык, который отдаёт площадка (i18n), пусто — если SDK не поднялся.
func sdk_lang() -> String:
	if provider != "yandex":
		return ""
	return str(JavaScriptBridge.eval("window.__vringeLang || ''", true)).to_lower()


## Почему SDK не готов (для лога/отладки).
func sdk_error() -> String:
	if provider != "yandex":
		return ""
	return str(JavaScriptBridge.eval("window.__vringeSdkError || ''", true))


## Опрашивать статус SDK: он инициализируется асинхронно, поэтому проверяем
## несколько секунд, а не один раз (иначе «готов» остаётся false навсегда).
var _sdk_poll_t := 0.0


func _poll_web() -> void:
	if _js_ready or provider != "yandex":
		return
	if _sdk_poll_t <= 0.0:
		_sdk_poll_t = 0.0
	_sdk_poll_t += 0.0
	_js_fail = sdk_error()
	_js_ready = bool(JavaScriptBridge.eval("window.__vringeSdkReady === true", true))
	if _js_ready:
		print("ADS web: SDK Яндекс Игр готов, язык=", sdk_lang())
	elif _log:
		print("ADS web: SDK пока не готов (", _js_fail, ")")


## --- android / AdMob ---------------------------------------------------------

## Плагин AdMob (если он собран в APK) даёт синглтон. Без плагина/ID — тишина.
func _setup_android() -> void:
	if not Engine.has_singleton("AdMob"):
		provider = "none"
		return
	_admob = Engine.get_singleton("AdMob")
	provider = "admob"
	_load_admob_ids()
	if admob_interstitial_id != "" and _admob.has_method("load_interstitial"):
		_admob.load_interstitial(admob_interstitial_id)


## ID блоков берём из user://ads.cfg (её кладёт заказчик/сборщик), затем env.
func _load_admob_ids() -> void:
	var path := "user://ads.cfg"
	var cfg := ConfigFile.new()
	if cfg.load(path) == OK:
		admob_interstitial_id = str(cfg.get_value("admob", "interstitial", admob_interstitial_id))
		admob_banner_id = str(cfg.get_value("admob", "banner", admob_banner_id))
	var env_i := OS.get_environment("VRINGE_ADMOB_INTERSTITIAL").strip_edges()
	if env_i != "":
		admob_interstitial_id = env_i


## --- показ ------------------------------------------------------------------

func _process(delta: float) -> void:
	if _cooldown > 0.0:
		_cooldown = maxf(0.0, _cooldown - delta)
	if provider == "yandex" and not _js_ready:
		_poll_web()


## Готов ли какой-то провайдер (для отладочного лога и гейта).
func ready_to_show() -> bool:
	if not enabled or _cooldown > 0.0:
		return false
	match provider:
		"yandex":
			return _js_ready
		"admob":
			return _admob != null and admob_interstitial_id != ""
	return false


## Сколько секунд игра уже идёт бе�� рекламы.
func _session_sec() -> float:
	return float(Time.get_ticks_msec() - _started_msec) / 1000.0


## Показать межстраничную рекламу. Возвращает true, если запрос реально ушёл.
## Безопасно вызывать откуда угодно: при отсутствии провайдера просто false.
func show_interstitial(tag: String = "") -> bool:
	_tried += 1
	if not ready_to_show():
		_log_skip(tag)
		return false
	match provider:
		"yandex":
			# 4.7: пока идёт полноэкранная реклама, звук игры заглушён; страница
			# вернёт его сама в onClose/onError через __vringeMute.
			JavaScriptBridge.eval("""
			(function () {
				try {
					if (!window.__vringeSdk || !window.__vringeSdk.adv) { return; }
					if (window.__vringeMute) { window.__vringeMute(true); }
					window.__vringeSdk.adv.showFullscreenAdv({callbacks: {
						onClose: function (wasShown) {
							window.__vringeLastAd = wasShown === true;
							if (window.__vringeMute) { window.__vringeMute(false); }
						},
						onError: function (e) {
							window.__vringeLastAd = false;
							if (window.__vringeMute) { window.__vringeMute(false); }
						}
					}});
					window.__vringeLastAd = true;
				} catch (e) {
					window.__vringeLastAd = false;
					if (window.__vringeMute) { window.__vringeMute(false); }
				}
			})();
			""", true)
		"admob":
			if _admob.has_method("show_interstitial"):
				_admob.show_interstitial()
			else:
				return false
		_:
			return false
	_shown += 1
	_cooldown = COOLDOWN_SEC
	fights_since_ad = 0
	print("ADS показ #", _shown, " тег=", tag, " провайдер=", provider,
			" сессия=%.0f с" % _session_sec())
	return true


## Новый бой начался/закончился: копим счётчик для частотного капа.
func note_fight_finished() -> void:
	fights_since_ad += 1
	if _log:
		print("ADS боёв_с_показа=", fights_since_ad, " порог=", AD_EVERY_FIGHTS)


## Момент, когда уместно показать рекламу после боя (результат на экране).
func fight_end_slot() -> bool:
	if fights_since_ad < AD_EVERY_FIGHTS:
		return false
	return show_interstitial("fight_end")


## Тренировка закончена (пауза между локациями) — не раньше HOLD_MIN секунд сессии.
func training_slot() -> bool:
	if _session_sec() < HOLD_MIN:
		return false
	return show_interstitial("training_end")


func _log_skip(tag: String) -> void:
	if not _log:
		return
	print("ADS пропуск тег=", tag, " провайдер=", provider, " готов=", ready_to_show(),
			" кулдаун=%.0f" % _cooldown, " боёв=", fights_since_ad)


## Сводка для отладочных прогонов/гейта.
func debug_state() -> Dictionary:
	return {"provider": provider, "enabled": enabled, "ready": ready_to_show(),
			"shown": _shown, "tried": _tried, "fights": fights_since_ad,
			"web_ready": _js_ready, "web_error": _js_fail, "hosted": is_hosted(),
			"admob_id": admob_interstitial_id != ""}


func shown_count() -> int:
	return _shown


func tried_count() -> int:
	return _tried
