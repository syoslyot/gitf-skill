# Plan：可插拔 Code Review + `.gitf/` 目錄 + 安裝/執行拆分

**Goal**：在 release 流程 merge to main 之前插入一道可插拔的 code-review 關卡；review 工具由使用者於安裝時設定，AI 自行判斷結果，乾淨就自動繼續，卡住才中斷等使用者。

**Architecture**：
- 新增專案級 `.gitf/` 目錄，統一收納 gitf 的所有狀態（`config` + `state.json`），取代散落在 `.git/` 的 `gitf-state.json` / `gitf-config.json`。
- 拆出一次性的 `INSTALL.md`（安裝設定）與每次執行的 `SKILL.md`（流程），避免每次跑都讀安裝內容。
- code-review 在 release 分支「尚未落地」時對 `main..<release-branch>` 做 diff 審查，與平台無關（github / local 都跑）。

---

## 一、`.gitf/` 目錄設計（取代 `.git/` 內的兩個檔）

放在**使用者當前專案根目錄**，每專案獨立，不會跨專案衝突。

```
<使用者專案>/
  .gitf/
    config        ← 設定（平台覆蓋 + review 工具）
    state.json    ← flow 暫時狀態
```

整個 `.gitf/` 屬於工具產物，**全部 gitignore**，不進 repo。安裝時將 `.gitf/` 加入專案 `.gitignore`。

### `.gitf/config` 格式（JSON，沿用 detect 腳本可解析的形式）

```json
{
  "platform": "auto",
  "reviewers": ["code-review"]
}
```

- `platform`：`auto` | `github` | `local`，取代舊的 `.git/gitf-config.json`。
- `reviewers`：**有序**字串陣列。安裝時偵測 + 詢問後填入。
  - 預設一個工具。
  - 使用者明確說要多個 → 依序執行（index 0 先跑，再 1…）。
  - 空陣列 `[]` 或缺欄位 → 不做 review。

### 遷移影響（這是最大宗的跨檔改動）

所有 `.git/gitf-state.json` → `.gitf/state.json`，`.git/gitf-config.json` → `.gitf/config`。涉及檔案：

- `gitf/SKILL.md`：state schema、Step 0.5 讀 state、Rules、Decision Tree
- `gitf/gitf-detect.sh`：`CONFIG_FILE` 改讀 `.gitf/config` 的 `platform` 欄位
- `gitf/gitf-update.sh`：rsync 的 `--exclude` 不再需要（state/config 已不在 INSTALL_DIR），清掉
- `gitf/flows/resume.md`、`flow-a.md`、`flow-b.md`、`flow-c.md`
- `gitf/providers/github.md`、`local.md`
- `gitf/flows/status-messages.md`：`needs-login` 訊息裡的 `.git/gitf-config.json` 路徑

---

## 二、state.json 不再是 github 專屬（關鍵架構變更）

**現狀**：只有 github provider 寫 state（PR 無法 auto-merge 時暫停）。`local never writes state`。

**變更**：code-review 關卡在 release 分支落地前執行，**兩種 provider 都可能在此暫停**，因此 `state.json` 改為兩種 provider 共用。

- github 既有的 PR-merge 暫停邏輯不變。
- 新增 `step=awaiting_code_review`，github / local 皆可寫入。
- local 的 resume：下次 `/gitf` 在 `release/*`（或 `hotfix/*`）分支上 → 路由到 flow-b（或 flow-c）→ 讀到 `state.json` 的 `awaiting_code_review` → 重跑 review 步驟，跳過前置步驟。

---

## 三、Flow B 步驟重編號 + 新增 B-4

原 B-4~B-7 全部後移一位，新 B-4 為 code-review：

| 新編號 | 內容 | 來源 |
|--------|------|------|
| B-1 | 決定 release 名稱 | 不變 |
| B-2 | 建立 release 分支 | 不變 |
| B-3 [version] | bump 版本 | 不變 |
| **B-4** | **code review（新增）** | — |
| B-5 | LAND release → main | 原 B-4 |
| B-6 [version] | tag main | 原 B-5 |
| B-7 | back-merge → develop | 原 B-6 |
| B-8 | cleanup | 原 B-7 |

### B-4 邏輯

```
讀 .gitf/config 的 reviewers
├─ 空 / 缺 / 帶 --skip-review 旗標 → 直接跳 B-5
└─ 有 reviewers：依序對每個 tool：
     在 <release-branch> 上對 main..<release-branch> 的 diff 執行該 review 工具
     AI 讀工具輸出，自行判斷有沒有需要處理的問題（不寫死「空=通過」）
     ├─ 沒問題 → 下一個 reviewer；全部跑完 → B-5
     ├─ 有問題且 AI 能修 → 修改並 commit 到 release 分支 → 重跑同一個 reviewer
     └─ 修不掉 / 需使用者決策 → 存 state(step=awaiting_code_review) → 列出剩餘問題 → 停
```

- review 對象是 release 分支的本地 diff，PR 尚未建立，因此平台無關。
- resume：`awaiting_code_review` → 從 B-4 頭重跑（重新審查），乾淨才進 B-5。

### Flow C（hotfix）同步加 review

hotfix 同樣 merge 進 main，比照 flow B 在 land 到 main 前插入同一道 review。原 C-2~C-5 後移一位，新 C-2 為 code review：

| 新編號 | 內容 | 來源 |
|--------|------|------|
| C-1 | patch 版本 | 不變 |
| **C-2** | **code review（新增）** | — |
| C-3 | LAND hotfix → main | 原 C-2 |
| C-4 | tag main | 原 C-3 |
| C-5 | back-merge → develop | 原 C-4 |
| C-6 | cleanup | 原 C-5 |

C-2 邏輯與 B-4 完全相同（審 `main..<hotfix-branch>`、AI 判斷、能修自動修、卡住存 `awaiting_code_review` 暫停）。B-4 與 C-2 共用同一段 review 邏輯描述，避免重複。

---

## 四、安裝 / 執行拆分

### `gitf/INSTALL.md`（一次性，使用者不需手動觸發）

由 `SKILL.md` 的 bootstrap 在偵測到 `.gitf/config` 不存在時自動讀取並執行：

1. 掃描可用的 review 工具（`~/.claude/skills/` 內的 skill + plugin skill，如 `code-review`、`review`、`superpowers:requesting-code-review`）。
2. 詢問使用者要用哪套（預設選偵測到的第一個；使用者可指定多個依序執行）。
3. 建立 `.gitf/` 目錄，寫入 `config`（含 `platform:auto` 與 `reviewers`）。
4. 將整個 `.gitf/` 加進專案 `.gitignore`（工具產物，不進 repo）。

另外把目前散在 `SKILL.md` 的「支援哪些平台 / 偵測能力」說明性內容移入 `INSTALL.md`，`SKILL.md` 只留每次執行必要的偵測呼叫。

### `gitf/SKILL.md`（每次執行）

Step -1 bootstrap 末端新增：

```bash
[ -f .gitf/config ] || echo "GITF_NOT_CONFIGURED"
```

印出 `GITF_NOT_CONFIGURED` → 讀 `INSTALL.md` 跑一次性設定，完成後續跑正常 flow。已設定則完全不碰 `INSTALL.md`。

平台偵測（`gitf-detect.sh`）維持每次重跑——gh 登入狀態會變，幾個 shell 指令成本趨近於零。

### `/gitf -v` 旗標 + 新增 `--skip-review`

Step 0.5 旗標解析新增 `--skip-review`（本次跑略過 B-4）。

---

## 五、實作順序（建議）

1. `.gitf/` 路徑遷移（state + config）：改 `gitf-detect.sh`、`SKILL.md`、所有 flows/providers/status-messages 的路徑字串。先讓既有功能在新路徑下不破。
2. 更新 `gitf/tests/test-detect.sh`：config 路徑改為 `.gitf/config`，驗證 `platform` 解析仍綠。
3. state.json 解禁給 local：改 `providers/local.md` 與 `SKILL.md` Rules 的「local never writes state」敘述，僅限 `awaiting_code_review`。
4. flow-b 重編號 + 新增 B-4；flow-c 重編號 + 新增 C-2；`resume.md` 新增 `awaiting_code_review` 處理列（B 與 C 共用：重跑 review 步驟）。B-4 / C-2 共用同一段 review 邏輯描述。
5. SKILL.md state schema 加 `awaiting_code_review`；Step 0.5 加 `--skip-review`。
6. 抽出 `INSTALL.md`；SKILL.md bootstrap 加 config 偵測與觸發。
7. 更新 `docs/`（installation/usage）與 `spec/`（flows/decision-tree）反映新流程。
8. 跑 `bash gitf/tests/test-detect.sh` 確認綠燈。

---

## 六、已拍板的決策

1. **flow-c 同步加 review** —— hotfix → main 比照辦理（見第三節）。
2. **整個 `.gitf/` gitignore** —— 工具產物，不進 repo。
3. **不保留舊路徑 fallback** —— `.git/gitf-config.json` / `.git/gitf-state.json` 直接視為不存在；舊使用者首次跑 `/gitf` 會走一次 `INSTALL.md` 重新設定。
