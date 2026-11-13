extends Node
## Единое сохранение игры: user://save.dat, секции [meta], [stats], [training],
## [arenas], [settings]. Запись атомарная: пишем во временный файл, потом
## переименовываем поверх основного — обрыв на середине записи не портит сейв.
##
## API:
##   SaveManager.save_value("stats", "strength", 42.0)
##   var v = SaveManager.load_value("stats", "strength", 0.0)
##   SaveManager.flush()   # записать на диск прямо сейчас
##   SaveManager.save_all()  # то же, что flush, для читаемости

signal saved

const SAVE_PATH := "user://save.dat"
const TEMP_PATH := "user://save.tmp"
const SAVE_VERSION := 1

var data: Dictionary = {}
var _dirty := false
## Рабочий путь сейва. Переопределяется переменной окружения
## VRINGE_SAVE_PATH — нужно для тестовых прогонов, когда user:// (папка
## профиля) недоступна на запись, например внутри песочницы.
var save_path := SAVE_PATH
var temp_path := TEMP_PATH


func _ready() -> void:
	_apply_override()
	load_all()
	# T3: автотест имени героя. Запускается из автозагрузки, потому что main.gd
	# на время T3 закрыт; тест ждёт, пока main построит HUD, и проверяет его.
	if OS.get_cmdline_user_args().has("--namestest"):
		# имя «Кирилл» пишем ДО сборки HUD — так проверяем, что HUD сам читает
		# сохранённое имя, без подсказок из main.
		save_value(NAME_SECTION, NAME_KEY, "Кирилл")
		flush()
		call_deferred("_run_namestest")


func _apply_override() -> void:
	if not OS.has_environment("VRINGE_SAVE_PATH"):
		return
	var custom := OS.get_environment("VRINGE_SAVE_PATH").strip_edges()
	if custom == "":
		return
	save_path = custom
	temp_path = custom + ".tmp"


## Читает сейв с диска. Возвращает true, если файл был и прочитался.
func load_all() -> bool:
	data = {}
	if not FileAccess.file_exists(save_path):
		return false
	var cfg := ConfigFile.new()
	var err := cfg.load(save_path)
	if err != OK:
		push_warning("SaveManager: не смог прочитать %s (err %d)" % [save_path, err])
		return false
	for section in cfg.get_sections():
		data[section] = {}
		for key in cfg.get_section_keys(section):
			data[section][key] = cfg.get_value(section, key)
	_migrate()
	return true


## Записывает сейв на диск атомарно.
func flush() -> void:
	if data.is_empty():
		data["meta"] = {"version": SAVE_VERSION}
	var cfg := ConfigFile.new()
	data["meta"] = data.get("meta", {})
	data["meta"]["version"] = SAVE_VERSION
	data["meta"]["saved_at"] = int(Time.get_unix_time_from_system())
	for section in data:
		var vals: Dictionary = data[section]
		for key in vals:
			cfg.set_value(String(section), String(key), vals[key])
	var err := cfg.save(temp_path)
	if err != OK:
		push_warning("SaveManager: не смог записать временный сейв (err %d)" % err)
		return
	var abs_temp := ProjectSettings.globalize_path(temp_path)
	var abs_save := ProjectSettings.globalize_path(save_path)
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(abs_save)
	err = DirAccess.rename_absolute(abs_temp, abs_save)
	if err != OK:
		push_warning("SaveManager: переименование сейва не удалось (err %d)" % err)
		return
	_dirty = false
	saved.emit()


## То же, что flush(); оставлено как понятный синоним для вызывающего кода.
func save_all() -> void:
	flush()


func save_value(section: String, key: String, value: Variant) -> void:
	if not data.has(section):
		data[section] = {}
	data[section][key] = value
	_dirty = true


func load_value(section: String, key: String, default_value: Variant = null) -> Variant:
	if not data.has(section):
		return default_value
	var s: Dictionary = data[section]
	if not s.has(key):
		return default_value
	return s[key]


func has_section(section: String) -> bool:
	return data.has(section)


func section(section: String) -> Dictionary:
	return (data.get(section, {}) as Dictionary).duplicate(true)


func replace_section(section: String, values: Dictionary) -> void:
	data[section] = values.duplicate(true)
	_dirty = true


func is_dirty() -> bool:
	return _dirty


## Совместимость версий: сейчас одна версия, но точка расширения нужна.
func _migrate() -> void:
	if not data.has("meta"):
		data["meta"] = {}
	var ver := int(data["meta"].get("version", 0))
	if ver == SAVE_VERSION:
		return
	if ver < 1:
		# v0 — сейва не было или он от будущей версии: оставляем как есть,
		# секции читаются по ключам с дефолтами.
		pass
	data["meta"]["version"] = SAVE_VERSION


# ---------------------------------------------------------------- имя героя (T3)
## Имя героя живёт в отдельной секции профиля, поэтому старый сейв без неё
## читается как есть и получает дефолт. Санитайзер общий для ввода и чтения.
const NAME_SECTION := "profile"
const NAME_KEY := "player_name"
const NAME_DEFAULT := "Искра"
const NAME_MIN := 2
const NAME_MAX := 16
const Lang := preload("res://scripts/lang.gd")


## Обрезка/чистка имени: убираем управляющие и невидимые символы, сжимаем
## пробелы, режем до 16 символов. Если после чистки меньше 2 значащих символов
## (пустая строка, одни пробелы, один эмодзи) — возвращаем дефолт «Искра».
static func sanitize_player_name(raw: String) -> String:
	var cleaned := ""
	var s := String(raw)
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 32 or c == 127:
			continue  # управляющие
		if c >= 0x200B and c <= 0x200F:
			continue  # zero-width/направление письма
		if c >= 0x202A and c <= 0x202E:
			continue
		if c == 0xFEFF:
			continue  # BOM
		if c >= 0xE000 and c <= 0xF8FF:
			continue  # приватная зона
		cleaned += String.chr(c)
	# пробелы/табы/переносы — по одному между словами
	var out := ""
	var prev_space := false
	for i in cleaned.length():
		var c := cleaned.unicode_at(i)
		var is_space := c == 32 or c == 9 or c == 10 or c == 13
		if is_space:
			if not prev_space and out != "":
				out += " "
			prev_space = true
		else:
			out += String.chr(c)
			prev_space = false
	out = out.strip_edges()
	if out.length() > NAME_MAX:
		out = out.substr(0, NAME_MAX).strip_edges()
	if _valid_name_chars(out) < NAME_MIN:
		return NAME_DEFAULT
	return out


## Значащие символы: всё, кроме пробелов (эмодзи считаются символами, поэтому
## два эмодзи имя, а один — уже нет).
static func _valid_name_chars(s: String) -> int:
	var n := 0
	for i in s.length():
		if s.unicode_at(i) != 32:
			n += 1
	return n


## Сохранённое имя с дефолтом (старый сейв → «Искра»).
func player_name() -> String:
	var raw := String(load_value(NAME_SECTION, NAME_KEY, ""))
	if raw.strip_edges() == "":
		return NAME_DEFAULT
	return sanitize_player_name(raw)


## Записать имя: санитайз → сейв → flush. Возвращает то, что реально сохранено.
func set_player_name(raw: String) -> String:
	var clean := sanitize_player_name(raw)
	save_value(NAME_SECTION, NAME_KEY, clean)
	flush()
	return clean


func reset_player_name() -> void:
	save_value(NAME_SECTION, NAME_KEY, NAME_DEFAULT)
	flush()


## T3-автотест. Живёт в автозагрузке, т.к. main.gd на время T3 закрыт.
## Печатает NAMESTESTNAME ок=<true|false> и таблицу.
func _run_namestest() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var ok := true
	var rows: Array = []
	# 1) HUD собрался из сейва, куда _ready записал «Кирилл»
	var from_save := player_name()
	ok = ok and from_save == "Кирилл"
	var hud := _find_hud()
	var hud_txt := ""
	if hud != null and hud.has_method("player_label_text"):
		hud_txt = String(hud.call("player_label_text"))
	ok = ok and hud_txt == "Кирилл"
	rows.append("hud_из_сейва=" + hud_txt)
	# 2) установка и повторное чтение с диска
	var set_ok := set_player_name("Кирилл")
	load_all()
	var re_read := player_name()
	ok = ok and set_ok == "Кирилл" and re_read == "Кирилл"
	rows.append("сейв/чтение=" + re_read)
	# 3) длинная строка режется до NAME_MAX
	var long_raw := "А".repeat(40)
	var cut := sanitize_player_name(long_raw)
	ok = ok and cut.length() == NAME_MAX
	rows.append("обрезка40→%d" % cut.length())
	# 4) эмодзи не ломают: один → дефолт (<2 значащих), два → остаются
	var emoji1 := sanitize_player_name("😀")
	var emoji2 := sanitize_player_name("😀😀")
	var emoji_mix := sanitize_player_name("Кирилл😀")
	ok = ok and emoji1 == NAME_DEFAULT
	ok = ok and emoji2 == "😀😀"
	ok = ok and emoji_mix == "Кирилл😀"
	rows.append("эмодзи: один=дефолт, два=ок, микс=" + emoji_mix)
	# 5) пустая строка/пробелы → дефолт, управляющие символы вычищаются
	ok = ok and sanitize_player_name("") == NAME_DEFAULT
	ok = ok and sanitize_player_name("     ") == NAME_DEFAULT
	ok = ok and sanitize_player_name(" Кирилл ") == "Кирилл"
	# \u0007 (звонок) и \u001F (unit separator) — оба управляющие, не NUL:
	# NUL в строке ломает вывод в консоль и сам тест.
	var ctrl := sanitize_player_name("Ки\u0007ри\u001Fлл")
	ok = ok and ctrl == "Кирилл"
	rows.append("чистка=" + ctrl)
	# 6) HUD обновляется после смены имени и умеет фолбэк «ТЫ»/«YOU»
	set_player_name("Мастер")
	if hud != null and hud.has_method("refresh_player_name"):
		hud.call("refresh_player_name")
	var hud2 := ""
	if hud != null and hud.has_method("player_label_text"):
		hud2 = String(hud.call("player_label_text"))
	ok = ok and hud2 == "Мастер"
	rows.append("hud_после_смены=" + hud2)
	var fallback := ""
	if hud != null and hud.has_method("display_name"):
		fallback = String(hud.call("display_name", ""))
	var expect_you := "ТЫ" if not Lang.is_en() else "YOU"
	ok = ok and fallback == expect_you
	rows.append("фолбэк_пустого=" + fallback)
	# 7) поле ввода в настройках реально сохраняет имя (проверяем виджет HUD)
	if hud != null and hud.has_method("show_settings"):
		hud.call("show_settings", {"tab": 2})
		var field = hud.get("name_edit")
		if field != null:
			field.set("text", "Тестер")
			hud.call("_save_player_name")
			load_all()
			ok = ok and player_name() == "Тестер"
			rows.append("поле_настроек=" + player_name())
		else:
			ok = false
			rows.append("поле_настроек=НЕТ ПОЛЯ")
	# 8) дефолт восстанавливается и остаётся в сейве
	reset_player_name()
	load_all()
	ok = ok and player_name() == NAME_DEFAULT
	rows.append("итог_в_сейве=" + player_name())
	for i in rows.size():
		print("NAMESTESTNAME строка", i + 1, ": ", rows[i])
	print("NAMESTESTNAME ок=", str(ok))
	get_tree().quit()


## Найти HUD, который построил main (main.hud), не трогая main.gd.
func _find_hud() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var scene := tree.current_scene
	if scene == null:
		return null
	var h = scene.get("hud")
	if h is Node:
		return h as Node
	return null
