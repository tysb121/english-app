# CEFR 主词书（cefr_core）

装配日期：2026-09-30（Asia/Shanghai）

## 产品映射

| 用户看到的水平 | CEFR-J 级别 | book_id |
|---|---|---|
| 入门 | A1 | `cefr_core` |
| 基础 | A2 | `cefr_core` |
| 进阶 | B1 | `cefr_core` |

职场约 70 条种子已删除；本仓库默认与唯一主词书为 `cefr_core`（不做职场加餐）。

## 源与许可

详见 [assets/wordbooks/ATTRIBUTION.md](../assets/wordbooks/ATTRIBUTION.md)。

- 英文 + 分级：CEFR-J Vocabulary Profile 1.5（Tono Laboratory / TUFS；研究与商用需引用）
- 中文释义：ECDICT（MIT）为主；曾评估 DictionaryData（Apache-2.0）作后备
- 源 CSV：`https://raw.githubusercontent.com/openlanguageprofiles/olp-en-cefrj/master/cefrj-vocabulary-profile-1.5.csv`
- ECDICT：`https://github.com/skywind3000/ECDICT`

## 装配方式

1. 读取 CEFR-J CSV，只保留 `CEFR ∈ {A1,A2,B1}`。
2. `headword` 规范化：取 `/` 前第一写法，去掉括号注释。
3. 同一 `(lemma, pos)` 多级别时保留更低级别。
4. 中文：lemma 大小写不敏感匹配 ECDICT；按 CEFR pos 优先挑对应义项，截成短释义。
5. 极少数短语/缩写缺口用手补，并在 jsonl 里标 `cn_source=curated`。
6. **不以 LLM 批量编造释义。**

脚本：`tool/build_cefr_core.py`（vendor 大文件 gitignore）。

## 词条形状

```json
{
  "id": "cc_a1_about_adverb_f4064a",
  "en": "about",
  "cn": "大约；四处",
  "pos": "adverb",
  "level": "a1",
  "book_id": "cefr_core"
}
```

稳定 `id`：`cc_{level}_{slug}_{pos}_{hash6}`。

## 数量（装配结果）

| level | 有中文词条 |
|---|---|
| A1 | 1164 |
| A2 | 1411 |
| B1 | 2445 |
| **合计** | **5020** |

匹配率：**100%**（5020 / 5020 唯一 en+pos）。其中 ECDICT ≈ 4974，手补 curated ≈ 46。

产物：

- `assets/wordbooks/cefr_core.json` — Flutter 资源（含 meta + entries）
- `assets/wordbooks/cefr_core.jsonl` — 一行一词（含 `cn_source` 便于审计）
- `assets/wordbooks/cefr_core.meta.json` — 计数与来源统计

## 代码现状

- `lib/data/cefr_core.dart`：数据类 + `rootBundle` 加载器。
- `main.dart` 启动时 `loadCefrCore()`，注入 `LessonStore(book: entries)`。
- 水平：入门=A1 / 基础=A2 / 进阶=B1；当天未教词中随机，计划冻住后改水平明天生效。
- `lib/data/seed_words.dart` 已删除。
