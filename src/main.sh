# ============================================================
# 主入口
# ============================================================
BOARD_MODEL=$(detect_board_model)
SOURCE_STR_WALNUTPI="deb [trusted=yes] http://${SERVER_DOMAIN}//debian/ bookworm ${BOARD_MODEL}"
SOURCE_STR_TSINGHUA="deb http://mirrors.tuna.tsinghua.edu.cn/debian bookworm main"
PATCH_LIST_URL="http://${SERVER_DOMAIN}/debian/patch-list/${BOARD_MODEL}.gz"

# 清理旧残留 / 写入 apt 源
rm -rf "$PATH_PATCH_LIST"
mkdir -p "$PATH_PATCH_LIST"
echo -e "$SOURCE_STR_WALNUTPI" > "$TMP_SOURCE_FILE_WPI"
echo -e "$SOURCE_STR_WALNUTPI" > "$TMP_SOURCE_FILE"
echo -e "$SOURCE_STR_TSINGHUA" >> "$TMP_SOURCE_FILE"

setup_i18n

# 删除 pip 的 EXTERNALLY-MANAGED 标记
find /usr/lib -type f -name "EXTERNALLY-MANAGED" -delete 2>/dev/null || true

# 权限检查
if [[ $EUID -ne 0 ]]; then
    echo -e "${STR[sudo_warn]}"
    exit 1
fi

COMMAND="${1:-}"

# 自更新
[[ $COMMAND != "no_update" ]] && self_update

# 子命令分发
case $COMMAND in
    -v)      cmd_version ;;
    -s)      cmd_server_version ;;
    -l)      cmd_log ;;
    install) cmd_install "${2:-}" ;;
    --fb)    do_update_fb "$@" ;;
    *)       do_update "$@" ;;
esac
