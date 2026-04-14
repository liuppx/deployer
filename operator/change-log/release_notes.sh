#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ENV_CANDIDATES=(
  "${RELEASE_NOTES_ENV_FILE:-}"
  "$script_dir/release_notes.env"
  "$script_dir/.env"
)

load_env_file() {
  local env_file
  for env_file in "${ENV_CANDIDATES[@]}"; do
    [[ -n "$env_file" ]] || continue
    if [[ -f "$env_file" ]]; then
      # shellcheck disable=SC1090
      source "$env_file"
      break
    fi
  done
}

load_env_file

TAG_GLOB="${RELEASE_NOTES_TAG_GLOB:-v[0-9]*.[0-9]*.[0-9]*}"
CODEX_BIN="${RELEASE_NOTES_CODEX_BIN:-codex}"
KEEP_RAW_INPUT="${RELEASE_NOTES_KEEP_RAW_INPUT:-false}"
KEEP_FINAL_TMP="${RELEASE_NOTES_KEEP_FINAL_TMP:-false}"

usage() {
  cat <<'EOF'
用法:
  ./scripts/release_notes.sh <旧tag> <新tag|HEAD> [最终输出文件]
  ./scripts/release_notes.sh [最终输出文件]

示例:
  ./scripts/release_notes.sh v1.0.0 v1.1.0
  ./scripts/release_notes.sh v1.0.0 HEAD
  ./scripts/release_notes.sh
  ./scripts/release_notes.sh ./output/release-notes.md

说明:
  1. 脚本先提取版本区间事实数据，再在脚本内调用 codex 生成最终 Markdown。
  2. 传两个参数时，分析 <旧tag>..<新tag|HEAD>，并输出到 stdout。
  3. 传三个参数时，第三个参数为最终 Markdown 输出文件。
  4. 不传 tag 时，默认分析：
     - 若 HEAD 正好是最新 semver tag，则分析“上一个 tag..最新 tag”
     - 否则分析“最新 tag..HEAD”
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

ensure_git_repo() {
  git -C "$root_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1 || fail "当前目录不是 Git 仓库。"
}

get_semver_tags() {
  git -C "$root_dir" tag -l "$TAG_GLOB" | sort -V
}

ref_exists() {
  git -C "$root_dir" rev-parse -q --verify "${1}^{commit}" >/dev/null 2>&1
}

resolve_default_range() {
  mapfile -t semver_tags < <(get_semver_tags)
  if [[ "${#semver_tags[@]}" -eq 0 ]]; then
    fail "仓库中没有找到符合规则的 tag（TAG_GLOB=$TAG_GLOB），无法自动推断版本范围。"
  fi

  latest_tag="${semver_tags[-1]}"
  latest_tag_commit="$(git -C "$root_dir" rev-list -n 1 "$latest_tag")"
  head_commit="$(git -C "$root_dir" rev-parse HEAD)"

  if [[ "$latest_tag_commit" == "$head_commit" ]]; then
    if [[ "${#semver_tags[@]}" -lt 2 ]]; then
      fail "只有一个 tag，无法自动推断“上一个 tag..最新 tag”。请显式传入两个版本。"
    fi
    old_ref="${semver_tags[-2]}"
    new_ref="$latest_tag"
  else
    old_ref="$latest_tag"
    new_ref="HEAD"
  fi
}

run_codex_compat() {
  local raw_input_file="$1"
  local final_output_file="$2"
  local codex_prompt
  local exec_supported="false"
  local codex_log_file=""
  local raw_payload

  command -v "$CODEX_BIN" >/dev/null 2>&1 || fail "未找到 codex 命令，请先安装并完成登录。"

  raw_payload="$(cat "$raw_input_file")"
  codex_prompt="$(cat <<EOF
你现在在仓库：$root_dir

下面是版本区间原始变更数据，请直接基于这份数据生成最终中文发布说明。
不要执行任何命令，不要再次读取文件，不要输出过程解释。

<raw_release_data>
$raw_payload
</raw_release_data>

要求：
1. 标题为：## 版本变更摘要（$old_ref → $new_ref）
2. 必须包含以下小节，且顺序固定：
   - 新增
   - 体验
   - 性能
   - 安全
3. 每个小节使用编号段落（1、2、3），内容要精炼、中文表达，不要直接照抄英文 commit。
4. 若某类无内容，写“无”。
5. 最后追加：
   - 提交总数
   - 变更文件数
   - 代码行数变化（+/-）
   - 贡献者列表（- @用户名 (提交次数)）

只输出 Markdown 正文，不要额外解释。
EOF
)"

  if "$CODEX_BIN" exec --help >/dev/null 2>&1; then
    exec_supported="true"
  fi

  codex_log_file="$(mktemp "${TMPDIR:-/tmp}/release-notes-codex.XXXXXX.log")"

  if [[ "$exec_supported" == "true" ]]; then
    if "$CODEX_BIN" exec -C "$root_dir" -o "$final_output_file" "$codex_prompt" > /dev/null 2>"$codex_log_file"; then
      [[ -s "$final_output_file" ]] || fail "codex exec 执行完成，但未生成有效输出文件：$final_output_file"
      rm -f "$codex_log_file"
      return 0
    fi
  fi

  if "$CODEX_BIN" --input "$codex_prompt" --output "$final_output_file" > /dev/null 2>"$codex_log_file"; then
    [[ -s "$final_output_file" ]] || fail "codex 执行完成，但未生成有效输出文件：$final_output_file"
    rm -f "$codex_log_file"
    return 0
  fi

  if [[ -s "$codex_log_file" ]]; then
    sed -n '1,40p' "$codex_log_file" >&2
  fi
  rm -f "$codex_log_file"
  fail "调用 codex 失败：当前 CLI 既不支持可用的 'exec -o' 流程，也不支持 '--input/--output' 流程。"
}

contributors_markdown() {
  local range="$1"
  local out=""
  while IFS=$'\t' read -r commit_count author_name author_email; do
    [[ -n "${commit_count:-}" ]] || continue
    local display_name="$author_name"
    if [[ -z "$display_name" && -n "$author_email" ]]; then
      display_name="${author_email%@*}"
    fi
    display_name="${display_name:-unknown}"

    if [[ -z "$out" ]]; then
      out="- @${display_name} (${commit_count} 次提交)"
    else
      out="${out}"$'\n'"- @${display_name} (${commit_count} 次提交)"
    fi
  done < <(
    git -C "$root_dir" shortlog -sne --format='%an%x09%ae' "$range" | awk '
      {
        count=$1
        $1=""
        sub(/^ +/, "", $0)
        name=$0
        email=""
        if (match(name, / <[^>]+>$/)) {
          email=substr(name, RSTART+2, RLENGTH-3)
          name=substr(name, 1, RSTART-1)
        }
        printf "%s\t%s\t%s\n", count, name, email
      }
    '
  )
  if [[ -n "$out" ]]; then
    printf '%s\n' "$out"
  else
    printf '%s\n' "- 无"
  fi
}

ensure_git_repo

if [[ "${1:-}" == "-h" ]] || [[ "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

old_ref=""
new_ref=""
output_file=""
raw_output_file=""
final_stdout_mode="false"
created_raw_tmp="false"
created_final_tmp="false"

case "$#" in
  0)
    resolve_default_range
    ;;
  1)
    output_file="$1"
    resolve_default_range
    ;;
  2)
    old_ref="$1"
    new_ref="$2"
    ;;
  3)
    old_ref="$1"
    new_ref="$2"
    output_file="$3"
    ;;
  *)
    usage
    exit 1
    ;;
esac

[[ -n "$old_ref" && -n "$new_ref" ]] || fail "未能确定版本范围。"
ref_exists "$old_ref" || fail "旧版本引用不存在: $old_ref"
ref_exists "$new_ref" || fail "新版本引用不存在: $new_ref"

old_commit="$(git -C "$root_dir" rev-parse "$old_ref")"
new_commit="$(git -C "$root_dir" rev-parse "$new_ref")"
[[ "$old_commit" != "$new_commit" ]] || fail "两个版本引用指向同一个提交，没有可分析的变更。"

range="${old_ref}..${new_ref}"
commit_total="$(git -C "$root_dir" rev-list --count "$range")"
[[ "$commit_total" -gt 0 ]] || fail "版本范围 ${range} 内没有提交记录。"

stats_line="$(git -C "$root_dir" diff --shortstat "$old_ref" "$new_ref" | sed 's/^ *//')"
files_changed="$(printf '%s\n' "$stats_line" | sed -n 's/.*\([0-9][0-9]*\) files\? changed.*/\1/p')"
insertions="$(printf '%s\n' "$stats_line" | sed -n 's/.*\([0-9][0-9]*\) insertions\?(+).*/\1/p')"
deletions="$(printf '%s\n' "$stats_line" | sed -n 's/.*\([0-9][0-9]*\) deletions\?(-).*/\1/p')"
files_changed="${files_changed:-0}"
insertions="${insertions:-0}"
deletions="${deletions:-0}"

contributor_total="$(git -C "$root_dir" shortlog -s "$range" | awk 'NF{count++} END{print count+0}')"
contributors_md="$(contributors_markdown "$range")"

commit_list="$(git -C "$root_dir" log --reverse --no-merges --format='- `%h` | %ad | %an | %s' --date=short "$range")"
if [[ -z "$commit_list" ]]; then
  commit_list="- 无（该范围只有合并提交）"
fi

commit_list_all="$(git -C "$root_dir" log --reverse --format='- `%h` | %ad | %an | %s' --date=short "$range")"

changed_files="$(git -C "$root_dir" diff --name-status "$old_ref" "$new_ref" | awk '{print "- `" $1 "` " $2}')"
if [[ -z "$changed_files" ]]; then
  changed_files="- 无"
fi

top_files="$(git -C "$root_dir" log --name-only --pretty=format: "$range" \
  | sed '/^$/d' \
  | sort \
  | uniq -c \
  | sort -nr \
  | head -n 20 \
  | awk '{count=$1; $1=""; sub(/^ +/, "", $0); printf "- `%s` (%d 次)\n", $0, count}')"
if [[ -z "$top_files" ]]; then
  top_files="- 无"
fi

report=""
report="${report}# 版本区间原始变更数据"$'\n\n'
report="${report}> 说明：本文件为原始输入，供大模型生成最终发布说明。"$'\n'
report="${report}> 版本范围：\`${old_ref}\` -> \`${new_ref}\`"$'\n'
report="${report}> 提交范围：\`${range}\`"$'\n\n'

report="${report}## 统计信息"$'\n'
report="${report}- 提交总数：${commit_total}"$'\n'
report="${report}- 变更文件数：${files_changed}"$'\n'
report="${report}- 代码行数变化：+${insertions} / -${deletions}"$'\n'
report="${report}- 贡献者数量：${contributor_total}"$'\n\n'

report="${report}## 贡献者"$'\n'
report="${report}${contributors_md}"$'\n\n'

report="${report}## 提交列表（不含 merge）"$'\n'
report="${report}${commit_list}"$'\n\n'

report="${report}## 提交列表（含 merge）"$'\n'
report="${report}${commit_list_all}"$'\n\n'

report="${report}## 变更文件（name-status）"$'\n'
report="${report}${changed_files}"$'\n\n'

report="${report}## 高频变更文件 TOP 20"$'\n'
report="${report}${top_files}"$'\n'

raw_output_file="${RELEASE_NOTES_RAW_OUTPUT_FILE:-}"
if [[ -z "$raw_output_file" ]]; then
  raw_output_file="$(mktemp "${TMPDIR:-/tmp}/release-notes-raw.XXXXXX.md")"
  created_raw_tmp="true"
fi

if [[ -z "$output_file" ]]; then
  output_file="$(mktemp "${TMPDIR:-/tmp}/release-notes-final.XXXXXX.md")"
  created_final_tmp="true"
  final_stdout_mode="true"
else
  mkdir -p "$(dirname "$output_file")"
fi

cleanup_tmp_files() {
  if [[ "$created_raw_tmp" == "true" && "$KEEP_RAW_INPUT" != "true" && -f "$raw_output_file" ]]; then
    rm -f "$raw_output_file"
  fi
  if [[ "$created_final_tmp" == "true" && "$KEEP_FINAL_TMP" != "true" && -f "$output_file" ]]; then
    rm -f "$output_file"
  fi
}
trap cleanup_tmp_files EXIT

printf '%s' "$report" > "$raw_output_file"
run_codex_compat "$raw_output_file" "$output_file"

if [[ "$final_stdout_mode" == "true" ]]; then
  cat "$output_file"
fi
