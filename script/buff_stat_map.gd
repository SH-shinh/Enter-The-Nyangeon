class_name BuffStatMap

const PLAYER := 0
const ENEMY := 1
const SUMMONED := 2

const MAP := {
	"damage_mult": {
		PLAYER: "bullet_damage_mult",
		ENEMY: "ally_damage_mult",
		SUMMONED: "summoned_damage_mult_add",
	},
	"damage_add": {
		PLAYER: "bullet_damage_add",
		ENEMY: "ally_damage_add",
		SUMMONED: "summoned_damage_add",
	},
	"shoot_time_mult": {
		PLAYER: "bullet_shoot_time_mult",
		SUMMONED: "summoned_shoot_time_mult",
	},
	"speed_mult": {
		PLAYER: "MAX_SPEED_mult",
		ENEMY: "MAX_SPEED_mult",
		SUMMONED: "summoned_speed_mult",
	},
	"crit_luck_add": {
		PLAYER: "critical_luck_add",
	},
	"crit_damage_add": {
		PLAYER: "critical_damage_add",
	},
	"global_damage_mult": {
		PLAYER: "global_damage_mult",
		ENEMY: "Enemy_damage_mult",
	},
	"hurt_invalid_add": {
		PLAYER: "hurt_invalid_add",
	},
	"life_num_add": {
		PLAYER: "life_num_add",
	},
	"ability_mult": {
		PLAYER: "ability_mult",
	},
	"coin_mult_add": {
		PLAYER: "coin_mult_add",
	},
	"bullet_scale_mult": {
		PLAYER: "bullet_scale_mult",
	},
	"bullet_count_add": {
		PLAYER: "bullet_count_add",
	},
	"bullet_arc_add": {
		PLAYER: "bullet_arc_add",
	},
	"bullet_kill_time_mult": {
		PLAYER: "bullet_kill_time_mult",
	},
	"kick_damage_mult": {
		PLAYER: "kick_damage_mult",
	},
	"hurt_mult_mult": {
		PLAYER: "hurt_mult_mult",
		ENEMY: "global_hurt_damage_mult",
		SUMMONED: "global_hurt_damage_add",
	},
	"knockback_resis_mult": {
		PLAYER: "knockback_resis_mult",
	},
}

static func resolve(host_kind: int, key: String) -> String:
	var entry = MAP.get(key)
	if entry == null:
		return ""
	return entry.get(host_kind, "")
