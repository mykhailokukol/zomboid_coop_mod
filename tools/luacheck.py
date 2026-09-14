import re, sys

KW_OPEN = {"function", "if", "for", "while", "do"}   # do handled separately
def tokens(src):
    i, n = 0, len(src)
    line = 1
    while i < n:
        c = src[i]
        if c == "\n":
            line += 1; i += 1; continue
        if src.startswith("--[[", i):
            j = src.find("]]", i)
            j = n if j < 0 else j + 2
            line += src.count("\n", i, j); i = j; continue
        if src.startswith("--", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("[[", i):
            j = src.find("]]", i)
            if j < 0: raise SyntaxError(f"unterminated long string at line {line}")
            line += src.count("\n", i, j); i = j + 2; continue
        if c in "\"'":
            j = i + 1
            while j < n:
                if src[j] == "\\": j += 2; continue
                if src[j] == c: break
                if src[j] == "\n": raise SyntaxError(f"unterminated string at line {line}")
                j += 1
            if j >= n: raise SyntaxError(f"unterminated string at line {line}")
            i = j + 1; continue
        m = re.match(r"[A-Za-z_][A-Za-z0-9_]*", src[i:])
        if m:
            yield m.group(0), line
            i += m.end(); continue
        if c in "()[]{}":
            yield c, line
            i += 1; continue
        i += 1

def check(path):
    src = open(path, encoding="utf-8").read()
    stack = []
    pairs = {")": "(", "]": "[", "}": "{"}
    prev = None
    for tok, line in tokens(src):
        if tok in ("function", "if", "while", "for"):
            if tok in ("while", "for"):
                stack.append((tok, line))     # its `do` is consumed below
            else:
                stack.append((tok, line))
        elif tok == "do":
            if stack and stack[-1][0] in ("while", "for"):
                pass                          # part of the loop header
            else:
                stack.append(("do", line))
        elif tok == "repeat":
            stack.append(("repeat", line))
        elif tok == "until":
            if not stack or stack[-1][0] != "repeat":
                return f"{path}: unexpected 'until' at line {line}"
            stack.pop()
        elif tok == "end":
            if not stack:
                return f"{path}: unexpected 'end' at line {line}"
            top = stack.pop()
            if top[0] in "([{":
                return f"{path}: 'end' at line {line} closes bracket from line {top[1]}"
        elif tok in "([{":
            stack.append((tok, line))
        elif tok in pairs:
            if not stack or stack[-1][0] != pairs[tok]:
                opened = stack[-1] if stack else ("nothing", "?")
                return f"{path}: '{tok}' at line {line} does not match {opened[0]} from line {opened[1]}"
            stack.pop()
        prev = tok
    if stack:
        kind, line = stack[-1]
        return f"{path}: unclosed '{kind}' opened at line {line}"
    return None

bad = False
for p in sys.argv[1:]:
    try:
        err = check(p)
    except SyntaxError as e:
        err = f"{p}: {e}"
    if err:
        bad = True
        print("FAIL", err)
    else:
        print("ok  ", p)
sys.exit(1 if bad else 0)
