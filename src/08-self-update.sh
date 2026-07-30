# ============================================================
# 自更新
# ============================================================
self_update() {
    wget -q -c "$THIS_SCRIPT_URL" -O "$THIS_SCRIPT_SAVE" || {
        echo_red "get updates ... [error]"
        exit 1
    }

    tar -xf "$THIS_SCRIPT_SAVE" -C /tmp || {
        echo_red "unzip the file ... [error]"
        exit 1
    }

    local new_ver
    new_ver=$(grep -o 'THIS_SCRIPT_VERSION=[0-9.]*' "$THIS_SCRIPT_FILE" | cut -d '=' -f 2)

    if version_gt "$new_ver" "$THIS_SCRIPT_VERSION"; then
        cp "$THIS_SCRIPT_FILE" "$0"
        exec bash "$0" no_update
    fi
}
