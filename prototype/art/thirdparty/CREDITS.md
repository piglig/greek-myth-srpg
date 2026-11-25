# 第三方美术素材来源

每加入一份外部素材，在这里记一行。**可商用**一栏写"否"的素材，在游戏商业化之前必须替换。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `nature/` | Stylized Nature MegaKit（免费标准版） | Quaternius | CC0 1.0 | 是 | 是 | https://opengameart.org/content/stylized-nature-megakit | TwistedTree_1–3（橄榄树）、Pine_1 / Pine_3（柏树位置）、Bush_Common、Grass_Wispy_Short；沼泽战场另取 DeadTree_1–3（枯树）、Rock_Medium_1–3（岸边石块）。贴图缩到 512，去掉了法线贴图 |
| `water/` | Seamless looping waves heightmaps（waves3，100 帧取 50）；Water Caustics Effect (Small)（16 帧） | 前者见 OpenGameArt 页面署名；后者 leeor_net | 均为 CC0 1.0 | 是 | 是 | https://opengameart.org/content/seamless-looping-waves-heightmaps 、https://opengameart.org/content/water-caustics-effect-small | 沼泽战场的水面。水波高度图由 `art/tools/bake_water.py` 算出坡度并打包成 `waves.png`（10×5 格）；水底光网打包成 `caustics.png`（4×4 格）。原始压缩包没有入库 |
| `ambientcg/` | Ground080（沙）、Ground109（泥）、Rock051（层状岩） | ambientCG（Lennart Demes） | CC0 1.0 | 是 | 是 | https://ambientcg.com/view?id=Ground080 、https://ambientcg.com/view?id=Ground109 、https://ambientcg.com/view?id=Rock051 | 沼泽战场（2-2、2-3）的三种地面：干处的沙、近水处的泥、陡坎的岩壁。各取 1K 的颜色图和法线图，存为 `sand_*`、`mud_*`、`rock_*`。沙的颜色在着色里压掉了大半，只留纹理 |

模型只提供形状，叶片颜色由 `view/flora.gdshader` 决定。设置环境变量 `SRPG_FLORA=0` 可以切回程序生成的树，用于对比。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `pixelfx/` | pixelfx 0.3.1 | Patch、Hugo Duprez | MIT（须保留 `LICENSE` 和 `NOTICE.md`） | 是 | 是 | https://github.com/patch-gg/pixelfx | `impacts/hit-spark`（命中）、`melee/sword-slash`（斩击）、`impacts/heavy-landing`（落地扬尘）、`explosions/small-explosion`（火油罐炸开）、`impacts/blunt-hit`（石块和标枪落点）、`holy/blessing`（喝药）、`status/burning` `nature/toxic-puddle` `status/stunned`（灼烧、中毒、眩晕，状态持续期间一直在身上循环）。新加的几个都按亮度改成了游戏自己的色系、`fire/campfire`（燃烧格）。前三个换成了铜色和石尘色 |

`pixelfx/` 里的图由 `art/tools/bake_pixelfx.py <pixelfx 目录>` 生成，要加特效或换颜色改这个脚本。

| 目录 | 素材 | 作者 | 许可 | 可商用 | 可随仓库分发 | 来源 | 用了哪些 |
|---|---|---|---|---|---|---|---|
| `fusion-pixel/` | 缝合像素字体 Fusion Pixel 2026.11.10 | TakWolf 及各源字体作者 | SIL OFL 1.1（须保留 `OFL.txt`，不得单独售卖字体） | 是 | 是 | https://github.com/TakWolf/fusion-pixel-font | 10 像素和 12 像素的简体中文比例字体，全部界面文字都用它 |

| `game-icons/` | game-icons.net 图标 138 个 | Lorc、Delapouite、Skoll、Cathelineau、HeavenlyDog、Lucas | CC BY 3.0（**必须署名**，名单在目录里的 `CREDITS.txt`） | 是 | 是 | https://game-icons.net | 技能、装备、材料、属性、营地页签、战斗指令的图标。清单和取用脚本：`art/tools/fetch_game_icons.py` |
| `camp/props/` | Fantasy Props MegaKit 标准版（免费部分，94 件里取了 23 件） | Quaternius | CC0 | 是 | 是 | https://quaternius.com/packs/fantasypropsmegakit.html（下载自 https://opengameart.org/content/fantasy-props-megakit ） | 早期营地的货摊、木箱、木桶、陶罐、布袋、武器架、训练假人、盾、长凳、凳子、旗帜、箱子等。四套共用贴图从 2048 缩到 1024（颜色）/ 512（法线、ORM） |
| `camp/survival/` | Survival Kit 2.0（80 件里取了 11 件） | Kenney | CC0 | 是 | 是 | https://kenney.nl/assets/survival-kit（下载自 https://opengameart.org/content/survival-kit ） | 早期营地的帐篷、铺盖、原木、路牌。原配色是现代露营的橙黄，游戏里用 `view/camp_canvas.gdshader` 只取明暗，改画成亚麻布和旧木 |
| `camp/greek/` | Doric Greek Column | Victor Viña | CC BY 3.0（**必须署名**） | 是 | 是 | https://poly.pizza/m/5VD5-v8NBZ4 | 早期营地里一立一倒两根残柱。模型没有贴图，表面用的是游戏里地标的石灰岩质感。 |

署名要求：game-icons 和 `camp/greek/` 的许可要求在游戏里列出作者。发布前需要做一个致谢页面，目前还没有。

## 原创生成素材

2026-11-25，OpenAI ImageGen。营地行商阿齐尔、教习达蒙、领路人伊俄的六姿势原画与对话半身像，以项目原创人物为画风参考。文件位于 `art/originals/` 和 `art/originals/portraits/`，标识为 `npc_trader`、`npc_drill`、`npc_guide`。

2026-11-25，OpenAI ImageGen。阿尔卡斯、阿塔兰忒、喀戎、美狄亚、赫拉克勒斯的对话半身像，以各自的游戏角色图为造型参考，沿用营地半身像的画法。文件位于 `art/originals/portraits/`。

## 原创图标

2026-11-25，Codex 为本项目绘制的 27 枚陶绘剪影，含状态、战斗指令、圣物与首领。SVG 位于 `prototype/art/original/icons/`，对应的透明 PNG 位于 `art/originals/icons/`。

2026-11-25，OpenAI ImageGen。美狄亚两面六姿势原画 `art/originals/medea.png`，参考其项目内角色图和半身像；移动、施法过渡与受击、倒地序列由项目制作脚本生成。

2026-11-25，OpenAI ImageGen。伊达斯、欧律提翁的正面及侧后方六姿势原画与配套半身像，伊达斯另有双手举斧蓄力稿。素材位于 `art/originals/` 与 `art/originals/portraits/`；游戏帧由 `art/tools/bake_epic.py` 从原画生成。

2026-11-25，OpenAI ImageGen。安开俄斯（`merc_captain`）与福洛斯（`merc_lancer`）的两面六姿势原画和配套半身像，以项目原画为画风参考。安开俄斯另有横扫蓄力稿。文件位于 `art/originals/` 及其 `portraits/` 目录。

2026-11-25，OpenAI ImageGen。伊菲克勒斯（`merc_sword`）和法勒洛斯（`merc_archer`）的六姿势原画与半身像以本项目的希腊水粉原画为画风参考，位于 `art/originals/` 及其 `portraits/` 目录。

2026-11-25，第六批。阿尔卡斯的三套进阶战场外观由本项目原画分区着色并沿用原动作。三张进阶半身像与五张神力特效主画面由 OpenAI ImageGen 生成；特效主画面位于 `art/originals/fx/divine-keys/`，依照各招的发动、落点和回落节奏逐帧处理。

2026-11-25，第七批。营地两顶帐篷与八种道具由本项目建模，文件位于 `prototype/art/camp/`。基础材质、黑绘陶纹和猫头鹰盾绘以项目行商原画为画风参考，由 OpenAI ImageGen 生成并整理为一张基础色贴图。三张绘制源图位于 `art/originals/camp/`。

2026-11-25，第八批。捕网、脚踝束缚和升级月桂光环由项目原创绘制，制作脚本为 `art/tools/draw_status_fx.py`，透明序列图位于 `art/originals/fx/` 与 `prototype/art/original/fx/`。

2026-11-25，第八批首页标志。陶罐与回纹装饰由 OpenAI ImageGen 为本项目生成。中英文分别取自项目内的缝合像素字体 12 像素与 10 像素字形，沿像素格排版。字体署名与 OFL 许可见上方 fusion-pixel 条目。源稿位于 `art/originals/title/`。

第八批商店页主视觉由 OpenAI ImageGen 以本项目的阿尔卡斯、阿塔兰忒、喀戎和美狄亚原画为参考生成，源图位于 `art/originals/title/pandora-key-art-source.png`。宣传版沿用首页标志。

第八批神力招式图标。雷矢、天火、雷行、天穹、天罚、雷躯均为本项目原创的陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批持盾主角的 14 枚招式与特性图标为本项目原创陶绘剪影，矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批六位招募英雄的 22 枚招式与特性图标为本项目原创陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批装备图标。手部、身体、足部和饰品共 26 枚，为本项目原创陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批随身物品。六枚陶绘剪影及投石弹丸由本项目原创绘制，矢量稿位于 `prototype/art/original/icons/`。六枚物品图标的 256 像素透明 PNG 位于 `art/originals/icons/`。

第八批战利品材料。狼皮、野猪獠牙、箭束、狮鬃等 14 枚黑绘陶器风格剪影为本项目原创。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批界面图标。德拉克马、七项人物属性及七个营地与菜单标识，均为本项目原创陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批阿塔兰忒图标。六种射术与五项特性均为本项目原创陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批喀戎图标。四种箭术与六项医者、导师特性均为本项目原创陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第八批美狄亚图标。六种巫火、咒术招式和五项特性使用本项目原创陶绘剪影。矢量稿位于 `prototype/art/original/icons/`，256 像素透明 PNG 位于 `art/originals/icons/`。

第二章勒拿沼泽敌军。沼蛇、巨蟹和赫拉的女祭司各六格原画均为本项目 AI 生成的原创素材，位于 `art/originals/`。游戏使用由原画转制的二维像素帧。

勒拿沼泽地表与气氛图为本项目 AI 生成的原创水粉素材。地表位于 `art/originals/lerna-mud.png`，战场概念图位于 `art/direction/lerna-marsh.png`。

第三章斯廷法利斯湖的湖岸地表、气氛图及铜羽鸟、五鸟群的两张六姿势原画，均为本项目 AI 生成的原创水粉素材。两种单位的游戏帧沿用项目的二维像素转制流程。

2026-11-25 · OpenAI ImageGen。第二章许德拉的六格头颈、两态断颈、盘绕身体及沼蛇、巨蟹、许德拉之首三张头像，依据本项目的许德拉概念图及沼蛇、巨蟹战场原画生成。

2026-11-25 · OpenAI ImageGen。伊俄拉俄斯六格原画参照本项目的山贼和山贼头领原画生成，半身像以伊俄拉俄斯六格原画为人物参考。

2026-11-25 · OpenAI ImageGen。勒拿神龛、垂柳、黑桤木、枯树依据本项目勒拿沼泽气氛图生成。干岸、湿泥、岸壁断面、林地、焦土参照同章气氛图与既有湿泥的水粉笔触生成，四向平铺版位于 `art/originals/lerna-terrain/`。

2026-11-25 · OpenAI ImageGen。第二章林火、残桩、烧封、断颈再生、毒涎、女祭司赐福、剧毒七张像素特效，参考本项目天火、升级特效与许德拉原画生成，统一导出为 96×96 单帧透明序列。
