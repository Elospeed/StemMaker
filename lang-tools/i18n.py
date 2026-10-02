#!/usr/bin/env python3
"""
StemMaker (Elospeed) - Sprachdateien erzeugen

Sucht im Quellcode alle Texte, die übersetzt werden:
  - in .pas/.lpr:  _('...')   (auch 'Teil 1' + 'Teil 2' und #228-Zeichen)
  - in .lfm:       Caption / Hint / TextHint / Items.Strings

und schreibt:
  lang/StemMaker.pot   Vorlage mit allen deutschen Texten (für neue Sprachen)
  lang/<code>.po       je Sprache, aus lang-tools/<code>.json (Deutsch -> Übersetzung)

Aufruf:  python3 i18n.py <src-ordner> <lang-ordner>
Fehlende Übersetzungen werden aufgelistet.
"""
import json, os, re, sys, glob

def parse_pascal_expr(s, i, stop_chars):
    """Liest eine Kette von Pascal-Literalen ab Position i:  'abc' + 'd''e' #228 ...
    Gibt (text, neue_position, ok) zurück. ok=False wenn etwas anderes als
    ein Literal vorkommt (z.B. eine Variable)."""
    out = []
    n = len(s)
    while i < n:
        c = s[i]
        if c in ' \t\r\n+':
            i += 1
        elif c == "'":
            i += 1
            buf = []
            while i < n:
                if s[i] == "'":
                    if i + 1 < n and s[i + 1] == "'":
                        buf.append("'"); i += 2
                    else:
                        i += 1; break
                else:
                    buf.append(s[i]); i += 1
            out.append(''.join(buf))
        elif c == '#':
            m = re.match(r'#(\d+)', s[i:])
            if not m:
                return None, i, False
            out.append(chr(int(m.group(1))))
            i += len(m.group(0))
        elif c in stop_chars:
            return ''.join(out), i, True
        else:
            return None, i, False
    return ''.join(out), i, True

def extract_pas(path, found, errors):
    src = open(path, encoding='utf-8').read()
    # Kommentare { ... } und // ... entfernen, aber Strings in Ruhe lassen
    clean = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "'":
            j = i + 1
            while j < n:
                if src[j] == "'":
                    if j + 1 < n and src[j + 1] == "'":
                        j += 2; continue
                    break
                j += 1
            clean.append(src[i:j + 1]); i = j + 1
        elif c == '{':
            j = src.find('}', i)
            j = n if j < 0 else j
            clean.append(' ' * (j - i + 1) if '\n' not in src[i:j+1] else re.sub(r'[^\n]', ' ', src[i:j+1]))
            i = j + 1
        elif src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            clean.append(' ' * (j - i)); i = j
        else:
            clean.append(c); i += 1
    text = ''.join(clean)
    for m in re.finditer(r'(?<![A-Za-z0-9_])_\(', text):
        val, end, ok = parse_pascal_expr(text, m.end(), ')')
        line = text.count('\n', 0, m.start()) + 1
        if not ok:
            errors.append(f'{os.path.basename(path)}:{line}: _() enthält nicht nur Text-Literale')
            continue
        if val:
            found.setdefault(val, []).append(f'{os.path.basename(path)}:{line}')

LFM_PROPS = ('Caption', 'Hint', 'TextHint', 'DialogTitle')

def extract_lfm(path, found, errors):
    src = open(path, encoding='utf-8').read()
    lines = src.split('\n')
    i = 0
    while i < len(lines):
        ln = lines[i].strip()
        m = re.match(r'(\w+)\s*=\s*(.*)$', ln)
        if m and m.group(1) in LFM_PROPS:
            expr = m.group(2)
            # mehrzeilig: Zeile endet mit '+'
            while expr.rstrip().endswith('+') and i + 1 < len(lines):
                i += 1; expr += lines[i].strip()
            val, _, ok = parse_pascal_expr(expr + '\x00', 0, '\x00')
            if ok and val:
                found.setdefault(val, []).append(f'{os.path.basename(path)}:{i+1}')
        elif ln.startswith('Items.Strings = (') or ln == 'Items.Strings = (':
            i += 1
            while i < len(lines) and not lines[i].strip().startswith(')'):
                part = lines[i].strip()
                if part.endswith(')'):
                    part = part[:-1]
                val, _, ok = parse_pascal_expr(part + '\x00', 0, '\x00')
                if ok and val:
                    found.setdefault(val, []).append(f'{os.path.basename(path)}:{i+1}')
                if lines[i].strip().endswith(')'):
                    break
                i += 1
        i += 1

def po_escape(s):
    s = s.replace('\\', '\\\\').replace('"', '\\"').replace('\t', '\\t')
    s = s.replace('\r\n', '\\n').replace('\n', '\\n')
    return '"' + s + '"'

HEADER = '''msgid ""
msgstr ""
"Content-Type: text/plain; charset=UTF-8\\n"
"Language: {lang}\\n"
"X-Source-Language: de\\n"
"Project-Id-Version: Elospeed StemMaker\\n"

'''

def main():
    src_dir, lang_dir = sys.argv[1], sys.argv[2]
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    found, errors = {}, []
    for p in sorted(glob.glob(os.path.join(src_dir, '*.pas')) + glob.glob(os.path.join(src_dir, '*.lpr'))):
        if os.path.basename(p) in ('ulang.pas', 'ulangui.pas'):
            continue                      # dort steht _() selbst bzw. dynamische Aufrufe
        extract_pas(p, found, errors)
    for p in sorted(glob.glob(os.path.join(src_dir, '*.lfm'))):
        extract_lfm(p, found, errors)
    os.makedirs(lang_dir, exist_ok=True)
    keys = sorted(found)
    with open(os.path.join(lang_dir, 'StemMaker.pot'), 'w', encoding='utf-8') as f:
        f.write(HEADER.format(lang=''))
        for k in keys:
            f.write('#: ' + ' '.join(found[k][:3]) + '\n')
            f.write('msgid ' + po_escape(k) + '\nmsgstr ""\n\n')
    for jf in sorted(glob.glob(os.path.join(tools_dir, '*.json'))):
        code = os.path.splitext(os.path.basename(jf))[0]
        tr = json.load(open(jf, encoding='utf-8'))
        missing = [k for k in keys if not tr.get(k)]
        unused = [k for k in tr if k not in found]
        with open(os.path.join(lang_dir, code + '.po'), 'w', encoding='utf-8') as f:
            f.write(HEADER.format(lang=code))
            for k in keys:
                f.write('#: ' + ' '.join(found[k][:3]) + '\n')
                f.write('msgid ' + po_escape(k) + '\nmsgstr ' + po_escape(tr.get(k, '')) + '\n\n')
        print(f'{code}.po: {len(keys) - len(missing)}/{len(keys)} übersetzt, {len(unused)} unbenutzt')
        for k in missing:
            print('  FEHLT:', repr(k), found[k][0])
    print(f'StemMaker.pot: {len(keys)} Texte')
    for e in errors:
        print('FEHLER:', e)

if __name__ == '__main__':
    main()
