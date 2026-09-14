#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RHVoice UA — localization inventory & checker (Part 2 of KIRO_TASK_i18n_inventory).

WHAT THIS DOES
  1. Re-scans the Swift sources under App/ and Shared/ for user-visible
     Cyrillic string literals and classifies each as:
       A — a SwiftUI literal that iOS localizes itself via LocalizedStringKey
           (a bare "…" literal sitting directly in Text(...), Label(...),
           Button(...), Toggle(...), Picker(...), Section(...),
           .navigationTitle(...), .accessibilityLabel(...),
           .accessibilityHint(...), .accessibilityValue(...), Alert(Text(...)),
           .confirmationDialog(...), Link(...), ProgressView(...), TextField(...),
           .tabItem, .alert title, etc.). iOS will translate these ONLY if a
           matching key exists in Localizable.strings.
       B — an ordinary String value iOS will NOT translate on its own
           (let/var value, array element, struct field, function argument of
           String type, interpolated string later shown). Needs a code change.
       C — a service string that must NOT be translated (UserDefaults keys,
           voice/language identifiers, file names, log/diagnostic tags, text
           sent into the synthesis engine, pronunciation/abbreviation data).
     C literals are NOT part of the translatable set.

  2. Reads the translation file
       UkrainianVoicesApp/App/en.lproj/Localizable.strings
     If it does not exist yet, it says so honestly and exits with code 1.

  3. Prints how many A+B literals were found, how many have a translation,
     and the full list of the ones with no translation.

  4. Exit code 0 only if every A+B literal has a translation.

RUN:
  PYTHONDONTWRITEBYTECODE=1 python3 scripts/i18n/check_localization.py

NOTE ON METHOD
  Swift has no stable, dependency-free AST parser in the stdlib, so this uses a
  line/character scanner that:
    * strips // line comments and /* */ block comments,
    * tolerates string interpolation "\\(...)" inside a literal,
    * records, for every double-quoted literal that contains a Cyrillic letter,
      the immediately-preceding non-space token/callsite,
  then applies the A/B/C rules by that callsite plus a fixed allow/deny list of
  known service literals. It is intentionally conservative: anything it cannot
  confidently place in A goes to B (needs a code change) unless it matches a
  service pattern (C). This mirrors the inventory in the report.
"""

import os
import re
import sys

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
APP_DIR = os.path.join(REPO_ROOT, "UkrainianVoicesApp", "App")
SHARED_DIR = os.path.join(REPO_ROOT, "UkrainianVoicesApp", "Shared")
STRINGS_FILE = os.path.join(
    REPO_ROOT, "UkrainianVoicesApp", "App", "en.lproj", "Localizable.strings"
)

CYRILLIC_RE = re.compile(r"[А-Яа-яЁёІіЇїЄєҐґ’]")
HAS_CYRILLIC_LETTER = re.compile(r"[А-Яа-яЁёІіЇїЄєҐґ]")

# SwiftUI callsites whose FIRST string parameter is a LocalizedStringKey and
# therefore localized by iOS automatically (class A) when a matching key exists.
A_CALL_PREFIXES = (
    "Text(",
    "Label(",
    "Button(",
    "Toggle(",
    "Picker(",
    "Section(",
    "Link(",
    "ProgressView(",
    "TextField(",
    "SecureField(",
    "Alert(",
    "Stepper(",
    "Menu(",
    "NavigationLink(",
)

# View-modifier callsites whose first string parameter is a LocalizedStringKey.
A_MODIFIER_SUFFIXES = (
    ".navigationTitle(",
    ".accessibilityLabel(",
    ".accessibilityHint(",
    ".accessibilityValue(",
    ".tabItem(",
    ".help(",
    ".confirmationDialog(",
    ".alert(",
    ".navigationBarTitle(",
    ".searchable(",
)

# Named-argument prefixes that also take a LocalizedStringKey (class A) when the
# literal is the value: prompt:, title:, titleKey:, label:, message: on Text.
A_NAMED_ARG_PREFIXES = (
    "prompt:",
    "titleKey:",
    "named:",  # .accessibilityAction(named: "…") { } — LocalizedStringKey
)


def strip_comments(text):
    """Return text with // and /* */ comments blanked (kept length/newlines) so
    line numbers stay correct and no literal inside a comment is scanned."""
    out = []
    i = 0
    n = len(text)
    in_line = False
    in_block = False
    in_str = False
    escape = False
    while i < n:
        c = text[i]
        two = text[i : i + 2]
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            else:
                out.append(" ")
            i += 1
            continue
        if in_block:
            if two == "*/":
                out.append("  ")
                i += 2
                in_block = False
                continue
            out.append("\n" if c == "\n" else " ")
            i += 1
            continue
        if in_str:
            out.append(c)
            if escape:
                escape = False
            elif c == "\\":
                escape = True
            elif c == '"':
                in_str = False
            i += 1
            continue
        # not in comment or string
        if two == "//":
            in_line = True
            out.append("  ")
            i += 2
            continue
        if two == "/*":
            in_block = True
            out.append("  ")
            i += 2
            continue
        if c == '"':
            in_str = True
            out.append(c)
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def swift_multiline_body(body):
    """Apply Swift's rules for a \"\"\" literal so the KEY matches at runtime.

    Swift drops the newline right after the opening delimiter, the newline
    before the closing delimiter, and the closing delimiter's indentation from
    every line. Without this the generated key carries the source indentation,
    never matches the key the app asks for, and the text silently stays
    Ukrainian on an English system.
    """
    if body.startswith("\r\n"):
        body = body[2:]
    elif body.startswith("\n"):
        body = body[1:]
    idx = body.rfind("\n")
    if idx == -1:
        return body
    indent = body[idx + 1:]
    if indent.strip():
        return body
    lines = body[:idx].split("\n")
    out = [ln[len(indent):] if ln.startswith(indent) else ln.lstrip() for ln in lines]
    return "\n".join(out)


def find_literals(text):
    """Yield (start_index, raw_literal_text) for every double-quoted string
    literal (single-line and triple-quoted), tolerating \\( ) interpolation and
    escaped quotes. Returns the literal body without the surrounding quotes."""
    results = []
    i = 0
    n = len(text)
    while i < n:
        # triple-quoted string
        if text[i : i + 3] == '"""':
            start = i
            i += 3
            body_start = i
            while i < n and text[i : i + 3] != '"""':
                i += 1
            body = swift_multiline_body(text[body_start:i])
            results.append((start, body))
            i += 3
            continue
        if text[i] == '"':
            start = i
            i += 1
            body_chars = []
            escape = False
            depth = 0  # interpolation paren depth
            while i < n:
                c = text[i]
                if escape:
                    body_chars.append(c)
                    escape = False
                    i += 1
                    continue
                if c == "\\":
                    # interpolation \( ... )
                    if text[i : i + 2] == "\\(":
                        depth = 1
                        body_chars.append("\\(")
                        i += 2
                        while i < n and depth > 0:
                            cc = text[i]
                            if cc == "(":
                                depth += 1
                            elif cc == ")":
                                depth -= 1
                            body_chars.append(cc)
                            i += 1
                        continue
                    escape = True
                    body_chars.append(c)
                    i += 1
                    continue
                if c == '"':
                    i += 1
                    break
                if c == "\n":
                    # unterminated on this line; stop
                    break
                body_chars.append(c)
                i += 1
            results.append((start, "".join(body_chars)))
            continue
        i += 1
    return results


def preceding_context(text, start, width=80):
    """Return the code immediately before the literal (single logical prefix),
    collapsed whitespace, for callsite classification."""
    lo = max(0, start - width)
    prefix = text[lo:start]
    # collapse whitespace/newlines
    prefix = re.sub(r"\s+", "", prefix)
    return prefix


# ---- Service (class C) detection ---------------------------------------------

# File-level: these files contain speech-engine / pronunciation data, not UI.
C_DATA_FILES = {
    "RHVoiceApostropheNormalizer.swift",
    "RHVoiceTextBreaks.swift",       # VoiceOver role-word match table
    "RHVoicePipelineSplitter.swift", # SSML/engine
    # DEBUG-only self-test: every Cyrillic literal is a phrase fed to
    # engine.synthesize(...) or a synthesis proof phrase — engine input, not UI.
    "RHVoiceSelfTestRunner.swift",
}


def enclosing_call_token(text, lit_start):
    """Walk backwards from a literal to find the identifier of the call/modifier
    whose parentheses directly enclose it, stepping over balanced (), [], {} and
    over string literals. Returns the collapsed token immediately before the
    enclosing '(' (e.g. 'Text', '.accessibilityLabel', 'Section'), or '' if the
    literal is not inside a paren call (e.g. it is an array/dict/assignment)."""
    i = lit_start - 1
    depth = 0
    while i >= 0:
        c = text[i]
        if c in ")]}":
            depth += 1
            i -= 1
            continue
        if c == "(":
            if depth == 0:
                # found the enclosing '(' — read the token before it
                j = i - 1
                while j >= 0 and text[j].isspace():
                    j -= 1
                end = j + 1
                while j >= 0 and (text[j].isalnum() or text[j] in "._"):
                    j -= 1
                return text[j + 1 : end]
            depth -= 1
            i -= 1
            continue
        if c in "[{":
            if depth == 0:
                # literal is inside an array/dict/closure, not a call arg list
                return ""
            depth -= 1
            i -= 1
            continue
        i -= 1
    return ""


def named_arg_before(text, lit_start):
    """Return the 'name:' immediately preceding the literal at the same paren
    level (collapsed), or '' if none. Used for prompt:/named:/titleKey:."""
    j = lit_start - 1
    while j >= 0 and text[j].isspace():
        j -= 1
    end = j + 1
    # a named arg looks like  identifier :
    if j >= 0 and text[j] == ":":
        k = j - 1
        while k >= 0 and text[k].isspace():
            k -= 1
        e2 = k + 1
        while k >= 0 and (text[k].isalnum() or text[k] == "_"):
            k -= 1
        name = text[k + 1 : e2]
        if name:
            return name + ":"
    return ""


def current_arg_expr(text, lit_start):
    """Return the source of the current call argument: from the nearest
    preceding ',' or '(' at the SAME paren level up to the literal start.
    Used to detect sibling expressions (?? , .map) that make the whole argument
    a runtime String rather than a LocalizedStringKey literal."""
    i = lit_start - 1
    depth = 0
    while i >= 0:
        c = text[i]
        if c in ")]}":
            depth += 1
        elif c in "([{":
            if depth == 0:
                return text[i + 1 : lit_start]
            depth -= 1
        elif c == "," and depth == 0:
            return text[i + 1 : lit_start]
        i -= 1
    return text[:lit_start]


def looks_like_service_literal(body, prefix, filename, named_arg):
    """Heuristic C rules. Applied only to Cyrillic-bearing literals."""
    # A phrase assigned as engine sample text / test text (spoken by the engine).
    if named_arg == "sampleText:":
        return True
    if prefix.endswith("sampleText=") or prefix.endswith("sampleText:"):
        return True
    if prefix.endswith("testText=") or prefix.endswith("self.testText="):
        return True
    # Canonical built-in voice sample phrases fed to engine.synthesize.
    if body.startswith("Привіт! Це тест"):
        return True
    return False


def classify(body, prefix, filename, enclosing, named_arg, arg_expr):
    """Return 'A', 'B' or 'C' for a Cyrillic-bearing literal.

    enclosing : identifier of the call whose () directly wrap the literal.
    named_arg : 'name:' token right before the literal, if any.
    """
    # Files that are pure engine/pronunciation data.
    if filename in C_DATA_FILES:
        return "C"

    # Engine sample text anywhere.
    if looks_like_service_literal(body, prefix, filename, named_arg):
        return "C"

    # Pronunciation/abbreviation DATA and file-format text (never UI):
    #   AbbreviationDictionary.bundledEntries: entry("пн", "понеділок") ...
    #   exported-file header lines starting with '#', and file names.
    if enclosing == "entry":
        return "C"
    if body.lstrip().startswith("#"):
        return "C"
    # A bare file-name literal (no spaces), e.g. "rhvoice-скорочення-\(date).txt".
    if (".txt" in body or ".json" in body) and " " not in body:
        return "C"

    # String interpolation \(...) produces a Swift String at runtime; SwiftUI
    # shows a String VERBATIM and never localizes it, even in a LocalizedStringKey
    # position. So any interpolated literal needs a code change → B.
    if "\\(" in body:
        return "B"

    # Class A: the literal sits (possibly through a `? :` ternary) directly
    # inside a SwiftUI call/modifier whose first parameter is a LocalizedStringKey.
    enc = enclosing
    # normalize: enclosing may be 'Text', 'Section', or a modifier like
    # 'accessibilityLabel' (dot already stripped by the backward scan) or a full
    # '.accessibilityLabel' depending on the text; test both forms.
    a_calls_bare = tuple(p.rstrip("(") for p in A_CALL_PREFIXES)
    a_mods_bare = tuple(m.lstrip(".").rstrip("(") for m in A_MODIFIER_SUFFIXES)
    if enc in a_calls_bare or enc in a_mods_bare:
        # A LocalizedStringKey parameter localizes a bare literal — UNLESS the
        # argument expression as a whole evaluates to a Swift String (then the
        # StringProtocol overload is chosen and the text is shown verbatim).
        # Detect that: a sibling `.map { ... }` or interpolation in the same
        # argument means the value is a runtime String → needs a code change (B).
        if arg_expr and (".map" in arg_expr or "\\(" in arg_expr):
            return "B"
        return "A"
    # named argument that is a LocalizedStringKey (prompt:, titleKey:, named:)
    if named_arg in A_NAMED_ARG_PREFIXES:
        return "A"

    # Everything else that is user-visible Cyrillic → B (needs code change).
    return "B"


def scan_file(path):
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    filename = os.path.basename(path)
    clean = strip_comments(text)
    # Build a line index for the cleaned text (same offsets as original,
    # because strip_comments preserves length).
    line_starts = [0]
    for idx, ch in enumerate(text):
        if ch == "\n":
            line_starts.append(idx + 1)

    def line_of(offset):
        # binary search
        lo, hi = 0, len(line_starts) - 1
        while lo < hi:
            mid = (lo + hi + 1) // 2
            if line_starts[mid] <= offset:
                lo = mid
            else:
                hi = mid - 1
        return lo + 1

    found = []
    for start, body in find_literals(clean):
        if not HAS_CYRILLIC_LETTER.search(body):
            continue
        prefix = preceding_context(clean, start)
        enclosing = enclosing_call_token(clean, start).lstrip(".").split(".")[-1]
        named = named_arg_before(clean, start)
        arg_expr = current_arg_expr(clean, start)
        cls = classify(body, prefix, filename, enclosing, named, arg_expr)
        found.append(
            {
                "file": os.path.relpath(path, REPO_ROOT),
                "line": line_of(start),
                "text": body,
                "class": cls,
                # Чи проходить літерал через локалізацію в самому коді.
                # Наявність ключа у .strings НІЧОГО не доводить: необгорнений
                # рядок ніколи туди не звернеться (урок критика, 07.09.2026).
                "wrapped": enclosing == "NSLocalizedString"
                or prefix.replace(" ", "").endswith("String(localized:"),
            }
        )
    return found


def collect():
    entries = []
    for base in (APP_DIR, SHARED_DIR):
        for name in sorted(os.listdir(base)):
            if not name.endswith(".swift"):
                continue
            entries.extend(scan_file(os.path.join(base, name)))
    return entries


def unescape_strings_value(text):
    """Unescape a .strings literal: \\n, \\t, \\" and \\\\ .

    The source side of a multi-line Swift literal contains REAL newlines, so the
    key read back from the file must be unescaped the same way iOS does it —
    otherwise long multi-line texts look untranslated when they are not.
    """
    out = []
    i = 0
    while i < len(text):
        ch = text[i]
        if ch == "\\" and i + 1 < len(text):
            nxt = text[i + 1]
            out.append({"n": "\n", "t": "\t", '"': '"', "\\": "\\"}.get(nxt, nxt))
            i += 2
        else:
            out.append(ch)
            i += 1
    return "".join(out)


def parse_strings_file(path):
    """Return set of translated source keys from a .strings file.
    Format: "key" = "value"; . We treat the KEY (left side) as the source text."""
    keys = set()
    with open(path, "r", encoding="utf-8") as f:
        text = f.read()
    # crude but dependency-free: match "..." = "..." ;
    pattern = re.compile(r'"((?:[^"\\]|\\.)*)"\s*=\s*"(?:[^"\\]|\\.)*"\s*;')
    for m in pattern.finditer(text):
        key = unescape_strings_value(m.group(1))
        keys.add(key)
    return keys


INTERP_RE = re.compile(r"\\\(")


def normalize_key(text):
    """Turn a source literal into its Localizable.strings KEY: every Swift
    string interpolation `\\( ... )` is replaced with `%@` (balanced-paren aware).
    A literal already wrapped (containing `%@` and no `\\(`) is returned as-is, so
    the key is stable whether or not the B-string has been wrapped in code yet.
    printf specifiers already present (e.g. `%.1f`, `%@`) are left untouched."""
    out = []
    i = 0
    n = len(text)
    while i < n:
        if text[i : i + 2] == "\\(":
            depth = 1
            i += 2
            while i < n and depth > 0:
                if text[i] == "(":
                    depth += 1
                elif text[i] == ")":
                    depth -= 1
                i += 1
            out.append("%@")
            continue
        out.append(text[i])
        i += 1
    return "".join(out)


def keys_mode():
    """Print the full list of EXPECTED Localizable.strings keys for the A+B
    translatable set: one normalized key per line (deduplicated, sorted)."""
    entries = collect()
    keys = set()
    for e in entries:
        if e["class"] in ("A", "B"):
            keys.add(normalize_key(e["text"]))
    for k in sorted(keys):
        print(k.replace("\n", "\\n"))
    return 0


def dump():
    """Print every literal as a tab-separated row: class, file, line, text.
    Same collection/classification code path as the check, so counts match."""
    entries = collect()
    entries.sort(key=lambda e: (e["file"], e["line"]))
    for e in entries:
        # keep text on one physical line for the table
        one_line = e["text"].replace("\n", "\\n").replace("\t", " ")
        print("%s\t%s\t%d\t%s" % (e["class"], e["file"], e["line"], one_line))
    return 0


# Рядки, які МАЮТЬ лишатися сирими: це не текст для очей, а тотожність.
# Перекладаються лише в МІСЦІ ПОКАЗУ (див. scripts/i18n/CONVENTION.md, §3).
# Формат: (кінець шляху файлу, точний текст, причина).
INTENTIONALLY_RAW = [
    ("App/ContentView.swift", "Українська", "порівнюється у preferredLanguageOrder — сортування груп голосів"),
    ("App/ContentView.swift", "Англійська", "те саме"),
    # 14.09.2026: імена англійських голосів переведено на ЛАТИНИЦЮ (Ben/Clara/
    # Sarah/Raj) — у роторі ім'я озвучує сам англійський голос, а кирилиці він
    # не читає. Кирилічних літералів тут більше немає; записи лишені як мітка,
    # щоб повернення кирилиці в цей файл одразу впало в око на рев'ю.
    ("Shared/RHVoiceRequestCapture.swift", "перевірка з застосунку", "діагностичні дані в App Group, не інтерфейс"),
    ("Shared/RHVoiceRequestCapture.swift", "не вдалося закодувати запис", "те саме"),
]


def is_intentionally_raw(entry):
    for suffix, text, _reason in INTENTIONALLY_RAW:
        if entry["file"].endswith(suffix) and entry["text"] == text:
            return True
    return False


def main():
    if "--dump" in sys.argv:
        return dump()
    if "--keys" in sys.argv:
        return keys_mode()
    entries = collect()
    translatable = [e for e in entries if e["class"] in ("A", "B")]
    a_count = sum(1 for e in entries if e["class"] == "A")
    b_count = sum(1 for e in entries if e["class"] == "B")
    c_count = sum(1 for e in entries if e["class"] == "C")

    print("RHVoice UA localization check")
    print("=============================")
    print("Total Cyrillic literals found: %d" % len(entries))
    print("  class A (iOS localizes via LocalizedStringKey): %d" % a_count)
    print("  class B (needs code change):                    %d" % b_count)
    print("  class C (service, must NOT translate):          %d" % c_count)
    print("Translatable set (A + B): %d" % len(translatable))
    print()

    if not os.path.exists(STRINGS_FILE):
        print("Translation file NOT found:")
        print("  %s" % os.path.relpath(STRINGS_FILE, REPO_ROOT))
        print("Nothing is translated yet. Create en.lproj/Localizable.strings")
        print("with one entry per A/B literal above.")
        return 1

    translated_keys = parse_strings_file(STRINGS_FILE)
    print("Translation file: %s" % os.path.relpath(STRINGS_FILE, REPO_ROOT))
    print("  entries in file: %d" % len(translated_keys))

    # Compare on the NORMALIZED key (\( ... ) -> %@) so a B-string matches its
    # Localizable.strings key regardless of whether the source has been wrapped
    # in NSLocalizedString yet.
    missing = [e for e in translatable if normalize_key(e["text"]) not in translated_keys]
    have = len(translatable) - len(missing)
    print("  translatable literals with a translation: %d" % have)
    print("  translatable literals WITHOUT a translation: %d" % len(missing))
    print()

    if missing:
        print("Untranslated (needs a key in Localizable.strings):")
        for e in missing:
            print("  [%s] %s:%d  %r" % (e["class"], e["file"], e["line"], normalize_key(e["text"])))
        return 1

    print("All A/B literals have a translation.")

    # Друга перевірка: ключ у файлі є, але сам рядок у коді не обгорнений —
    # тоді переклад ніколи не спрацює. Перша версія скрипта цього не бачила.
    unwrapped = [e for e in entries if e["class"] == "B" and not e.get("wrapped")
                 and not is_intentionally_raw(e)]
    print()
    print("  class B literals NOT wrapped in code: %d" % len(unwrapped))
    if unwrapped:
        print()
        print("Not wrapped (translation will never be used):")
        for e in unwrapped:
            print("  %s:%d  %r" % (e["file"], e["line"], e["text"][:70]))
        return 1

    print()
    print("ЗАСТЕРЕЖЕННЯ: скрипт бачить лише ЛІТЕРАЛИ. Українську у ЗМІННІЙ,")
    print("поданій у формат чи в Text(...), він не помітить — так пройшли")
    print("дефекти з іменами голосів і назвою мови. Його «зелено» не є доказом.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
