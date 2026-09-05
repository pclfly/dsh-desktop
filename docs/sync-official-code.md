# 同步官方代码 / 更新 Harness 指南

本文面向 DSH-Desktop（`dataelement/dsh-desktop`）的本地副本，说明三件事：

1. 从官方仓库 `git pull` 同步最新代码
2. **判断**：这次同步是否动了 Harness，要不要 `npm ci`
3. 把 Harness 升级到新版本（完整流程）

> **先分清楚三件不同的事**
>
> - **git pull**：把官方仓库的最新源码拿到本地，本来就无关 Harness 是否更新。
> - **检测要不要 `npm ci`**：判断这次 pull 是否让 Harness 的依赖内容变了。
> - **完整升级 Harness**：主动把 `@deepseek-ai/dsh` 系列升到新版本，是一套大工程（改依赖 + 重做补丁 + 验证）。

---

## 0. 背景：这个仓库是怎么“含”着 Harness 的

DSH-Desktop 不直接使用 npm 上的 `@deepseek-ai/dsh`，而是把 Harness **本地打包**成 tarball 放进仓库，再用 `file:` 路径引用：

```text
packages/harness-<版本>/
  ├── npm-dsh/       # @deepseek-ai/dsh* 系列 tarball（运行时闭包）
  └── npm-vendor/    # @deepseek-ai/cordis / cosmokit / schemastery 等
patches/             # 桌面端对 Harness 的定制（patch-package 补丁）
package.json         # "@deepseek-ai/*": "file:packages/harness-<版本>/..."
```

- **为什么要 vendor**：上游经常“只有 git tag、还没发 npm”，为让 `npm ci` 对所有人可复现，就先把 tarball 纳入仓库。
- **为什么用补丁**：桌面端特有的功能（provider 错误分类、永久删除会话、可搜索模型网格、预设导入导出等）不写成 node_modules 里的未跟踪修改，而是做成 `patches/*.patch`，在 `npm ci`（postinstall 的 `patch-package`）时打上。

**用户数据在哪里**：Harness 的 Profile、插件、工作区、会话、模型配置都在 Electron 用户数据目录（`<appData>/dsh-desktop/harness`，开发版是 `dsh-desktop-dev/harness`），**不在仓库里**。所以同步代码、重装依赖、升级 Harness 都不会动你的历史数据。

---

## 1. 拉取官方最新代码（git pull）

### 1.1 确认 remote 和分支

```bash
git remote -v                    # 确认 origin 指向 dataelement/dsh-desktop
git branch -a                    # 看本地/远程分支
git branch --show-current        # 当前分支
```

默认分支是 `main`（`origin/main`）。

### 1.2 先 fetch，看领先/落后

```bash
git fetch origin
git status -sb                   # 显示 ahead/behind
```

状态含义：

| 状态 | 含义 | 下一步 |
|---|---|---|
| `[ahead 3]` | 本地比 origin/main 多 3 个提交（未推送） | pull 可能“Already up to date”，因为本地已包含 origin 内容 |
| `[behind 2]` | 远程比本地新 | 直接 pull 会 fast-forward |
| `[ahead 3, behind 2]` | 分了叉 | pull 会做一次 merge，可能有冲突 |

### 1.3 执行 pull

```bash
git pull origin main             # 或直接 git pull（main 默认跟踪 origin/main）
```

- 输出 `Already up to date`：说明本地已经包含 origin/main 的全部内容（常见于本地有未推送的领先提交）。
- 输出 `Fast-forward`：正常拉取新提交。
- 输出冲突：说明本地有私改跟官方改了同一处，需手动解决。

### 1.4 有过未提交改动时

先看 `git status`。如果 worktree 不干净（本地正改着东西、或做了实验），pull 可能被拒绝或带入混乱。建议先撤销到 clean 再 pull：

```bash
git status --short
git stash                     # 或 git reset --hard HEAD（谨慎：会丢弃未提交改动，但不会动未跟踪文件）
```

---

## 2. 判断：这次有没有动 Harness / 要不要 `npm ci`

`npm ci` 是**严格按 `package-lock.json` 重装 `node_modules`**，所以只要“影响 Harness 的文件”在 pull 里变了，就需要 `npm ci`。

### 2.1 影响 Harness 的文件

| 文件/目录 | 变了意味着 | 要 `npm ci`？ |
|---|---|---|
| `package.json` 里 `@deepseek-ai/*` 的 `file:` 行 | Harness 换版本 / 增删包 | ✅ |
| `package-lock.json` | 安装清单变了 | ✅ |
| `patches/*.patch` | 桌面定制补丁改了 | ✅（补丁是 postinstall 阶段 `patch-package` 打的，不重装就没有） |
| `packages/harness-*/` | tarball 本体换了 | ✅ |
| `docs/harness-*-upgrade.md` | 只是升级说明文档 | ❌（但它提示“该跟着升了”） |

### 2.2 两条判断命令

**① 看这次 pull 动了哪些相关文件**（`HEAD@{1}` = 上一次 commit；若 pull 后你又 commit 了，改用 `HEAD~1`）

```bash
git diff HEAD@{1} --name-only -- package.json package-lock.json patches/ packages/harness-*/ docs/harness-*-upgrade.md
```

输出为空 → Harness 相关没变，**不用 `npm ci`**。

**② 期望版本 vs 已装版本**（最省心，因为版本号就写在 `file:` 路径里）

```bash
echo -n "期望: "; grep '"@deepseek-ai/dsh":' package.json | grep -o 'dsh-[^/"]*\.tgz'
echo -n "已装: "; node -e "console.log(require('./node_modules/@deepseek-ai/dsh/package.json').version)"
```

两者不一致 → **要 `npm ci`**；一致 → 不用。

### 2.3 结论

- **只要 ② 里版本号一致、且 ① 为空 → 不用 `npm ci`**。
- **只要上面任一文件在 pull 中变了 → 跑 `npm ci`**。
- 拿不准就 `npm ci`（幂等，装旧/装错反正要重来）。

---

## 3. 完整升级 Harness（主动升版本）

这是另一套流程，参考历次升级文档（`docs/harness-0.1.2*-upgrade.md`）和 `docs/development.md` 的 “Maintaining upstream patches”。

### 3.1 确定目标版本 + 依赖来源

两条路，取决于上游有没有发到 npm：

| 情形 | 做法 |
|---|---|
| 上游**还没**发 npm | 从 git tag 本地打包 tarball → vendor 进 `packages/harness-<新版本>/` |
| 上游**已**发 npm | 把 `file:` 依赖换回语义化版本，并重新生成 lockfile |

本地打包复现命令（上游 release pipeline）：

```bash
git clone --depth 1 --branch <tag> https://github.com/deepseek-ai/deepseek-harness.git
cd deepseek-harness
corepack enable                                   # packageManager 指定 pnpm@<版本>
corepack pnpm install --frozen-lockfile
corepack pnpm run build:official                  # release:pack 要求 official 客户端构建记录
corepack pnpm exec tsx scripts/release/pack.ts --family vendor --out dist/npm-vendor --concurrency 8
corepack pnpm exec tsx scripts/release/pack.ts --family dsh    --out dist/npm-dsh    --concurrency 8
```

> 注意：`pnpm run release:pack -- --family dsh` 会把参数当位置参数报错，需直接 `pnpm exec tsx`。

### 3.2 对比上游结构性变更

- 删了哪些包 / 加了哪些包（更新 `package.json` 的 `file:` 行，以及 `test/release.test.ts` 的 `excludedHarnessPackages`）
- vendor 版本号是否上抬（`@deepseek-ai/cordis`、`cosmokit`、`schemastery` 等）
- 是否有 breaking change（协议、controller 签名、CSS hash 等）

### 3.3 逐个重放/改写桌面补丁

这是最重的活。判断标准是 **“上游是否已原生提供”**，而不是“补丁能不能修好”：

- 上游已原生 → 交还给上游（从补丁里删掉）
- 上游没有等价能力 → 保留并 rebase 到新产物

补丁有 version 字样时需改名（如 `+0.1.2-alpha.4.patch` → `+0.1.2-rc.1.patch`）；CSS module hash 或行号漂移需对着新产物重新生成。

### 3.4 对齐版本字样 / 引用

- `packages/dsh-desktop-*/package.json` 里的 `@deepseek-ai/dsh*` peer 范围（预发布版的 `^` 只在同一 `major.minor.patch` 内匹配）
- `packages/dsh-desktop-preset-transfer/index.js` 的 `PRESET_SOURCE_DSH_VERSION`
- 6 份 README（en/zh/ja/es/pt/ru）里的 `@deepseek-ai/dsh@<版本>`
- 相关 `test/*` 断言（`readme-parity`、`profile-compatibility`、`preset-transfer-patch`、`release` 等）

### 3.5 验证清单（文档要求）

```bash
# 完整安装 + 打补丁（务必完整，别加 --ignore-scripts）
env -u NODE_ENV npm ci

# 校验
env -u NODE_ENV npm run typecheck
env -u NODE_ENV npm test
env -u NODE_ENV npm run build
node scripts/verify-harness-auth.mjs
```

再**实机启动**走一遍受影响流程（启动、Profile、插件、目录选择、移动端、更新）。

---

## 4. 安装/校验命令与 `NODE_ENV` 坑

> **⚠️ 本项目环境若设了 `NODE_ENV=production`**，`npm ci` 会**跳过所有 devDependencies**（`patch-package`、`electron`、`vitest`、`electron-vite` 全部不装），导致 postinstall 里 `patch-package` 找不到而失败。这**不是代码问题**。
>
> 处理方式：在命令前取消该变量。
>
> ```bash
> env -u NODE_ENV npm ci
> env -u NODE_ENV npm run build
> ```

在普通终端（没有 NODE_ENV=production）里则直接 `npm ci` 即可。

---

## 5. 常见坑

- **不要提交本机绝对路径生成的 lockfile**：用仓库内 tarball 装的 `package-lock.json`，其 `resolved` 指向本机 `file:` 路径，别人 `npm ci` 会直接失败。版本 bump 和 lockfile 必须等上游发布后由真实 registry 生成。
- **别用 `--ignore-scripts`**：跳过了 postinstall（Electron 二进制、品牌资源、补丁全都不跑），测试/typecheck 可能全绿但应用起不来。
- **补丁里的绝对路径 context 行**：某些补丁含上游构建产物内嵌的源码绝对路径，作为 context 被 patch-package 逐行匹配；若换机器重新 pack，这行路径会变，相关补丁需对着新产物重新生成。
- **`feishu-release-notes.test.ts` 对 git tag 敏感**：给脚本传 `0.7.2` 时，若仓库只有带 `v` 前缀的 `v0.7.2` tag（如 `git fetch` 后），会回退到 HEAD 把它当成“上一个版本”而失败。真实 release checkout 有裸 tag，会正确解析；这不是代码回归。
- **别把未启用 provider / 测试包转发成依赖**：`package.json` 只引用 `@deepseek-ai/dsh` 实际运行闭包、运行时引用的前端公共包，以及 `dsh-desktop-*` 插件；可选 Bundle 应由插件安装流程按需安装。

---

## 6. 更新 Harness 时保留你的数据

- 你的 3 个本地提交（如模型推理修复、One-click 打包脚本）在合并官方升级时可能冲突——冲突点往往是**某个补丁文件**（官方升级重命名了它，而你也改了它）。用 `git merge` 后手动解决即可。
- Harness 升级只动“程序代码”，你的 Profile / 会话 / 插件 / 工作区 / 模型配置都在用户数据目录，全程不受影响。

---

## 参考文档

- `docs/development.md`：本地环境、验证、补丁维护、原生平台打包
- `docs/harness-0.1.2-rc.1-upgrade.md`（及前序 `alpha.4` / `alpha.3` / `0.1.2`）：历次 Harness 升级的详细记录
- `docs/architecture.md`：启动流程、持久化、安全边界、故障恢复、手机连接与更新
