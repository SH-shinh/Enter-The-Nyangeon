#!/usr/bin/env python3
"""按 mod 版本聚合中继日志的带宽 / 踢人统计。

版本来源：客户端在 create_room / join_room 控制帧里上报 `ver` / `proto`
（老客户端不带这两个字段，统一记为 "-"），服务端写进
`[STATS]` / `[BACKPRESSURE]` / `[PROBE]` / `created by` 日志。

用法：
  journalctl -u etn-relay --since '7 days ago' --no-pager | python3 relay_stats_by_version.py
  python3 relay_stats_by_version.py '7 days ago'     # 由本脚本自己调 journalctl

输出：按版本分组的 Markdown 表（会话数、peer 分钟数、上下行分位与峰值、
缓冲峰值、踢人次数与踢人率）。
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections import defaultdict

STATS_NEW = re.compile(
    r"\[STATS\] room=(\S+) peer=(\d+) role=(\w+) ver=(\S+) proto=(\d+) "
    r"rx=([\d.]+)KB/s tx=([\d.]+)KB/s buffered_max=(\d+)KB"
)
STATS_OLD = re.compile(
    r"\[STATS\] room=(\S+) peer=(\d+) role=(\w+) "
    r"rx=([\d.]+)KB/s tx=([\d.]+)KB/s buffered_max=(\d+)KB"
)
# 版本字段前缀必须是独立单词，避免 `over=20.0s` 被 `ver=` 误匹配
VER = r"(?<![A-Za-z0-9_])ver=(\S+)"
KICK_NEW = re.compile(r"\[BACKPRESSURE\].*?" + VER)
KICK_OLD = re.compile(r"\[BACKPRESSURE\]")
JOIN_NEW = re.compile(r"\[PROBE\] join_room accepted:.*?" + VER)
JOIN_OLD = re.compile(r"\[PROBE\] join_room accepted:")
CREATE_NEW = re.compile(r"\] created by .*?" + VER)
CREATE_OLD = re.compile(r"\] created by .*?; host peer_id=")


def read_text() -> str:
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        # 支持直接喂一个已保存的日志文件（离线分析），否则当作 journalctl 的 --since
        try:
            if os.path.isfile(arg):
                with open(arg, "r", encoding="utf-8", errors="replace") as fh:
                    return fh.read()
        except OSError:
            pass
        return subprocess.run(
            ["journalctl", "-u", "etn-relay", "--since", arg, "--no-pager"],
            capture_output=True, text=True,
        ).stdout
    return sys.stdin.read()


def pct(values: list[float], q: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    idx = min(len(ordered) - 1, int(len(ordered) * q))
    return ordered[idx]


def main() -> int:
    text = read_text()
    if not text.strip():
        print("没有输入；用 journalctl ... | python3 relay_stats_by_version.py")
        return 1

    sessions: dict[str, int] = defaultdict(int)
    peer_minutes: dict[str, int] = defaultdict(int)
    tx: dict[str, list[float]] = defaultdict(list)
    rx: dict[str, list[float]] = defaultdict(list)
    buf_max: dict[str, int] = defaultdict(int)
    kicks: dict[str, int] = defaultdict(int)

    for line in text.splitlines():
        m = STATS_NEW.search(line)
        ver = None
        if m:
            ver, rx_kb, tx_kb, buf = m.group(4), float(m.group(6)), float(m.group(7)), int(m.group(8))
        else:
            m2 = STATS_OLD.search(line)
            if m2:
                ver, rx_kb, tx_kb, buf = "-", float(m2.group(4)), float(m2.group(5)), int(m2.group(6))
        if ver is not None:
            peer_minutes[ver] += 1
            tx[ver].append(tx_kb)
            rx[ver].append(rx_kb)
            buf_max[ver] = max(buf_max[ver], buf)
            continue
        k = KICK_NEW.search(line)
        if k:
            kicks[k.group(1)] += 1
            continue
        if KICK_OLD.search(line):
            kicks["-"] += 1
            continue
        j = JOIN_NEW.search(line)
        if j:
            sessions[j.group(1)] += 1
            continue
        if JOIN_OLD.search(line):
            sessions["-"] += 1
            continue
        c = CREATE_NEW.search(line)
        if c:
            sessions[c.group(1)] += 1
            continue
        if CREATE_OLD.search(line):
            sessions["-"] += 1

    versions = sorted(set(list(peer_minutes) + list(kicks) + list(sessions)))
    if not versions:
        print("日志里没有可识别的 STATS/PROBE/BACKPRESSURE 行（是否还没有带 ver 的新客户端？）")
        return 1

    print("| 版本 | 会话数 | peer分钟 | tx p50 | tx p90 | tx p99 | tx max | rx p90 | 缓冲峰值 | 踢人 | 踢人率 |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for ver in versions:
        s = sessions.get(ver, 0)
        k = kicks.get(ver, 0)
        rate = f"{k / s * 100:.1f}%" if s else "-"
        print(
            "| {ver} | {s} | {pm} | {tx50:.1f} | {tx90:.1f} | {tx99:.1f} | {txmax:.1f} | "
            "{rx90:.1f} | {buf} KB | {k} | {rate} |".format(
                ver=ver, s=s, pm=peer_minutes.get(ver, 0),
                tx50=pct(tx.get(ver, []), 0.50), tx90=pct(tx.get(ver, []), 0.90),
                tx99=pct(tx.get(ver, []), 0.99),
                txmax=max(tx.get(ver, [0.0])), rx90=pct(rx.get(ver, []), 0.90),
                buf=buf_max.get(ver, 0), k=k, rate=rate,
            )
        )
    print("\n注：tx/rx 单位为 KB/s（服务端按 bytes/1024 计算，即 KiB/s）；"
          "踢人率 = 踢人数 / 会话数。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
