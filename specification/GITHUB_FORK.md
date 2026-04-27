# GitHub Fork 协作规范

## 目标

统一社区仓库、个人 Fork 仓库和本地仓库的协作方式，降低直接向上游仓库提交代码、分支长期漂移和后续合并冲突的风险。

## 仓库角色

- `upstream`：社区维护的主仓库，只维护稳定的主线代码和正式发布版本。
- `origin`：开发者在 GitHub 上 Fork 出来的个人仓库，用于保存个人开发分支和提交 Pull Request。
- `local`：开发者本地工作副本，同时配置 `origin` 和 `upstream`。

## 分支规则

- 社区仓库的 `main` 分支只接受 Pull Request 合并，不允许直接推送。
- 社区仓库的版本发布使用 `tag`，命名格式为 `v<主版本>.<次版本>.<修订>`，例如 `v1.2.3`。
- 个人仓库的 `main` 分支必须长期跟随 `upstream/main`，不要在落后的 `main` 上持续开发。
- 日常开发应使用短生命周期分支，完成后通过 Pull Request 合并到社区仓库。

## 分支命名建议

- 新功能：`feat/<topic>`
- 缺陷修复：`fix/<topic>`
- 文档更新：`docs/<topic>`
- 重构优化：`refactor/<topic>`
- 工程事务：`chore/<topic>`

`<topic>` 建议使用简洁的英文短语，例如 `fix/postgresql-env-parser`。

## 首次配置

先在 GitHub 页面将社区仓库 Fork 到个人账户下，然后在本地克隆个人仓库，并补充 `upstream` 远程：

```bash
git clone git@github.com:<your-account>/<project>.git
cd <project>

git remote add upstream git@github.com:<community-org>/<project>.git
git remote -v
```

配置完成后，远程仓库角色应满足：

- `origin` 指向个人 Fork 仓库
- `upstream` 指向社区主仓库

## 日常同步

开发前先同步社区仓库最新代码，再更新个人仓库的 `main`：

```bash
git fetch upstream
git checkout main
git pull --rebase upstream main
git push origin main
```

如果使用当前仓库提供的辅助脚本，也可以在仓库根目录执行：

```bash
./scripts/sync.sh
```

## 开发流程

推荐流程如下：

1. 从最新的 `main` 创建功能分支。
2. 在功能分支上完成开发、测试和自检。
3. 将功能分支推送到个人 Fork 仓库。
4. 使用个人功能分支向社区仓库的 `main` 发起 Pull Request。
5. Pull Request 合并后，同步本地和个人 Fork 的 `main`。

对应命令示例：

```bash
git checkout main
git pull --rebase upstream main

git checkout -b fix/example-change

# 开发完成后
git add .
git commit -m "fix(example): adjust implementation"
git push origin fix/example-change
```

## 冲突处理

如果功能分支开发周期较长，应定期将社区仓库最新代码同步到本地后再 rebase 当前分支：

```bash
git checkout main
git pull --rebase upstream main

git checkout fix/example-change
git rebase main
```

发生冲突时，先解决冲突文件，再继续 rebase：

```bash
git add <conflicted-files>
git rebase --continue
```

## 禁止事项

- 不要直接向社区仓库的 `main` 分支推送代码。
- 不要在长期落后的 `main` 分支上直接开发。
- 不要将多个无关需求混在同一个开发分支中。
- 不要在个人 Fork 中长期保留大量未同步的主线分支。
