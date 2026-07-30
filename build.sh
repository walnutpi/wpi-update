#!/bin/bash
# build.sh - 将 src/ 下分散的模块合并为单个 wpi-update 脚本
set -euo pipefail

cd "$(dirname "$0")"

output="${1:-wpi-update}"
src_dir="src"

> "$output"

# 收集文件列表：编号文件按序排列，main.sh 始终在最后
files=()
for f in "$src_dir"/[0-9][0-9]-*.sh; do
    [[ -f $f ]] && files+=("$f")
done
[[ -f "$src_dir/main.sh" ]] && files+=("$src_dir/main.sh")

first=true
for f in "${files[@]}"; do
    if $first; then
        cat "$f" >> "$output"           # 第一个文件原样保留（含 shebang）
        first=false
    else
        # 后续文件跳过 shebang（如果有），保留其余内容
        if head -n 1 "$f" | grep -q '^#!'; then
            tail -n +2 "$f" >> "$output"
        else
            cat "$f" >> "$output"
        fi
        echo "" >> "$output"            # 文件间空行分隔
    fi
done

chmod +x "$output"

bash -n "$output" && echo "[build] OK → $output ($(wc -l < "$output") lines)"
