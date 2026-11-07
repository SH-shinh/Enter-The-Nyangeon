# 分类 id 清单（ENN 常用）

路径前缀：`third_party/pixelfx-godot/godot/addons/pixelfx/fx/<分类>/<id>.gd`。
循环列 = `meta.loop`；挑"状态贴花/常驻光环"时优先带循环的。

## status（13，全部循环）
`bleeding` `burning` `charmed` `confused` `cursed` `frozen` `haste` `petrified`
`poisoned` `rage` `sleep` `slowed` `stunned`

- 敌人状态光环：`poisoned`（已用于腐化）、`rage`（已用于狂怒）、`bleeding`、`cursed`。
- 玩家增益：`haste`、`blessing`（在 holy）。

## impacts（11，一次性 0.3–3.2s）
`blunt-hit` `bullet-impact` `crit-hit` `ground-slam` `heavy-landing` `hit-flash`
`hit-spark` `impact-frame` `parry` `ricochet` `shield-block`

- 命中反馈首选 `hit-spark` / `crit-hit`；格挡 `shield-block` / `parry`。

## pickups（11）
`chest-open` `coin-spin` `collect-burst` `crystal-shard` `gem-spin` `heart-pickup`
`key-glint` `loot-beam` `potion` `power-star` `xp-orb`

## ui（12，一次性）
`achievement` `coin-collect` `combo-counter` `confetti` `countdown` `crit-number`
`damage-number` `exclamation` `health-bar-hit` `heart-lost` `level-up` `quest-complete`

## holy（10）
`blessing` `divine-shield` `feather-burst` `halo` `heal-aoe` `heal` `holy-pillar`
`resurrection` `smite` `sunburst`

- 范围治疗/光环：`heal-aoe`（已 fork）、`halo`、`divine-shield`。

## nature（13）
`acid-splash` `boulder` `earth-spike` `healing-bloom` `leaf-storm` `poison-cloud`
`quake` `root-snare` `spore-burst` `thorns` `tornado` `toxic-puddle` `vine-whip`

- 地面毒池：`toxic-puddle`（冒泡已 fork）；扩散毒雾：`poison-cloud`。

## melee（12）
`claw-swipe` `dagger-flurry` `double-slash` `hammer-smash` `heavy-cleave`
`scythe-reap` `spear-sweep` `spin-slash` `sword-slash` `thrust` `uppercut` `whip-crack`

## fire（12）
`brazier` `campfire` `candle` `fire-breath` `fire-ring` `fire-tornado` `fireball`
`flame-pillar` `flamethrower` `meteor` `spirit-flame` `torch`

## ice（10）
`blizzard-vortex` `freeze` `frost-breath` `frost-nova` `ice-crystal` `ice-lance`
`ice-shatter` `ice-spikes` `icicle-fall` `snowflake-burst`

## arcane（12）
`arcane-beam` `arcane-missiles` `arcane-orb` `blink-in` `blink-out` `magic-circle-cast`
`mana-burst` `portal` `rune-circle` `spell-charge` `star-fall` `time-stop`

## 选型经验

| 需求 | 首选 | 备选 |
|---|---|---|
| 范围治疗提示 | `holy/heal-aoe` | `holy/halo`、`holy/blessing` |
| 中毒/腐化状态 | `status/poisoned` | `status/cursed`、`nature/poison-cloud` |
| 狂怒/狂暴 | `status/rage` | `status/haste` |
| 地面毒池 | `nature/toxic-puddle` | `nature/acid-splash` |
| 受击反馈 | `impacts/hit-spark` | `impacts/crit-hit` |
| 拾取/开箱 | `pickups/coin-spin` | `pickups/chest-open` |
| 伤害数字 | `ui/damage-number` | `ui/crit-number` |
