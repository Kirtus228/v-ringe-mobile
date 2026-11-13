class_name TrainingLocationDef
extends Resource
## Описание тренировочной локации (зал, парк, додзё, крыша, подвал).
## Геометрия строится процедурно по полям этих ресурсов + кодом локации.

@export var id := ""
@export var title := ""
@export_multiline var description := ""
## Множители прироста статов в этой локации, например {"stamina": 1.2}.
@export var stat_bonus := {"strength": 1.0}
## Условия разблокировки: {"wins": 2} / {"stat": "strength", "min": 20}
## / {"visited": ["gym"]} / {"any_stat": ["stamina", 30]}. Пусто — открыта всегда.
@export var unlock := {}
## Полосы станций этой локации.
@export var stations: Array[StationDef] = []
## Атмосфера: цвет бетона/пола, цвет света, яркость (для процедурной сцены).
@export var floor_color := Color(0.32, 0.30, 0.28)
@export var light_color := Color(1.0, 0.86, 0.66)
@export var light_energy := 1.1
@export var ambient_energy := 0.35
## Сколько света (0 — тускло, 1 — ярко).
@export var brightness := 0.6


func bonus_mult(stat_name: String) -> float:
	return float(stat_bonus.get(stat_name, 1.0))
