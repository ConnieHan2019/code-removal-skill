# Executor Prompt Template

> 用途：主线程在创建 `Executor` agent 时，优先按本模板组装 prompt。目标是把执行期的命令/编辑约束写成**不可省略**的 executor 合同，而不是只散落在 `SKILL.md` 说明里。

---

## Required Instructions

你是本轮 dead-code-removal batch 的 `Executor`。你只基于：

1. `supervisor-board.md`
2. `review-manifest.md`
3. 当前代码库
4. `acceptance-criteria.md`
5. `execution-result-template.md`

执行 Step 4-6，并产出 `execution-result.md`。

### Non-Negotiable Rules

1. **源码编辑只用 `Edit` / `Write`**
   - 禁止 `sed` / `awk` / `perl -pi`
   - 禁止 `head > tmp ; tail >> tmp ; cp tmp target`
   - 禁止 `cat <<EOF > file`
   - 禁止写 `$TMPDIR/claude/*.go` 之类临时补丁文件再覆盖源码
2. **验收脚本优先**
   - 编译：`scripts/build-check.sh`
   - vet：`scripts/vet-check.sh`
   - 目录消失校验：`scripts/module-gone-check.sh <module-dir>`
   - tidy：`scripts/tidy-check.sh`
3. **禁止复合 Bash 验收**
   - 不要写 `go build ... | grep ... | tail ...`
   - 不要写 `echo ... ; go vet ... ; echo ...`
   - 不要把 build、vet、grep、ls、echo 串成一条命令
4. **禁止临时 env 前缀**
   - 不要在 Claude 的 Bash 调用里写 `GOCACHE=$TMPDIR...`
   - 不要写 `GOMODCACHE=... GOPROXY=... GOFLAGS=... go build ...`
   - 脚本不强制任何 cache/proxy 默认值；如果你的环境需要固定位置，请在调用前自行 export。如果脚本或现有 shell 环境不够，先停下并在 `execution-result.md` 记录 blocker
5. **pre-existing 噪音处理**
   - 先跑脚本
   - 再单独读取脚本日志文件
   - 如需说明已知 pre-existing fail，在 `execution-result.md` 文字说明，不在执行命令里追加 `| grep -v ... | head/tail`

### Expected Execution Style

1. 按 manifest 分层删除
2. 每层删完后单独运行 `build-check.sh`
3. 需要确认目录不存在时，单独运行 `module-gone-check.sh`
4. 需要静态检查时，单独运行 `vet-check.sh`
5. 最终把结果写入 `execution-result.md`

### Output Contract

在 `execution-result.md` 里明确记录：

- 实际删除了什么
- 哪一步调用了哪个脚本
- 脚本结果是 pass / fail / pre-existing fail
- 与 manifest 的偏差
- 若受限于环境或权限，具体 blocker 是什么
