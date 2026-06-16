# 設計：多分支 state（branch-keyed map + idempotent flows）

**Goal**：讓 `/gitf` 同時記住多個分支各自掛起的 flow 狀態，依「當前分支」resume，並在 state 遺失/過期時能從 git/gh 現況安全自我重建。

**動機**：常見工作流是同時有多個 feature/fix 分支、release 審查中插隊 hotfix、或一個分支擱置數天再回來。目前 `.gitf/state.json` 是單一物件，「state 存在就霸佔下一次 `/gitf`」，無法並行掛起多個 flow。

---

## §1 資料結構：branch 為 key 的 map

`.gitf/state.json` 從單一物件改為：

```json
{
  "version": 2,
  "flows": {
    "feature/auth-jwt": {
      "flow": "A", "step": "awaiting_merge",
      "pr_number": 3, "target_branch": "develop",
      "pause_sha": "a1b2c3d"
    },
    "release/v1.2.0": {
      "flow": "B", "step": "awaiting_code_review",
      "release_branch": "release/v1.2.0", "version": "1.2.0",
      "version_mode": true, "pause_sha": "e4f5a6b"
    }
  }
}
```

- key = **擁有該 flow 的分支**：A = feature/fix、B = release/*、C = hotfix/*。
- value = 原本的扁平 state 物件（欄位不變），**新增 `pause_sha`**（暫停當下 `git rev-parse <branch>` 的 tip，用於身份驗證，見 §3）。
- 多個 flow 各佔一個 entry，互不干擾。
- 同一 repo/worktree 內 git 保證分支名唯一，故同一時刻不會有兩個同名 key。

---

## §2 查找邏輯（重寫 SKILL.md Step 0.5）

```
current = git branch --show-current
state   = read .gitf/state.json

IF state.flows[current] 存在 AND  git merge-base --is-ancestor <pause_sha> current 為真：
    → CACHE HIT：信任該 entry，直接 resume。不做任何 git/gh 推導。
ELSE：
    → CACHE MISS：跑正常分支偵測（decision tree），
      所選 flow 以 idempotent 模式執行（§4），每步先問 git/gh「做過沒」。
```

- 命中時除了 resume 本身必要的查詢（如 `gh pr view <pr_number>` 查等待中的 PR）外，不付額外推導代價。這是常態路徑。
- 未命中（含 SHA 驗證失敗）才走較重的重新推導。

---

## §3 撞名（時間上重用）與兩層防護

**問題不是同名並存**（git 禁止），**而是重用造成假命中**：分支被刪、entry 沒清、之後又建同名分支 → 新分支誤命中舊 entry → 信任過期資料。

**防護一：cache hit 的 SHA 指紋驗證（純本地、零網路）**

```
git merge-base --is-ancestor <pause_sha> <current-branch>
├─ true  → 同一條分支（可能往前長了幾個 commit）→ 真命中
└─ false → pause_sha 不在當前分支歷史 → 重建的同名分支 → 當 MISS，重新推導
```

`merge-base --is-ancestor` 是瞬間完成的本地操作，不破壞「命中不付推導代價」的目標。

**防護二：gitf 自清 entry**

flow 跑完、`CLEANUP` 刪分支的同時，刪掉對應 entry。凡 gitf 經手刪的分支不會變僵屍；只有使用者手動刪分支才需靠防護一兜底。

---

## §4 idempotent 探測（僅 cache miss 路徑）

未命中時，flow 靠探測 git/gh 現況把進度重建出來，跳過已完成步驟。核心探測四種：

| 探測 | 指令 | 命中時動作 |
|---|---|---|
| PR 是否已存在 | `gh pr list --head <branch> --base <base> --state all` | open→去查狀態（等同 resume）；merged→跳過此 land；none→正常建 |
| tag 是否已打 | `git tag -l v<version>` | 有→跳過 TAG |
| 版本是否已 bump | 比對版本檔內容 vs 目標版本 | 已是目標→跳過 bump |
| 分支是否已併入 | local：`git log <base>..<branch>` 為空 | 空→已併，跳過 merge 直接 cleanup |

逐 flow：

- **Flow A**：LAND 前探 PR（open→查狀態 / merged→sync+cleanup / none→建）。
- **Flow B/C**：探分支存在否、版本已 bump 否、PR（main / develop 兩段）、tag、分支還在否。
- **review gate**：重跑天生無害，不需探測。

### 總原則：模稜兩可即中斷

> 遇到模稜兩可或非預期狀態，一律**中斷並回報**，不臆測、不自動修復。

具體落地：

- **孤兒分支**：Flow B/C 開始前探到「已有未併入 main 的 release/* 或 hotfix/* 分支」→ **中斷**，告知使用者先處理（合併或刪除）該分支後再 `/gitf`。不接續、不另開 `-2`。
- **合併衝突**：停下回報，由使用者解決。
- **探測結果互相矛盾**：停下回報。

探測的目的是「安全跳過已完成的步驟」，不是「聰明搶救爛攤子」。

---

## §5 實作面

### 受影響檔案

| 檔案 | 改動 |
|---|---|
| `gitf/gitf-state.sh` | **新增**：state 存取層（見下） |
| `gitf/SKILL.md` | state schema 改 v2 map；Step 0.5 cache hit（含 SHA 驗證）/miss；加中斷原則；暫停寫 keyed entry + `pause_sha` |
| `gitf/flows/resume.md` | 依當前分支取 entry + SHA 驗證 |
| `gitf/flows/flow-a.md` `flow-b.md` `flow-c.md` | cache-miss idempotent 探測；B/C 孤兒分支中斷 |
| `gitf/flows/code-review-gate.md` | entry 以分支為 key 寫入 |
| `gitf/providers/github.md` | LAND 加「PR 是否已存在」探測 |
| `gitf/providers/local.md` | LAND 加「是否已併入」探測 |
| `gitf/providers/README.md`、`spec/flows.md`、`spec/decision-tree.md` | 文件化 map、cache 語意、idempotency、中斷原則 |
| `docs/usage.md` | 說明可並行掛起多分支 |

### 狀態存取層：`gitf-state.sh`

state 目前由 AI 用 `cat`/`Write` 讀寫，無可測單元。比照 `gitf-detect.sh` 抽出腳本：

```
gitf-state.sh get   <branch>          # 印出 entry JSON，無則空
gitf-state.sh put   <branch> <json>   # 寫入/更新 entry
gitf-state.sh del   <branch>          # 刪除 entry
gitf-state.sh valid <branch> <sha>    # merge-base --is-ancestor 驗證 → exit 0/1
```

- 路徑同 detect：worktree root 的 `.gitf/state.json`。
- 容忍檔案不存在 / 非 v2 形狀（視為無 entry）。

### 測試策略

- **機械、確定性部分**（map 增刪查、SHA 驗證）→ `gitf-state.sh` + 新增 `tests/test-state.sh` 單元測試（純本地，比照 `test-detect.sh`）。
- **判斷部分**（idempotent 探測、何時中斷）→ 留在 flow markdown，以 `evals/evals.json` 測。

### 遷移：不需要

v1 舊格式（無 `flows` key）一律當「無 state」→ 全部 cache miss → idempotent 路徑自然重建進度。idempotent 本身就是遷移，零特例。

### 分支疊放

先把 `feature/code-review-integration` 用 `/gitf` 併進 develop，再從 develop 開新分支做本案。理由：本案大改 state schema、Step 0.5、所有 flow——正是 code-review 分支剛動過的檔案。先落地成完整單元，PR 才乾淨。merge 時機由使用者決定。

---

## 已拍板決策

1. state 改 branch-keyed map（§1）。
2. cache hit/miss 語意；命中信任、不推導（§2）。
3. 撞名以 `pause_sha` + `merge-base --is-ancestor` 本地驗證，加 gitf 自清 entry 雙層防護（§3）。
4. cache-miss 走 idempotent 探測；模稜兩可一律中斷（§4）。
5. 抽 `gitf-state.sh` 狀態存取層 + `test-state.sh`（§5）。
6. 無 v1→v2 遷移特例（§5）。
