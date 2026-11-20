"""对拍：逐行比较 Godot 基准行和 Go 输出（忽略 ms 耗时字段）。用法: compare.py <godot.jsonl> <go.jsonl>"""
import json, sys

def load(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        if line.strip():
            r = json.loads(line)
            r.pop("ms", None)
            rows.append(r)
    return rows

a, b = load(sys.argv[1]), load(sys.argv[2])
bad = 0
if len(a) != len(b):
    print(f"row count differs: {len(a)} vs {len(b)}"); bad += 1
for ra, rb in zip(a, b):
    if ra != rb:
        bad += 1
        keys = [k for k in sorted(set(ra) | set(rb)) if ra.get(k) != rb.get(k)]
        if bad <= 5:
            print(f"seed {ra.get('seed')}: differs in {keys}")
            for k in keys[:3]:
                print("   godot:", json.dumps(ra.get(k), ensure_ascii=False)[:300])
                print("   go:   ", json.dumps(rb.get(k), ensure_ascii=False)[:300])
print(f"{sys.argv[1]}: {len(a)} rows, mismatches = {bad}")
sys.exit(1 if bad else 0)
