# ============================================================
# 工具函数
# ============================================================
cleanup() {
    rm -rf "$PATH_PATCH_LIST" "$THIS_SCRIPT_SAVE" "$THIS_SCRIPT_FILE" \
           "$TMP_SOURCE_FILE" "$TMP_SOURCE_FILE_WPI" \
           "$FILE_LOG_SAVE" "$FILE_PACKAGES" 2>/dev/null || true
}
trap cleanup EXIT

echo_red()    { echo -e "\r\033[31m$1\033[0m"; }
echo_green()  { echo -e "\r\033[32m$1\033[0m"; }

run_status() {
    local message="$1"
    shift
    echo -n "...	$message"
    local output
    output=$("$@" 2>&1) || {
        echo -e "\r\033[31m[error]\033[0m"
        echo "$output"
        exit 1
    }
    echo -e "\r\033[32m[ok]\033[0m	$message"
}

# 数字逐段比较版本号: $1 > $2 返回 0
version_gt() {
    local IFS=.
    local a=($1) b=($2)
    local i
    for ((i=0; i<${#a[@]} || i<${#b[@]}; i++)); do
        local av=${a[$i]:-0}
        local bv=${b[$i]:-0}
        (( av > bv )) && return 0
        (( av < bv )) && return 1
    done
    return 1
}
