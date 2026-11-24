"""Fetch the game-icons.net drawings the interface uses (CC BY 3.0, https://game-icons.net).

    python art/tools/fetch_game_icons.py

Each entry maps the name the game asks for to `<artist>/<icon>` in the game-icons
repository. The files are saved as SVG; `Px.icon()` redraws them as small one-colour
stamps at run time. A credits file listing every artist is written beside them, which
the licence requires us to ship.
"""
from pathlib import Path
import urllib.request

out = Path(__file__).resolve().parents[2] / "prototype/art/thirdparty/game-icons"
out.mkdir(parents=True, exist_ok=True)

ICONS = {
    # camp pages
    "party": "delapouite/three-friends", "skills": "delapouite/skills", "gear": "lorc/knapsack",
    "shop": "lorc/trade", "talk": "lorc/conversation", "march": "lorc/flying-flag",
    "system": "lorc/cog", "coins": "delapouite/two-coins", "campfire": "lorc/campfire",
    "lock": "lorc/padlock", "done": "delapouite/check-mark", "here": "delapouite/position-marker",
    "laurel": "lorc/laurel-crown", "helmet": "delapouite/spartan-helmet", "temple": "delapouite/greek-temple",
    "heart": "skoll/hearts", "boot": "lorc/walking-boot", "jump": "delapouite/jump-across",
    "strength": "delapouite/biceps", "armor": "lorc/armor-vest", "will": "lorc/inner-self",
    "divinity": "lorc/sunbeams", "relic": "lorc/lion", "boon": "lorc/laurels",
    # charms
    "olive": "delapouite/olive", "wrist": "delapouite/bracer", "brooch": "cathelineau/medusa-head",
    "anklet": "lorc/winged-leg", "stone": "lorc/rune-stone",
    # hero
    "shield_wall": "heavenly-dog/defensive-wall", "intercept": "delapouite/shield-opposition",
    "shield_drive": "delapouite/shield-bash", "bulwark": "lorc/bordered-shield",
    "phalanx_thrust": "lorc/spears", "slam": "lorc/heavy-fall", "iron_arm": "lorc/mailed-fist",
    "heel_strike": "lorc/foot-trip", "wrestler": "lorc/meditation", "breaker": "delapouite/hammer-break",
    # atalanta
    "vital_shot": "lorc/on-target", "patience": "lorc/sands-of-time", "pin_shot": "lorc/nailed-foot",
    "beast_hunter": "lorc/boar-tusks", "calydon": "lorc/flaming-arrow", "skirmish": "lorc/sprint",
    "leap_shot": "lorc/high-shot", "fleet": "lorc/pine-tree", "ridge_shot": "lorc/peaks",
    "high_jump": "delapouite/deer-track",
    # chiron
    "purify_arrow": "lorc/arrow-flights", "field_medicine": "delapouite/caduceus",
    "herb_pouch": "delapouite/herbs-bundle", "triage": "lorc/bandage-roll", "antidote": "delapouite/medicines",
    "weak_point": "lorc/target-arrows", "mentor_stagger": "lorc/awareness", "repel_arrow": "lorc/striking-arrows",
    "keen_eye": "delapouite/eye-target", "centaur_volley": "delapouite/sagittarius",
    # medea
    "kindling": "lorc/small-fire", "solar_flame": "lorc/sun-radiations", "cinder_lance": "lorc/fire-ray",
    "long_flame": "lorc/burning-embers", "solar_blood": "skoll/blood", "frailty": "lorc/cursed-star",
    "lingering_hex": "lorc/chained-heart", "bind_hex": "lorc/manacles", "hex_ward": "lorc/magic-shield",
    "night_hex": "lorc/evil-moon",
    # battle commands and the battle bar
    "act_spear": "lorc/spear-hook",
    "act_slash": "lorc/broadsword",
    "act_shield": "delapouite/shield-bash",
    "act_grapple": "lorc/grab",
    "act_wait": "lorc/hourglass",
    "act_facing": "delapouite/clockwise-rotation",
    "act_undo": "delapouite/anticlockwise-rotation",
    "act_shoot": "lorc/pocket-bow",
    "act_fire": "lorc/fire-ray",
    "act_release": "lorc/hand",
    "act_guard": "lorc/checked-shield",
    "act_mark": "lorc/target-arrows",
    "act_push": "delapouite/push",
    "ui_threat": "lorc/crossed-swords",
    "ui_terrain": "lorc/mountains",
    "ui_log": "lorc/scroll-unfurled",
    "ui_keys": "delapouite/keyboard",
    "ui_menu": "delapouite/hamburger-menu",
    "ui_next": "delapouite/next-button",
    # conditions shown beside a unit's bar
    "st_poison": "lorc/poison-bottle", "st_stun": "lorc/star-swirl", "st_dodge": "lorc/dodging", "st_shield": "lorc/shield-reflect",
    # things carried into battle
    "item_potion": "lorc/potion-ball",
    "item_antidote": "lorc/round-bottom-flask",
    "item_stone": "delapouite/stone-pile",
    "item_javelin": "lorc/thrown-spear",
    "item_firepot": "lorc/molotov",
    "item_net": "lorc/fishing-net",
    "act_item": "lorc/swap-bag",
    "act_move": "delapouite/walk",
    # gear and spoils
    "art_glove": "delapouite/gloves",
    "art_gauntlet": "lorc/mailed-fist",
    "art_bracers": "delapouite/forearm",
    "art_ring_hand": "delapouite/ring",
    "art_knuckle": "delapouite/brass-knuckles",
    "art_thread": "delapouite/sewing-string",
    "art_leather": "lorc/leather-vest",
    "art_breastplate": "lorc/breastplate",
    "art_cloak": "lorc/cloak-dagger",
    "art_tunic": "delapouite/sleeveless-jacket",
    "art_scale": "lorc/scale-mail",
    "art_belt": "lucasms/belt",
    "art_pelt": "delapouite/animal-hide",
    "art_sandal": "delapouite/sandal",
    "art_boots": "lorc/boots",
    "art_greaves": "delapouite/greaves",
    "art_wingfoot": "lorc/wingfoot",
    "art_steps": "lorc/footprint",
    "art_necklace": "lorc/gem-necklace",
    "art_pendant": "lorc/gem-pendant",
    "art_amulet": "lorc/gem-chain",
    "art_fang_charm": "lorc/sharp-smile",
    "art_owl": "lorc/owl",
    "art_cup": "lorc/chalice-drops",
    "art_feather": "lorc/feather",
    "art_tooth": "lorc/tooth",
    "art_claw": "lorc/claw-slashes",
    "art_tusk": "lorc/boar-tusks",
    "art_pouch": "lorc/swap-bag",
    "art_bronze": "lorc/metal-bar",
    "art_broken": "lorc/broken-shield",
    "art_arrows": "lorc/arrow-cluster",
    "art_rope": "delapouite/rope-coil",
    "art_mane": "lorc/lion",
    "art_wine": "lorc/wine-glass",
    "art_bone": "lorc/bone-knife",
    "art_horsehair": "lorc/horse-head",
    "art_wolf": "lorc/wolf-head",
}
ARTISTS = {"lorc": "Lorc", "delapouite": "Delapouite", "skoll": "Skoll", "cathelineau": "Cathelineau",
           "heavenly-dog": "HeavenlyDog", "lucasms": "Lucas"}

credits = {}
for name, source in ICONS.items():
    target = out / f"{name}.svg"
    if not target.exists():
        url = f"https://raw.githubusercontent.com/game-icons/icons/master/{source}.svg"
        target.write_bytes(urllib.request.urlopen(url, timeout=30).read())
    artist = source.split("/")[0]
    credits.setdefault(ARTISTS.get(artist, artist), []).append(source.split("/")[1])

lines = ["Icons from https://game-icons.net, used under CC BY 3.0",
         "https://creativecommons.org/licenses/by/3.0/", ""]
for artist in sorted(credits):
    lines.append(f"{artist}: {', '.join(sorted(credits[artist]))}")
(out / "CREDITS.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(len(ICONS), "icons;", {k: len(v) for k, v in credits.items()})
