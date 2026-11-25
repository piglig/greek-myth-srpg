# 28 待补美术素材清单（含出图提示词）

> 建立：2026-11-24。2026-11-25 重写：每一项素材下面都附了可以直接用的出图提示词；按这两天的改动更新了清单（佣兵改为有名字的英雄、神性改为四阶、界面改为陶瓶画风格、新增圣物和神力）。
>
> 做完一项就把 `[ ]` 改成 `[x]`。画法和验收标准见 [26 主美设定](26-art-bible.md) 与 [27 制作指南](27-chapter-art-production.md)；尺寸以本文第 6 节为准。

## 0. 怎么用这些提示词

- **提示词是英文的**，大多数出图工具对英文更稳。每条可以直接整段复制。
- **一定要带参考图**。工具支持"参考图 / 风格参考"的话，人物类附上 `art/originals/bandit.png` 和 `bandit_chief.png`，四足类附上 `art/originals/pholoe-centaurs.png`。只靠文字，同一批人物很难画成一个风格。
- **同一个人的原画和半身像要一起出**，先出原画，再把原画作为参考图出半身像，衣服和配色才对得上。
- **图标是成批的**：每一批给一个模板，表里每一行是要填进去的主体。完整提示词 = 模板里的 `{主体}` 换成那一行。
- **出不准是常事**。六格图最常见的毛病是六格不是同一个人、格子之间粘连、带了地面或文字。出现这些就重出，不要修。验收标准在第 6 节。
- 所有 AI 生成的图交给我之后，我来切图、对齐、接进游戏。来源记在 `prototype/art/thirdparty/CREDITS.md`（工具名、日期）。

排成三档：第一档是第一章现在就缺的，第二档提升质感，第三档到后续章节才用得上。

---

## 0.1 审核返工（2026-11-25）

第一批交付已审核，大部分通过。下面几项退回重做，对应条目已改回未完成，提示词已更新：

| 项 | 位置 | 原因 |
|---|---|---|
| 福洛斯原画与半身像 | 1.1、1.3 | 和喀戎几乎一样：都是白发白须、白马身、蓝披布 |
| 伊达斯半身像 | 1.3 | 构图和别人不同：身体撑满画面，边缘是硬切的矩形 |
| 主角「受火」战场外观 | 2.4 | 缩到战场尺寸后和凡人阶段看不出区别；眼睛在脸上糊成蓝斑 |
| 铜羽鸟战场小人 | 3.2 | 画成了苍鹭一样的水鸟，和青铜秃鹫概念图对不上 |
| 五枚图标 | 2.1 | 24 像素下认不出：扫膝、指隙箭、劈盾、不信预言、青铜碎片 |

重做图标时守一条：一枚图标只画一个主体，不超过三个部件。

## 0.2 第二章新增、暂借图标的六种材料（2026-11-25）

按 2.1 的图标共用提示词出，{主体} 如下。做好后文件名用标识交给我，我把借用关系去掉（材料的借用写在 `campaign_checkpoint.gd` 的 `art` 一项里；剧毒是直接复制了蛇血的图标文件）。

| 完成 | 名称 | 标识 | 现在借用 | {主体} |
|---|---|---|---|---|
| [ ] | 蛇皮 | `snake_skin` | 鳞甲 | `a shed snake skin lying in one loose S-curve, the scale pattern shown as a row of diamonds` |
| [ ] | 毒囊 | `venom_sac` | 中毒 | `a small teardrop-shaped sac tied at the neck with one drop hanging below it` |
| [ ] | 蟹壳 | `crab_shell` | 破盾 | `the round top shell of a crab seen from above, with a notched front edge` |
| [ ] | 蟹钳 | `crab_claw` | 兽爪 | `a single large crab claw, pincers slightly open` |
| [ ] | 祭带 | `sacred_ribbon` | 红线团 | `a long ribbon tied in a bow with two trailing ends, a peacock-feather eye on one end` |
| [ ] | 乳香 | `incense` | 引火 | `three rough grains of resin with a thin curl of smoke rising from them` |
| [ ] | 剧毒（蛇血的主动） | `hydra_venom` | 蛇血 | `a serpent's open jaws with two fangs and one drop falling between them` |

## 0.3 第二章缺的和不合适的美术（2026-11-25）

第二章六场战斗（2-1 到 2-5、2-S）都能玩了，但有一批美术是借用的或者拼的。下面先列"现在游戏里用的是什么、为什么不合适"，再按类给提示词。标 **缺** 的是完全没有，标 **借** 的是拿别的东西顶着，标 **拼** 的是我用现成零件和代码凑的。

| 状态 | 东西 | 现在用的是什么 | 问题 |
|---|---|---|---|
| **借** | 许德拉的五个头 | 沼蛇的小人放大到两倍 | 看着就是五条大蛇，不是一只怪物的五个头；没有断颈和烧封后的样子 |
| **拼** | 许德拉的身体 | 地图中央一块 3×3 的岩台 | 没有身体，头像是从石头里长出来的 |
| **缺** | 沼蛇、巨蟹、许德拉之首的头像 | 回合顺序条上是一个色块 | 分不清谁是谁 |
| **缺** | 伊俄拉俄斯 | 没有 | 放过许德拉后加入的人，原画和半身像都没有 |
| **拼** | 2-2 对岸的神龛 | 营地的祭坛和火盆，加代码生成的石柱和石台 | 石柱一节深一节浅像条纹，没有屋顶和台阶，不像一座建筑 |
| **借** | 沼泽里的树 | 第一章的扭干橄榄树，加免费素材包的枯树 | 橄榄树长在沼泽里不对；没有垂柳、水生的树 |
| **借** | 沼泽的地面 | 三张免费的照片贴图（沙、泥、层状岩） | 是照片质感，和人物的水粉画风不是一种东西 |
| **缺** | 2-4 林地着火、烧成焦土 | 火焰借第一章的篝火，焦土是代码画的黑灰色 | 能看懂，但没有树烧起来和烧剩的残桩 |
| **缺** | 断颈再生、烧封、女祭司治疗、毒涎 | 只弹出文字 | 首领战最关键的两个时刻没有演出 |
| **借** | 七枚图标 | 见 0.2 | 借用的是别的图标 |
| **缺** | 六枚招式图标、一枚状态图标 | 显示默认图标 | 第二章敌人的招式和"蛇毒"状态没有图标 |

### 0.3.1 许德拉（最优先）

首领战现在最不像样的就是它。概念图 `art/direction/lerna-hydra.png` 可以当参考图一起给。

#### [ ] 许德拉之首 `hydra_head`（六格原画）

每个头是一个不会移动的单位，从地面立起来。按 6.1 的六格出，三列分别是待机、后仰蓄力、前探噬咬，没有行走。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same single head and neck of the Lernaean hydra rising straight out of the ground like a thick column, the neck as thick as a tree trunk and twice a man's height, pale olive and bone-coloured overlapping scales, a row of spikes down the back of the neck, heavy wedge-shaped serpent head with yellow eyes, no body and no legs, the base of the neck cut off cleanly at the ground line, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns swaying upright at rest, rearing back with jaws closed, lunging forward and down with jaws wide open. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, the whole neck and head fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 断颈 `hydra_stump`（两格）

头倒下后留在原地的东西。左格是刚砍断、还会再生的；右格是被火封住、再也长不出来的。两格大小和位置一致。

```
Original PC tactical game sprite atlas on transparent background, precisely 2 columns and 1 row. The same severed stump of a hydra's neck in both cells, a thick scaled column cut off at knee height, seen from a high overhead 35 degree orthographic view. Left cell: the cut is raw and wet, dark red, with two small pale buds of new flesh already swelling from it. Right cell: the cut is burnt black and sealed, cracked like charcoal, with a few orange embers and a thin thread of smoke. Ancient Mediterranean gouache illustration, broad rich earthy color planes, wide empty gutter between the two. No text no dividers no backdrop or pedestal.
```

#### [ ] 许德拉的身体 `hydra_body`（单张）

放在地图中央，占 3×3 格，五个头围着它。它不动，不需要动作帧。

```
The coiled body of the Lernaean hydra with no heads, a great knot of thick scaled coils piled into a low mound three times as wide as a man is tall, pale olive and bone-coloured scales with a row of spikes along each coil, five short neck roots rising from it where the heads would join, half sunk in marsh mud with a few reeds against it. Seen from a high three-quarter angle about 35 degrees, lit softly from the upper left. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork. Transparent background, the whole mound inside the picture with empty margin on every side. No heads, no characters, no text.
```

#### [ ] 三个头像：沼蛇、巨蟹、许德拉之首

回合顺序条和信息卡用。按 1.3 的半身像规格出（6.2），动物就画头和前半身。

| 完成 | 谁 | 文件名 | 接在共用后半段前面 |
|---|---|---|---|
| [ ] | 沼蛇 | `portraits/marsh_snake.png` | `A large marsh water snake, thick mottled olive body, head raised and turned three-quarters, mouth slightly open showing one fang, a coil of its body behind the head.` |
| [ ] | 巨蟹 | `portraits/giant_crab.png` | `A giant marsh crab, dark green shell crusted with mud, seen from the front three-quarters, two small stalked eyes, one oversized claw raised beside its face.` |
| [ ] | 许德拉之首 | `portraits/hydra_head.png` | `One head of the Lernaean hydra, heavy wedge-shaped serpent head with yellow eyes, pale olive and bone-coloured scales, a crest of spikes, jaws slightly parted, the thick neck filling the bottom of the picture.` |

共用后半段把 `Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression.` 换成 `Head and upper body only, three-quarter view.`，其余不变。

### 0.3.2 伊俄拉俄斯 `iolaus`

放过许德拉后加入的英雄：赫拉克勒斯的侄子，神话里举着火把烧断颈的人。定位是持火把的辅助。武器定为**火把加短剑**，攻击动作是短剑刺。先出原画，再拿原画当参考出半身像。

#### [ ] 原画

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same young Greek charioteer about eighteen, slim and quick, short sun-bleached brown hair held back by a leather band, short white tunic with a rust-red border belted high, a charioteer's long leather wrist guards, a burning pine torch held high in the left hand and a short sword in the right, soot smudges on his forearms, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking with a short sword thrust while the torch is held back. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 半身像 `portraits/iolaus.png`

```
A young Greek charioteer about eighteen, slim, short sun-bleached brown hair held back by a leather band, short white tunic with a rust-red border, a burning pine torch held up beside his face so its light falls warm on one cheek, soot on his forearm. Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.
```

### 0.3.3 场景

#### [ ] 2-2 对岸的神龛 `lerna-shrine`（单张）

玩家要走到的地方，隔着沼泽要能认出来。概念图 `art/direction/lerna-marsh.png` 右上角就是它。

```
A small ruined Greek shrine on a low stone platform of two worn steps: four slim Doric columns at the corners, two still standing and carrying a broken piece of lintel, one snapped off at half height, one fallen and lying in drums on the ground; a plain block altar in the middle and a bronze tripod bowl with a small fire burning in it beside the altar; moss in the cracks and reeds growing against the steps. Seen from a high three-quarter angle about 35 degrees, lit softly from the upper left. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork. Transparent background, the whole shrine inside the picture with empty margin on every side. No characters, no text.
```

#### [ ] 沼泽的树（三张，各单张）

替换沼泽里的橄榄树。每张一棵，透明底，同一个角度。

| 完成 | 树 | 文件名 | 提示词开头 |
|---|---|---|---|
| [ ] | 垂柳 | `marsh-willow.png` | `A weeping willow on a marsh bank, a thick leaning trunk and long thin branches hanging almost to the ground in grey-green curtains,` |
| [ ] | 水生的树 | `marsh-alder.png` | `A black alder growing out of standing water, several slim dark trunks rising from one root mass that stands above the water on arched roots, a small crown of dull green leaves,` |
| [ ] | 枯树 | `marsh-snag.png` | `A dead drowned tree standing in a marsh, bare bleached trunk and a few broken branches, the bark peeling, a clump of reeds at its foot,` |

每条后面接：

> …seen from a high three-quarter angle about 35 degrees, lit softly from the upper left. Ancient Mediterranean gouache illustration, broad colour planes, visible brushwork. Transparent background, the whole tree inside the picture with empty margin on every side. No ground plane, no characters, no text.

#### [ ] 沼泽的五张地面（各 1024×1024，可平铺）

替换现在的三张照片贴图，并补上林地和焦土两种。每条后面接 3.3 的"地表材质共用的后半段"。

| 完成 | 用在哪 | 文件名 | 提示词开头 |
|---|---|---|---|
| [ ] | 干的岸和沙洲 | `lerna-sand.png` | `Pale grey-brown river sand with faint wind ripples, a few small shells and bits of dry reed.` |
| [ ] | 水边和水底的湿泥 | `lerna-mud.png` | `Dark wet marsh mud, glossy in patches, with small stones, rotting leaves and a few water-filled hollows.` |
| [ ] | 陡坎的断面 | `lerna-bank.png` | `A cut earth bank seen face on: horizontal layers of brown clay, grey silt and a band of pebbles, with thin roots hanging out of it.` |
| [ ] | 林地的地面 | `lerna-litter.png` | `Damp forest floor under trees: dark green moss, brown fallen leaves, twigs and a few fern fronds lying flat.` |
| [ ] | 烧过的焦土 | `lerna-ash.png` | `Burnt ground after a brush fire: black ash and grey cinders, charred twigs, a few pale patches of white ash.` |

注意第三张"断面"不是从正上方看的，把共用后半段里的 `seen from directly above` 换成 `seen face on`。

### 0.3.4 特效

按 2.2 的特效模板出。

| 完成 | 特效 | 文件名 | {内容} | {帧数} | 循环 |
|---|---|---|---|---|---|
| [ ] | 林地着火 | `brushfire.png` | `a bush and a small tree burning, tall orange and yellow flames with dark smoke rising, the branches visible as black lines inside the fire` | 8 | 是 |
| [ ] | 烧尽的残桩 | `charred.png` | `a burnt tree stump and a few blackened sticks with thin smoke rising and two or three embers glowing and fading` | 6 | 是 |
| [ ] | 烧封断颈 | `cauterize.png` | `a burst of fire closing over a wound: flames rush inward to a point, flare white once, then leave a ring of orange embers that fade` | 8 | 否 |
| [ ] | 断颈再生 | `regrow.png` | `pale flesh swelling up fast from a stump into the shape of a snake's head, wet and glistening, with a spray of dark droplets as it bursts upward` | 8 | 否 |
| [ ] | 毒涎 | `venom_spit.png` | `a glob of sickly green venom flying left to right, stretching into a tail, then splashing into a small puddle with a few rising bubbles` | 8 | 否 |
| [ ] | 女祭司的赐福 | `hera_blessing.png` | `a soft ring of pale gold light rising from the ground around a figure, with three peacock-feather eyes of light opening and closing in it` | 8 | 否 |
| [ ] | 剧毒（蛇血的主动） | `hydra_venom.png` | `dark green vapour coiling round a figure like a snake, tightening once, then sinking into them and leaving a faint green stain` | 8 | 否 |

### 0.3.5 图标

按 2.1 的图标模板出。0.2 那七枚也还没做。

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [ ] | 毒牙（沼蛇） | `venom_bite` | `a snake's head in profile with jaws open and two long fangs` |
| [ ] | 钳制（巨蟹） | `claw_grip` | `a crab claw closed tight round a short bar` |
| [ ] | 石榴杖（女祭司） | `sacred_staff` | `a staff topped with a pomegranate` |
| [ ] | 天后的赐福（女祭司） | `hera_blessing` | `an open hand held palm down over a single peacock feather` |
| [ ] | 噬咬（许德拉） | `hydra_bite` | `a wide serpent jaw seen from the front with four fangs` |
| [ ] | 毒涎（许德拉） | `hydra_spit` | `a serpent's head spitting three drops in an arc` |
| [ ] | 蛇毒（状态：无法被治疗） | `blighted` | `a heart shape with a snake coiled once round it` |
| [ ] | 许德拉之首（回合条上的小标） | `boss_hydra_head` | `a single serpent head on a thick neck rising from the ground` |

---

## 0.4 六位支援英雄的登场动作（2026-11-25）

招募来的英雄不再上场，改成支援：主角一召，他登场、出手一次、离场。所以每人要补一张
**登场三连**——三列依次是**登场、招牌出手、离场**，仍按 6.1 的六格出（上排正面朝右，下排背面朝左）。

- 文件放在各自的形象目录下，叫 `support.png`，例如 `prototype/art/pixel/merc_sword/support.png`。
- **把这个人现有的原画当参考图一起给**（下面每条都写了是哪一张），衣服、配色、武器要和原画是同一个人。
- 现有的待机、行走、攻击、倒地几张图不用重做。它们以后只在营地和招募页里用得上。
- 在这些图到位之前，游戏里用他现有的图顶替：英雄出现在主角身边，面朝目标做一次平时的攻击动作再消失。
- 福洛斯的原画还在返工（见 0.1），他这一张等新原画定了再出。

#### [ ] 伊菲克勒斯「并肩」 `merc_sword/support.png`

冲到同伴身前，举盾护住对方。盾要举在身体前上方，一眼看得出是在挡，不是在砍。参考图：`art/originals/merc_sword.png`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same ordinary Theban Greek foot soldier, sturdy but unremarkable build, short brown hair, undyed linen tunic, blue scarf and blue headband, small round wooden shield and short iron sword, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns running in at a sprint with the shield arm leading, planted in a low wide stance holding the round shield high and forward to cover someone behind him with the sword held back, stepping back out with the shield lowered and a glance over the shoulder. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 法勒洛斯「远射」 `merc_archer/support.png`

从很远的地方射来的一箭。出手那一格弓要拉满、身体后仰，和阿塔兰忒贴身的短射拉开。参考图：`art/originals/merc_archer.png`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same slim Athenian Greek archer, pine green hood, tan leather jerkin, a quiver painted with a coiled snake, long recurved bow, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns dropping to one knee and nocking an arrow, at full draw with the bow tilted high for a long shot and the body leaning back, standing and lowering the bow with the string still quivering. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 安开俄斯「劈盾」 `merc_captain/support.png`

一斧从上往下劈开对方的防御。蓄力要大，斧头举过头顶。参考图：`art/originals/merc_captain.png`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same burly Arcadian Greek axeman, a brown bearskin worn over head and shoulders with the bear's muzzle as a hood, sea green tunic, thick bare arms, double-headed bronze axe, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns striding in with the axe resting on one shoulder, the axe raised high overhead in both hands at the top of a huge downward chop, the axe buried low after the blow with the body bent over it. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 福洛斯「驮行」 `merc_lancer/support.png`

冲进来把一个同伴接上背，驮到几格外放下。第二格背上要留出一个人的位置，同伴由游戏另外叠上去，不要画进图里。参考图：`art/originals/merc_lancer.png`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same gentle middle-aged centaur, dark bay horse body with black mane and tail, sun-browned lean human torso, short dark brown beard streaked with grey, dark curly hair bound with a vine wreath, a wine-red sash and a wineskin slung at his side, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns galloping in with one arm reaching forward and down to offer a hand, standing braced with the horse back level and empty and the human torso twisted round holding the wineskin out behind him, cantering away with the lance tucked under one arm. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 伊达斯「碎阵」 `idas/support.png`

全身的力气砸下去，要有"地都震了"的感觉。和他平时的劈砍相比，这一下是双脚离地跳起来砸。参考图：`art/originals/idas.png`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same huge Greek strongman warrior, enormously broad shoulders and thick neck, bronze helmet with a tall black horsehair crest, saffron yellow cloak thrown back, bare chest crossed by a leather strap, heavy two-handed bronze axe, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns charging in with head lowered and the axe trailing behind, leaping with both feet off the ground and the axe swung back over the head at the peak of the jump, landed in a deep crouch with the axe head driven down in front of him and the cloak flaring. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 欧律提翁「冲锋」 `eurytion/support.png`

沿一条直线冲过去。三格都是全速奔跑，矛始终放平指向前方。参考图：`art/originals/eurytion.png`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same centaur chieftain, glossy black horse body, muscular bearded human torso, wild dark hair, a gold sash across the chest, long bronze-tipped spear, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns rearing up on the hind legs with the spear raised before the charge, at full gallop with all four hooves off the ground and the spear couched level and pointing straight ahead, at full gallop looking back over the shoulder with the spear still level. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 六枚召援图标

按 2.1 的图标模板出。战斗里主角的招式菜单上用。

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [ ] | 并肩（伊菲克勒斯） | `sup_iphicles` | `a round shield held up in front of a smaller figure's outline` |
| [ ] | 远射（法勒洛斯） | `sup_phalerus` | `a single arrow in a high arc over a distant hill line` |
| [ ] | 劈盾（安开俄斯） | `sup_ancaeus` | `a double-headed axe splitting a round shield in two` |
| [ ] | 驮行（福洛斯） | `sup_pholus` | `a centaur in profile with a small rider on his back` |
| [ ] | 碎阵（伊达斯） | `sup_idas` | `an axe head struck into cracked ground with three cracks spreading` |
| [ ] | 冲锋（欧律提翁） | `sup_eurytion` | `a level spear with three speed lines behind it` |

---

## 1. 第一档：第一章现在就缺

### 1.1 九个借用形象的人物原画

这九人已完成各自的六姿势原画。规格见 6.1：一张图 6 个姿势。

**共用的后半段**（下面每条提示词都以它结尾，已经写全，不用再拼）：

> …in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.

设计上要注意：上战场的六位，武器种类不能变（剑、弓、斧、矛），否则攻击动作对不上；头部和主色要和所借用的敌人拉开。

#### [x] 行商阿齐尔 `npc_trader`（先做）

不上战场，可以完全换体型。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same stout middle-aged Greek travelling merchant, round belly, short curly black beard, deep purple cloak pinned at one shoulder over a saffron tunic, a bulging pack of wares on his back and a small bronze hand scale hanging from his belt, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, holding out the hand scale to weigh coins. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 教习达蒙 `npc_drill`（先做）

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same old Greek drillmaster, lean and upright, grey beard, plain bronze helmet without a crest, undyed cream wool cloak, scarred bare forearms, a long wooden training staff, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle leaning on the staff, walking, striking downward with the staff. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 领路人伊俄 `npc_guide`（先做）

设计文档里没有写伊俄的性别和年龄，我按"年轻的女斥候"写的；不合适就改提示词里的 `young Greek woman scout`。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same young Greek woman scout, wiry build, sun-browned skin, madder red hood pushed back over braided dark hair, worn leather jerkin, short bow across her back and a coiled rope at her hip, dusty sandals, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle shading her eyes to look ahead, walking, pointing the way with an outstretched arm. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 伊达斯 `idas`（史诗，其次）

墨塞涅的力士，自称世上最强壮的凡人。武器必须是斧。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same huge Greek strongman warrior, enormously broad shoulders and thick neck, bronze helmet with a tall black horsehair crest, saffron yellow cloak thrown back, bare chest crossed by a leather strap, heavy two-handed bronze axe, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking with an overhead axe chop. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 欧律提翁 `eurytion`（史诗，其次）

半人马首领。四足，参考图用 `pholoe-centaurs.png`。武器必须是长矛。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same centaur chieftain, glossy black horse body, muscular bearded human torso, wild dark hair, a gold sash across the chest, long bronze-tipped spear, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, trotting, attacking with a spear thrust. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 安开俄斯 `merc_captain`（稀有）

阿卡迪亚人，披熊皮，使双刃斧。武器必须是斧。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same burly Arcadian Greek axeman, a brown bearskin worn over head and shoulders with the bear's muzzle as a hood, sea green tunic, thick bare arms, double-headed bronze axe, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking with a wide axe swing. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 福洛斯 `merc_lancer`（稀有）

福洛厄山的半人马，好客的主人。四足。武器必须是长矛。

返工：上一版和喀戎撞脸。喀戎是白发、白马身、蓝披布，福洛斯要全部避开：深色马身、深色须发、酒红披布。半身像跟着重出。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same gentle middle-aged centaur, dark bay horse body with black mane and tail, sun-browned lean human torso, short dark brown beard streaked with grey, dark curly hair bound with a vine wreath, a wine-red sash and a wineskin slung at his side, plain wooden lance, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, trotting, attacking with a lance thrust. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 伊菲克勒斯 `merc_sword`（普通）

赫拉克勒斯的孪生兄弟，身上没有一滴神的血。武器必须是短剑。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same ordinary Theban Greek foot soldier, sturdy but unremarkable build, short brown hair, undyed linen tunic, blue scarf and blue headband, small round wooden shield and short iron sword, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking with a sword cut. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [x] 法勒洛斯 `merc_archer`（普通）

雅典的弓手，小时候被蛇缠住。武器必须是弓。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same slim Athenian Greek archer, pine green hood, tan leather jerkin, a quiver painted with a coiled snake, long recurved bow, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking by drawing the bow to the cheek. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

### 1.2 美狄亚补动作

她目前只有待机和行走。交一张完整的 6 姿势原画，受击和倒地由脚本生成。参考图用她现有的原画，保证是同一个人。

#### [x] 美狄亚完整原画 `medea`

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same Colchian sorceress, tall and narrow, long dark robe with a saffron hem, black hair bound with a gold band, several small clay vials hanging from her belt, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, casting by snapping the wax seal of a vial and flinging fire seed in an arc with the other hand. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

### 1.3 人物半身像

现在所有头像都是从战斗小人上裁出来的头部，放大后发糊。规格见 6.2。**先出原画，再拿原画当参考图出半身像。**

**共用的后半段**（每条都已写全）：

> …Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.

#### [x] 主角阿尔卡斯 `hero`

```
A young Greek shepherd turned spearman, about twenty, sun-browned skin, short dark curls, a red cord tied round his right wrist, ochre cloak worn off one shoulder, the rim of a round shield at his back. Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.
```

#### [x] 阿塔兰忒 `atalanta`

```
A Greek huntress in her twenties, lean and alert, tawny hair tied back tightly, a short close-fitting cloak, the curve of a long bow and a slanted quiver behind her shoulder. Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.
```

#### [x] 喀戎 `chiron`

```
An old wise centaur healer shown from the human chest up, long grey hair and beard, kind tired eyes, a pale shawl over bare shoulders, the strap of a medicine bag across his chest. Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.
```

#### [x] 美狄亚 `medea`

```
A Colchian sorceress in her late twenties, sharp narrow face, black hair bound with a thin gold band, dark robe with a saffron edge, a small clay vial hanging from a cord at her collarbone. Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.
```

#### [x] 赫拉克勒斯 `heracles`

```
The Greek hero Heracles as a weary man in his forties, massive bare shoulders, heavy brow, thick dark beard streaked with grey, a fresh wound bound with cloth on one arm, the knotted head of a wooden club resting on his shoulder. Bust portrait from the chest up, three-quarter face, gaze slightly off to one side, calm expression. Ancient Mediterranean gouache illustration, broad rich earthy color planes, visible brushwork, soft warm side light. Transparent background, about one tenth empty space above the head. No text, no frame, no border.
```

#### [x] 营地三人与六位英雄

跟着 1.1 的原画一起做。提示词 = 1.1 里那个人的外貌描述（"Same …" 之后到 "in all six cells" 之前的那一段）+ 上面共用的后半段。

| 完成 | 人物 | 标识 |
|---|---|---|
| [x] | 行商阿齐尔 | `npc_trader` |
| [x] | 教习达蒙 | `npc_drill` |
| [x] | 领路人伊俄 | `npc_guide` |
| [ ] | 伊达斯 | `idas` |
| [x] | 欧律提翁 | `eurytion` |
| [x] | 安开俄斯 | `merc_captain` |
| [ ] | 福洛斯 | `merc_lancer` |
| [x] | 伊菲克勒斯 | `merc_sword` |
| [x] | 法勒洛斯 | `merc_archer` |

返工说明：

- 伊达斯：和其他半身像用同一构图。在提示词末尾加 `Head and shoulders bust with clear empty margin on all four sides, the figure fading out softly at the chest, nothing touching the edge of the frame, the helmet crest fully inside the picture.`
- 福洛斯：按 1.1 里改过的外貌重出（深色须发、藤叶冠、酒红披布）。

### 1.4 营地场景

十件营地模型已完成，位于 `prototype/art/camp/`，共用 `camp-pigments.jpg` 基础色贴图。行商帐边陈列双耳瓶与黑绘陶罐，教习身后是矛架、圆盾和兽皮架。营火使用炭火盆，后方的小祭坛与青铜鼎共用一处空地。

**共用的后半段**：

> …Single object, isolated, centered, seen from a high three-quarter angle about 35 degrees, plain flat mid-grey background, even soft light, no cast shadow, no ground, no people, no text. Hand-painted gouache look, broad earthy color planes, simple forms suitable for a low-poly game model.

| 完成 | 道具 | 提示词的前半段（后面接共用的后半段） |
|---|---|---|
| [x] | 行军帐篷（大） | `An ancient Greek military campaign tent, undyed cream canvas over a wooden frame with a ridge pole, one side flap tied open, a red painted meander band along the lower edge.` |
| [x] | 行军帐篷（小） | `A small ancient Greek lean-to shelter, a single sheet of weathered cream canvas pegged over two crossed spears, bedroll visible inside.` |
| [x] | 双耳瓶 | `An ancient Greek transport amphora, tall terracotta jar with two handles and a pointed foot, leaning in a simple wooden stand.` |
| [x] | 陶罐 | `An ancient Greek black-figure hydria water jar, terracotta with a band of black painted figures round the shoulder.` |
| [x] | 三脚鼎 | `An ancient Greek bronze tripod cauldron on three tall legs with ring handles, greenish patina.` |
| [x] | 小祭坛 | `A small ancient Greek stone field altar, a low limestone block with a shallow bowl on top holding ash and a few olive twigs.` |
| [x] | 矛架 | `A wooden rack holding four ancient Greek bronze-tipped spears upright, leather binding at the joints.` |
| [x] | 盾 | `An ancient Greek round hoplite shield of bronze-faced wood leaning on its rim, a simple painted ochre device, worn leather grip visible at the back.` |
| [x] | 兽皮 | `A tanned wolf pelt stretched on a simple wooden drying frame.` |
| [x] | 火盆 | `An ancient Greek bronze brazier on three short legs holding glowing coals.` |

---

## 2. 第二档：提升质感

### 2.1 图标

本节 162 项已完成，采用项目原创的希腊陶绘单色剪影，尺寸规格见 6.3。

**图标模板**（所有图标共用，把 `{主体}` 换成表里的英文）：

```
A single game icon in the manner of ancient Greek black-figure vase painting: {主体}. One solid flat white silhouette on a fully transparent background, with a few thin incised lines inside the shape for detail. No outline box, no circle, no border, no shading, no gradient, no colour, no text. Centered, filling about 80 percent of a square canvas, bold and readable when shrunk to 24 pixels.
```

#### 状态徽章（8 个，先做）

战斗里一直挂在血条旁，要在 14 像素下认得出。

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 灼烧 | `kindling` | `a single tongue of flame` |
| [x] | 中毒 | `st_poison` | `a small vial with one drop falling from its lip` |
| [x] | 束缚 | `bind_hex` | `an ankle shackle with three chain links` |
| [x] | 眩晕 | `st_stun` | `three small stars circling in a ring` |
| [x] | 防御 | `act_guard` | `a round hoplite shield seen from the front with a single boss` |
| [x] | 闪避 | `st_dodge` | `a running figure leaning sharply to one side` |
| [x] | 不坏之皮 | `st_shield` | `a lion's pelt hung by its forepaws` |
| [x] | 被标记 | `act_mark` | `an arrow striking the centre of a ring` |

#### 指令（6 个，先做）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 移动 | `act_move` | `a striding sandalled foot` |
| [x] | 攻击 | `act_slash` | `a spear head with a short length of shaft, pointing up and right` |
| [x] | 技能 | `skills` | `an open hand with three rays above the palm` |
| [x] | 物品 | `act_item` | `a drawstring leather pouch` |
| [x] | 待机 | `act_wait` | `an hourglass` |
| [x] | 撤销移动 | `act_undo` | `an arrow curling back on itself to the left` |

#### 圣物（7 个）

"夺圣物 / 放过"界面和天平上用。

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 涅墨亚狮皮 | `art_pelt` | `a lion's pelt with the head and mane, spread flat` |
| [x] | 蛇血 | `relic_blood` | `a small round flask with a serpent coiled round its neck` |
| [x] | 铜羽 | `art_feather` | `a single stiff feather with a blade-sharp edge` |
| [x] | 阿里阿德涅之线 | `art_thread` | `a ball of thread with one loose end trailing away` |
| [x] | 蛇发之首 | `brooch` | `the head of Medusa seen from the front, snakes for hair, eyes closed` |
| [x] | 冥河之水 | `relic_styx` | `a shallow two-handled cup with dark water and one drop above it` |
| [x] | 泰坦之力 | `relic_titan` | `a huge clenched fist bound by a broken chain` |

#### 首领的剪影（6 个）

"夺圣物 / 放过"界面顶部和卡片上用，尺寸比别的图标大，交 512×512。

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 许德拉 | `boss_hydra` | `the Hydra, a serpent body with five rearing heads` |
| [x] | 铜羽鸟 | `boss_bird` | `a great bird of prey with wings spread and metal-edged feathers` |
| [x] | 米诺陶洛斯 | `boss_minotaur` | `the Minotaur standing, bull's head and horns on a man's body` |
| [x] | 美杜莎 | `boss_medusa` | `Medusa standing in profile, a long robe, a mass of snakes for hair` |
| [x] | 刻耳柏洛斯 | `boss_cerberus` | `Cerberus, a three-headed hound with a serpent tail` |
| [x] | 泰坦 | `boss_titan` | `a chained giant on one knee, far broader than a man` |

#### 神力招式（6 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 雷矢 | `thunder_bolt` | `a single jagged thunderbolt shaped like a thrown javelin` |
| [x] | 天火 | `sky_fire` | `a ball of fire falling from above with a short tail` |
| [x] | 雷行 | `thunder_step` | `a footprint split by a lightning fork` |
| [x] | 天穹 | `sky_dome` | `a half dome arching over three small standing figures` |
| [x] | 天罚 | `sky_wrath` | `three thunderbolts striking down side by side onto a patch of ground` |
| [x] | 雷躯 | `thunder_body` | `a standing man with lightning forking outward from his whole outline` |

六枚共用同一套陶绘剪影。营地升阶以 24 像素图标显示当阶两项选择，战斗指令与悬停说明沿用各招的同一剪影。

#### 主角的招式和特性（14 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 矛刺 | `act_spear` | `a spear thrusting straight forward` |
| [x] | 盾击 | `act_shield` | `a round shield pushed forward with impact lines in front of it` |
| [x] | 过肩摔 | `shoulder_throw` | `one wrestler throwing another over his shoulder` |
| [x] | 盾墙 | `shield_wall` | `three overlapping round shields in a row` |
| [x] | 截击 | `intercept` | `a shield stepping between an arrow and a standing figure` |
| [x] | 盾缘猛推 | `shield_drive` | `a shield rim driving a falling figure backward` |
| [x] | 执盾如山 | `bulwark` | `a round shield planted on the ground in front of a mountain peak` |
| [x] | 方阵贯刺 | `phalanx_thrust` | `three parallel spears pointing the same way` |
| [x] | 铁臂 | `iron_arm` | `a flexed forearm with a clenched fist` |
| [x] | 破势之拳 | `stagger_fist` | `a fist striking a cracked breastplate` |
| [ ] | 扫膝 | `heel_strike` | `one bent leg kicking low to the side, a single short curved motion line under the foot` |
| [x] | 角力呼吸 | `wrestler` | `a wrestler crouched in a ready stance, arms forward` |
| [x] | 碎阵重击 | `breaker` | `a shield shattering into three pieces` |
| [x] | 不坏之皮 | `impervious_hide` | `a man wearing a lion's head as a hood` |

营地找达蒙选「操练」，可在主角的战阵、搏击两支查看 10 枚节点图标。树顶另列三项随身招式，装备狮皮时显示「不坏之皮」。战斗指令及悬停说明沿用已携带招式的同一剪影。

#### 阿塔兰忒（11 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 射击 | `act_shoot` | `a drawn bow with an arrow nocked` |
| [x] | 要害射击 | `vital_shot` | `an arrow buried in the centre of a small heart` |
| [x] | 跃射 | `leap_shot` | `an archer in mid-leap loosing an arrow downward` |
| [x] | 钉足箭 | `pin_shot` | `an arrow pinning a foot to the ground` |
| [x] | 卡吕冬之矢 | `calydon` | `an arrow piercing a boar's head` |
| [x] | 越岭射 | `ridge_shot` | `an arrow arcing over a mountain ridge` |
| [x] | 猎人耐心 | `patience` | `a kneeling archer holding a drawn bow perfectly still` |
| [x] | 巨兽克星 | `beast_hunter` | `a pair of boar tusks crossed` |
| [x] | 游击 | `skirmish` | `a running figure looking back over the shoulder` |
| [x] | 越林步 | `fleet` | `a bare foot stepping between two tree trunks` |
| [x] | 羚跃 | `high_jump` | `a leaping deer` |

达蒙的操练页在「随身」栏显示射击，两条技能树显示五种进阶射术与五项特性。战斗指令与悬停说明使用同一套射术图标。

#### 喀戎（10 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 净化箭 | `purify_arrow` | `an arrow with a sprig of herb bound to its shaft` |
| [ ] | 指隙箭 | `weak_point` | `one arrow pointing into a V-shaped notch in the edge of a single armour plate` |
| [x] | 退敌箭 | `repel_arrow` | `an arrow knocking a figure backward` |
| [x] | 射手座之矢 | `centaur_volley` | `a centaur drawing a bow, rearing` |
| [x] | 战地医术 | `field_medicine` | `a staff with a single serpent twined round it` |
| [x] | 药囊 | `herb_pouch` | `a small pouch with leaves spilling from its mouth` |
| [x] | 止血包扎 | `triage` | `a forearm wrapped in a bandage` |
| [x] | 复方解毒 | `antidote` | `a mortar and pestle` |
| [x] | 识破架势 | `mentor_stagger` | `an open eye above a tilted shield` |
| [x] | 观隙 | `keen_eye` | `an eye with a single arrow as its pupil` |

达蒙的「医者」与「导师」两条技能树共显示四种箭术和六项特性。四种箭术可同时携带，战斗指令与悬停说明使用对应剪影。

#### 美狄亚（11 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 巫火 | `act_fire` | `a flame rising from an open palm` |
| [x] | 日轮焰 | `solar_flame` | `a sun disc with long wavy rays` |
| [x] | 烬火长矛 | `cinder_lance` | `a spear made of flame` |
| [x] | 蚀骨咒 | `frailty` | `a cracked thigh bone` |
| [x] | 缚足咒 | `bind_hex` | `two feet bound together by a knotted cord` |
| [x] | 长夜咒 | `night_hex` | `a crescent moon with a closed eye inside it` |
| [x] | 助燃 | `kindling` | `a small flame fed by a drop of oil` |
| [x] | 焚尽 | `long_flame` | `a pile of embers with a thin flame still rising` |
| [x] | 日神血脉 | `solar_blood` | `a drop of blood with a small sun inside it` |
| [x] | 缠身咒 | `lingering_hex` | `a heart wrapped in a chain` |
| [x] | 赫卡忒的庇护 | `hex_ward` | `two crossed torches behind a small shield` |

达蒙的技能树显示随身巫火，以及「烈焰」「诅咒」两支的十个节点。六种主动招式在指令盘与悬停说明中沿用同一剪影。「助燃」「缚足咒」的素材分别为 `medea_kindling` 和 `medea_bind_hex`，血条旁的灼烧与束缚保留各自的状态徽章。

#### 六位英雄（22 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 劈砍 / 重劈 | `heavy_cut` | `a short sword in a downward diagonal cut` |
| [x] | 断矛斩 | `spear_breaker` | `a sword cutting a spear shaft in two` |
| [x] | 并肩而立 | `iph_stand` | `two warriors standing shoulder to shoulder` |
| [x] | 以身相护 | `iph_cover` | `a warrior with arms spread in front of a fallen comrade` |
| [x] | 瞄准射击 | `aimed_shot` | `a bow at full draw with a sighting line to a small dot` |
| [x] | 远射 | `long_shot` | `an arrow in a long high arc` |
| [x] | 绊足箭 | `snare_arrow` | `an arrow trailing a looped cord` |
| [x] | 破甲箭 | `bodkin_arrow` | `a narrow needle-pointed arrowhead piercing a metal plate` |
| [x] | 稳弓 | `pha_steady` | `a bow held level on a steady extended arm` |
| [ ] | 劈盾 | `shield_split` | `a round shield broken into two clean halves with a single axe blade between them` |
| [x] | 回旋斧 | `axe_sweep` | `a double-headed axe with a circular motion line round it` |
| [x] | 伐木式 | `felling_blow` | `an axe sunk into a tree trunk` |
| [x] | 熊皮 | `anc_hide` | `a bear's head worn as a hood` |
| [ ] | 不信预言 | `anc_defy` | `a wide two-handled wine cup lying on its side, three large drops falling from its rim` |
| [x] | 践踏 | `trample` | `two horse hooves coming down on a small shield` |
| [x] | 后蹄 | `hind_kick` | `a horse's hind legs kicking backward` |
| [x] | 陈酒 | `old_wine` | `a wineskin pouring into a shallow cup` |
| [x] | 洞口相迎 | `pho_shelter` | `a cave mouth with a small fire inside` |
| [x] | 疾蹄 / 熟路 | `eury_gallop` | `a galloping centaur at full stretch` |
| [x] | 跃涧 | `eury_vault` | `a centaur leaping across a gap` |
| [x] | 厚实筋骨 | `idas_frame` | `a broad bare torso with thick arms held out from the sides` |
| [x] | 不服神意 | `idas_pride` | `a raised fist shaken at a thundercloud` |

达蒙的技能树按 24 像素显示这套剪影。「随身」栏显示各英雄自带的基础攻击与招式，重劈、瞄准射击和践踏也能在这里辨认。战斗指令与说明卡沿用同一图标。福洛斯的熟路与欧律提翁的疾蹄共用疾驰剪影，两人的跃涧共用跨涧剪影。

#### 装备（26 个）

盘边的颜色由游戏按稀有度上，图标本身是白色剪影。

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 橄榄枝 | `olive` | `an olive branch with five leaves and two olives` |
| [x] | 皮手套 | `glove_hide` | `a single leather glove` |
| [x] | 拳带 | `fist_wrap` | `a fist wrapped in leather thongs` |
| [x] | 青铜护腕 | `bracer_bronze` | `a bronze forearm guard` |
| [x] | 誓约指环 | `ring_oath` | `a plain ring with an engraved bezel` |
| [x] | 铁臂甲 | `gauntlet` | `an armoured forearm and hand` |
| [x] | 红线团 | `red_thread` | `a small tight ball of thread` |
| [x] | 亚麻短衣 | `tunic` | `a short sleeveless Greek tunic` |
| [x] | 宽皮带 | `belt_wide` | `a broad leather belt with a round buckle` |
| [x] | 皮甲 | `leather` | `a leather cuirass with shoulder straps` |
| [x] | 旅人斗篷 | `cloak_travel` | `a hooded travelling cloak` |
| [x] | 鳞甲 | `scale` | `a cuirass covered in overlapping scales` |
| [x] | 青铜胸甲 | `cuirass` | `a muscled bronze breastplate` |
| [x] | 狼皮披肩 | `wolf_cape` | `a wolf pelt worn as a shoulder cape, the head on one shoulder` |
| [x] | 草鞋 | `sandal` | `a single strapped sandal` |
| [x] | 牧人皮靴 | `boots` | `a soft ankle boot with a turned-down cuff` |
| [x] | 胫甲 | `greaves` | `a pair of bronze shin guards` |
| [x] | 山行绑腿 | `trail_wraps` | `a lower leg wrapped in crossed cloth bindings` |
| [x] | 飞翼凉鞋 | `wingfoot` | `a sandal with a small wing at the ankle` |
| [x] | 鹰羽 | `feather` | `a single broad eagle feather` |
| [x] | 狼牙坠 | `fang_charm` | `a wolf's fang hung on a cord` |
| [x] | 祭酒杯 | `cup` | `a shallow two-handled libation cup` |
| [x] | 琥珀项链 | `necklace` | `a necklace of round beads with one large central stone` |
| [x] | 青金坠 | `pendant` | `a teardrop pendant on a chain` |
| [x] | 猫头鹰小像 | `owl` | `a small owl figurine seen from the front` |
| [x] | 祭司护符 | `amulet` | `an amulet shaped like an eye inside a triangle of cord` |

#### 随身物品（6 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 回复药 | `item_potion` | `a round-bellied potion flask with a stopper` |
| [x] | 解毒药 | `item_antidote` | `a narrow-necked flask with a leaf tied to it` |
| [x] | 投石 | `item_stone` | `a sling with a stone in its pouch` |
| [x] | 标枪 | `item_javelin` | `a short javelin with a throwing loop` |
| [x] | 火油罐 | `item_firepot` | `a small clay pot with a burning rag in its mouth` |
| [x] | 捕网 | `item_net` | `a weighted throwing net spread open` |

#### 材料（14 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 狼皮 | `wolf_hide` | `a wolf pelt spread flat` |
| [x] | 狼牙 | `wolf_fang` | `two wolf fangs side by side` |
| [x] | 兽骨 | `bone` | `a long bone` |
| [x] | 兽爪 | `claw` | `three curved claws` |
| [x] | 野猪獠牙 | `boar_tusk` | `a single curved boar tusk` |
| [x] | 野猪皮 | `boar_hide` | `a bristly boar hide spread flat` |
| [x] | 钱袋 | `coin_pouch` | `a small coin purse with two coins beside it` |
| [ ] | 青铜碎片 | `bronze_scrap` | `one bent rectangular metal plate with a torn corner and a single rivet hole` |
| [x] | 破盾 | `broken_shield` | `a round shield with a large piece broken out of it` |
| [x] | 箭束 | `arrows` | `a bundle of five arrows tied with cord` |
| [x] | 麻绳 | `rope` | `a coil of rope` |
| [x] | 酒囊 | `wine_skin` | `a wineskin with a stopper and a carrying strap` |
| [x] | 马鬃 | `horsehair` | `a tied hank of horsehair` |
| [x] | 狮鬃 | `lion_mane` | `a tuft of lion's mane` |

#### 界面（15 个）

| 完成 | 名称 | 标识 | {主体} |
|---|---|---|---|
| [x] | 德拉克马 | `coins` | `two stacked coins, the top one stamped with an owl` |
| [x] | 生命 | `heart` | `a heart` |
| [x] | 力量 | `strength` | `a flexed upper arm` |
| [x] | 防御 | `armor` | `a breastplate seen from the front` |
| [x] | 意志 | `will` | `a head in profile with a small flame at the brow` |
| [x] | 神性 | `divinity` | `a sun disc with straight rays` |
| [x] | 移动 | `boot` | `a walking boot` |
| [x] | 跳跃 | `jump` | `a figure leaping across a gap` |
| [x] | 营地 | `campfire` | `a campfire of three crossed logs` |
| [x] | 队伍 | `party` | `three standing figures side by side` |
| [x] | 行商 | `shop` | `a hanging hand scale with two pans` |
| [x] | 招募 | `talk` | `two figures clasping forearms` |
| [x] | 出征 | `march` | `a pennant on a spear` |
| [x] | 神赐 | `boon` | `a laurel wreath` |
| [x] | 系统 | `system` | `a Greek key meander folded into a square` |

### 2.2 特效

规格见 6.5：透明底序列帧，横排在一张图里。已有的来自免费特效库 pixelfx；下面是仍然缺的。

**特效模板**（把 `{内容}` 和 `{帧数}` 换掉）：

```
Pixel art visual effect sprite sheet for a 2D game: {内容}. Exactly {帧数} frames laid out left to right in a single horizontal row, every frame the same square size, showing the effect from start to finish. Fully transparent background. Crisp pixels, limited palette, no anti-aliasing blur, no text, no frame numbers, no borders between frames.
```

| 完成 | 特效 | 文件名 | {内容} | {帧数} | 循环 |
|---|---|---|---|---|---|
| [x] | 雷击落点（雷矢、天罚、升阶落雷） | `lightning.png` | `a white-gold lightning bolt striking straight down onto the ground, forking at the point of impact, then a brief ring of sparks spreading outward and fading` | 10 | 否 |
| [x] | 天火落下 | `skyfire.png` | `a ball of fire dropping from the top of the frame, bursting on the ground into a low spreading flame that dies down to embers` | 12 | 否 |
| [x] | 雷行的落点 | `thunderstep.png` | `a figure-sized column of blue-white light snapping into existence with small arcs of electricity crawling outward along the ground, then vanishing` | 8 | 否 |
| [x] | 天穹护盾 | `dome.png` | `a translucent pale gold half dome rising over a spot on the ground, shimmering once, then fading` | 10 | 否 |
| [x] | 雷躯（附在身上） | `thunderbody.png` | `thin arcs of white-gold electricity crawling over an invisible standing human shape, endlessly` | 8 | 是 |
| [x] | 捕网张开 | `net.png` | `a rope net flying in folded, opening wide in the air, and dropping flat` | 8 | 否 |
| [x] | 升级 | `levelup.png` | `a ring of warm ochre light rising from the feet to above the head of an invisible standing figure, ending in a small burst of laurel leaves` | 10 | 否 |
| [x] | 束缚（附在脚踝） | `rooted.png` | `two loops of rope tightening round a pair of invisible ankles, creaking slightly, endlessly` | 6 | 是 |

五张神力序列位于 `art/originals/fx/`，单帧 96×96。雷击约 20 帧/秒，天火约 19 帧/秒，雷行落点约 17 帧/秒，天穹约 13 帧/秒，均为单次播放。雷躯以 10 帧/秒循环至状态消失。

捕网、束缚和升级各使用一张 96×96 单帧的透明序列图。捕网在飞行途中张开，下落时收拢，末帧与脚踝绳圈的首帧相同。束缚持续时循环，解除时消失。战后经验跨过等级门槛时，赭金色月桂光环沿角色轮廓上升。

雷和火要按神性的阶位换颜色（受火偏蓝、半神偏金、僭神白金）。只交一套白色或白金色的即可，颜色由游戏叠上去。

### 2.3 标题画面

#### [x] 游戏标志

首页已使用正式标志。「潘多拉之裔」五字使用与菜单相同的缝合像素字体（12 像素字形四倍排印），英文副题使用同系列 10 像素字形，陶罐、烟缕和回纹作为独立装饰。排版源稿与装饰原图位于 `art/originals/title/`，游戏使用 `prototype/art/original/interface/pandora-title.png`。

```
A wide horizontal emblem for a game title in the manner of ancient Greek black-figure vase painting: an open storage jar (pithos) lying on its side at the centre, a thin wisp rising from its mouth, flanked left and right by a running Greek key meander border that fades out at both ends. Flat terracotta orange and black glaze colours only, with thin incised white lines. Transparent background, generous empty space in the middle band for lettering to be added later. No text, no letters.
```

#### [x] 主视觉图（可选）

商店页和宣传用的两版横图均为 1920×1080。无字版为 [pandora-key-art.png](art/originals/title/pandora-key-art.png)，宣传版为 [pandora-key-art-titled.png](art/originals/title/pandora-key-art-titled.png)。两版共用一幅画，宣传版在左侧天空叠放首页像素字标。[生成原稿](art/originals/title/pandora-key-art-source.png)保留原始尺寸。

```
Key art for a tactical role-playing game set in mythic ancient Greece. A young spearman with a red cord on his wrist stands on a limestone ridge at dawn, seen from behind and slightly above, a round shield on his back; on the ground beside him lies a great broken storage jar. Far ahead, storm light gathers over a mountain crowned with white columns. Three companions stand a few steps behind him: a huntress with a long bow, an old centaur, a dark-robed sorceress. Ancient Mediterranean gouache illustration, broad rich earthy colour planes, warm white limestone against a deep blue sky, visible brushwork, strong diagonal composition, wide 16:9 format. No text, no logo.
```

<details>
<summary>横版主视觉的实用提示词与参考原画</summary>

ImageGen 参考图依次为 `portraits/hero.png`、`figures.png`、`pholoe-centaurs-rear.png` 和 `medea.png`，均来自 `art/originals/`。正式字标在出图后单独合成。

> Paint the actual finished, full-bleed, 16:9 landscape store key art, landscape 2048×1152 if possible. Mythic ancient Greece at dawn. Imagine a painted book cover commissioned from the artist of these character originals, using the attached references for the EXACT character designs, cloth colours, builds, hair, materials and hand-painted gouache finish. Ref 1 the curly-haired young hero's portrait. Ref 2, use only rows 1 and 2 (young spearman and huntress); ref 3 use ONLY the elderly silver-haired WHITE HORSE centaur in the bottom row; ref 4 Medea in burgundy. References are model sheets, NOT the scene layout. Only FOUR people in the entire picture. Make a single continuous narrative landscape image: from a slightly elevated viewpoint behind the party, a broad limestone spur cuts diagonally up from the lower right toward the middle of the frame. At its forward edge, just right of centre at x .57, the young curly dark-haired spearman pauses in a strong three-quarter rear silhouette. Dusty oxide-red chlamys and rough ivory short chiton, sandals, round bronze shield strapped to his BACK, one long straight wooden spear gripped in his right hand with an unmistakable red cord tied round his bare wrist, spare cord end in the wind. Make him a bold focal point with a little of his sunlit cheek visible. At his feet in the near foreground, a very LARGE broken open storage jar with warm clay interior, chipped rim, ochre and black Greek key bands, distinct hand-sized shards, hint of pale vapour crossing the rock. A few paces behind him, spaced from one another on the right slope, the companions in character: Atalanta (brown hair tied up, tawny layered hunter's cloak, quiver and longbow), Chiron (wise aged white-bearded centaur in teal drape, physically single body with a complete white dappled equine lower half and FOUR horse legs, no rider), Medea (dark curls and wine-coloured gold-edged robe, little earthenware vial, no staff). Let us recognize each silhouette at thumbnail scale; vary the angles of their heads and poses, unify by their shared gaze. Across a huge blue Aegean gulf far ahead, storm light strikes a distant mountain crowned with a cluster of white Greek columns under a break in the cloud, lending the party a destination. Dawn bronze highlights touch their windblown clothes while an indigo storm front occupies the sky. Strong clear silhouettes, rich earthy color planes with warm chalk-white limestone in the foreground, deep marine blue, ochre and iron red; confident hand-painted dry gouache strokes across rock, fabric and sky, restrained paper tooth, beautifully observed gestures. A mythic journey, ominous and hopeful. Compose a quiet middle-dark expanse of natural sky/sea on the LEFT third in its upper/middle area so a title can be added later without covering faces or temple. Let sky and sea feel like a convincing continuation of the terrain there, not an artificial graphic vignette or flat blank field. Wide horizontal premium narrative illustration with foreground, middle distance and far-off architecture. No text, letters, logo, UI, frame, watermarks, modern objects, figurine bases, pixelated edges or photographic/CGI gloss.

</details>

### 2.4 主角的神性外观

[15 §2](15-relics-boons.md) 规定主角每升一阶换一次外观。战场与营地均按圣物数量显示当前阶位。

交四张图，**姿势和构图完全不变，只改颜色和光**。用主角现有的原画做参考图（`art/originals/figures.png` 里他的那一组；转身的八个朝向在 `hero-turn.png`），让工具只改指定的部分。

**共用的前半段**：

> Using the reference image, keep the character's pose, proportions, equipment and the six-cell layout exactly unchanged. Change only the following:

| 完成 | 阶 | 文件名 | 接在共用前半段后面 |
|---|---|---|---|
| [x] | 凡人 | 现有原画 | 不用改 |
| [ ] | 受火 | `hero-tier1.png` | `the ochre cloak gains a broad band of bright blue along its whole hem, about a quarter of the cloak's width, and the spearhead turns pale blue-white as if faintly glowing. Do not change the face or the eyes. Everything else stays earthy and human.` |
| [x] | 半神 | `hero-tier2.png` | `the cloak becomes deep blue with a gold border, the spearhead and shield rim become polished gold, and a thin rim of pale light outlines his whole figure. His skin is still warm and human.` |
| [x] | 僭神 | `hero-tier3.png` | `nearly everything he wears and carries becomes blue and gold, his skin loses its warmth and turns pale as marble, his eyes glow faintly white, and thin threads of lightning cling to the spear. The red cord on his wrist remains the only warm colour left on him.` |

半身像同样四个版本，文件名 `portraits/hero-tier1.png` 等，提示词用 1.3 里主角的那一条加上表里对应的一句。

返工：「受火」上一版只有一条细蓝边，战场上看不出来，所以蓝边加宽、矛尖带蓝光。淡蓝的眼睛只留在半身像里（半身像已通过，不用重出），战场原画不要动脸。

「僭神」的战场小人已加一圈金色描边（2026-11-25），免得大理石肤色在战场上像石像。描边由 `art/tools/bake_divinity.py` 生成，矛上的闪电和手腕红绳不描。

---

## 3. 第三档：后续章节

### 3.1 六位未登场的同伴

每人一张人物原画（6.1）加一张半身像（6.2）。下面是原画的提示词；半身像用"Same …"之后的外貌描述加 1.3 的共用后半段。

#### [ ] 代达罗斯（工匠，第 4 章）

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same aging Greek craftsman and inventor, wiry, balding with a grey fringe, thick dust-covered leather apron, a square wooden frame of tools strapped to his back, a coil of cord and a bronze compass at his belt, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, kneeling to pull a cord taut and set a device. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus equipment fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 阿斯忒里俄斯（米诺陶洛斯，第 4 章）

大型，占两格见方。敌我共用这一套原画。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same Minotaur, a huge heavy man's body with a bull's head and wide horns, about twice the bulk of an ordinary warrior, head carried low so the horns form an arch, dark hide on the shoulders, a torn red loincloth, broken shackles on both wrists, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, charging with head lowered and one hoof scraping the ground. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 卡珊德拉（特洛伊的女祭司，第 5 章）

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same Trojan priestess, slender, a long pale veil drawn low over half her forehead, white robe with a narrow purple border, bare arms, both hands empty and held slightly away from her sides, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, raising one open hand in warning while looking past the viewer. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 美杜莎（戈尔贡，第 5 章）

朝向必须一眼读得出来。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same Gorgon Medusa, a tall woman in a long dark green robe, her hair a dense dark mass of coiled snakes, a single line of pale light along the front of her face, eyes closed in the idle and walking poses, bare feet, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, attacking with the snakes turned toward the target and her eyes wide open. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 彭忒西勒亚（亚马逊女王，第 5–7 章）

骑兵，按四足单位处理，参考图用半人马那一张。

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same Amazon queen on horseback, a lean warrior woman in a short patterned tunic and trousers, crescent-shaped light shield, long cavalry lance, riding a bay horse with a cropped mane, rider leaning forward along the horse's neck so horse and rider form one long wedge, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, trotting, charging with the lance point lowered. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, horse and rider fit within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

#### [ ] 俄耳甫斯（歌者，第 6 章前）

```
Original PC tactical game sprite atlas on transparent background, precisely 3 columns and 2 rows. Same Thracian singer, a slight young man with long fair hair, pale blue mantle, a tortoiseshell lyre held so that his elbow and the lyre's arms frame a hollow ring, no weapon, in all six cells. Top row front three-quarter view facing right, bottom row rear three-quarter view facing away left. Columns idle, walking, playing with one hand stilled on the strings and head tilted back. High overhead 35 degree orthographic. Ancient Mediterranean gouache illustration, broad rich earthy color planes, distinctive readable silhouette, full body plus instrument fits within each cell, wide empty gutters. No text no dividers no backdrop or pedestal.
```

### 3.2 第 2 到第 8 章的敌人和首领

普通敌人用 6.1 的六格原画。下面每条是"Same" 之后、"in all six cells" 之前的那一段，前后套上 1.1 的固定句式即可。

| 完成 | 章 | 敌人 | 填在 `Same … in all six cells` 中间 |
|---|---|---|---|
| [x] | 2 | 沼蛇 | `large marsh water snake, thick mottled olive body, head raised to strike, half coiled` |
| [x] | 2 | 巨蟹 | `giant marsh crab the size of a shield wall, dark green shell crusted with mud, one oversized claw` |
| [x] | 2 | 赫拉的女祭司 | `priestess of Hera, stern woman in a white robe with a peacock-blue stole, tall diadem, a staff topped with a pomegranate` |
| [ ] | 3 | 铜羽鸟 | `Stymphalian bird, a heavy vulture-like bird of prey as tall as a man, short thick neck with a pale ruff, hooked bronze beak, every feather a plate of polished bronze with sharp edges, bronze talons, wings half raised. Not a heron, not a crane, no long legs, no long neck` |
| [x] | 3 | 鸟群 | `tight flock of five small dark marsh birds flying as one cluster` |
| [ ] | 3 | 沼地佣兵 | `Greek mercenary spearman in mud-stained grey cloak, wicker shield, wide-brimmed felt hat` |
| [ ] | 4 | 克里特卫兵 | `Minoan palace guard, bare chest, tight waist belt, kilt with a blue wave pattern, tall figure-eight shield and short spear` |
| [ ] | 4 | 青铜牛像 | `animated bronze statue of a bull, greenish patina, glowing seams at the joints` |
| [ ] | 4 | 迷宫祭司 | `Cretan labyrinth priest, long layered skirt, bare shoulders, bull-horn headdress, a double axe held upright like a standard` |
| [ ] | 5 | 塞壬 | `siren, a woman's head and arms on a large seabird's body, grey-white feathers, mouth open in song` |
| [ ] | 5 | 海盗 | `Aegean pirate, sun-bleached headscarf, bare tattooed arms, hooked boarding knife and a small round shield` |
| [ ] | 5 | 石卫 | `warrior turned to grey stone and moving again, cracked limestone surface, frozen startled face, stone spear` |
| [ ] | 6 | 亡魂 | `pale translucent shade of a dead soldier, drawn as two slightly offset layers of the same figure, hollow eyes, trailing off into mist below the knees` |
| [ ] | 6 | 溺者 | `drowned corpse rising from black water, waterlogged grey skin, long wet hair over the face, reaching arms` |
| [ ] | 6 | 复仇女神 | `Fury, a gaunt winged woman in a short black tunic, snakes wound round her arms, a burning torch and a whip` |
| [ ] | 7 | 地生巨人 | `earth-born giant, three times a man's height, rough clay-coloured skin, serpents for legs, carrying a boulder` |
| [ ] | 7 | 狱卒 | `gaoler of Tartarus, a hulking figure in blackened iron plates, a ring of huge keys, a hooked chain` |
| [ ] | 8 | 龙牙武士 | `sown warrior sprung from dragon's teeth, bone-white skin, bronze armour grown onto the body like bark, featureless helmet` |

第二章三名普通敌人的六格透明原画位于 `art/originals/`，标识分别为 `marsh_snake`、`giant_crab`、`hera_priestess`。沼蛇从盘身到伸颈探咬，巨蟹横移时收钳、出手时张钳，女祭司始终用右手持石榴杖、左手施福。运行时像素帧位于同名的 `prototype/art/pixel/` 子目录。已在 2-1 地形上用正常游戏镜头核对相邻格占位和转镜后的背面。本项勾选范围为角色美术，正式沼泽遭遇与战斗规则另行实现。

返工：铜羽鸟上一版照旧提示词里的「鹤一样大、长喙」画成了水鸟，和概念图 `art/direction/stymphalus-bronze-vulture.png` 对不上。重出时把这张概念图当参考图一起给。鸟群已通过。

第三章的[铜羽鸟](art/originals/stymphalian_bird.png)和[鸟群](art/originals/marsh_flock.png)各有正面斜视、侧后方两排，每排依次为待机、飞行、攻击。前者以长铜喙和整片翼缘辨认，后者在六个姿势中都保留五只独立的小鸟，整群共占一格。游戏像素帧位于同名的 `prototype/art/pixel/` 子目录。

首领的体型和部位各不相同，做到那一章时单独写规格。下面是先出概念图用的提示词（单张立绘，不是六格）：

**首领概念图共用的后半段**：

> …Single full-figure creature design on a plain dark background, seen from a high three-quarter angle about 35 degrees. Ancient Mediterranean gouache illustration, broad rich earthy colour planes, strong readable silhouette. No text.

| 完成 | 章 | 首领 | 前半段 |
|---|---|---|---|
| [x] | 2 | [许德拉](art/direction/lerna-hydra.png) | `The Hydra of Lerna: a massive serpent body half sunk in a marsh pool with five long necks and heads, each head clearly separate so it can be struck off on its own; one neck stump is a wet glistening open wound, another is a seared matte black ring.` |
| [x] | 3 | [阿瑞斯的铜鹫](art/direction/stymphalus-bronze-vulture.png) | `The bronze vulture of Ares: an enormous bird in flight, every feather a sharpened bronze blade, a thin bright line of light along the leading edge of its wings.` |
| [x] | 5 | [美杜莎的两位姐妹](art/direction/gorgon-sisters.png) | `Stheno and Euryale, the two immortal Gorgon sisters: broad-shouldered winged women with tusked faces, snake hair, bronze hands, standing back to back.` |
| [x] | 6 | [刻耳柏洛斯](art/direction/cerberus.png) | `Cerberus: a hound the size of a house with three distinct heads on three necks, a mane of small snakes, a serpent for a tail, standing before a dark gate.` |
| [x] | 7 | [伊阿珀托斯](art/direction/tartarus-iapetus.png) | `The Titan Iapetus chained in Tartarus: a colossal kneeling figure of dark stone and iron, each limb held by a chain whose links grow larger toward the wall; a separate notch in the silhouette at each shoulder, wrist and knee marks a place that can be attacked.` |
| [x] | 8 | [阿瑞斯](art/direction/olympus-ares.png) | `The god Ares: a towering warrior in crested bronze armour the red of dried blood, advancing straight ahead with spear levelled, shield rim catching the light.` |
| [x] | 8 | [阿波罗](art/direction/olympus-apollo.png) | `The god Apollo: a slender radiant archer in white, a silver bow drawn, a single thin perfectly straight line of light running from the arrowhead.` |
| [x] | 8 | [宙斯](art/direction/olympus-zeus.png) | `The god Zeus enthroned: a vast bearded figure in ivory and gold, one hand raised holding a thunderbolt, storm cloud for a cloak, the columns behind him casting almost no shadow.` |

米诺陶洛斯和美杜莎本人见 3.1，赫拉克勒斯已有原画。

### 3.3 第 2 到第 8 章的战场

每章需要一张可平铺的地表材质（6.4）和一张气氛概念图。

**地表材质共用的后半段**：

> …Seamless tileable ground texture seen from directly above, flat even lighting with no cast shadows and no perspective, hand-painted gouache look with visible brush marks, 1024 by 1024. No objects, no plants standing up, no text.

**气氛图共用的后半段**：

> …Tactical game battlefield seen from a high three-quarter angle about 35 degrees, terrain arranged in clear stepped levels so heights are easy to read. Ancient Mediterranean gouache illustration, broad colour planes, visible brushwork, wide 16:9 format. No characters, no text, no grid.

| 完成 | 章 | 地表材质的前半段 | 气氛图的前半段 |
|---|---|---|---|
| [x] | 2 勒拿沼泽 | `Dark wet marsh mud with shallow verdigris-green pools, flattened reeds and a few drowned roots.` | `The swamp of Lerna at dusk: flat verdigris-green water in horizontal bands, vertical reeds, a few broken temple columns standing in the mire, one small bright fire the brightest point in the scene.` |
| [x] | 3 斯廷法利斯湖 | `Pale grey lakeshore silt with scattered pebbles, dry reed stubble and a few fallen bronze feathers.` | `Lake Stymphalia under a pearl-grey sky: a wooden jetty and a fisherman's hut on the shore, reed beds, a set of bronze clappers on a post, sky and water almost the same colour.` |
| [ ] | 4 克里特迷宫 | `Worn dark terracotta-red floor slabs with a faint incised spiral pattern and dust in the joints.` | `The labyrinth of Crete: dark red walls folding back on themselves round a black pit, a stone doorway, a horned altar, torches in brackets, a single red thread caught at one corner.` |
| [ ] | 5 爱琴海诸岛 | `White island limestone with wind-blown sand in the hollows and patches of dry sea thrift.` | `An Aegean island shore in hard noon light: white rock, ultramarine sea, a beached ship, a sea cave, and several figures of people turned to stone, backlit, their cloaks all blown the same way.` |
| [ ] | 6 冥界 | `Ash-grey plain of fine dust with faint pale footprints and thin cracks.` | `The underworld: indigo-black water swallowing the far bank, a ferry with a single amber lantern, a huge dark gate, a grey plain with no horizon.` |
| [ ] | 7 塔尔塔罗斯 | `Black slate floor split by pressure cracks, a faint glow of molten orange deep in the widest cracks.` | `The pit of Tartarus: dark iron chains crossing a deep shaft on the diagonal, each link larger than the last, a bronze wall, furnace seams glowing near white.` |
| [ ] | 8 奥林匹斯 | `Polished ivory-white marble paving with fine grey veining and thin gold inlay lines.` | `Olympus above the clouds: endless repeating ivory colonnades, a broad stair, a throne, statues of gods, a sky with almost no shadow in it.` |

第二章地表原图见 [勒拿湿泥](art/originals/lerna-mud.png)，黄昏配色与地标布局见 [战场气氛图](art/direction/lerna-marsh.png)。湿泥可四向平铺。沼泽场景按地形格混合泥岸、浅水与深水，水纹在水面移动，岸沿芦苇随风摆动。[场景试镜](art/tools/preview_lerna_marsh.gd)使用常规战斗镜头、1.2 米格距及三名敌人的正式帧，可复查它们在相邻格与转镜后的轮廓。

第三章的[湖岸地表](art/originals/stymphalus-silt.png)可四向平铺，[气氛图](art/direction/stymphalus-lake.png)确定了珍珠灰湖水、渔屋、木栈桥与铜响板的配色。[湖岸试镜](art/tools/preview_stymphalus_lake.gd)中，两种单位各占相邻的一格，常规战斗镜头按默认缩放转动 90°。

地标的三维模型按 1.4 的办法：先出单件参考图，再图生三维。

---

## 4. 建议的制作顺序

1. [x] 营地三人的原画和半身像（1.1 的前三位、1.3）。每次回营地都看到，投入最少、改观最大。
2. [x] 五位主线人物的半身像（1.3）。
3. [x] 状态徽章、指令、圣物和首领剪影（2.1 的前四批，共 27 个）。新做的"夺圣物 / 放过"界面正在用。
4. [x] 美狄亚补动作（1.2）。
5. [x] 六位英雄的原画和配套半身像（1.1、1.3）。已完成 6/6。
6. [x] 主角四阶外观与配套半身像（2.4），以及六招神力使用的五张特效序列（2.2）。
7. [x] 营地帐篷和希腊道具（1.4），10/10 已接入营地。
8. 其余按需。已完成 2.1 的六枚神力招式图标、主角的 14 枚、阿塔兰忒的 11 枚、喀戎的 10 枚、美狄亚的 11 枚及六位招募英雄的 22 枚招式和特性图标，以及 26 枚装备、6 枚随身物品、14 枚战利品材料和 15 枚界面图标，2.2 的捕网张开、脚踝束缚与升级特效，以及 2.3 的首页游戏标志、商店页与宣传横版主视觉。

## 5. 素材数量一览

| 类别 | 数量 | 档 |
|---|---|---|
| 人物原画（第一章） | 10 | 一 |
| 半身像（第一章） | 14 | 一 |
| 营地道具 | 10 | 一 |
| 图标 | 162 | 二 |
| 特效 | 8 | 二 |
| 标题 | 2 | 二 |
| 主角神性外观 | 3 套原画 + 3 张半身像 | 二 |
| 后续同伴 | 6 套原画 + 6 张半身像 | 三 |
| 后续敌人 | 18 套原画 | 三 |
| 后续首领概念图 | 8 | 三 |
| 后续战场 | 7 张材质 + 7 张气氛图 | 三 |

图标的数量按现在的技能表和物品表逐个数过；敌方专用的招式（撕咬、冲撞、咆哮等）玩家看不到图标，没有列。

## 6. 交付规格

### 6.1 人物原画

一张图 6 个姿势，其余帧由脚本生成。

| 项目 | 要求 |
|---|---|
| 画幅 | 1536×1024，横向 3 列 × 纵向 2 行，每格 512×512 |
| 上排 | 正面四分之三视角，面朝右：待机、行走、攻击 |
| 下排 | 背面四分之三视角，背朝镜头偏左：待机、行走、攻击 |
| 视角 | 约 35° 俯视，正交，和现有角色一致。**不要**画成 50° 以上的高俯视 |
| 一致性 | 6 格是同一个人：同样的衣服、武器、持械手、体型 |
| 占位 | 全身连同武器完整落在格内，格与格之间留出明显空隙 |
| 背景 | 透明，或纯深色。不要地面、底座、投影、文字、分隔线 |
| 画法 | 古地中海水粉插画，大块的土色色面，轮廓清晰易辨 |
| 文件 | `art/originals/<标识>.png` |

**参照图**：`art/originals/bandit.png`、`bandit_archer.png`、`bandit_chief.png`、`refugee.png`；四足单位用 `pholoe-centaurs.png` 和 `pholoe-centaurs-rear.png`。新图放在它们旁边应该看不出是两批画的。

**验收时最常见的问题**：六格里人不一样（衣服颜色、持械手换边）；格子之间肢体或武器粘连；带了地面阴影或底座；视角太俯。任何一条都重出。

**想要更好的动作**，可以像主角那样多交（都不是必需）：

| 追加 | 内容 | 参照 |
|---|---|---|
| 行走分解 | 6 帧 × 正背两面 | `art/originals/hero-gait.png` |
| 攻击关键帧 | 4 帧 × 正背两面 | `art/originals/hero-attack.png` |
| 转身 | 8 个朝向 | `art/originals/hero-turn.png` |
| 专属招式 | 该招的 2 到 3 个关键姿势，正背两面 | `art/originals/strike-keys.png` |

第一章敌人用过的三份原始提示词在 `art/originals/supplemental-prompts.json`，本文的人物提示词都是照它的句式写的。

### 6.2 半身像

| 项目 | 要求 |
|---|---|
| 画幅 | 640×800，透明底 |
| 构图 | 胸部以上，四分之三侧脸，视线略偏向画面一侧。头顶留出约一成空白 |
| 画法 | 和人物原画同一套水粉画法、同一套服装和配色 |
| 表情 | 先交平静。以后再补怒、忧、喜 |
| 文件 | `art/originals/portraits/<标识>.png`，补表情时用 `<标识>-angry.png` 这样的后缀 |

游戏里头像现在显示成圆章。半身像交上来后我会按圆形裁切，所以**脸要在画面中间偏上，肩膀以下可以被裁掉**。

### 6.3 图标

| 项目 | 要求 |
|---|---|
| 格式 | SVG 最好；或 256×256 的透明底 PNG（首领剪影 512×512） |
| 画法 | 单色剪影，白色图形、透明背景，内部用几道细线表示细节。颜色由游戏按稀有度和状态上色 |
| 可读性 | 缩到 24×24 仍能认出是什么。状态徽章要在 14×14 下能认 |
| 文件 | 交到 `art/originals/icons/<标识>.png`。标识就是各表里的那一列 |

出图工具常给图标加上圆底、方框或渐变。出现这些就在提示词末尾再强调一遍 `no background shape`，或者出完后抠掉。

### 6.4 场景模型和材质

| 项目 | 要求 |
|---|---|
| 模型格式 | `.glb` 或 `.gltf` |
| 尺度 | 1 个单位 = 1 米；一格地面是 1.2 米见方；普通人高约 1.75 米 |
| 材质 | 一张基础色贴图即可，不要金属度、粗糙度、法线贴图。游戏里会套统一的手绘质感 |
| 面数 | 单个道具 2000 三角面以内，帐篷这类大件 5000 以内 |
| 原点 | 底面中心，落在地面上 |
| 地表材质 | 1024×1024，可平铺，参照 `art/originals/limestone.png` |

### 6.5 特效

| 项目 | 要求 |
|---|---|
| 格式 | 透明底的序列帧，横排在一张 PNG 里，帧与帧等宽 |
| 单帧 | 64×64 或 96×96 |
| 帧数 | 6 到 12 帧，以 2.2 的表为准 |
| 文件 | `art/originals/fx/<文件名>`，另附一句话说明每秒几帧、是否循环 |

出图工具出的序列帧，帧与帧之间经常对不齐。交上来后我会逐帧重新对位；对不齐得太厉害的那几帧会丢掉。

## 7. 交给我之后

素材交到对应目录后，告诉我是哪一项，我负责切图对齐、生成全套动作帧、接进游戏、截图给你确认，并把这份清单里对应的 `[ ]` 改成 `[x]`。

第三方素材和 AI 生成的素材，都要在 `prototype/art/thirdparty/CREDITS.md` 里记一行（来源或工具、作者、许可或日期）。
