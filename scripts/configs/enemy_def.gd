class_name EnemyDef
extends Resource
## Описание противника для арен: статы, манера, спецприёмы.
## AI остаётся существующий (main.gd/fighter.gd), здесь только пресет.

@export var id := ""
@export var title := ""
## Английское имя (additive, старые ресурсы без поля читают "").
@export var title_en := ""
## archetype: puncher / speedster / defender / aggressor / sniper / counter /
## tank / clincher (используются существующие стили ИИ).
@export var archetype := "aggressor"
@export var max_hp := 120.0
@export var damage_mult := 1.0
@export var speed_mult := 1.0
@export var aggression := 0.5
@export var stamina := 100.0
@export var skin_color := Color(0.72, 0.56, 0.44)
@export var shorts_color := Color(0.7, 0.1, 0.1)
## Спецприёмы: ["body_focus", "counter_hook", "pressure"] — читаются ареной.
@export var specials: Array[String] = []
