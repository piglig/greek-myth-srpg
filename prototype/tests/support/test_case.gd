extends GdUnitTestSuite
## Base for rule tests: thin helpers on top of gdUnit4 assertions.


func check(cond: bool, msg: String) -> void:
	assert_bool(cond).override_failure_message(msg).is_true()


func eq(actual, expected, msg: String = "") -> void:
	assert_that(actual).override_failure_message(
		"%s: expected %s, got %s" % [msg, str(expected), str(actual)]).is_equal(expected)


## Sums event field `field` over events matching `type` (and optionally `source`).
func sum_events(events: Array, type: String, field: String, source: String = "") -> int:
	var total := 0
	for e in events:
		if e["type"] == type and (source == "" or e.get("source", "") == source):
			total += int(e[field])
	return total


func has_event(events: Array, type: String) -> bool:
	for e in events:
		if e["type"] == type:
			return true
	return false
