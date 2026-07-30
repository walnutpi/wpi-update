# ============================================================
# 检测板卡型号
# ============================================================
detect_board_model() {
    local model=""
    if [ -f /proc/device-tree/model ]; then
        model=$(tr -d '\0' < /proc/device-tree/model)
    elif [ -f /etc/model ]; then
        model=$(tr -d '\0' < /etc/model)
    elif [ -f /tmp/walnutpi-board_model ]; then
        model=$(tr -d '\0' < /tmp/walnutpi-board_model)
    fi
    echo "${model,,}"  # 转小写
}
