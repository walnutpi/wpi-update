# ============================================================
# 子命令实现
# ============================================================
cmd_version() {
    echo "$THIS_SCRIPT_VERSION"
    exit 0
}

cmd_server_version() {
    download_release_log
    get_newest_version
    exit 0
}

cmd_log() {
    download_release_log
    load_local_version
    local local_date_secs=0
    [[ "$BOARD_DATE" != "1970-01-01" ]] && local_date_secs=$(date -d"$BOARD_DATE" +%s 2>/dev/null || echo 0)

    local last=""
    local dates
    dates=$(get_dates_from_log)
    for d in $dates; do
        local d_secs
        d_secs=$(date -d"$d" +%s 2>/dev/null || echo 0)
        if (( d_secs <= local_date_secs )); then
            last="$d"
            break
        fi
    done

    if [[ -n $last ]]; then
        sed -n "1,/\\[${last}\\]/p" "$FILE_LOG_SAVE" | sed '/\['"${last}"'\]/d'
    else
        cat "$FILE_LOG_SAVE"
    fi
    exit 0
}

cmd_install() {
    local pkg="${1:-}"
    echo -e "$SOURCE_STR_WALNUTPI" > "$TMP_SOURCE_FILE_WPI"
    echo -e "$SOURCE_STR_WALNUTPI" > "$TMP_SOURCE_FILE"
    echo -e "$SOURCE_STR_TSINGHUA" >> "$TMP_SOURCE_FILE"

    run_status "get the package info ..." apt-get update \
        -o Dir::Etc::sourcelist="$TMP_SOURCE_FILE_WPI" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0"

    apt-get install \
        -o Dir::Etc::sourcelist="$TMP_SOURCE_FILE" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0" \
        $pkg
    exit 0
}
