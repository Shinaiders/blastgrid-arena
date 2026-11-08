class_name TestCase
extends RefCounted
## Base leve para suítes de teste headless (ARCHITECTURE §3 — sem plugins pagos).

var failures: Array[String] = []
var assertions := 0


func check(cond: bool, msg: String) -> void:
	assertions += 1
	if not cond:
		failures.append(msg)


func eq(actual: Variant, expected: Variant, msg: String) -> void:
	assertions += 1
	if actual != expected:
		failures.append("%s (esperado=%s, obtido=%s)" % [msg, str(expected), str(actual)])


func ne(actual: Variant, unexpected: Variant, msg: String) -> void:
	assertions += 1
	if actual == unexpected:
		failures.append("%s (não esperava=%s)" % [msg, str(actual)])

