#!/usr/bin/env python3
"""Assemble cefr_core wordbook: CEFR-J A1/A2/B1 + open Chinese glosses.

Sources (see assets/wordbooks/ATTRIBUTION.md):
  - CEFR-J Vocabulary Profile 1.5 via openlanguageprofiles/olp-en-cefrj
  - ECDICT (MIT) primary glosses
  - LinXueyuanStdio/DictionaryData word_translation.csv (Apache-2.0) fallback
"""

from __future__ import annotations

import csv
import json
import re
import hashlib
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VENDOR = Path(__file__).resolve().parent / "vendor"
OUT_DIR = ROOT / "assets" / "wordbooks"
CEFR_CSV = VENDOR / "cefrj-vocabulary-profile-1.5.csv"
ECDICT_CSV = VENDOR / "ecdict.csv"
DICTDATA_CSV = VENDOR / "word_translation.csv"

KEEP_LEVELS = {"A1", "A2", "B1"}
LEVEL_ORDER = {"A1": 1, "A2": 2, "B1": 3, "B2": 4}

POS_MAP = {
    "noun": "n.",
    "verb": "v.",
    "adjective": "adj.",
    "adverb": "adv.",
    "preposition": "prep.",
    "conjunction": "conj.",
    "determiner": "det.",
    "pronoun": "pron.",
    "interjection": "interj.",
    "numeral": "num.",
    "auxiliary verb": "aux.",
    "modal verb": "modal",
    "article": "art.",
}

# Small curated fills for common multi-word / orthography gaps after both dicts.
# Marked cn_source=curated in meta; keep tiny.
CURATED = {
    "a.m.": "上午",
    "p.m.": "下午",
    "air conditioning": "空调",
    "air force": "空军",
    "alarm clock": "闹钟",
    "all right": "好的；没关系",
    "according to": "根据；按照",
    "because of": "因为；由于",
    "bus station": "汽车站",
    "bus stop": "公交车站",
    "board game": "桌游",
    "bank account": "银行账户",
    "brand-new": "崭新的",
    "capital letter": "大写字母",
    "credit card": "信用卡",
    "department store": "百货商店",
    "dining room": "餐厅",
    "each other": "互相",
    "first name": "名",
    "full stop": "句号",
    "good luck": "好运",
    "high school": "高中",
    "ice cream": "冰淇淋",
    "living room": "客厅",
    "mobile phone": "手机",
    "of course": "当然",
    "post office": "邮局",
    "primary school": "小学",
    "swimming pool": "游泳池",
    "traffic jam": "交通堵塞",
    "washing machine": "洗衣机",
    "web site": "网站",
    "web-site": "网站",
    "website": "网站",
    "aborigine": "原住民",
    "babysit": "照看小孩",
    "backpacker": "背包客",
    "backpacking": "背包旅行",
    "blogger": "博主",
    "brainstorming": "头脑风暴",
    "boiled": "煮熟的",
    "'m": "是（I am 的缩写）",
    "'re": "是（are 的缩写）",
    "'s": "是（is/has 的缩写）",
    "MP3 player": "MP3 播放器",
    "sports center": "体育中心",
    "check-in desk": "值机柜台",
    "eco": "生态的；环保的",
    "pence": "便士（复数）",
}


def normalize_headword(hw: str) -> str:
    """Pick primary orthography from CEFR-J slash/paren variants."""
    s = hw.strip()
    # Drop trailing parenthetical notes: being (be ...)
    s = re.sub(r"\s*\([^)]*\)\s*", " ", s).strip()
    # Prefer first slash alternative
    if "/" in s:
        s = s.split("/")[0].strip()
    # Collapse whitespace
    s = re.sub(r"\s+", " ", s)
    return s


def lemma_keys(en: str) -> list[str]:
    """Candidate lookup keys, most specific first."""
    low = en.strip().lower()
    keys = [low]
    # without trailing punctuation
    keys.append(low.rstrip("."))
    # hyphen / space variants
    keys.append(low.replace("-", " "))
    keys.append(low.replace(" ", "-"))
    keys.append(low.replace("-", ""))
    keys.append(low.replace(" ", ""))
    # American/British -ise/-ize not handled here
    out = []
    seen = set()
    for k in keys:
        k = k.strip()
        if k and k not in seen:
            seen.add(k)
            out.append(k)
    return out


_POS_TAG = re.compile(
    r"^(?:"
    r"n|v|vt|vi|a|adj|adv|prep|conj|pron|art|num|int|interj|aux|modal|abbr|pl|"
    r"pref|suf|det|phrase|web"
    r")\.\s*",
    re.I,
)
_BRACKET = re.compile(r"\[[^\]]*\]")
_PAREN_EN = re.compile(r"\([^)]*[A-Za-z][^)]*\)")


def clean_gloss(raw: str, prefer_pos: str | None = None) -> str:
    """Turn ECDICT/DictionaryData long gloss into a short learner cn."""
    if not raw:
        return ""
    # ECDICT CSV often stores the two-char sequence \n instead of real newlines.
    text = raw.replace("\\n", "\n").replace("\r", "\n")
    text = _BRACKET.sub("", text)

    # Split into sense clauses
    chunks = []
    for block in re.split(r"[\n]", text):
        block = block.strip()
        if not block:
            continue
        for part in re.split(r"[；;]", block):
            part = part.strip()
            if part:
                chunks.append(part)

    def pos_needles(prefer: str | None) -> tuple[str, ...]:
        if not prefer:
            return ()
        p = prefer.lower().strip()
        short = POS_MAP.get(p, p).lower().rstrip(".")
        # CEFR-J odd tags
        if "verb" in p and p not in ("adverb",):
            short = "v"
        if p in ("adjective",):
            short = "adj"
        if p in ("adverb",):
            short = "adv"
        if p in ("noun",):
            short = "n"
        if p in ("determiner", "article"):
            short = "det"
        if p in ("preposition",):
            short = "prep"
        if p in ("pronoun",):
            short = "pron"
        if p in ("conjunction",):
            short = "conj"
        if p in ("interjection",):
            short = "interj"
        aliases = {
            "n": ("n.", "pl.", "noun"),
            "v": ("v.", "vt.", "vi.", "verb"),
            "adj": ("a.", "adj.", "adjective"),
            "adv": ("adv.", "ad.", "adverb"),
            "prep": ("prep.", "preposition"),
            "conj": ("conj.", "conjunction"),
            "pron": ("pron.", "pronoun"),
            "det": ("det.", "art.", "a.", "determiner", "article"),
            "num": ("num.", "numeral"),
            "interj": ("int.", "interj.", "interjection"),
            "aux": ("aux.", "auxiliary"),
            "modal": ("modal", "mod."),
        }
        return aliases.get(short, (short + ".",))

    needles = pos_needles(prefer_pos)
    ranked = []
    for ch in chunks:
        low = ch.lower()
        score = 0
        if needles and any(low.startswith(n) for n in needles):
            score = 2
        elif re.match(
            r"^(?:n|v|vt|vi|a|adj|adv|prep|conj|pron|art|num|int|interj|aux|modal|abbr|pl|pref|suf|det)\.",
            low,
        ):
            score = 0  # other explicit POS — deprioritize when we have a prefer
        else:
            score = 1
        ranked.append((score, ch))
    ranked.sort(key=lambda x: -x[0])
    if needles:
        # Keep only preferred POS chunks when any matched
        preferred = [c for s, c in ranked if s == 2]
        if preferred:
            ranked = [(2, c) for c in preferred]

    pieces = []
    for _, ch in ranked:
        ch = _POS_TAG.sub("", ch)
        ch = _PAREN_EN.sub("", ch)
        # Drop leading leftover latin crumbs
        ch = re.sub(r"^[A-Za-z0-9./'\s\-]+", "", ch) if re.match(r"^[A-Za-z]", ch) else ch
        for part in re.split(r"[,，、/]", ch):
            part = part.strip(" ;；.。:：")
            if not part:
                continue
            if re.fullmatch(r"[A-Za-z0-9\s\-'.]+", part):
                continue
            if not re.search(r"[\u4e00-\u9fff]", part):
                continue
            # Skip obvious abbreviation dumps
            if "振荡" in part or "组织（" in part or "Organization" in part:
                continue
            if len(part) > 20:
                part = part[:20]
            pieces.append(part)
            if len(pieces) >= 3:
                break
        if len(pieces) >= 2:
            break

    seen = set()
    uniq = []
    for p in pieces:
        if p not in seen:
            seen.add(p)
            uniq.append(p)
    return "；".join(uniq[:2])


def load_ecdict() -> dict[str, str]:
    """word.lower() -> raw translation."""
    out: dict[str, str] = {}
    with ECDICT_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            w = (row.get("word") or "").strip().lower()
            t = (row.get("translation") or "").strip()
            if not w or not t or w in out:
                continue
            out[w] = t
    return out


def load_dictdata() -> dict[str, str]:
    out: dict[str, str] = {}
    with DICTDATA_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            w = (row.get("word") or "").strip().lower()
            t = (row.get("translation") or "").strip()
            if not w or not t or w in out:
                continue
            out[w] = t
    return out


def stable_id(en: str, pos: str, level: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", en.lower()).strip("_")
    if not slug:
        slug = "x"
    if len(slug) > 40:
        slug = slug[:40].rstrip("_")
    pos_slug = re.sub(r"[^a-z0-9]+", "", pos.lower())[:8] or "x"
    base = f"cc_{level.lower()}_{slug}_{pos_slug}"
    # Harden uniqueness with short hash of exact en|pos|level
    h = hashlib.sha1(f"{en}|{pos}|{level}".encode()).hexdigest()[:6]
    return f"{base}_{h}"


# Lowercase curated map once
_CURATED_LC = {k.lower(): v for k, v in CURATED.items()}


def lookup_gloss(
    en: str,
    pos: str,
    ecdict: dict[str, str],
    dictdata: dict[str, str],
) -> tuple[str, str]:
    """Return (cn, source). source in ecdict|dictdata|curated|."""
    for key in lemma_keys(en):
        if key in _CURATED_LC:
            return _CURATED_LC[key], "curated"
    for key in lemma_keys(en):
        if key in ecdict:
            cn = clean_gloss(ecdict[key], prefer_pos=pos)
            if cn:
                return cn, "ecdict"
    for key in lemma_keys(en):
        if key in dictdata:
            cn = clean_gloss(dictdata[key], prefer_pos=pos)
            if cn:
                return cn, "dictdata"
    return "", ""


def main() -> None:
    assert CEFR_CSV.exists(), CEFR_CSV
    assert ECDICT_CSV.exists(), ECDICT_CSV
    assert DICTDATA_CSV.exists(), DICTDATA_CSV

    print("Loading ECDICT...")
    ecdict = load_ecdict()
    print(f"  {len(ecdict)} lemmas")
    print("Loading DictionaryData...")
    dictdata = load_dictdata()
    print(f"  {len(dictdata)} lemmas")

    # Collect CEFR rows for A1/A2/B1. Same (en_norm, pos) may appear once.
    # If same en+pos at multiple levels (shouldn't often), keep lowest level.
    best: dict[tuple[str, str], dict] = {}
    raw_rows = 0
    with CEFR_CSV.open(newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            level = (row.get("CEFR") or "").strip().upper()
            if level not in KEEP_LEVELS:
                continue
            hw = (row.get("headword") or "").strip()
            pos = (row.get("pos") or "").strip().lower()
            if not hw:
                continue
            en = normalize_headword(hw)
            if not en:
                continue
            raw_rows += 1
            key = (en.lower(), pos)
            prev = best.get(key)
            if prev is None or LEVEL_ORDER[level] < LEVEL_ORDER[prev["level"]]:
                best[key] = {
                    "en": en,
                    "pos": pos,
                    "level": level,
                    "headword_raw": hw,
                }

    entries = []
    source_counts = Counter()
    level_counts = Counter()
    missing = []

    for (en_l, pos), info in sorted(
        best.items(), key=lambda kv: (LEVEL_ORDER[kv[1]["level"]], kv[1]["en"].lower(), kv[0][1])
    ):
        en = info["en"]
        level = info["level"]
        cn, src = lookup_gloss(en, pos, ecdict, dictdata)
        if not cn:
            missing.append({"en": en, "pos": pos, "level": level, "raw": info["headword_raw"]})
            source_counts["missing"] += 1
            continue
        eid = stable_id(en, pos, level)
        entries.append(
            {
                "id": eid,
                "en": en,
                "cn": cn,
                "pos": pos,
                "level": level.lower(),
                "book_id": "cefr_core",
                "cn_source": src,
            }
        )
        source_counts[src] += 1
        level_counts[level] += 1

    OUT_DIR.mkdir(parents=True, exist_ok=True)

    jsonl_path = OUT_DIR / "cefr_core.jsonl"
    with jsonl_path.open("w", encoding="utf-8") as f:
        for e in entries:
            f.write(json.dumps(e, ensure_ascii=False) + "\n")

    # Compact JSON array for Flutter asset loading convenience
    json_path = OUT_DIR / "cefr_core.json"
    payload = {
        "book_id": "cefr_core",
        "title": "CEFR 核心词",
        "title_levels": {"a1": "入门", "a2": "基础", "b1": "进阶"},
        "version": 1,
        "source": "CEFR-J Vocabulary Profile 1.5 + open EN-CN glosses",
        "counts": {k.lower(): level_counts[k] for k in ("A1", "A2", "B1")},
        "entries": [
            {k: e[k] for k in ("id", "en", "cn", "pos", "level", "book_id")}
            for e in entries
        ],
    }
    with json_path.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    meta = {
        "book_id": "cefr_core",
        "cefr_source_rows_a1_b1": raw_rows,
        "unique_en_pos_kept": len(best),
        "shipped_with_cn": len(entries),
        "missing_cn": len(missing),
        "match_rate": round(len(entries) / max(len(best), 1), 4),
        "per_level": {k.lower(): level_counts[k] for k in ("A1", "A2", "B1")},
        "cn_sources": dict(source_counts),
        "missing_sample": missing[:40],
    }
    with (OUT_DIR / "cefr_core.meta.json").open("w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)

    # Also write missing list for follow-up
    with (OUT_DIR / "cefr_core.missing.json").open("w", encoding="utf-8") as f:
        json.dump(missing, f, ensure_ascii=False, indent=2)

    print("Done.")
    print(json.dumps(meta, ensure_ascii=False, indent=2))
    print(f"Wrote {jsonl_path} ({jsonl_path.stat().st_size // 1024} KB)")
    print(f"Wrote {json_path} ({json_path.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
