# ============================================================
# Framebuffer 绘制模块（Python 脚本嵌入 shell，无需外部文件）
# ============================================================

FB_PY="/tmp/.wpi-fbdraw.py"
FB_DEV="/dev/fb0"
FB_STATE_FILE="/tmp/.wpi-fb-state"
FB_TIMER_PID="/tmp/.wpi-fb-timer.pid"

fb_init() {
    # 检查依赖
    if ! python3 -c "import numpy,cv2" 2>/dev/null; then
        echo "fbdraw: numpy or cv2 not available, fb mode disabled"
        return 1
    fi
    [[ -e $FB_DEV ]] || { echo "fbdraw: $FB_DEV not found"; return 1; }

    # 写入嵌入的 Python 脚本到临时文件
    cat > "$FB_PY" << 'PYEOF'
#!/usr/bin/env python3
"""fbdraw - single-frame framebuffer renderer (embedded)"""
import sys,os,mmap,argparse
import numpy as np
import cv2
from pathlib import Path

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--progress", type=int, default=0)
    ap.add_argument("--status",  default="")
    ap.add_argument("--count",   type=int, default=0)
    ap.add_argument("--total",   type=int, default=1)
    ap.add_argument("--from-ver", default="")
    ap.add_argument("--to-ver",   default="")
    ap.add_argument("--fail-list", default="")
    ap.add_argument("--elapsed",  type=int, default=0)
    ap.add_argument("--fb-dev",   default="/dev/fb0")
    args = ap.parse_args()

    fb_dev = args.fb_dev
    base   = Path(f"/sys/class/graphics/{Path(fb_dev).name}")
    fw, fh = map(int, (base / "virtual_size").read_text().strip().split(","))
    bpp    = int((base / "bits_per_pixel").read_text().strip())
    sp     = base / "stride"
    fb_stride = int(sp.read_text().strip()) if sp.exists() else fw * bpp // 8

    vw, vh = fh, fw          # 旋转 90° 后的可视区域
    img    = np.zeros((vh, vw, 3), dtype=np.uint8)
    img[:] = (32, 24, 16)    # 底色
    m = 32

    # --- 标题：WalnutPi + 版本号（同一行） ---
    title = "WalnutPi"
    (tw, th), _ = cv2.getTextSize(title, cv2.FONT_HERSHEY_DUPLEX, 2.0, 3)
    title_y = m + 56
    cv2.putText(img, title, (m, title_y),
                cv2.FONT_HERSHEY_DUPLEX, 2.0, (255, 180, 40), 3)
    # 版本号跟在 WalnutPi 右侧，同基线
    if args.from_ver or args.to_ver:
        cv2.putText(img, f"  {args.from_ver}  ->  {args.to_ver}",
                    (m + tw + 12, title_y),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.65, (160, 160, 160), 2)

    # 底部警告位置（共用）
    tip_y = vh - m

    if args.fail_list:
        # ============================
        #  错误页面
        # ============================
        fail_items = [x.strip() for x in args.fail_list.strip().split("\n") if x.strip()]

        # 失败标题
        fail_title = "UPDATE FAILED"
        (ftw, fth), _ = cv2.getTextSize(fail_title, cv2.FONT_HERSHEY_DUPLEX, 1.2, 2)
        cv2.putText(img, fail_title, (vw // 2 - ftw // 2, vh // 2 - 40),
                    cv2.FONT_HERSHEY_DUPLEX, 1.2, (200, 60, 40), 2)

        # 副标题
        sub = "The following packages failed after 3 retries:"
        (sw, sh), _ = cv2.getTextSize(sub, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
        cv2.putText(img, sub, (vw // 2 - sw // 2, vh // 2),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (160, 160, 160), 1)

        # 失败包列表
        max_show = 6
        list_y = vh // 2 + 28
        for i, item in enumerate(fail_items[:max_show]):
            cv2.putText(img, f"  {item}", (m + 20, list_y + i * 24),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (220, 100, 80), 1)
        if len(fail_items) > max_show:
            cv2.putText(img, f"  ... and {len(fail_items) - max_show} more",
                        (m + 20, list_y + max_show * 24),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (160, 160, 160), 1)

        # 底部提示
        hint = "Please check network and run again."
        (hw, hh), _ = cv2.getTextSize(hint, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1)
        cv2.putText(img, hint, (vw // 2 - hw // 2, tip_y - 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (140, 140, 140), 1)

    else:
        # ============================
        #  正常进度页面
        # ============================
        # --- 进度条 ---
        bh = 28
        bx, by, bw = m, vh // 2 - 68, vw - 2 * m

        cv2.rectangle(img, (bx, by), (bx + bw, by + bh), (50, 50, 50), -1)
        fill = int(bw * args.progress / 100)
        if fill > 0:
            cv2.rectangle(img, (bx, by), (bx + fill, by + bh),
                          (0, int(130 + args.progress * 0.8), 0), -1)

        # --- 状态文本（垂直居中，超长自动截断） ---
        sy = vh // 2
        if args.status:
            s = args.status
            (sw, _), _ = cv2.getTextSize(s, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 1)
            max_w = vw - 2 * m
            while sw > max_w and len(s) > 4:
                s = s[:-4] + "..."
                (sw, _), _ = cv2.getTextSize(s, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 1)
            cv2.putText(img, s, (m, sy),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (150, 150, 150), 1)

        # 包计数
        if args.count > 0:
            cv2.putText(img, f"[ {args.count} / {args.total} ]", (m, sy + 45),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.0, (200, 200, 200), 2)

        # 已用时间（右下角，秒级刷新让用户感知程序在运行）
        if args.elapsed > 0:
            ts = f"{args.elapsed // 60:02d}:{args.elapsed % 60:02d}"
            (tw_ts, th_ts), _ = cv2.getTextSize(ts, cv2.FONT_HERSHEY_SIMPLEX, 0.9, 2)
            cv2.putText(img, ts, (vw - m - tw_ts, tip_y - 30),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.9, (160, 160, 160), 2)

    # --- 底部警告（两种页面共用） ---
    cv2.line(img, (m, tip_y - 26), (vw - m, tip_y - 26), (55, 55, 55), 1)
    cv2.putText(img, "Do not power off or disconnect", (m, tip_y - 6),
                cv2.FONT_HERSHEY_SIMPLEX, 0.55, (90, 90, 90), 1)

    # --- 旋转 90° 并写入 fb ---
    rotated = cv2.rotate(img, cv2.ROTATE_90_CLOCKWISE)

    if bpp == 16:
        r = rotated[:,:,2].astype(np.uint16)
        g = rotated[:,:,1].astype(np.uint16)
        b = rotated[:,:,0].astype(np.uint16)
        pix = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
    elif bpp == 24:
        pix = rotated
    else:
        pix = np.dstack([rotated, np.zeros(rotated.shape[:2], dtype=np.uint8)])

    raw = pix.tobytes()
    ph  = pix.shape[0]
    ps  = pix.shape[1] * bpp // 8

    fb = os.open(fb_dev, os.O_RDWR)
    buf = mmap.mmap(fb, fb_stride * fh, mmap.MAP_SHARED, mmap.PROT_WRITE)
    try:
        if ps == fb_stride:
            buf[:len(raw)] = raw
        else:
            for row in range(ph):
                so = row * ps
                do = row * fb_stride
                buf[do:do + ps] = raw[so:so + ps]
    finally:
        buf.close()
        os.close(fb)

if __name__ == "__main__":
    main()
PYEOF
    chmod +x "$FB_PY"
    return 0
}

fb_render() {
    [[ -f $FB_PY ]] || return
    # 保存状态供背景定时器每秒刷新使用
    echo "${1:-0}|${2:-}|${3:-0}|${4:-1}|${5:-}|${6:-}" > "$FB_STATE_FILE"
    python3 "$FB_PY" \
        --progress "${1:-0}" \
        --status   "${2:-}" \
        --count    "${3:-0}" \
        --total    "${4:-1}" \
        --from-ver "${5:-}" \
        --to-ver   "${6:-}" \
        --elapsed  "${7:-0}" \
        2>/dev/null
}

fb_render_error() {
    [[ -f $FB_PY ]] || return
    python3 "$FB_PY" \
        --fail-list "${1:-}" \
        --from-ver  "${2:-}" \
        --to-ver    "${3:-}" \
        2>/dev/null
}

# 启动背景计时器：每秒用最新状态 + 已用秒数重新绘制 fb
# 参数: $1 = 父进程 PID（父进程退出后定时器自动停止）
fb_timer_start() {
    local parent_pid=$1
    local start_ts
    start_ts=$(date +%s)
    {
        while kill -0 "$parent_pid" 2>/dev/null; do
            if [[ -f $FB_STATE_FILE ]]; then
                IFS='|' read -r prog status count total fv tv < "$FB_STATE_FILE"
                python3 "$FB_PY" \
                    --progress "${prog:-0}" \
                    --status   "${status:-}" \
                    --count    "${count:-0}" \
                    --total    "${total:-1}" \
                    --from-ver "${fv:-}" \
                    --to-ver   "${tv:-}" \
                    --elapsed  "$(( $(date +%s) - start_ts ))" \
                    2>/dev/null
            fi
            sleep 1
        done
    } &
    echo $! > "$FB_TIMER_PID"
}

fb_timer_stop() {
    [[ -f $FB_TIMER_PID ]] && kill "$(cat "$FB_TIMER_PID")" 2>/dev/null
    rm -f "$FB_TIMER_PID" "$FB_STATE_FILE"
}

fb_cleanup() {
    fb_timer_stop
    rm -f "$FB_PY"
}
