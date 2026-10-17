import json, sys
src, dst = sys.argv[1], sys.argv[2]
d = json.load(open(src, encoding='utf-8'))
keep = lambda o, ks: {k: o[k] for k in ks if k in o}
out = {
    "heroList": [keep(h, ["id","heroGuid","roleGuid","roleType","name","icon","smallIconUrl","cover","ddHeroIcon","destinyHeroBanner","isStadium"]) for h in d["heroList"]],
    "mapList": [keep(m, ["guid","id","icon","name","mode"]) for m in d["mapList"]],
    "heroAttrList": [keep(a, ["heroGuid","valueGuid","valueText","valueType"]) for a in d["heroAttrList"]],
    "perkList": [keep(p, ["id","guid","name","icon"]) for p in d["perkList"]],
    "heroPerkList": {k: [keep(p, ["heroId","id","name","icon"]) for p in v] for k, v in d["heroPerkList"].items()},
    "modTrait": {k: [keep(t, ["heroId","id","name","category","level"]) for t in v] for k, v in d["modTrait"].items()},
    "seasonList": d.get("seasonList", {}),
    "rankList": [keep(r, ["key","icon","level"]) for r in d.get("rankList", [])],
    "rankListFight": [keep(r, ["key","icon"]) for r in d.get("rankListFight", [])],
    "appreciationLevelIcon": d.get("appreciationLevelIcon", {}),
    "AIEvaluateConfig": d.get("AIEvaluateConfig", []),
}
json.dump(out, open(dst, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, separators=(",", ":"))
print({k: len(v) for k, v in out.items()})
