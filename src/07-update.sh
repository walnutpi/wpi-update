# ============================================================
# 主更新流程
# ============================================================
do_update() {
    if [[ $* =~ -[yY] ]] && [[ $BOARD_MODEL == *cybercam* ]]; then
        local self_path
        self_path=$(readlink -f "$0")
        if command -v systemd-run >/dev/null 2>&1; then
            # 以临时系统服务运行，彻底脱离登录会话，终端断开不影响更新
            systemd-run --unit=wpi-update-fb --collect --quiet \
                --description="wpi-update (fb mode)" "$self_path" --fb
        else
            # 退化方案：独立会话 + 忽略 SIGHUP + 脱离终端标准流
            setsid nohup "$self_path" --fb </dev/null >/dev/null 2>&1 &
        fi
        exit 1
    fi

    # 阶段 1: 版本检测
    load_local_version
    download_release_log
    NEW_VERSION=$(get_newest_version)

    HAS_NEW=""
    LAST_DATE=""
    check_update "$NEW_VERSION"

    # -N 强制更新
    [[ $* =~ -N ]] && HAS_NEW=yes

    if [[ -z $HAS_NEW ]]; then
        printf "${STR[newest]}" "$BOARD_VER"
        exit 0
    fi

    # 阶段 2: 展示与确认
    clear
    echo -e "[${BOARD_VER}] -> \033[32m[${NEW_VERSION}]\033[0m"
    echo -e "${STR[backup_warn]}"
    show_changelog
    echo -n "${STR[are_u_ready]} "

    if [[ $* =~ -[yY] ]]; then
        echo ""
    else
        read -p "[Y/n]" CHOICE
        if [[ "$CHOICE" != "y" && "$CHOICE" != "Y" ]]; then
            echo -e "${STR[abort]}."
            exit 1
        fi
    fi

    # 阶段 3: 执行更新
    mkdir -p "$PATH_PATCH_LIST"
    cd "$PATH_PATCH_LIST"

    local source_file="$TMP_SOURCE_FILE"
    local source_file_wpi="$TMP_SOURCE_FILE_WPI"

    run_status "download the package list" wget -q "$PATCH_LIST_URL" -O list.gz
    run_status "unzip the package list"   tar -xf list.gz
    run_status "apt-get update" apt-get update \
        -o Dir::Etc::sourcelist="$source_file" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0"

    # 批量收集要操作的包
    local del_list=() add_list=() upgrade_list=()

    # 缓存 dpkg 已安装列表
    local installed
    installed=$(dpkg -l | awk '/^ii/ {print $2}')

    # 删除废弃包
    local del_file="del-${BOARD_OS_TYPE}"
    if [[ -f $del_file ]]; then
        while IFS= read -r pkg; do
            [[ -z $pkg ]] && continue
            echo "$installed" | grep -qxF "$pkg" && del_list+=("$pkg")
        done < "$del_file"
    fi

    # 安装新增包
    local add_file="add-${BOARD_OS_TYPE}"
    if [[ -f $add_file ]]; then
        while IFS= read -r pkg; do
            [[ -z $pkg ]] && continue
            echo "$installed" | grep -qxF "$pkg" || add_list+=("$pkg")
        done < "$add_file"
    fi

    # 获取可升级包
    local pkgs
    pkgs=$(apt-get --just-print upgrade \
        -o Dir::Etc::sourcelist="$source_file_wpi" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0" 2>/dev/null \
        | grep '^Inst' | cut -d ' ' -f 2)
    for pkg in $pkgs; do
        upgrade_list+=("$pkg")
    done

    # 批量执行
    local total=$(( ${#del_list[@]} + ${#add_list[@]} + ${#upgrade_list[@]} ))
    local count=0

    apt_do() {
        local verb="$1"
        local cmd="$2"
        shift 2
        [[ $# -eq 0 ]] && return
        count=$((count + $#))
        echo "[${count}/${total}] $verb: $*"
        apt-get "$cmd" -y \
            -o Dir::Etc::sourcelist="$source_file" \
            -o Dir::Etc::sourceparts="-" \
            -o APT::Get::List-Cleanup="0" \
            "$@"
    }

    apt_do remove  remove  "${del_list[@]:-}"
    apt_do add     install "${add_list[@]:-}"
    apt_do update  install "${upgrade_list[@]:-}"

    # 写回版本信息
    local new_date
    new_date=$(grep -o '\[[^]]*\]' "$FILE_LOG_SAVE" | head -n 1 | tr -d '[]')

    if [[ -f $RELEASE_FILE ]]; then
        sed -i "s/^version=.*/version=$NEW_VERSION/" "$RELEASE_FILE"
        sed -i "s/^date=.*/date=$new_date/" "$RELEASE_FILE"
    else
        cat > "$RELEASE_FILE" <<EOF
version=$NEW_VERSION
date=$new_date
os_type=$BOARD_OS_TYPE
EOF
    fi

    echo_green "\n\n【OK】please reboot"
}

# --fb 模式：所有进度通过 framebuffer 绘制，不输出到终端
do_update_fb() {
    if ! fb_init; then
        echo "fbdraw init failed, falling back to terminal mode..."
        do_update "$@"
        return
    fi

    if systemctl is-active --quiet cybercam-desktop.service; then
        systemctl stop cybercam-desktop.service
    fi

    # 启动背景计时器（每秒在画面上刷新已用时间，让用户感知程序在运行）
    fb_timer_start $$

    # === 前期准备（全部在 0% 完成，不推进进度条） ===
    fb_render 0 "Preparing update..." 0 1

    load_local_version
    download_release_log
    NEW_VERSION=$(get_newest_version)

    HAS_NEW=""
    LAST_DATE=""
    check_update "$NEW_VERSION"

    [[ $* =~ -N ]] && HAS_NEW=yes

    if [[ -z $HAS_NEW ]]; then
        fb_render 100 "Already up-to-date" 1 1 "$BOARD_VER" "$BOARD_VER"
        fb_cleanup
        exit 0
    fi

    mkdir -p "$PATH_PATCH_LIST"
    cd "$PATH_PATCH_LIST"

    local source_file="$TMP_SOURCE_FILE"
    local source_file_wpi="$TMP_SOURCE_FILE_WPI"

    wget -q "$PATCH_LIST_URL" -O list.gz || {
        fb_render 0 "Download failed" 0 1 "$BOARD_VER" "$NEW_VERSION"
        fb_cleanup
        exit 1
    }
    tar -xf list.gz

    apt-get update \
        -o Dir::Etc::sourcelist="$source_file" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0" 2>/dev/null

    # 收集包列表
    local del_list=() add_list=() upgrade_list=()

    local installed
    installed=$(dpkg -l | awk '/^ii/ {print $2}')

    local del_file="del-${BOARD_OS_TYPE}"
    if [[ -f $del_file ]]; then
        while IFS= read -r pkg; do
            [[ -z $pkg ]] && continue
            echo "$installed" | grep -qxF "$pkg" && del_list+=("$pkg")
        done < "$del_file"
    fi

    local add_file="add-${BOARD_OS_TYPE}"
    if [[ -f $add_file ]]; then
        while IFS= read -r pkg; do
            [[ -z $pkg ]] && continue
            echo "$installed" | grep -qxF "$pkg" || add_list+=("$pkg")
        done < "$add_file"
    fi

    local pkgs
    pkgs=$(apt-get --just-print upgrade \
        -o Dir::Etc::sourcelist="$source_file_wpi" \
        -o Dir::Etc::sourceparts="-" \
        -o APT::Get::List-Cleanup="0" 2>/dev/null \
        | grep '^Inst' | cut -d ' ' -f 2)
    for pkg in $pkgs; do
        upgrade_list+=("$pkg")
    done

    local total=$(( ${#del_list[@]} + ${#add_list[@]} + ${#upgrade_list[@]} ))
    if [[ $total -eq 0 ]]; then
        fb_render 100 "Nothing to do" 0 0 "$BOARD_VER" "$NEW_VERSION"
        fb_cleanup
        exit 0
    fi

    # === 收集每个包的大小（用于按体积加权进度） ===
    fb_render 0 "Computing package sizes..." 0 1 "$BOARD_VER" "$NEW_VERSION"

    declare -A pkg_size
    local total_size=0

    get_size() {
        local sz
        # apt-cache 获取下载大小（install/upgrade 包）
        sz=$(apt-cache show "$1" 2>/dev/null | grep "^Size:" | head -1 | awk '{print $2}')
        if [[ -z $sz ]]; then
            # dpkg 获取已安装大小（remove 包，单位 KB）
            sz=$(dpkg -s "$1" 2>/dev/null | grep "^Installed-Size:" | head -1 | awk '{print $2}')
            [[ -n $sz ]] && sz=$(( sz * 1024 ))
        fi
        echo "${sz:-1048576}"
    }

    for pkg in "${del_list[@]}" "${add_list[@]}" "${upgrade_list[@]}"; do
        local sz
        sz=$(get_size "$pkg")
        pkg_size["$pkg"]=$sz
        total_size=$(( total_size + sz ))
    done
    [[ $total_size -eq 0 ]] && total_size=1

    # === 逐包处理（带重试，任一包失败则立即退出） ===
    local count=0
    local done_size=0

    pkg_do() {
        local verb="$1" cmd="$2" pkg="$3"
        local attempt=0
        local ok=0

        # apt 执行前先绘制当前包信息，让用户立即知道在处理什么
        local curr_pct=$(( done_size * 100 / total_size ))
        fb_render "$curr_pct" "[$verb] $pkg" "$(( count + 1 ))" "$total" \
            "$BOARD_VER" "$NEW_VERSION"

        while [[ $attempt -lt 3 ]]; do
            attempt=$(( attempt + 1 ))

            if apt-get "$cmd" -y \
                -o Dir::Etc::sourcelist="$source_file" \
                -o Dir::Etc::sourceparts="-" \
                -o APT::Get::List-Cleanup="0" \
                "$pkg" 2>/dev/null; then
                ok=1
                break
            fi

            [[ $attempt -lt 3 ]] && sleep 2
        done

        if [[ $ok -eq 0 ]]; then
            fb_render_error "$verb  $pkg" "$BOARD_VER" "$NEW_VERSION"
            fb_cleanup
            exit 1
        fi

        count=$(( count + 1 ))
        done_size=$(( done_size + ${pkg_size["$pkg"]:-1048576} ))
        local pct=$(( done_size * 100 / total_size ))
        [[ $pct -gt 99 ]] && pct=99
        fb_render "$pct" "[$verb] $pkg" "$count" "$total" \
            "$BOARD_VER" "$NEW_VERSION"
    }

    for pkg in "${del_list[@]}"; do
        pkg_do "Remove"  remove  "$pkg"
    done
    for pkg in "${add_list[@]}"; do
        pkg_do "Install" install "$pkg"
    done
    for pkg in "${upgrade_list[@]}"; do
        pkg_do "Upgrade" install "$pkg"
    done

    # === 全部成功，收尾 ===
    fb_render 99 "Writing version info..." "$count" "$total" \
        "$BOARD_VER" "$NEW_VERSION"

    local new_date
    new_date=$(grep -o '\[[^]]*\]' "$FILE_LOG_SAVE" | head -n 1 | tr -d '[]')

    if [[ -f $RELEASE_FILE ]]; then
        sed -i "s/^version=.*/version=$NEW_VERSION/" "$RELEASE_FILE"
        sed -i "s/^date=.*/date=$new_date/" "$RELEASE_FILE"
    else
        cat > "$RELEASE_FILE" <<EOF
version=$NEW_VERSION
date=$new_date
os_type=$BOARD_OS_TYPE
EOF
    fi

    fb_render 100 "Update complete. rebooting ......" "$count" "$total" \
        "$BOARD_VER" "$NEW_VERSION"
    fb_cleanup
    reboot
}

