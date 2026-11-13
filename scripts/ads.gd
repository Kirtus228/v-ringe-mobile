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

## Подгружаем SDK Яндекс Игр, только если страница открыта внутри площадки или
## SDK уже есть. На обычном хостинге (GitHub Pages) init просто не поднимется —
## игра работает как раньше, без рекламы.
func _setup_web() -> void:
	_js_fail = ""
	if not OS.has_feature("web"):
		return
	JavaScriptBridge.eval("""
	(function () {
		if (window.__vringeAdsBoot) { return; }
		window.__vringeAdsBoot = true;
		window.__vringeAdsReady = false;
		window.__vringeAdsError = "";
		function markReady() { window.__vringeAdsReady = true; }
		function load() {
			if (window.YaGames) {
				YaGames.init().then(function (sdk) {
					window.__vringeSdk = sdk;
					markReady();
				}).catch(function (e) { window.__vringeAdsError = String(e); });
				return;
			}
			// площадки нет — пробуем подтянуть SDK, он нужен только внутри Яндекс Игр
			var s = document.createElement('script');
			s.src = 'https://yandex.ru/games/sdk/v2';
			s.onload = function () {
				if (window.YaGames) { load(); } else { window.__vringeAdsError = 'no_sdk'; }
			};
			s.onerror = function () { window.__vringeAdsError = 'sdk_offline'; };
			document.head.appendChild(s);
		}
		load();
	})();
	""", true)
	provider = "yandex"


func _poll_web() -> void:
	if _js_checked or provider != "yandex":
		return
	_js_checked = true
	_js_fail = str(JavaScriptBridge.eval("window.__vringeAdsError || ''", true))
	_js_ready = bool(JavaScriptBridge.eval("window.__vringeAdsReady === true", true))
	if not _js_ready and _log:
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
	if provider == "yandex" and not _js_ready and not _js_checked:
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
			JavaScriptBridge.eval("""
			(function () {
				try {
					if (!window.__vringeSdk || !window.__vringeSdk.adv) { return; }
					window.__vringeSdk.adv.showFullscreenAdv({callbacks: {
						onClose: function (wasShown) { window.__vringeLastAd = wasShown === true; },
						onError: function (e) { window.__vringeLastAd = false; }
					}});
					window.__vringeLastAd = true;
				} catch (e) { window.__vringeLastAd = false; }
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
			"web_ready": _js_ready, "web_error": _js_fail,
			"admob_id": admob_interstitial_id != ""}


func shown_count() -> int:
	return _shown


func tried_count() -> int:
	return _tried
