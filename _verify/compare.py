#!/usr/bin/env python3
"""Bandingkan dua dump (JS asli vs port C#) secara NUMERIK.

Kenapa bukan `diff` biasa: nilai dicetak dengan 9 desimal, jadi angka
yang tepat jatuh di tengah (mis. -0.5556640625) bisa dibulatkan berbeda
oleh toFixed JS dan ToString .NET meski double-nya IDENTIK. diff biasa
melaporkan itu sebagai selisih; pembanding ini tidak.

Sebaliknya pembanding ini JAUH lebih ketat dari diff untuk kasus nyata:
ia melaporkan selisih sekecil apa pun di atas TOL dan menyebut selisih
maksimum yang terlihat, jadi pergeseran halus tidak bisa sembunyi.
"""
import re, sys

TOL = 1e-9

def tokens(value):
    return re.split(r'[,|:()]', value)

def load(path):
    d, order = {}, []
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if not line:
            continue
        k, _, v = line.partition('=')
        d[k] = v
        order.append(k)
    return d, order

def is_num(t):
    try:
        float(t)
        return True
    except ValueError:
        return False

def main():
    js, order_js = load(sys.argv[1])
    cs, order_cs = load(sys.argv[2])

    problems, max_delta, max_key, numeric = [], 0.0, '', 0

    if order_js != order_cs:
        problems.append(f"URUTAN/KUNCI BEDA: {len(order_js)} vs {len(order_cs)} baris")
        only_js = [k for k in order_js if k not in cs][:5]
        only_cs = [k for k in order_cs if k not in js][:5]
        if only_js: problems.append(f"hanya di JS : {only_js}")
        if only_cs: problems.append(f"hanya di C# : {only_cs}")

    for k in order_js:
        if k not in cs:
            continue
        a, b = js[k], cs[k]
        ta, tb = tokens(a), tokens(b)
        if len(ta) != len(tb):
            problems.append(f"{k}: jumlah token beda\n      JS = {a}\n      C# = {b}")
            continue
        for x, y in zip(ta, tb):
            x, y = x.strip(), y.strip()
            if is_num(x) and is_num(y):
                numeric += 1
                delta = abs(float(x) - float(y))
                if delta > max_delta:
                    max_delta, max_key = delta, k
                if delta > TOL:
                    problems.append(f"{k}: selisih {delta:g}\n      JS = {a}\n      C# = {b}")
                    break
            elif x != y:
                problems.append(f"{k}: token bukan-angka beda\n      JS = {a}\n      C# = {b}")
                break

    print(f"baris dibandingkan      : {len(order_js)}")
    print(f"nilai numerik dibanding : {numeric}")
    print(f"toleransi               : {TOL:g}")
    print(f"selisih maksimum        : {max_delta:g}  ({max_key or '-'})")
    print()
    if problems:
        print(f"TIDAK SETARA - {len(problems)} masalah:")
        for p in problems[:25]:
            print("  - " + p)
        sys.exit(1)
    print("SETARA - port C# menghasilkan angka identik dengan JS asli")

main()
