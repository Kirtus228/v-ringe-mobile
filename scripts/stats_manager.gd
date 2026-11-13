extends Node
## Статы персонажа: strength, stamina, speed в диапазоне 0..max_stat.
## Живут в autoload, сохраняются в save.dat (секция [stats]) и влияют на бой
## через коэффициенты StatsConfig, а не хардкодом в боевой логике.
##
## API:
##   StatsManager.get_stat("strength") -> float
##   StatsManager.add_stat("strength", 0.2)   # с клампингом и сигналом
##   StatsManager.damage_mult() / max_hp_mult() / move_mult()
##   StatsManager.connect("stat_changed", Callable(self, "_on_stat"))

signal stat_changed(name: String, value: float)
signal stats_loaded

const StatsConfigScript := preload("res://scripts/configs/stats_config.gd")
const CONFIG_PATH := "res://resources/stats_config.tres"
const STAT_NAMES := ["strength", "stamina", "speed"]
const SECTION := "stats"
const AUTOSAVE_DELAY := 0.6

var config: Resource
var _stats: Dictionary = {}
var _autosave: Timer


func _ready() -> void:
	config = _load_config()
	_autosave = Timer.new()
	_autosave.one_shot = true
	_autosave.wait_time = AUTOSAVE_DELAY
	_autosave.timeout.connect(_on_autosave_timeout)
	add_child(_autosave)
	if SaveManager != null:
		SaveManager.load_all()
	load_stats()


func _load_config() -> Resource:
	if ResourceLoader.exists(CONFIG_PATH):
		var res := ResourceLoader.load(CONFIG_PATH)
		if res != null and res.get_script() == StatsConfigScript:
			return res
	return StatsConfigScript.new()


func max_stat() -> float:
	return float(config.max_stat) if config != null else 100.0


func load_stats() -> void:
	_stats = {}
	var defaults: Dictionary = config.default_stats if config != null else {}
	for n in STAT_NAMES:
		var def := float(defaults.get(n, 0.0))
		var v := def
		if SaveManager != null:
			v = float(SaveManager.load_value(SECTION, n, def))
		_stats[n] = clampf(v, 0.0, max_stat())
	stats_loaded.emit()


func save_stats() -> void:
	if SaveManager == null:
		return
	for n in STAT_NAMES:
		SaveManager.save_value(SECTION, n, float(_stats.get(n, 0.0)))
	SaveManager.flush()


func get_stat(name: String) -> float:
	return float(_stats.get(name, 0.0))


## Добавляет стат с клампингом. Возвращает фактическую прибавку (может быть 0,
## если стат уже на максимуме). Прибавка учитывает бонусы локаций — множители
## передаются снаружи, чтобы StationDef решал, сколько начислить.
func add_stat(name: String, amount: float) -> float:
	if not STAT_NAMES.has(name) or amount == 0.0:
		return 0.0
	var old := get_stat(name)
	var new_value := clampf(old + amount, 0.0, max_stat())
	if is_equal_approx(old, new_value):
		return 0.0
	_stats[name] = new_value
	stat_changed.emit(name, new_value)
	if _autosave != null:
		_autosave.start()
	return new_value - old


func set_stat(name: String, value: float) -> void:
	if not STAT_NAMES.has(name):
		return
	var new_value := clampf(value, 0.0, max_stat())
	if is_equal_approx(get_stat(name), new_value):
		return
	_stats[name] = new_value
	stat_changed.emit(name, new_value)
	if _autosave != null:
		_autosave.start()


func reset_stats() -> void:
	var defaults: Dictionary = config.default_stats if config != null else {}
	for n in STAT_NAMES:
		set_stat(n, float(defaults.get(n, 0.0)))
	save_stats()


func to_dict() -> Dictionary:
	return _stats.duplicate(true)


# --- влияние на бой: сюда смотрит боевая логика -----------------------------

## Множитель урона игрока: 1.0 при strength=0, 1.0+strength_to_damage на максимуме.
func damage_mult() -> float:
	if config == null:
		return 1.0
	return 1.0 + config.strength_to_damage * (get_stat("strength") / maxf(1.0, max_stat()))


## Множитель максимального здоровья.
func max_hp_mult() -> float:
	if config == null:
		return 1.0
	return 1.0 + config.stamina_to_hp * (get_stat("stamina") / maxf(1.0, max_stat()))


## Множитель скорости/темпа.
func move_mult() -> float:
	if config == null:
		return 1.0
	return 1.0 + config.speed_to_move * (get_stat("speed") / maxf(1.0, max_stat()))


func _on_autosave_timeout() -> void:
	save_stats()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if SaveManager != null:
			SaveManager.flush()
