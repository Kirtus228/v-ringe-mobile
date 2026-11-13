class_name ArenaDef
extends Resource
## Описание боевой локации (арены) для режима «Боевые локации».
## Экземпляры — resources/arenas/*.tres, каталог собирает ArenaManager.

@export var id := ""
@export var title := ""
## Английское название (additive, старые ресурсы без поля читают "").
@export var title_en := ""
@export_multiline var description := ""
## Сцена/описание окружения: тип постройки, палитра, освещение.
@export var scene_kind := "underground"      # underground / club / street / cage / ring / beach / roof / factory / ship / boss
@export var floor_color := Color(0.24, 0.23, 0.22)
@export var light_color := Color(0.9, 0.75, 0.55)
@export var light_energy := 0.9
@export var ambient_energy := 0.25
@export var crowd := true
@export var obstacles := false
## 1..5
@export var difficulty := 1
@export var rounds := 1
@export var round_time := 90.0
@export var money_reward := 0
@export var reputation_reward := 0
## Прибавка статов за победу, например {"strength": 1.5, "stamina": 0.5}.
@export var stat_bonus_on_win := {}
## Условие открытия: {"visited_training": "gym", "wins": 2} / {"arena": "club"} / {}.
@export var unlock_condition := {}
## Модификаторы среды: surface_friction, gravity, wind, stamina_drain,
## hazards (Array), rocking, edge_hazard, fall_defeat, confined.
@export var environment_modifiers := {}
## Модификаторы правил: referee, rounds_to_win, time_limit, no_knockdown,
## no_healing, betting, boss_fight, phases, edge_hazard.
@export var rules_modifiers := {}
## Пул противников (EnemyDef).
@export var opponent_pool: Array[EnemyDef] = []
## Штрафовать очки за поражение (по умолчанию на аренах НЕ штрафуют).
@export var apply_ranked_penalty := false


func env_value(key: String, default_value: Variant = 0.0) -> Variant:
	return environment_modifiers.get(key, default_value)


func rule_value(key: String, default_value: Variant = null) -> Variant:
	return rules_modifiers.get(key, default_value)


func friction() -> float:
	return float(env_value("surface_friction", 1.0))
