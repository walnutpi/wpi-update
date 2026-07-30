# ============================================================
# Release log 工具
# ============================================================
download_release_log() {
    local url="${1:-$LOG_URL}"
    rm -f "$FILE_LOG_SAVE"
    wget -q -c "$url" -O "$FILE_LOG_SAVE" || {
        echo_red "download release log ... [error]"
        exit 1
    }
}

# 从 release log 提取最新版本号
get_newest_version() {
    grep -o '\[[^]]*\] - [^ ]*' "$FILE_LOG_SAVE" | head -n 1 | awk '{print $3}'
}

# 从 release log 提取所有日期（从新到旧）
get_dates_from_log() {
    grep -o '\[[^]]*\]' "$FILE_LOG_SAVE" | tr -d '[]'
}

# 读取本地版本信息
load_local_version() {
    if [[ -f $RELEASE_FILE ]]; then
        BOARD_VER=$(grep '^version=' "$RELEASE_FILE" | cut -d '=' -f 2)
        BOARD_DATE=$(grep '^date=' "$RELEASE_FILE" | cut -d '=' -f 2)
        BOARD_OS_TYPE=$(grep '^os_type=' "$RELEASE_FILE" | cut -d '=' -f 2)
    else
        BOARD_VER="0"
        BOARD_DATE="1970-01-01"
        BOARD_OS_TYPE="bookworm"
    fi
}

# 检查是否需要更新，设置 HAS_NEW / NEW_VERSION / LAST_DATE
check_update() {
    local new_ver="$1"
    local local_date_secs
    local_date_secs=$(date -d"$BOARD_DATE" +%s 2>/dev/null || echo 0)

    local dates
    dates=$(get_dates_from_log)

    # 条件 A: 日期比较
    for d in $dates; do
        local d_secs
        d_secs=$(date -d"$d" +%s 2>/dev/null || echo 0)
        if (( d_secs > local_date_secs )); then
            HAS_NEW=yes
        fi
        if (( d_secs <= local_date_secs )); then
            LAST_DATE="$d"
            break
        fi
    done

    # 条件 B: 版本号比较
    if version_gt "$new_ver" "$BOARD_VER"; then
        HAS_NEW=yes
    fi
}

# 展示增量 changelog
show_changelog() {
    if [[ -n ${LAST_DATE:-} ]]; then
        sed -n "1,/\\[${LAST_DATE}\\]/p" "$FILE_LOG_SAVE" | sed '/\['"${LAST_DATE}"'\]/d'
    else
        cat "$FILE_LOG_SAVE"
    fi
}
