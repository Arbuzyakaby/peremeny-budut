extends "res://tests/test_case.gd"
## «Контакт» (v10.0) по частям: знаки и оценка обводки (gesture.gd), мирный шаг врагов (calm_update)
## и мирный отряд (peace_squad.gd).

const Gesture = preload("res://scripts/contact/gesture.gd")
const PeaceSquad = preload("res://scripts/contact/peace_squad.gd")
const Fork = preload("res://scripts/entities/fork.gd")
const Pill = preload("res://scripts/entities/pill.gd")
const TeddyBear = preload("res://scripts/entities/teddy_bear.gd")
const Matryoshka = preload("res://scripts/entities/matryoshka.gd")

const AREA := Rect2(24, 24, 1232, 672)
const DT := 1.0 / 60.0
const C := Vector2(640, 360)
const HALF := 115.0


func before_each() -> void:
	use_temp_storage()


# ---------------------------------------------------------------- знаки

func test_every_kind_has_its_own_figure() -> void:
	for kind: String in Gesture.KINDS:
		var pts := Gesture.unit(kind)
		assert_gt(pts.size(), 10.0, "у знака «%s» есть контур" % kind)
		assert_gt(Gesture.length(pts), 3.0, "знак «%s» — длинная линия, а не точка" % kind)
		for p in pts:
			assert_true(absf(p.x) <= 1.05 and absf(p.y) <= 1.05, "знак «%s» в квадрате −1..1" % kind)
		assert_true(Gesture.NAMES.has(kind), "у знака «%s» есть название" % kind)


func test_exact_trace_is_accepted() -> void:
	for kind: String in Gesture.KINDS:
		var tmpl := Gesture.template(kind, C, HALF)
		var res := Gesture.score(tmpl, tmpl, Gesture.tol_for(1))
		assert_true(res["ok"], "точная обводка «%s» засчитана" % kind)
		assert_gt(float(res["coverage"]), 0.99)


func test_shaky_trace_within_tolerance_is_accepted() -> void:
	var tmpl := Gesture.template("bear", C, HALF)
	var trace := PackedVector2Array()
	for i in tmpl.size():
		trace.append(tmpl[i] + Vector2(sin(i * 1.3), cos(i * 0.7)) * 12.0)  # рука дрожит на 12 px
	assert_true(Gesture.score(trace, tmpl, Gesture.tol_for(1))["ok"], "дрожащая, но аккуратная обводка")


func test_reversed_trace_is_accepted() -> void:
	var tmpl := Gesture.template("doll", C, HALF)
	var rev := tmpl.duplicate()
	rev.reverse()
	assert_true(Gesture.score(rev, tmpl, Gesture.tol_for(1))["ok"], "направление обводки не важно")


func test_half_figure_is_rejected() -> void:
	var tmpl := Gesture.template("pill", C, HALF)
	var half := tmpl.slice(0, tmpl.size() / 2)
	var res := Gesture.score(half, tmpl, Gesture.tol_for(1))
	assert_false(res["ok"], "половина знака — не знак")
	assert_true(float(res["coverage"]) < 0.7)


func test_scribble_is_rejected() -> void:
	var tmpl := Gesture.template("egg", C, 150.0)
	seed(47)
	var scribble := PackedVector2Array()
	for i in 200:
		scribble.append(C + Vector2(randf_range(-150, 150), randf_range(-150, 150)))
	assert_false(Gesture.score(scribble, tmpl, Gesture.tol_for(0))["ok"], "каракули не засчитываются даже на лёгкой")


func test_figures_are_not_confused() -> void:
	for a: String in Gesture.KINDS:
		for b: String in Gesture.KINDS:
			if a == b:
				continue
			var res := Gesture.score(Gesture.template(a, C, HALF), Gesture.template(b, C, HALF), Gesture.tol_for(0))
			assert_false(res["ok"], "знак «%s» не сойдёт за «%s»" % [a, b])


func test_tolerance_tightens_with_difficulty() -> void:
	for i in 3:
		assert_gt(Gesture.tol_for(i), Gesture.tol_for(i + 1), "сложнее — точнее")
	assert_eq(Gesture.tol_for(99), Gesture.tol_for(3), "за краем — как на Ультра")


func test_resample_is_even() -> void:
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(100, 0)])
	var r := Gesture.resample(line, 11)
	assert_len(r, 11)
	for i in r.size():
		assert_near(r[i].x, i * 10.0, 0.01)


# ---------------------------------------------------------------- мирный шаг

func test_calm_bear_never_attacks() -> void:
	var b: TeddyBear = add(TeddyBear.new())
	b.setup(Vector2(300, 300), 60.0, AREA, TeddyBear.Type.BOXER, 2.0)
	var thrown := [0]
	b.throw_item.connect(func(_p: Vector2, _v: Vector2, _k: int) -> void: thrown[0] += 1)
	for i in 600:
		b.calm_update(DT, (Vector2(900, 500) - b.position).limit_length(120.0))
		assert_true(b.st == TeddyBear.St.ROAM, "мирный медведь не замахивается")
	assert_eq(thrown[0], 0, "ничего не бросает")
	assert_true(b.position.distance_to(Vector2(900, 500)) < 30.0, "дошёл, куда звали")


func test_calm_fork_pill_doll_never_attack() -> void:
	var f: Fork = add(Fork.new())
	f.setup(Vector2(300, 300), AREA, 1.0, 2.0, 1.0, Fork.Kind.PITCH)
	f.attack_cd = 0.0
	var p: Pill = add(Pill.new())
	p.setup(Vector2(400, 300), AREA, 1.0, 2.0)
	var m: Matryoshka = add(Matryoshka.new())
	m.setup(Vector2(500, 300), AREA, Matryoshka.Size.TINY, 1.0, 2.0)
	var events := [0]
	f.attack.connect(func(_k: String, _d: Dictionary) -> void: events[0] += 1)
	p.landed.connect(func(_pos: Vector2) -> void: events[0] += 1)
	m.landed.connect(func(_pos: Vector2) -> void: events[0] += 1)
	var goal := Vector2(1000, 500)
	for i in 600:
		f.calm_update(DT, (goal - f.position).limit_length(100.0), goal)
		p.calm_update(DT, (goal - p.position).limit_length(100.0))
		m.calm_update(DT, (goal - m.position).limit_length(100.0))
		assert_true(f.st == Fork.St.ROAM and p.st == Pill.St.IDLE and m.st == Matryoshka.St.ROAM, "ни прицела, ни прыжка")
	assert_eq(events[0], 0, "ни залпа, ни приземления с давкой")
	for n: Node2D in [f, p, m]:
		assert_true(n.position.distance_to(goal) < 40.0, "дошли, куда звали")


# ---------------------------------------------------------------- мирный отряд

func _entry(pos: Vector2, kind: String, convinced: bool, trust := 0.0) -> Dictionary:
	var n: Node2D = add(Node2D.new())
	n.position = pos
	return {"node": n, "kind": kind, "convinced": convinced, "trust": trust, "scared": 0.0, "speed": 80.0,
		"protected": false, "r": 18.0, "want": Vector2.ZERO}


func _history(from: Vector2, dir: Vector2, n := 60) -> PackedVector2Array:
	var h := PackedVector2Array()
	for i in n:
		h.append(from - dir * 12.0 * i)
	return h


func test_followers_take_separate_slots() -> void:
	var sq := PeaceSquad.new()
	var head := Vector2(640, 200)
	var list: Array = []
	for i in 5:
		list.append(_entry(Vector2(640, 600), "bear", true))
	sq.update(DT, head, true, _history(head, Vector2.UP), list, null)
	var slots := {}
	for k in 5:
		var p := PeaceSquad.slot_pos(k, _history(head, Vector2.UP), head)
		slots[Vector2i(p)] = true
		assert_true(p.y > head.y, "место — позади головы")
	assert_eq(slots.size(), 5, "у каждого своё место")
	for e: Dictionary in list:
		assert_true((e["want"] as Vector2).y < 0.0, "идут к змее")


func test_heralds_at_most_two_and_target_unconvinced() -> void:
	var sq := PeaceSquad.new()
	var head := Vector2(300, 360)
	var list: Array = []
	for i in 6:
		list.append(_entry(Vector2(300 + i * 20, 420), "bear", true))
	var wary := _entry(Vector2(900, 360), "fork", false)
	list.append(wary)
	sq.update(DT, head, true, _history(head, Vector2.RIGHT), list, null)
	var heralds := 0
	for e: Dictionary in list:
		if sq.is_herald(e["node"]):
			heralds += 1
			assert_true(e["convinced"], "вестник — из убеждённых")
			assert_true((e["want"] as Vector2).x > 0.0, "вестник идёт к неубеждённому")
	assert_eq(heralds, PeaceSquad.MAX_HERALDS, "вестников не больше двух")


func test_heralds_build_trust_then_wary_comes_to_talk() -> void:
	var sq := PeaceSquad.new()
	var head := Vector2(300, 360)
	var wary := _entry(Vector2(800, 360), "pill", false)
	var h1 := _entry(Vector2(800, 300), "bear", true)
	var h2 := _entry(Vector2(800, 420), "bear", true)
	var list: Array = [wary, h1, h2]
	for i in 300:
		sq.update(DT, head, false, _history(head, Vector2.RIGHT), list, null)
	assert_gt(float(wary["trust"]), PeaceSquad.LEAD_TRUST, "рядом вестники — доверие растёт")
	assert_true((wary["want"] as Vector2).x < 0.0, "доверяет — сам идёт к змее")


func test_wary_backs_off_and_scared_runs() -> void:
	var sq := PeaceSquad.new()
	var head := Vector2(600, 360)
	var wary := _entry(Vector2(700, 360), "doll", false)
	sq.update(DT, head, false, _history(head, Vector2.LEFT), [wary], null)
	assert_true((wary["want"] as Vector2).x > 0.0, "насторожен — пятится от змеи")
	var talking := _entry(Vector2(700, 360), "doll", false)
	sq.update(DT, head, false, _history(head, Vector2.LEFT), [talking], talking["node"])
	assert_eq(talking["want"], Vector2.ZERO, "с кем говорят — стоит и слушает")
