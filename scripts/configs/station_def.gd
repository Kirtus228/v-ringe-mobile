class_name StationDef
extends Resource
## Описание тренажёрной станции. Один и тот же скрипт станции читает эти поля,
## поэтому локации отличаются конфигом, а не копипастой кода.

enum Kind { BAG, QTE, RHYTHM, HOLD }

@export var id := ""
@export var title := ""
@export_multiline var description := ""
@export var kind: Kind = Kind.BAG
## Прибавка к статам за одно успешное действие (например {"strength": 0.1}).
@export var stat_bonus := {"strength": 0.1}
## Пауза между успешными действиями, сек.
@export var cooldown := 0.5
## Сколько «повторов» надо сделать за подход (QTE/ритм/удержание), 0 — бесконечно.
@export var reps := 10
## Окно успеха для QTE/ритма, сек (perfect_window из ТЗ).
@export var perfect_window := 0.25
## Интервал, с которым идёт тайминг QTE (сек между подсказками), 0 — по умолчанию.
@export var interval := 0.9
## T-trainanim: пауза между окнами нажатий (QTE/ритм), сек. 3–5 с по ТЗ.
@export var qte_gap_seconds := 3.5
## T-trainanim: разброс паузы в обе стороны, сек (0.5 → 3.0…4.0 с).
@export var qte_gap_jitter := 0.5
## Сколько промахов прощается до конца подхода (ритм).
@export var mistakes_allowed := 3
## Длительность удержания для HOLD, сек.
@export var hold_time := 3.0
## Сколько прочности снимает одно использование (если износ включён).
@export var wear_per_use := 5.0
## Звук успеха/промаха (имена из sfx.gd).
@export var sfx_hit := "hit"
@export var sfx_fail := "gasp"


func display_bonus() -> String:
	var parts: Array[String] = []
	for k in stat_bonus:
		parts.append("%s +%s" % [String(k), String(stat_bonus[k])])
	return ", ".join(parts)
