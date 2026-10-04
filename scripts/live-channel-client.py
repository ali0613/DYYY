# 电脑端：读写设备上 DYYY 实时通道（自动扫描端口 8899-8908）
#
#   python dyyy_live.py state                       读当前诊断 + 参数
#   python dyyy_live.py set cell=1 extra=-83        下发参数（立即生效）
#   python dyyy_live.py set cell=0                  关闭该处补偿
#   python dyyy_live.py clear                       清空诊断缓冲
#   python dyyy_live.py watch                       实时刷新（只在变化时打印）
#   python dyyy_live.py ping
#
# 参数：cell（0关/1按屏幕/2按表格）overlay（0旧逻辑/1满高）player（0关/1开）
#       tablepad（0关/1开）extra（附加点数，正负皆可）
import sys
import time
import urllib.request

DEVICE = "192.168.1.19"
PORTS = range(8899, 8909)
_cached_port = None


def _try(port, path, timeout=4):
    url = "http://%s:%d%s" % (DEVICE, port, path)
    with urllib.request.urlopen(url, timeout=timeout) as response:
        return response.read().decode("utf-8", "replace")


def discover(force=False):
    global _cached_port
    if _cached_port and not force:
        try:
            _try(_cached_port, "/ping", timeout=3)
            return _cached_port
        except Exception:
            _cached_port = None
    for port in PORTS:
        try:
            if _try(port, "/ping", timeout=2).strip() == "ok":
                _cached_port = port
                return port
        except Exception:
            continue
    raise RuntimeError("在 %s 的 %s 上都没找到 DYYY 实时通道（确认诊断开关已打开、抖音已重启）"
                       % (DEVICE, "8899-8908"))


def get(path, timeout=8):
    port = discover()
    try:
        return _try(port, path, timeout)
    except Exception:
        port = discover(force=True)
        return _try(port, path, timeout)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "state"

    if cmd == "ping":
        print("port %d -> %s" % (discover(), get("/ping").strip()))
    elif cmd == "state":
        print(get("/state"))
    elif cmd == "clear":
        print(get("/clear"))
    elif cmd == "set":
        query = "&".join(sys.argv[2:])
        if not query:
            print("用法: set cell=1 overlay=1 player=1 tablepad=1 extra=0")
            return
        print(get("/set?" + query))
    elif cmd == "watch":
        last = None
        while True:
            try:
                text = get("/state")
                if text != last:
                    print("\n==== %s ====" % time.strftime("%H:%M:%S"))
                    print(text)
                    last = text
            except Exception as exc:
                print("(连接失败: %s)" % exc)
            time.sleep(1.0)
    else:
        print(__doc__ or "用法: state | set k=v ... | clear | ping | watch")


main()
