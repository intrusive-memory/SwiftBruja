#!/usr/bin/env python3
"""Build the nine Personaje prompt fixtures from a Highland (.highland) script.

Usage: python3 build-fixtures.py <path-to.highland>

Writes NN-<CHARACTER>-<major|minor>.txt next to this script. Standard library
only; output is deterministic.

Context rules (Personaje REQUIREMENTS-APP-UI.md 11.3):
  major: every scene the character speaks in, complete.
  minor: each line of the character with the 3 elements before and after it,
         clipped to the scene and merged where the windows overlap.
An element is one dialogue block, narrator block or action paragraph, each
labelled with its speaker.
"""
import re
import sys
import zipfile
from collections import Counter
from pathlib import Path

MAJORS = ["HUNTER", "SHANE", "ARCHER", "CLARK", "KEVIN"]
MINORS = ["TOBY", "IOLA"]
EXTRA_MINORS = 2
WINDOW = 3

INSTRUCTIONS = """You are extracting a character profile from excerpts of a screenplay.
The character to profile is named on the line after the marker below.
Read the excerpts below and return one JSON object and nothing else. The
object has exactly these fields, in this order:
age, pronouns, occupation, languages, logline, sampleLine, appearance,
wardrobe, personality, backstory, arc, relationships, voiceAndSpeech,
canonFacts.
relationships is a list of objects with the fields with and nature.
canonFacts is a list of objects with the fields fact and quote.
Every field can be null. A field the excerpts say nothing about must be
null. Do not guess or invent. Use the JSON value null, never the text "null".
sampleLine must be one of the character's own lines, word for word. A quote
in canonFacts must appear word for word in the excerpts.
Return the JSON object only, with no text before or after it.
"""
MARKER = "=== EXCERPTS ==="

HEADING = re.compile(r"^\.?(INT|EXT|EST|INT\./EXT|I/E)[. ]", re.I)
FORCED = re.compile(r"^\.[A-Za-z]")
CUE = re.compile(r"^[A-Z][A-Z0-9 .'\-#&]*(\s*\([^)]*\))*\s*\^?$")


def read_fountain(path):
    with zipfile.ZipFile(path) as z:
        names = sorted(n for n in z.namelist() if n.endswith("/text.md") or n.endswith(".fountain"))
        if not names:
            sys.exit("no text.md or .fountain inside " + path)
        return z.read(names[0]).decode("utf-8")


def speaker_of(cue):
    name = re.sub(r"\([^)]*\)", "", cue).replace("^", "").strip()
    return name


def parse(text):
    """Return a list of scenes; each scene is {heading, elements:[(speaker, text)]}.
    speaker is a character name, or 'ACTION' for action paragraphs."""
    text = text.replace("\r\n", "\n")
    # Drop inline production notes such as [[ <breath/> ]] (block-level notes are skipped below).
    text = re.sub(r"[ \t]*\[\[[^\]\n]*\]\](?=[^\n])", "", text)
    blocks = re.split(r"\n[ \t]*\n", text)
    scenes = []
    cur = None
    for raw in blocks:
        lines = [l.rstrip() for l in raw.strip("\n").split("\n")]
        lines = [l for l in lines if l.strip()]
        if not lines:
            continue
        first = lines[0].strip()
        # Skip title page (key: lines) until the first page break/heading.
        if first.startswith("![") or first == "===" or first.startswith("[[") or first.startswith(">"):
            if first == "===" or first.startswith("!["):
                cur = None if first == "===" else cur
            continue
        if HEADING.match(first) or FORCED.match(first) and first.upper() == first:
            title = first.lstrip(".")
            cur = {"heading": title, "elements": []}
            scenes.append(cur)
            rest = lines[1:]
            if rest:
                cur["elements"].append(("ACTION", "\n".join(rest)))
            continue
        if cur is None:
            continue
        if first.startswith("[["):
            continue
        if len(lines) >= 2 and CUE.match(first) and not first.startswith("."):
            cur["elements"].append((speaker_of(first), "\n".join(l.strip() for l in lines[1:])))
        else:
            cur["elements"].append(("ACTION", "\n".join(lines)))
    return [s for s in scenes if s["elements"]]


def fmt(el):
    spk, txt = el
    return "[%s]\n%s" % (spk, txt)


def fmt_scene_header(s):
    return "SCENE: " + s["heading"]


def major_excerpt(scenes, name):
    out = []
    for s in scenes:
        if any(sp == name for sp, _ in s["elements"]):
            out.append(fmt_scene_header(s) + "\n\n" + "\n\n".join(fmt(e) for e in s["elements"]))
    return "\n\n---\n\n".join(out)


def minor_excerpt(scenes, name):
    out = []
    for s in scenes:
        els = s["elements"]
        idx = [i for i, (sp, _) in enumerate(els) if sp == name]
        if not idx:
            continue
        spans = []
        for i in idx:
            lo, hi = max(0, i - WINDOW), min(len(els) - 1, i + WINDOW)
            if spans and lo <= spans[-1][1] + 1:
                spans[-1][1] = max(spans[-1][1], hi)
            else:
                spans.append([lo, hi])
        for lo, hi in spans:
            out.append(fmt_scene_header(s) + "\n\n" + "\n\n".join(fmt(e) for e in els[lo:hi + 1]))
    return "\n\n---\n\n".join(out)


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: build-fixtures.py <path-to.highland>")
    scenes = parse(read_fountain(sys.argv[1]))
    counts = Counter(sp for s in scenes for sp, _ in s["elements"] if sp != "ACTION" and sp != "NARRATOR")
    taken = set(MAJORS + MINORS)
    extras = sorted(((c, n) for n, c in counts.items() if n not in taken), key=lambda x: (-x[0], x[1]))[:EXTRA_MINORS]
    minors = MINORS + [n for _, n in extras]
    plan = [(n, "major") for n in MAJORS] + [(n, "minor") for n in minors]
    out_dir = Path(__file__).resolve().parent
    for i, (name, tier) in enumerate(plan, 1):
        if counts[name] == 0:
            sys.exit("character %s has no dialogue" % name)
        ex = major_excerpt(scenes, name) if tier == "major" else minor_excerpt(scenes, name)
        content = INSTRUCTIONS + MARKER + "\nCHARACTER: " + name + "\n\n" + ex + "\n"
        (out_dir / ("%02d-%s-%s.txt" % (i, name, tier))).write_text(content, encoding="utf-8")
        print("%02d %-8s %-5s %3d dialogue blocks %7d bytes" % (i, name, tier, counts[name], len(content.encode())))


if __name__ == "__main__":
    main()
