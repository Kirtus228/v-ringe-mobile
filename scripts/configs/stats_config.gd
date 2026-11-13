class_name StatsConfig
extends Resource
## Конфиг влияния статов на бой. Экземпляр — resources/stats_config.tres.
## Коэффициенты не хардкодятся в логике: StatsManager берёт их отсюда.

## Во сколько раз растёт урон при стате = max_stat (при стате 0 — ×1.0).
@export var strength_to_damage := 0.60
## Прибавка к максимуму здоровья при стате = max_stat.
@export var stamina_to_hp := 0.35
## Прибавка к скорости бойца при стате = max_stat.
@export var speed_to_move := 0.25
## Верхняя граница стата.
@export var max_stat := 100.0
## Стартовые значения (новый сейв).
@export var default_stats := {"strength": 10.0, "stamina": 10.0, "speed": 10.0}
