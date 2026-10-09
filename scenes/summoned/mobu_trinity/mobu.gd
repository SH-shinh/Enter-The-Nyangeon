class_name MobSummoned
extends SummonedFollower

func idle_state():
	super.idle_state()
	GameEvents.round_end.connect(queue_free)
