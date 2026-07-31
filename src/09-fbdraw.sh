# ============================================================
# Framebuffer 绘制模块（Python 脚本嵌入 shell，无需外部文件）
# ============================================================

FB_PY="/tmp/.wpi-fbdraw.py"
FB_DEV="/dev/fb0"
FB_FIFO="/tmp/.wpi-fb-fifo"
FB_DAEMON_PID="/tmp/.wpi-fb-daemon.pid"
FB_READY="/tmp/.wpi-fb-ready"
FB_STATE_FILE="/tmp/.wpi-fb-state"
FB_TIMER_PID="/tmp/.wpi-fb-timer.pid"
FB_TIMER_TS="/tmp/.wpi-fb-timer-ts"

fb_init() {
    # 检查依赖
    if ! python3 -c "import numpy,cv2" 2>/dev/null; then
        echo "fbdraw: numpy or cv2 not available, fb mode disabled"
        return 1
    fi
    [[ -e $FB_DEV ]] || { echo "fbdraw: $FB_DEV not found"; return 1; }

    # 清理旧文件
    rm -f "$FB_FIFO" "$FB_READY"
    mkfifo "$FB_FIFO"

    # 写入嵌入的 Python daemon 脚本
    cat > "$FB_PY" << 'PYEOF'
#!/usr/bin/env python3
"""fbdraw daemon - persistent framebuffer renderer"""
import sys, os, mmap, signal, base64
import numpy as np
import cv2
from pathlib import Path

BG_RGB = (32, 24, 16)
M = 32
FIFO_PATH = "/tmp/.wpi-fb-fifo"
READY_FILE = "/tmp/.wpi-fb-ready"
FB_DEV = "/dev/fb0"

class FBDaemon:
    def __init__(self):
        # 读取 fb 参数
        base = Path(f"/sys/class/graphics/{Path(FB_DEV).name}")
        fw, fh = map(int, (base/"virtual_size").read_text().strip().split(","))
        self.bpp = int((base/"bits_per_pixel").read_text().strip())
        sp = base / "stride"
        self.fb_stride = int(sp.read_text().strip()) if sp.exists() else fw * self.bpp // 8
        self.fw, self.fh = fw, fh
        self.vw, self.vh = fh, fw          # 90° 旋转后的可视尺寸

        # 打开 fb mmap（常驻）
        self.fb_fd = os.open(FB_DEV, os.O_RDWR)
        self.buf = mmap.mmap(self.fb_fd, self.fb_stride * self.fh,
                             mmap.MAP_SHARED, mmap.PROT_WRITE)

        # canvas
        self.img = np.zeros((self.vh, self.vw, 3), dtype=np.uint8)

        # 状态
        self.progress = 0
        self.status   = ""
        self.count    = 0
        self.total    = 1
        self.from_ver = ""
        self.to_ver   = ""
        self.elapsed  = 0
        self.mode     = "normal"   # "normal" | "error"
        self.fail_list = ""

        # 信号处理
        self.running = True
        signal.signal(signal.SIGTERM, lambda *_: setattr(self, 'running', False))
        signal.signal(signal.SIGINT,  lambda *_: setattr(self, 'running', False))

    # ------------------------------------------------------------------
    # 全帧绘制
    # ------------------------------------------------------------------
    def _draw_frame(self):
        """完整重绘整帧并写入 fb"""
        self.img[:] = BG_RGB

        if self.mode == "error":
            self._draw_error_page()
        else:
            self._draw_normal_page()

        self._write_full_fb()

    def _draw_normal_page(self):
        m, vw, vh = M, self.vw, self.vh
        tip_y = vh - m

        # --- 标题 ---
        title = "WalnutPi"
        (tw, th), _ = cv2.getTextSize(title, cv2.FONT_HERSHEY_DUPLEX, 2.0, 3)
        title_y = m + 56
        cv2.putText(self.img, title, (m, title_y),
                    cv2.FONT_HERSHEY_DUPLEX, 2.0, (255, 180, 40), 3)
        if self.from_ver or self.to_ver:
            cv2.putText(self.img, f"  {self.from_ver}  ->  {self.to_ver}",
                        (m + tw + 12, title_y),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.65, (160, 160, 160), 2)

        # --- 进度条 ---
        bh = 28
        bx, by, bw = m, vh // 2 - 68, vw - 2 * m
        cv2.rectangle(self.img, (bx, by), (bx + bw, by + bh), (50, 50, 50), -1)
        fill = int(bw * self.progress / 100)
        if fill > 0:
            cv2.rectangle(self.img, (bx, by), (bx + fill, by + bh),
                          (0, int(130 + self.progress * 0.8), 0), -1)

        # --- 状态文本 ---
        sy = vh // 2
        if self.status:
            s = self.status
            (sw, _), _ = cv2.getTextSize(s, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 1)
            max_w = vw - 2 * m
            while sw > max_w and len(s) > 4:
                s = s[:-4] + "..."
                (sw, _), _ = cv2.getTextSize(s, cv2.FONT_HERSHEY_SIMPLEX, 0.7, 1)
            cv2.putText(self.img, s, (m, sy),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.7, (150, 150, 150), 1)

        # --- 包计数 ---
        if self.count > 0:
            cv2.putText(self.img, f"[ {self.count} / {self.total} ]", (m, sy + 45),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.0, (200, 200, 200), 2)

        # --- 计时器（始终显示，包括 00:00） ---
        ts = f"{self.elapsed // 60:02d}:{self.elapsed % 60:02d}"
        (twe, the), _ = cv2.getTextSize(ts, cv2.FONT_HERSHEY_SIMPLEX, 0.9, 2)
        cv2.putText(self.img, ts, (vw - m - twe, tip_y - 30),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.9, (160, 160, 160), 2)

        # --- 底部分隔线 + 警告 ---
        cv2.line(self.img, (m, tip_y - 26), (vw - m, tip_y - 26), (55, 55, 55), 1)
        cv2.putText(self.img, "Do not power off or disconnect", (m, tip_y - 6),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (90, 90, 90), 1)

    def _draw_error_page(self):
        m, vw, vh = M, self.vw, self.vh
        tip_y = vh - m

        fail_items = [x.strip() for x in self.fail_list.strip().split("\n") if x.strip()]

        fail_title = "UPDATE FAILED"
        (ftw, fth), _ = cv2.getTextSize(fail_title, cv2.FONT_HERSHEY_DUPLEX, 1.2, 2)
        cv2.putText(self.img, fail_title, (vw // 2 - ftw // 2, vh // 2 - 40),
                    cv2.FONT_HERSHEY_DUPLEX, 1.2, (200, 60, 40), 2)

        sub = "The following packages failed after 3 retries:"
        (sw, sh), _ = cv2.getTextSize(sub, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
        cv2.putText(self.img, sub, (vw // 2 - sw // 2, vh // 2),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (160, 160, 160), 1)

        max_show = 6
        list_y = vh // 2 + 28
        for i, item in enumerate(fail_items[:max_show]):
            cv2.putText(self.img, f"  {item}", (m + 20, list_y + i * 24),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (220, 100, 80), 1)
        if len(fail_items) > max_show:
            cv2.putText(self.img, f"  ... and {len(fail_items) - max_show} more",
                        (m + 20, list_y + max_show * 24),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.5, (160, 160, 160), 1)

        hint = "Please check network and run again."
        (hw, hh), _ = cv2.getTextSize(hint, cv2.FONT_HERSHEY_SIMPLEX, 0.6, 1)
        cv2.putText(self.img, hint, (vw // 2 - hw // 2, tip_y - 50),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (140, 140, 140), 1)

        cv2.line(self.img, (m, tip_y - 26), (vw - m, tip_y - 26), (55, 55, 55), 1)
        cv2.putText(self.img, "Do not power off or disconnect", (m, tip_y - 6),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (90, 90, 90), 1)

    # ------------------------------------------------------------------
    # 全帧写入 fb
    # ------------------------------------------------------------------
    def _write_full_fb(self):
        rotated = cv2.rotate(self.img, cv2.ROTATE_90_CLOCKWISE)
        if self.bpp == 16:
            r = rotated[:,:,2].astype(np.uint16)
            g = rotated[:,:,1].astype(np.uint16)
            b = rotated[:,:,0].astype(np.uint16)
            pix = ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)
            raw = pix.tobytes()
            ps = pix.shape[1] * 2
            ph = pix.shape[0]
        elif self.bpp == 24:
            raw = rotated.tobytes()
            ps = rotated.shape[1] * 3
            ph = rotated.shape[0]
        else:
            pad = np.zeros(rotated.shape[:2], dtype=np.uint8)
            pix = np.dstack([rotated, pad])
            raw = pix.tobytes()
            ps = pix.shape[1] * 4
            ph = pix.shape[0]

        if ps == self.fb_stride:
            self.buf[:len(raw)] = raw
        else:
            for row in range(ph):
                so = row * ps
                do = row * self.fb_stride
                self.buf[do:do + ps] = raw[so:so + ps]

    # ------------------------------------------------------------------
    # 指令处理（全部走全帧重绘）
    # ------------------------------------------------------------------
    def cmd_full(self, payload):
        """F progress|status|count|total|fv|tv|elapsed"""
        parts = payload.split("|")
        if len(parts) < 7:
            return
        self.mode     = "normal"
        self.progress = int(parts[0])
        self.status   = parts[1]
        self.count    = int(parts[2])
        self.total    = int(parts[3])
        self.from_ver = parts[4]
        self.to_ver   = parts[5]
        self.elapsed  = int(parts[6])
        self._draw_frame()

    def cmd_error(self, payload):
        """E base64_fail_list|fv|tv"""
        parts = payload.split("|", 2)
        if len(parts) < 1:
            return
        try:
            self.fail_list = base64.b64decode(parts[0]).decode("utf-8")
        except Exception:
            self.fail_list = parts[0]
        self.from_ver = parts[1] if len(parts) > 1 else ""
        self.to_ver   = parts[2] if len(parts) > 2 else ""
        self.mode = "error"
        self._draw_frame()

    # ------------------------------------------------------------------
    # 主循环
    # ------------------------------------------------------------------
    def run(self):
        # 先画首帧（空状态），然后发送 ready 信号
        self._draw_frame()
        Path(READY_FILE).touch()

        while self.running:
            try:
                fd = os.open(FIFO_PATH, os.O_RDONLY)
            except InterruptedError:
                continue
            except FileNotFoundError:
                break

            with os.fdopen(fd, 'r') as f:
                for line in f:
                    line = line.rstrip('\n')
                    if not line:
                        continue
                    if line == 'Q':
                        self.running = False
                        break
                    sp = line.find(' ')
                    cmd = line[:sp] if sp > 0 else line
                    payload = line[sp + 1:] if sp > 0 else ''
                    if cmd == 'F':
                        self.cmd_full(payload)
                    elif cmd == 'E':
                        self.cmd_error(payload)

        # cleanup
        self.buf.close()
        os.close(self.fb_fd)

if __name__ == "__main__":
    FBDaemon().run()
PYEOF
    chmod +x "$FB_PY"

    # 后台启动 daemon
    python3 "$FB_PY" &
    echo $! > "$FB_DAEMON_PID"

    # 等待 daemon 初始化完成（至多 30 秒）
    for _ in $(seq 1 150); do
        if [[ -f $FB_READY ]]; then
            break
        fi
        sleep 0.2
    done
    rm -f "$FB_READY"

    return 0
}

fb_render() {
    [[ -f $FB_PY ]] || return
    # 保存状态供背景定时器使用
    echo "${1:-0}|${2:-}|${3:-0}|${4:-1}|${5:-}|${6:-}" > "$FB_STATE_FILE"
    local elapsed="${7:-0}"
    # 如果未显式传入 elapsed 且计时器已启动，自动计算
    if [[ ${elapsed} -eq 0 ]] && [[ -f $FB_TIMER_TS ]]; then
        local start_ts
        start_ts=$(cat "$FB_TIMER_TS")
        elapsed=$(( $(date +%s) - start_ts ))
        [[ ${elapsed} -lt 0 ]] && elapsed=0
    fi
    echo "F ${1:-0}|${2:-}|${3:-0}|${4:-1}|${5:-}|${6:-}|${elapsed}" > "$FB_FIFO" 2>/dev/null
}

fb_render_error() {
    [[ -f $FB_PY ]] || return
    local encoded
    encoded=$(echo -n "${1:-}" | base64 -w0 2>/dev/null || echo -n "${1:-}" | base64)
    echo "E ${encoded}|${2:-}|${3:-}" > "$FB_FIFO" 2>/dev/null
}

# 启动背景计时器：每 0.5s 读取状态文件 + 已用秒数，发送全帧刷新指令
# 参数: $1 = 父进程 PID（父进程退出后定时器自动停止）
fb_timer_start() {
    local parent_pid=$1
    local start_ts
    start_ts=$(date +%s)
    echo "$start_ts" > "$FB_TIMER_TS"
    {
        while kill -0 "$parent_pid" 2>/dev/null; do
            local e
            e=$(( $(date +%s) - start_ts ))
            if [[ -f $FB_STATE_FILE ]]; then
                IFS='|' read -r prog status count total fv tv < "$FB_STATE_FILE"
                echo "F ${prog:-0}|${status:-}|${count:-0}|${total:-1}|${fv:-}|${tv:-}|${e}" > "$FB_FIFO" 2>/dev/null
            fi
            sleep 0.5
        done
    } &
    echo $! > "$FB_TIMER_PID"
}

fb_timer_stop() {
    [[ -f $FB_TIMER_PID ]] && kill "$(cat "$FB_TIMER_PID")" 2>/dev/null
    rm -f "$FB_TIMER_PID" "$FB_STATE_FILE" "$FB_TIMER_TS"
}

fb_cleanup() {
    fb_timer_stop
    # 通知 daemon 退出
    echo "Q" > "$FB_FIFO" 2>/dev/null
    # 等待 daemon 退出，超时强制 kill
    if [[ -f $FB_DAEMON_PID ]]; then
        local dp waited=0
        dp=$(cat "$FB_DAEMON_PID")
        while kill -0 "$dp" 2>/dev/null && [[ $waited -lt 30 ]]; do
            sleep 0.1
            waited=$((waited + 1))
        done
        kill "$dp" 2>/dev/null
    fi
    rm -f "$FB_PY" "$FB_FIFO" "$FB_DAEMON_PID" "$FB_READY"
}
