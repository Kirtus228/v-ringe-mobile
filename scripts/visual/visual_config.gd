class_name VisualConfig
extends Resource
## Визуальный конфиг (Этап 1 визуального промта): единая точка правды по
## «насколько богатый визуал» и «есть ли процедурные анимации тренировки».
##
## Правила, под которые сделан файл:
##  - значения по умолчанию = поведение ДО правок (visual_level=OFF,
##    train_anim_level=OFF, use_skin_models=false): ничего не меняется;
##  - никаких хардкодов интенсивностей/лимитов: всё через @export-поля;
##  - логика боя/станций/баланса/сохранений сюда НЕ смотрит — только визуал,
##    свет, частицы и звук;
##  - в каждом модуле ровно ОДНА точка проверки: он спрашивает visual_on()/
##    anim_on()/use_skins()/light_mult()/particle_budget(), а не читает поля сам.

enum Level { OFF = 0, LOW = 1, MEDIUM = 2, HIGH = 3 }
enum AnimLevel { OFF = 0, BASIC = 1, FULL = 2 }
## v71: профиль качества для телефона/слабого ПК. AUTO — сам выбирает по платформе.
enum Quality { AUTO = 0, HIGH = 1, MEDIUM = 2, LOW = 3 }

## Ветка A (процедурные «модельки» вместо .glb). Включено по умолчанию:
## заказчик попросил, чтобы новые модельки были в игре, а не за флагом.
@export var use_skin_models := true
## Общий уровень визуала. HIGH — новые модельки, свет, локации и арены.
## Для проверки «как было» можно запустить с -- --visual=OFF --trainanim=OFF.
@export var visual_level: int = Level.HIGH
## Процедурные ключи анимации станций тренировки (бёрпи, жим, бег и т.д.).
@export var train_anim_level: int = AnimLevel.FULL

@export_group("Профиль качества v71 (телефон / слабый ПК)")
## Текущий профиль качества. AUTO = по платформе (mobile → LOW, desktop → HIGH).
@export var quality: int = Quality.AUTO
## Что ставить при AUTO на десктопе (HIGH = картинка как сейчас, без ухудшений).
@export var auto_desktop_quality: int = Quality.HIGH
## Что ставить при AUTO на мобильном (Android/iOS): LOW — главный антилаг-профиль.
@export var auto_mobile_quality: int = Quality.LOW
## MSAA 3D: 0=off, 1=2x, 2=4x, 3=8x (значение совпадает с Viewport.MSAA_*).
@export var msaa_high := 2
@export var msaa_medium := 0
@export var msaa_low := 0
## Масштаб 3D-рендера (1.0 = нативное разрешение; меньше = дешевле по пикселям).
@export var render_scale_high := 1.0
@export var render_scale_medium := 0.85
@export var render_scale_low := 0.70
## Множитель glow в окружении по профилю (0 = выключить свечение целиком).
@export var glow_scale_high := 1.0
@export var glow_scale_medium := 0.55
@export var glow_scale_low := 0.0
## Тени направленного света: HIGH/MEDIUM — вкл, LOW — выкл.
@export var shadows_high := true
@export var shadows_medium := true
@export var shadows_low := false
## Множители бюджетов по профилю.
@export var particles_mult_medium := 0.60
@export var particles_mult_low := 0.35
@export var decals_mult_medium := 0.50
@export var decals_mult_low := 0.25
@export var lights_mult_medium := 0.6
@export var lights_mult_low := 0.50
@export var crowd_mult_medium := 0.70
@export var crowd_mult_low := 0.45
## Базовые бюджеты (при HIGH): декали на сцену, источники света на сцену.
@export var decals_budget_high := 8
@export var lights_budget_high := 6

@export_group("Бюджеты частиц (Этап 7)")
## Лимит живых частиц на локацию при HIGH (железо: 2000).
@export var particles_budget_high := 2000
## Лимит живых частиц на локацию при LOW/MEDIUM (железо: 300).
@export var particles_budget_low := 300

@export_group("Интенсивности (Этапы 2-6)")
## Множитель энергии света (1.0 — как в baseline).
@export var light_energy_mult := 1.0
## Множитель свечения (glow) в Environment (1.0 — как в baseline).
@export var glow_mult := 1.0
## Множитель длины/яркости следов перчаток и искр (1.0 — как в baseline).
@export var fx_mult := 1.0

@export_group("Свет на бойцов (Этап 2)")
## Заполняющий свет (мягкая подсветка спереди-сверху): энергия.
@export var fighter_fill_energy := 0.35
## Радиус заполняющего света, м.
@export var fighter_fill_range := 2.4
## Цвет заполняющего света.
@export var fighter_fill_color := Color(1.0, 0.93, 0.84)
## Контровой свет (обводит силуэт сзади): энергия.
@export var fighter_rim_energy := 0.75
## Радиус контрового света, м.
@export var fighter_rim_range := 6.5
## Угол контрового света, градусы.
@export var fighter_rim_angle := 54.0
## Цвет контрового света.
@export var fighter_rim_color := Color(0.62, 0.78, 1.0)
## Множитель для света заставки: энергии бойцовского fill/rim переводятся в
## энергии прожекторов отдельного вьюпорта заставки (у них другой масштаб сцены).
@export var splash_light_mult := 3.2


## Есть ли хоть какой-то дополнительный визуал (уровень выше OFF).
func visual_on() -> bool:
    return visual_level != Level.OFF


## Включены ли процедурные ключи анимации тренировки.
func anim_on() -> bool:
    return train_anim_level != AnimLevel.OFF


## Включены ли «скин-модельки» (ветка A).
func use_skins() -> bool:
    return use_skin_models


## Уровень как читаемая строка (для логов и отчётов).
func level_name() -> String:
    return level_to_string(visual_level)


func anim_level_name() -> String:
    return anim_level_to_string(train_anim_level)


## Множитель света: OFF — строго 1.0 (байт-в-байт как раньше).
func light_mult() -> float:
    if not visual_on():
        return 1.0
    return maxf(0.0, light_energy_mult)


## Множитель свечения: OFF — строго 1.0.
func glow_factor() -> float:
    if not visual_on():
        return 1.0
    return maxf(0.0, glow_mult)


## Бюджет живых частиц для текущего уровня и профиля качества.
func particle_budget() -> int:
    if not visual_on():
        return 0
    var base := int(particles_budget_high) if visual_level >= Level.HIGH \
            else int(particles_budget_low)
    return int(float(base) * quality_particle_mult())


## v71: разрешённый профиль качества (AUTO разворачивается по платформе).
## env VRINGE_QUALITY=HIGH|MEDIUM|LOW|AUTO — для замеров/QA без правки main.gd.
func effective_quality() -> int:
    var env_q := OS.get_environment("VRINGE_QUALITY").strip_edges()
    if env_q != "":
        var eq := quality_from_string(env_q)
        if eq != Quality.AUTO:
            return eq
    if quality != Quality.AUTO:
        return quality
    if OS.has_feature("mobile") or DisplayServer.is_touchscreen_available():
        return int(auto_mobile_quality)
    return int(auto_desktop_quality)


func quality_name() -> String:
    return quality_to_string(effective_quality())


## Множитель частиц по профилю (HIGH = 1.0 — не меняет текущее поведение).
func quality_particle_mult() -> float:
    match effective_quality():
        Quality.LOW:
            return maxf(0.0, particles_mult_low)
        Quality.MEDIUM:
            return clampf(particles_mult_medium, 0.0, 1.0)
        _:
            return 1.0


func quality_decal_mult() -> float:
    match effective_quality():
        Quality.LOW:
            return maxf(0.0, decals_mult_low)
        Quality.MEDIUM:
            return clampf(decals_mult_medium, 0.0, 1.0)
        _:
            return 1.0


func quality_light_mult() -> float:
    match effective_quality():
        Quality.LOW:
            return maxf(0.0, lights_mult_low)
        Quality.MEDIUM:
            return clampf(lights_mult_medium, 0.0, 1.0)
        _:
            return 1.0


func quality_crowd_mult() -> float:
    match effective_quality():
        Quality.LOW:
            return maxf(0.0, crowd_mult_low)
        Quality.MEDIUM:
            return clampf(crowd_mult_medium, 0.0, 1.0)
        _:
            return 1.0


## Бюджет декалей на сцену (HIGH = как сейчас).
func decal_budget() -> int:
    if not visual_on():
        return 0
    return int(float(decals_budget_high) * quality_decal_mult())


## Бюджет источников света на сцену (HIGH = как сейчас).
func light_budget() -> int:
    if not visual_on():
        return 0
    return maxi(1, int(float(lights_budget_high) * quality_light_mult()))


func msaa_mode() -> int:
    match effective_quality():
        Quality.LOW:
            return int(msaa_low)
        Quality.MEDIUM:
            return int(msaa_medium)
        _:
            return int(msaa_high)


func render_scale() -> float:
    match effective_quality():
        Quality.LOW:
            return clampf(render_scale_low, 0.4, 1.0)
        Quality.MEDIUM:
            return clampf(render_scale_medium, 0.4, 1.0)
        _:
            return clampf(render_scale_high, 0.4, 1.0)


func shadows_enabled() -> bool:
    match effective_quality():
        Quality.LOW:
            return bool(shadows_low)
        Quality.MEDIUM:
            return bool(shadows_medium)
        _:
            return bool(shadows_high)


## Множитель glow с учётом профиля (LOW может полностью выключить свечение).
func quality_glow_scale() -> float:
    match effective_quality():
        Quality.LOW:
            return maxf(0.0, glow_scale_low)
        Quality.MEDIUM:
            return clampf(glow_scale_medium, 0.0, 1.0)
        _:
            return clampf(glow_scale_high, 0.0, 1.0)


## v71: ЕДИНАЯ точка применения профиля к вьюпорту (MSAA, масштаб 3D-рендера)
## + debug-лог. main.gd должен вызвать это ОДИН раз после создания VisualConfig:
##   visual.apply_to_viewport(get_viewport(), get_window())
## Глоу/тени применяются в apply_environment() и в модулях света.
func apply_to_viewport(vp: Viewport, win: Window = null) -> void:
    if vp == null:
        return
    vp.msaa_3d = msaa_mode()
    vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
    vp.scaling_3d_scale = render_scale()
    if win != null:
        win.msaa_2d = Viewport.MSAA_DISABLED if msaa_mode() == 0 else win.msaa_2d
    log_quality()


## QA-хук: если VRINGE_APPLY_QUALITY=1, первый собранный модуль применяет профиль
## к вьюпорту сам (чтобы проверить MSAA/масштаб до патча main.gd). В обычной игре
## main.gd вызывает apply_to_viewport() напрямую, и хук не нужен.
var _quality_applied_once := false


func maybe_apply_quality(vp: Viewport, win: Window = null) -> void:
    if _quality_applied_once or OS.get_environment("VRINGE_APPLY_QUALITY") != "1":
        return
    _quality_applied_once = true
    apply_to_viewport(vp, win)


## Однострочный debug-лог профиля (для отчётов и QA).
func log_quality() -> void:
    print("QUALITY profile=", quality_name(),
            " auto_desktop=", quality_to_string(int(auto_desktop_quality)),
            " auto_mobile=", quality_to_string(int(auto_mobile_quality)),
            " visual=", level_name(), " skins=", str(use_skin_models),
            " train_anim=", anim_level_name(),
            " msaa=", msaa_mode(), " render_scale=%.2f" % render_scale(),
            " glow×%.2f" % quality_glow_scale(), " shadows=", str(shadows_enabled()),
            " particles_mult=%.2f" % quality_particle_mult(),
            " decals_mult=%.2f" % quality_decal_mult(),
            " lights_mult=%.2f" % quality_light_mult())


## Профиль одним словарём (для модулей: arena_visual/decor/blood_fx).
func quality_profile() -> Dictionary:
    return {"quality": effective_quality(), "name": quality_name(),
            "msaa": msaa_mode(), "render_scale": render_scale(),
            "glow": quality_glow_scale(), "shadows": shadows_enabled(),
            "particles": quality_particle_mult(), "decals": quality_decal_mult(),
            "lights": quality_light_mult(), "crowd": quality_crowd_mult(),
            "decal_budget": decal_budget(), "light_budget": light_budget()}


## Энергия заполняющего света на бойцов: OFF — 0.0 (свет вообще не создаётся).
func fighter_fill() -> float:
    if not visual_on():
        return 0.0
    return maxf(0.0, fighter_fill_energy)


## Энергия контрового света на бойцов: OFF — 0.0 (свет не создаётся).
func fighter_rim() -> float:
    if not visual_on():
        return 0.0
    return maxf(0.0, fighter_rim_energy)


## ЕДИНАЯ точка применения к WorldEnvironment. При OFF ничего не трогает
## (важно для гейта: кадр по умолчанию обязан совпасть с baseline).
func apply_environment(env: Environment) -> void:
    if env == null or not visual_on():
        return
    var g := glow_factor() * quality_glow_scale()
    if is_zero_approx(g):
        # v71 LOW: свечение выключаем совсем — дешевле на мобильном GPU
        env.glow_enabled = false
    elif not is_equal_approx(g, 1.0):
        env.glow_intensity = clampf(env.glow_intensity * g, 0.0, 8.0)


## Однострочное описание конфига для stdout (диагностика/отчёты).
func describe() -> String:
    return "visual=%s skins=%s train_anim=%s quality=%s light×%.2f glow×%.2f fx×%.2f part=%d" % [
        level_name(), str(use_skin_models), anim_level_name(), quality_name(),
        light_mult(), glow_factor(), maxf(0.0, fx_mult), particle_budget()]


# --- разбор аргументов командной строки (используется main.gd) --------------

static func level_from_string(s: String) -> int:
    match s.strip_edges().to_upper():
        "LOW", "1":
            return Level.LOW
        "MEDIUM", "MED", "2":
            return Level.MEDIUM
        "HIGH", "3":
            return Level.HIGH
        _:
            return Level.OFF


static func anim_level_from_string(s: String) -> int:
    match s.strip_edges().to_upper():
        "BASIC", "1":
            return AnimLevel.BASIC
        "FULL", "2":
            return AnimLevel.FULL
        _:
            return AnimLevel.OFF


static func level_to_string(v: int) -> String:
    match v:
        Level.LOW:
            return "LOW"
        Level.MEDIUM:
            return "MEDIUM"
        Level.HIGH:
            return "HIGH"
        _:
            return "OFF"


static func quality_from_string(s: String) -> int:
    match s.strip_edges().to_upper():
        "HIGH", "3":
            return Quality.HIGH
        "MEDIUM", "MED", "2":
            return Quality.MEDIUM
        "LOW", "1":
            return Quality.LOW
        _:
            return Quality.AUTO


static func quality_to_string(v: int) -> String:
    match v:
        Quality.LOW:
            return "LOW"
        Quality.MEDIUM:
            return "MEDIUM"
        Quality.HIGH:
            return "HIGH"
        _:
            return "AUTO"


static func anim_level_to_string(v: int) -> String:
    match v:
        AnimLevel.BASIC:
            return "BASIC"
        AnimLevel.FULL:
            return "FULL"
        _:
            return "OFF"
