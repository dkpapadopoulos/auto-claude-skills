import sys, re, difflib
a = open(sys.argv[1]).read(); b = open(sys.argv[2]).read()
def lev(x, y):
    prev = list(range(len(y)+1))
    for i, cx in enumerate(x, 1):
        cur = [i]
        for j, cy in enumerate(y, 1):
            cur.append(min(prev[j]+1, cur[j-1]+1, prev[j-1]+(cx != cy)))
        prev = cur
    return prev[-1]
wa, wb = a.split(), b.split()
d = lev(wa, wb)
print(f"word-edit-distance={d} norm={d/max(len(wa),len(wb)):.3f} words_before={len(wa)} words_after={len(wb)}")
nums_a = set(re.findall(r'\b\d+\b', a)); nums_b = set(re.findall(r'\b\d+\b', b))
print("numbers lost:", sorted(nums_a - nums_b), "numbers added:", sorted(nums_b - nums_a))
