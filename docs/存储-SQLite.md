# 本地存储方案：SQLite

日期：2026-09-30。产品已定：**业务数据用 SQLite；密钥仍走系统安全存储**。实现入口：`lib/app/coach_database.dart`（库文件 `english_coach.db`）。密钥仍 `flutter_secure_storage`。旧 `english_progress.json` 首启迁移一次后不再写入。

与 [产品方向-2026-09-30.md](产品方向-2026-09-30.md) 一致：无后端、无账号云同步；词书与进度都在本机。

## 为什么改

- 一般学习 App：只读词书 + 可写进度用结构化库；密钥进 Keystore/Keychain。
- 单 JSON 整文件读写在词量、聊天变长后难查询、易损坏、迁移痛苦。
- `cefr_core` 约五千词，已适合按级别 / 未教随机用 SQL 查。

## 原则

| 数据 | 存哪 | 说明 |
|---|---|---|
| 词书（cefr_core） | SQLite 只读表或安装时导入 | 也可首启从 assets JSON 灌库 |
| 计划、答题、错词、复习、打卡 | SQLite 可写表 | 替代 `english_progress.json` 里的 lesson 部分 |
| 教练线程消息 / 检查点 | SQLite | 替代进度外壳里的 chat |
| DeepSeek / TokenHub 密钥 | `flutter_secure_storage` | **不进 SQLite** |
| 用户偏好（水平、每天词数等） | SQLite settings 或同库 kv | 水平变更仍「明天生效」 |

## 建议库与表（草案）

库文件：应用文档目录 `english_coach.db`（名称实现时可定）。Flutter 侧优先 Drift 或 sqflite。

- `wordbook`：`id`, `en`, `cn`, `pos`, `level`（a1/a2/b1）, `book_id`
- `user_words`：用户自加词，字段对齐词书
- `settings`：level, daily_words, level_chosen, reasoning_effort, …
- `day_plan`：日期、冻住的新词 id 列表、场景/造句/对话状态、打卡标记
- `word_progress`：word_id、教过标记、复习日、掌握相关字段
- `attempts` / `error_log`：答题与错词队列（间隔规则与能力设计对齐，方向文档已取消单独四题考核）
- `chat_messages` / `chat_checkpoints`：线程全文与压缩检查点

词书与进度可同库；若需「重装清进度保留词书」，词书也可做成 assets 内只读 db + 用户库分离——实现时二选一，默认 **同库、词书表只灌一次** 更简单。

## 迁移

1. 首启或升级：若存在 `english_progress.json`，导入后可保留备份文件若干次启动。
2. 旧 `s0x` 职场 id：与 CEFR 不对齐的进度可丢弃或忽略（职场种子已删除）。
3. 导入完成前读写仍可用旧 JSON 作只读回退（可选）；稳定后删除 JSON 写入路径。

## 明确不做（本方案范围外）

- 自建后端、账号、云同步
- 把 API Key 写入 SQLite
- 为「省内存」再拆远程词库（本机 1MB 级足够）

## 实现顺序与状态

1. ~~加依赖与空库 / schema 版本~~（sqflite + ffi）
2. ~~灌入 `cefr_core`~~；SQL `pickUntaughtIds` 已提供。`LessonStore.ensureTodayPlan` 经同名内存 `pickUntaughtIds` 抽词（与 SQL API 对齐）；不灌全量内存的纯 SQL 抽词仍可选。
3. ~~迁移 settings + day_plan + progress（attempts / error_log / word_progress）~~
4. ~~迁移 chat_messages + chat_checkpoints~~
5. ~~去掉 JSON 写入主路径~~；`LocalProgress` 仅供一次性迁移读取。

## 现状指针

- 业务库：`lib/app/coach_database.dart` → `english_coach.db`
- 旧进度（只读迁移）：`lib/app/local_progress.dart` → `english_progress.json`
- 密钥：`lib/app/secrets.dart` → secure storage
- 词书资源：`assets/wordbooks/cefr_core.json`（首启灌入 `wordbook` 表）
