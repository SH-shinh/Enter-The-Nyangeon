#!/usr/bin/env python3
import asyncio
import base64
import hashlib
import json
import os
import random
import socket
import struct
import time
from dataclasses import dataclass, field

try:
    # 房间码随机源必须是密码学安全随机数（原 random.choice 用 Mersenne Twister，可由少量输出预测）。
    # 标准库必然自带 secrets，此处 try 仅为极端裁剪环境留回退路径（回退仍保持 4 字符与既有字母表）。
    import secrets

    _secure_choice = secrets.choice
except ImportError:  # pragma: no cover
    _secure_choice = random.choice


PORT = int(os.environ.get("PORT", "7716"))
RELAY_BIND_ADDRESS = os.environ.get("RELAY_BIND_ADDRESS", "0.0.0.0")
MAX_CLIENTS_PER_ROOM = int(os.environ.get("MAX_CLIENTS_PER_ROOM", "3"))
ROOM_TIMEOUT_MS = int(os.environ.get("ROOM_TIMEOUT_MS", str(30 * 60 * 1000)))
HEADER_SIZE = 4
MAX_PLAYERS_PER_ROOM = 4
# 分级背压水位：软水位先给宽限并继续写可靠帧，硬水位或宽限超时再断开慢端。
# 2026-11-19 现网实测：256KB / 5s 会把下行较慢的客户端反复踢掉——房间 X7CH 一局内被踢 18 次，
# 积压 0.65–2.5MB，每次重连 5–8s 后又被踢；房间 863Y 的主机也因 650KB 积压被踢，房间直接销毁。
# 故放宽默认值，并全部改为环境变量可调（内存代价：4 人房最坏 4×16MB）。
WRITE_SOFT_WATER = int(os.environ.get("RELAY_WRITE_SOFT_WATER", str(2 * 1024 * 1024)))
WRITE_HARD_WATER = int(os.environ.get("RELAY_WRITE_HARD_WATER", str(16 * 1024 * 1024)))
WRITE_GRACE_SEC = float(os.environ.get("RELAY_WRITE_GRACE_SEC", "20"))
# host 卡顿时整房都会断：给 host 更长的宽限期，避免一次 20s 停顿直接毁掉房间
WRITE_GRACE_SEC_HOST = float(os.environ.get("RELAY_WRITE_GRACE_SEC_HOST", "60"))
# 带宽遥测打印间隔（秒）：定位「谁在灌、灌多少」，用于后续降低同步量。
STATS_INTERVAL_SEC = float(os.environ.get("RELAY_STATS_INTERVAL_SEC", "60"))
COMPACT_THRESHOLD = 65536
DEBUG = os.environ.get("RELAY_DEBUG", "").strip().lower() in ("1", "true", "yes", "on")
# 连接级心跳：客户端约每 1s 有游戏数据/心跳包，超过该阈值无任何数据即判定半开连接并回收。
PEER_TIMEOUT_MSEC = int(os.environ.get("PEER_TIMEOUT_MSEC", "20000"))
HEARTBEAT_INTERVAL_SEC = float(os.environ.get("HEARTBEAT_INTERVAL_SEC", "5"))
# 与 CoopRelayPeer._get_max_packet_size 的 16 MiB 契约一致，另加目标 peer 头。
MAX_FRAME_BYTES = (1 << 24) + HEADER_SIZE
MAX_BUFFER_BYTES = MAX_FRAME_BYTES + 65536 + 14
# 读 HTTP Upgrade 头的时限：从 TCP 被 accept 后起算（DNS/TCP 连接时间不计入）。移动链路抖动大，
# 原来 10s 会在客户端 30s 握手预算（CONNECT_TIMEOUT_MSEC）用完之前先掐断，客机只能看到 STATE_CLOSED
# 并提示 "Relay connection failed"，拿不到原因，故 2026-11-05 放宽到 30s；仍可用环境变量回压
# （该值同时是「慢连接占用 socket 的上限」）。
HTTP_HANDSHAKE_TIMEOUT_SEC = float(os.environ.get("HTTP_HANDSHAKE_TIMEOUT_SEC", "30"))
# WS 已建好却仍未 join_room 的连接时限：服务端兜底，须 ≥ 客户端 JOIN_HANDSHAKE_TIMEOUT_MSEC(30s)。
JOIN_TIMEOUT_SEC = float(os.environ.get("JOIN_TIMEOUT_SEC", "35"))
FRAME_TIMEOUT_SEC = 30.0
WRITE_TIMEOUT_SEC = 5.0
# 准入兜底：join_room 已被接受、停在 Room.pending 等 client_ready 的连接。这一段不能只靠无数据超时
# 回收——服务端每 HEARTBEAT_INTERVAL_SEC 发一次 PING，客户端自动回 PONG 会刷新 last_seen，卡死但
# TCP 还活着的客机会长期占位；而 pending 计入房间容量（见 join_room 的 max_clients 判断），别人
# 会看到 "Room full"。该时限从 join_room 被接受起算，client_ready 到达（admitted=True）后失效。
ADMIT_TIMEOUT_SEC = float(os.environ.get("ADMIT_TIMEOUT_SEC", "30"))
# 资源上限：房间总数与在线连接总数，超限拒绝新建（环境变量可配，默认按单机小规模中继估算）。
MAX_ROOMS = int(os.environ.get("MAX_ROOMS", "256"))
MAX_TOTAL_CLIENTS = int(os.environ.get("MAX_TOTAL_CLIENTS", "512"))
# WRITE_OVERFLOW_LIMIT 已退役：可靠帧不能容忍跳过，改为分级水位——软水位给宽限、硬水位或宽限超时再断开慢端。
# join 失败（房间不存在）限速：窗口内每连接/每 IP 的失败次数上限，超限进入冷却。
JOIN_FAIL_WINDOW_SEC = float(os.environ.get("JOIN_FAIL_WINDOW_SEC", "60"))
MAX_JOIN_FAILS_PER_PEER = int(os.environ.get("MAX_JOIN_FAILS_PER_PEER", "8"))
MAX_JOIN_FAILS_PER_IP = int(os.environ.get("MAX_JOIN_FAILS_PER_IP", "40"))
JOIN_BLOCK_SEC = float(os.environ.get("JOIN_BLOCK_SEC", "30"))
# 汇总日志：每 SUMMARY_INTERVAL_SEC 一条 [SUMMARY]（房间/连接/总流量/踢人次数）
SUMMARY_INTERVAL_SEC = float(os.environ.get("RELAY_SUMMARY_INTERVAL_SEC", "300"))
# 建房限速：正常玩家一局只建一次；下列上限只挡"建房重试死循环"与脚本
CREATE_WINDOW_SEC = float(os.environ.get("RELAY_CREATE_WINDOW_SEC", "60"))
MAX_CREATE_PER_IP = int(os.environ.get("RELAY_MAX_CREATE_PER_IP", "5"))
MAX_ROOMS_PER_IP = int(os.environ.get("RELAY_MAX_ROOMS_PER_IP", "3"))
# 软水位持续该秒数后先下发 shed 劝降（新客户端可据此降载），而不是直接等宽限超时踢人
SHED_ADVISE_SEC = float(os.environ.get("RELAY_SHED_ADVISE_SEC", "5"))
SHED_TTL_MS = int(os.environ.get("RELAY_SHED_TTL_MS", "3000"))
# 房间存活不足该秒数即被销毁 → 记 [ROOM CHURN]，用于发现客户端"建房即断"重试循环
ROOM_CHURN_SEC = float(os.environ.get("RELAY_ROOM_CHURN_SEC", "5"))
# 服务端公网带宽声明：客户端据此计算自身发送预算（LAN 不走中继，不受影响）。
# 按控制台实际带宽填 RELAY_LINK_MBPS；REL.../1000/8/1.024 换算成 KiB/s，再留 reserve 给重传与控制帧。
LINK_MBPS = float(os.environ.get("RELAY_LINK_MBPS", "3"))
LINK_RESERVE_PCT = float(os.environ.get("RELAY_LINK_RESERVE_PCT", "12"))
LINK_EGRESS_KIB = LINK_MBPS * 1000.0 / 8.0 / 1.024 * (1.0 - LINK_RESERVE_PCT / 100.0)
# 每个房间能分到的最小出口；房间数变化时按房间数分摊，避免多房各自按整条链路抢带宽
MIN_ROOM_EGRESS_KIB = float(os.environ.get("RELAY_MIN_ROOM_EGRESS_KIB", "80"))
# 最低协议版本：旧客户端（无预算/压缩）会把共享链路打满，直接拒绝入境
MIN_PROTO = int(os.environ.get("RELAY_MIN_PROTO", "13"))
_last_budget_kib = 0.0


def room_egress_kib() -> float:
    n = max(1, len(rooms))
    return max(MIN_ROOM_EGRESS_KIB, LINK_EGRESS_KIB / n)

rooms = {}
connected_peers: set["Peer"] = set()
# 每 IP 的 join 失败时间戳（滑动窗口）；仅保留窗口内的记录，条目在无近期失败时被回收。
ip_join_fails: dict[str, list[float]] = {}
# 每 IP 的建房时间戳（滑动窗口），用于建房限速
ip_create_times: dict[str, list[float]] = {}
# 汇总窗口计数器（[SUMMARY] 输出后清零）
stat_rx_bytes = 0
stat_tx_bytes = 0
stat_kicks_bp = 0
stat_kicks_timeout = 0


def debug_log(*args):
    if DEBUG:
        print(*args, flush=True)


@dataclass(eq=False)
class Peer:
    reader: asyncio.StreamReader
    writer: asyncio.StreamWriter
    room: "Room | None" = None
    role: str = ""
    id: int = 0
    name: str = ""
    buffer: bytearray = field(default_factory=bytearray)
    read_pos: int = 0
    admitted: bool = False
    token: str = ""
    last_seen: float = 0.0
    connected_at: float = field(default_factory=time.monotonic)
    frame_started: float | None = None
    # join_room 被接受（进入 Room.pending）的时刻；client_ready 前用于 ADMIT_TIMEOUT_SEC 兜底。
    joined_at: float | None = None
    # 背压：首次超过软水位的时刻（monotonic，0.0 表示未超）；超过宽限仍未回落才断开。
    over_since: float = 0.0
    # 对端 IP（握手后取 peername），用于每 IP 的 join 限速
    ip: str = ""
    # join 失败时间戳（滑动窗口）与冷却截止点（monotonic），用于每连接限速
    join_fails: list[float] = field(default_factory=list)
    join_blocked_until: float = 0.0
    # 带宽遥测：累计收发字节 + 每个统计窗口的基线（用于算 KB/s）+ 写缓冲峰值
    rx_bytes: int = 0
    tx_bytes: int = 0
    buffered_max: int = 0
    stats_at: float = 0.0
    stats_rx: int = 0
    stats_tx: int = 0
    # 客户端上报的 mod 版本（create_room/join_room 携带；老客户端不带时保持 "-"）。
    # 写进 [STATS]/[BACKPRESSURE]/[DISCONNECT]，用于按版本聚合带宽与踢人率。
    ver: str = "-"
    proto: int = 0
    # 已下发的劝降档位（0=未劝降；1/2 对应 shed level）
    shed_level: int = 0
    # 已通告给房主的拥塞档位（0/1/2）；房主据此对该客机停发视觉
    congest_level: int = 0


@dataclass
class Room:
    code: str
    host: Peer | None
    clients: set[Peer] = field(default_factory=set)
    pending: set[Peer] = field(default_factory=set)
    next_peer_id: int = 2
    last_active: float = field(default_factory=lambda: time.time() * 1000)
    # 建房者 IP（每 IP 并发房间配额用）与创建时刻（[ROOM CHURN] 用）
    owner_ip: str = ""
    created_at: float = field(default_factory=time.monotonic)
    # 房主离开且无客机时置位；cleanup_rooms 用它兜底回收（正常情况下 remove_peer 已立即删除）
    empty_since: float = 0.0


def ws_accept_key(key: str) -> str:
    guid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
    digest = hashlib.sha1((key + guid).encode("ascii")).digest()
    return base64.b64encode(digest).decode("ascii")


def encode_frame(opcode: int, payload: bytes = b"") -> bytes:
    length = len(payload)
    first = 0x80 | opcode

    if length < 126:
        header = bytes([first, length])
    elif length <= 0xFFFF:
        header = bytes([first, 126]) + struct.pack(">H", length)
    else:
        header = bytes([first, 127]) + struct.pack(">Q", length)

    return header + payload


def try_parse_frame(peer: Peer):
    buffer = peer.buffer
    start = peer.read_pos
    if len(buffer) - start < 2:
        return None

    opcode = buffer[start] & 0x0F
    masked = (buffer[start + 1] & 0x80) != 0
    length = buffer[start + 1] & 0x7F
    offset = start + 2

    if length == 126:
        if len(buffer) < offset + 2:
            return None
        length = struct.unpack_from(">H", buffer, offset)[0]
        offset += 2
    elif length == 127:
        if len(buffer) < offset + 8:
            return None
        length = struct.unpack_from(">Q", buffer, offset)[0]
        offset += 8

    if length > MAX_FRAME_BYTES:
        raise ValueError("frame too large")
    if opcode in (0x8, 0x9, 0xA) and length > 125:
        raise ValueError("control frame too large")

    mask = None
    if masked:
        if len(buffer) < offset + 4:
            return None
        mask = bytes(buffer[offset : offset + 4])
        offset += 4

    if len(buffer) < offset + length:
        return None

    payload = bytes(buffer[offset : offset + length])
    peer.read_pos = offset + length

    if masked and mask is not None and payload:
        value = int.from_bytes(payload, "big") ^ int.from_bytes(
            (mask * ((len(payload) + 3) // 4))[: len(payload)], "big"
        )
        payload = value.to_bytes(len(payload), "big")

    return opcode, payload


def compact_buffer(peer: Peer):
    pos = peer.read_pos
    if pos <= 0:
        return
    if pos >= COMPACT_THRESHOLD or pos * 2 >= len(peer.buffer):
        del peer.buffer[:pos]
        peer.read_pos = 0


def peer_avg_rate_kb(peer: Peer) -> tuple[float, float]:
    """连接建立以来的平均收发速率（KB/s），用于背压/断开时归因是谁在灌。"""
    elapsed = max(0.001, time.monotonic() - peer.connected_at)
    return peer.rx_bytes / elapsed / 1024.0, peer.tx_bytes / elapsed / 1024.0


async def send(peer: Peer, opcode: int, payload: bytes = b"") -> bool:
    """写入一帧，且绝不等待 drain（避免慢 peer 拖住广播/心跳）。

    分级背压：超过软水位先记录时刻并继续写入（给瞬时突发一个宽限窗口），
    持续超过 WRITE_GRACE_SEC 仍未回落、或直接超过硬水位，才断开慢端。
    控制帧与游戏 RPC 都依赖可靠有序传输，禁止跳帧后继续发送、制造静默状态分叉。
    返回 True 表示帧已排入传输缓冲，False 表示该连接已失败。
    """
    writer = peer.writer
    if writer.is_closing():
        return False
    global stat_tx_bytes, stat_kicks_bp
    transport = writer.transport
    if transport is not None:
        buffered = transport.get_write_buffer_size()
        if buffered > peer.buffered_max:
            peer.buffered_max = buffered
        if buffered >= WRITE_HARD_WATER:
            rx_kb, tx_kb = peer_avg_rate_kb(peer)
            stat_kicks_bp += 1
            print(
                f"[BACKPRESSURE] closing peer={peer.id or '?'} role={peer.role or '?'} ver={peer.ver} "
                f"buffered={buffered} hard rx={rx_kb:.1f}KB/s tx={tx_kb:.1f}KB/s",
                flush=True,
            )
            print_backpressure_ctx(peer)
            writer.close()
            return False
        if buffered >= WRITE_SOFT_WATER:
            now = time.monotonic()
            grace = WRITE_GRACE_SEC_HOST if peer.role == "host" else WRITE_GRACE_SEC
            if peer.over_since == 0.0:
                peer.over_since = now

            held: float = now - peer.over_since
            if held >= grace:
                rx_kb, tx_kb = peer_avg_rate_kb(peer)
                stat_kicks_bp += 1
                print(
                    f"[BACKPRESSURE] closing peer={peer.id or '?'} role={peer.role or '?'} ver={peer.ver} "
                    f"buffered={buffered} over={now - peer.over_since:.1f}s "
                    f"rx={rx_kb:.1f}KB/s tx={tx_kb:.1f}KB/s",
                    flush=True,
                )
                print_backpressure_ctx(peer)
                writer.close()
                return False
            elif held >= SHED_ADVISE_SEC:
                # 软水位持续：先劝降（新客户端据此下调视觉发送量），宽限期到点才踢。
                # 5s → level1；10s（两倍）→ level2。只在档位提升时下发，避免刷帧。
                if peer.role == "host" and not getattr(peer, "host_stall_logged", False):
                    peer.host_stall_logged = True
                    print(
                        f"[HOST STALL] room={peer.room.code if peer.room else '-'} buf={buffered} "
                        f"held={held:.1f}s",
                        flush=True,
                    )
                want_level = 2 if held >= SHED_ADVISE_SEC * 2.0 else 1
                if want_level > peer.shed_level:
                    # 先置位避免 send_control 递归进入本分支再次下发
                    peer.shed_level = want_level
                    await send_control(peer, {"type": "shed", "level": want_level, "ttl_ms": SHED_TTL_MS})
                await _notify_peer_congested(peer, want_level)
        else:
            peer.over_since = 0.0
            peer.shed_level = 0
            await _notify_peer_congested(peer, 0)
    frame = encode_frame(opcode, payload)
    writer.write(frame)
    peer.tx_bytes += len(frame)
    stat_tx_bytes += len(frame)
    return True


async def send_control(peer: Peer, message: dict):
    payload = json.dumps(message, separators=(",", ":")).encode("utf-8")
    debug_log(
        f"[SEND CONTROL] peer={peer.id or '?'} role={peer.role or '?'} "
        f"room={peer.room.code if peer.room else '-'} "
        f"type={message.get('type')} payload={message}"
    )
    await send(peer, 0x1, payload)

async def send_data(peer: Peer, sender_id: int, payload: bytes):
    packet = struct.pack("<i", sender_id) + payload
    await send(peer, 0x2, packet)


async def _notify_peer_congested(peer: "Peer", level: int) -> None:
    """把慢客机的拥塞档位通告给房主：host 对 level>=2 的 peer 停发视觉，状态/事件照发。
    只对客机通告、档位变化才发，避免刷帧。"""
    if peer.role != "client" or peer.room is None or peer.room.host is None:
        return
    host = peer.room.host
    if host is peer or host.writer.is_closing():
        return
    if peer.congest_level == level:
        return
    peer.congest_level = level
    print(f"[PEER_STATE] room={peer.room.code} peer={peer.id or '?'} level={level}", flush=True)
    await send_control(host, {"type": "peer_congested", "peer": peer.id or 0, "level": level})


def print_backpressure_ctx(kickee: Peer) -> None:
    """踢人前打印同房间**所有** peer 的实时状态。

    排查经验：如果同房其它 peer 的 buf 接近 0，说明是"被踢者自己的链路慢"；如果所有 peer
    同时堆积，才是服务器出口打满。没有这条对照，日志里只看得到被踢者。
    """
    room = kickee.room
    if room is None:
        return
    parts = []
    for peer in sorted(room_peers(room), key=lambda p: p.id or 0):
        transport = peer.writer.transport
        buffered = transport.get_write_buffer_size() if transport is not None else 0
        rx_kb, tx_kb = peer_avg_rate_kb(peer)
        parts.append(
            f"peer={peer.id or '?'} ver={peer.ver} role={peer.role or '?'} "
            f"tx={tx_kb:.1f}KB/s rx={rx_kb:.1f}KB/s buf={buffered // 1024}KB"
        )
    print(
        f"[BACKPRESSURE_CTX] room={room.code} kickee={kickee.id or '?'} | " + " | ".join(parts),
        flush=True,
    )


def room_peers(room: Room) -> list[Peer]:
    peers = []
    if room.host:
        peers.append(room.host)
    peers.extend(room.clients)
    return peers


def all_peers(room: Room) -> list[Peer]:
    # 含 pending（join_room 后尚未 client_ready 的连接）：心跳/清理/同 token 去重都要覆盖
    peers = room_peers(room)
    peers.extend(room.pending)
    return peers


def alloc_peer_id(room: Room) -> int:
    # 复用已释放的 peer id（含 pending/clients），避免重复加入把 id 一直往后推
    used = {p.id for p in all_peers(room) if p.id > 0}
    pid = 2
    while pid in used:
        pid += 1
    return pid


async def route_packet(peer: Peer, payload: bytes):
    if len(payload) <= HEADER_SIZE or peer.room is None:
        return

    peer.room.last_active = time.time() * 1000
    target_id = struct.unpack("<i", payload[:HEADER_SIZE])[0]
    game_payload = payload[HEADER_SIZE:]
    peers = room_peers(peer.room)

    if target_id == 0:
        # return_exceptions=True：任一接收者发送异常只影响该 peer，不再中断整条广播链
        await asyncio.gather(*(
            send_data(receiver, peer.id, game_payload)
            for receiver in peers
            if receiver.id != peer.id
        ), return_exceptions=True)
        return

    if target_id < 0:
        excluded_id = abs(target_id)
        await asyncio.gather(*(
            send_data(receiver, peer.id, game_payload)
            for receiver in peers
            if receiver.id != peer.id and receiver.id != excluded_id
        ), return_exceptions=True)
        return

    for receiver in peers:
        if receiver.id == target_id:
            await send_data(receiver, peer.id, game_payload)
            return


def generate_room_code() -> str:
    # 字母表与长度（4 字符）保持不变：UI 输入框与用户习惯已固定，只是把随机源换成
    # 密码学安全的 _secure_choice，消除「房间码可预测 → 可被抢先加入 / 枚举」的问题。
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for _ in range(1000):
        code = "".join(_secure_choice(alphabet) for _ in range(4))
        if code not in rooms:
            return code
    raise RuntimeError("room code exhausted")


def _prune_join_fails(stamps: list[float], now: float) -> list[float]:
    """只保留 JOIN_FAIL_WINDOW_SEC 窗口内的失败时间戳。"""
    cutoff = now - JOIN_FAIL_WINDOW_SEC
    return [ts for ts in stamps if ts > cutoff]


def _prune_ip_join_fails(now: float):
    """回收窗口外的每 IP 记录，避免字典被一次性扫描的地址撑大。"""
    for ip in list(ip_join_fails):
        stamps = _prune_join_fails(ip_join_fails[ip], now)
        if stamps:
            ip_join_fails[ip] = stamps
        else:
            ip_join_fails.pop(ip, None)


def join_block_reason(peer: Peer) -> str:
    """返回当前拒绝 join 的原因（"" 表示放行）。

    房间码空间只有 20 bit，必须限制失败尝试：每连接与每 IP 各自维护滑动窗口，
    窗口内失败次数超限即拒绝。正常用户即便手输错码也远不会到达阈值。
    """
    now = time.monotonic()
    if peer.join_blocked_until > now:
        return "peer"
    peer.join_fails = _prune_join_fails(peer.join_fails, now)
    if len(peer.join_fails) >= MAX_JOIN_FAILS_PER_PEER:
        return "peer"
    if peer.ip:
        stamps = _prune_join_fails(ip_join_fails.get(peer.ip, []), now)
        if stamps:
            ip_join_fails[peer.ip] = stamps
        else:
            ip_join_fails.pop(peer.ip, None)
        if len(stamps) >= MAX_JOIN_FAILS_PER_IP:
            return "ip"
    return ""


def record_join_fail(peer: Peer):
    """记录一次失败的 join 尝试（房间不存在）；连接级超限时进入冷却。"""
    now = time.monotonic()
    peer.join_fails = _prune_join_fails(peer.join_fails, now)
    peer.join_fails.append(now)
    if peer.ip:
        if len(ip_join_fails) > 4096:
            _prune_ip_join_fails(now)
        stamps = _prune_join_fails(ip_join_fails.get(peer.ip, []), now)
        stamps.append(now)
        ip_join_fails[peer.ip] = stamps
    if len(peer.join_fails) >= MAX_JOIN_FAILS_PER_PEER:
        peer.join_blocked_until = now + JOIN_BLOCK_SEC


async def handle_control(peer: Peer, payload: bytes):
    raw_text = payload.decode("utf-8", errors="replace")
    debug_log(
        f"[RECV TEXT] peer={peer.id or '?'} role={peer.role or '?'} "
        f"room={peer.room.code if peer.room else '-'} raw={raw_text}"
    )

    try:
        message = json.loads(raw_text)
    except Exception as exc:
        print(f"[PROTOCOL ERROR] Invalid JSON: {exc}", flush=True)
        await send_control(peer, {"type": "error", "message": "Invalid JSON"})
        return

    msg_type = str(message.get("type") or "")
    debug_log(
        f"[RECV CONTROL] peer={peer.id or '?'} type={msg_type!r} "
        f"keys={list(message.keys())} payload={message}"
    )
    name = str(message.get("player_name") or "Player")[:24]
    token = str(message.get("token") or "")[:64]
    # 版本上报（可选字段，老客户端不带）：只用于日志聚合，不参与任何准入判断
    ver = str(message.get("ver") or "-")[:16]
    try:
        proto = int(message.get("proto") or 0)
    except (TypeError, ValueError):
        proto = 0

    if msg_type == "create_room":
        if proto < MIN_PROTO:
            print(f"[REJECT] outdated create_room ver={ver} proto={proto} min={MIN_PROTO} ip={peer.ip or '-'}", flush=True)
            await send_control(peer, {"type": "error", "message": f"Outdated mod: require proto>={MIN_PROTO}"})
            return
        if peer.room:
            await send_control(peer, {"type": "error", "message": "Already in room"})
            return

        # 建房限速：正常玩家一局只建一次。窗口内超频或并发房间过多 → 拒绝
        # （复用既有 error 类型，不关连接，客户端可自行退避重试）。
        ip = peer.ip or "-"
        now_mono = time.monotonic()
        stamps = [t for t in ip_create_times.get(ip, []) if now_mono - t <= CREATE_WINDOW_SEC]
        ip_create_times[ip] = stamps
        active_rooms = sum(1 for r in rooms.values() if r.owner_ip == ip)
        if len(stamps) >= MAX_CREATE_PER_IP or active_rooms >= MAX_ROOMS_PER_IP:
            print(
                f"[CREATE LIMIT] reject create_room ip={ip} window={len(stamps)}/{MAX_CREATE_PER_IP} "
                f"active={active_rooms}/{MAX_ROOMS_PER_IP}",
                flush=True,
            )
            await send_control(peer, {"type": "error", "message": "Too many rooms"})
            return
        stamps.append(now_mono)

        # 房间总数上限：防止无限建房把 rooms 撑爆（空房回收逻辑保持不变）。
        if len(rooms) >= MAX_ROOMS:
            print(
                f"[ROOM LIMIT] reject create_room: rooms={len(rooms)} >= {MAX_ROOMS}",
                flush=True,
            )
            await send_control(peer, {"type": "error", "message": "Server full"})
            return

        code = generate_room_code()
        room = Room(code=code, host=peer)
        room.owner_ip = ip
        rooms[code] = room
        peer.room = room
        peer.role = "host"
        peer.id = 1
        peer.name = name
        peer.token = token
        peer.admitted = True
        peer.ver = ver
        peer.proto = proto

        print(f"[{code}] created by {name} ver={ver} proto={proto}; host peer_id=1", flush=True)
        await send_control(peer, {
            "type": "room_created",
            "room_code": code,
            "peer_id": 1,
            "link_mbps": LINK_MBPS,
            "egress_kib": round(room_egress_kib(), 1),
        })
        return

    if msg_type == "join_room":
        if peer.room:
            await send_control(peer, {"type": "error", "message": "Already in room"})
            return

        # join 限速：房间码仅 20 bit，必须挡住暴力枚举（错误消息复用既有 error 类型，不新增消息类型）。
        block = join_block_reason(peer)
        if block:
            print(
                f"[JOIN LIMIT] reject join_room peer={peer.id or '?'} ip={peer.ip or '-'} "
                f"reason={block} fails={len(peer.join_fails)}",
                flush=True,
            )
            await send_control(peer, {"type": "error", "message": "Too many join attempts"})
            # 连接级超限（疑似枚举脚本）直接断开；每 IP 超限只做节流，保留正常重连可能。
            if block == "peer":
                peer.writer.close()
            return

        if proto < MIN_PROTO:
            print(f"[REJECT] outdated join_room ver={ver} proto={proto} min={MIN_PROTO} ip={peer.ip or '-'}", flush=True)
            await send_control(peer, {"type": "error", "message": f"Outdated mod: require proto>={MIN_PROTO}"})
            return
        code = str(message.get("room_code") or "").strip().upper()
        room = rooms.get(code)
        if not room or not room.host:
            record_join_fail(peer)
            await send_control(peer, {"type": "error", "message": "Room not found"})
            return

        # 同 token 重连：先回收房间内残留的旧连接（pending 或已准入），网络波动/重复点击时旧连接可能仍占位。
        # 释放名额后再接纳新连接；remove_peer 会向其余端广播 peer_disconnected(old_id)，
        # host 侧据此把该 peer 转入「重连宽限」并由 token 迁移状态（仅对已准入 peer 广播）。
        if token:
            stale = [c for c in all_peers(room) if c.token == token and c is not room.host]
            for old in stale:
                print(
                    f"[REJOIN] replacing stale peer={old.id} token={token[:8]} room={code}",
                    flush=True,
                )
                await remove_peer(old)
                old.writer.close()

        # 容量含 pending（未完成 client_ready 的连接也占位）。MAX_CLIENTS_PER_ROOM 与
        # MAX_PLAYERS_PER_ROOM-1 取小值：两处上限任一被下调都生效，默认 3 表示房主+3 客机=4，
        # 与客户端 coop_net.gd 的 MAX_PLAYERS=4 契约一致。
        max_clients = min(MAX_CLIENTS_PER_ROOM, MAX_PLAYERS_PER_ROOM - 1)
        if len(room.clients) + len(room.pending) >= max_clients:
            await send_control(peer, {"type": "error", "message": "Room full"})
            return

        peer.room = room
        peer.role = "client"
        peer.id = alloc_peer_id(room)          # 复用空出的 id，重复加入不再把序号往后推
        room.next_peer_id = max(room.next_peer_id, peer.id + 1)
        peer.name = name
        peer.token = token
        peer.admitted = False
        peer.ver = ver
        peer.proto = proto
        room.pending.add(peer)
        # 准入兜底计时起点：从「已被接受进 pending」起算，而不是从 client_ready 起算。
        peer.joined_at = time.monotonic()

        peers = [
            {"peer_id": room_peer.id, "name": room_peer.name or ""}
            for room_peer in room_peers(room)
            if room_peer.id != peer.id
        ]

        print(
            f"[PROBE] join_room accepted: room={code} "
            f"assigned_peer_id={peer.id} ver={ver} proto={proto} existing_peers={peers}",
            flush=True,
        )
        print(
            "[PROBE] Sending ETN-style join_prepared; now waiting for client_ready",
            flush=True,
        )

        await send_control(peer, {
            "type": "join_prepared",
            "room_code": code,
            "peer_id": peer.id,
            "peers": peers,
            "link_mbps": LINK_MBPS,
            "egress_kib": round(room_egress_kib(), 1),
        })
        return

    if msg_type == "client_ready":
        if peer.room is None or peer.role != "client":
            print("[PROTOCOL ERROR] client_ready received before join_room", flush=True)
            await send_control(peer, {
                "type": "error",
                "message": "client_ready before join_room",
            })
            return

        if peer.admitted:
            return

        # join_prepared 是入房请求时的快照；等待 ready 期间其他 pending 客机可能已准入。
        # 在本端准入前补齐当前成员，保证其拒收未知 sender 的边界不会丢弃合法客机数据。
        for room_peer in room_peers(peer.room):
            if room_peer is not peer:
                await send_control(peer, {
                    "type": "peer_pending",
                    "peer_id": room_peer.id,
                    "name": room_peer.name,
                })

        print(
            f"[PROBE SUCCESS] client_ready received from peer={peer.id}. "
            "This proves the client accepted join_prepared.",
            flush=True,
        )

        peer.room.pending.discard(peer)
        peer.room.clients.add(peer)
        peer.admitted = True

        print(
            f"[PROBE] peer={peer.id} formally admitted; sending join_admitted",
            flush=True,
        )
        await send_control(peer, {
            "type": "join_admitted",
            "link_mbps": LINK_MBPS,
            "egress_kib": round(room_egress_kib(), 1),
        })

        for room_peer in room_peers(peer.room):
            if room_peer is not peer:
                await send_control(room_peer, {
                    "type": "peer_pending",
                    "peer_id": peer.id,
                    "name": peer.name,
                })

        print(
            f"[{peer.room.code}] {peer.name} admitted as peer {peer.id}",
            flush=True,
        )
        return

    if msg_type == "peer_admitted":
        admitted_id = int(message.get("peer_id") or 0)
        print(
            f"[PROBE] peer_admitted received from peer={peer.id}: "
            f"peer_id={admitted_id}",
            flush=True,
        )
        return

    if msg_type == "leave_room":
        print(f"[RECV] leave_room from peer={peer.id}", flush=True)
        await remove_peer(peer)
        return

    print(
        f"[UNKNOWN CONTROL] peer={peer.id or '?'} type={msg_type!r} "
        f"payload={message}",
        flush=True,
    )
    await send_control(peer, {
        "type": "error",
        "message": f"Unknown message: {msg_type}",
    })

async def remove_peer(peer: Peer):
    room = peer.room
    if not room:
        return

    was_admitted = peer.admitted
    peer.room = None

    if room.host is peer:
        lived = time.monotonic() - room.created_at
        if lived < ROOM_CHURN_SEC:
            # 建房即断：多见于客户端建房重试死循环，单独记一条便于定位
            print(
                f"[ROOM CHURN] code={room.code} lived={lived:.1f}s ip={room.owner_ip} ver={peer.ver}",
                flush=True,
            )
        for client in list(room.clients) + list(room.pending):
            await send_control(client, {"type": "peer_disconnected", "peer_id": peer.id})
            await send(client, 0x8)
            client.writer.close()
        rooms.pop(room.code, None)
        return

    room.pending.discard(peer)
    room.clients.discard(peer)
    # 仅对已准入 peer 广播断开：pending 的 id 房主从未见过，广播会产生幽灵事件
    if was_admitted:
        if room.host:
            await send_control(room.host, {"type": "peer_disconnected", "peer_id": peer.id})
        for client in list(room.clients):
            await send_control(client, {"type": "peer_disconnected", "peer_id": peer.id})

    if not room.host and len(room.clients) == 0 and len(room.pending) == 0:
        rooms.pop(room.code, None)


def close_with_http(writer: asyncio.StreamWriter, status: int, message: str):
    writer.write(f"HTTP/1.1 {status} {message}\r\nConnection: close\r\n\r\n".encode("ascii"))
    writer.close()


async def read_http_headers(reader: asyncio.StreamReader):
    data = await asyncio.wait_for(reader.readuntil(b"\r\n\r\n"), HTTP_HANDSHAKE_TIMEOUT_SEC)
    text = data.decode("iso-8859-1")
    lines = text.split("\r\n")
    request_line = lines[0]
    headers = {}

    for line in lines[1:]:
        if not line or ":" not in line:
            continue
        key, value = line.split(":", 1)
        headers[key.strip().lower()] = value.strip()

    return request_line, headers


async def handle_websocket(reader: asyncio.StreamReader, writer: asyncio.StreamWriter, headers: dict):
    key = headers.get("sec-websocket-key")
    if not key:
        close_with_http(writer, 400, "Missing WebSocket key")
        return

    response = "\r\n".join(
        [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            f"Sec-WebSocket-Accept: {ws_accept_key(key)}",
            "\r\n",
        ]
    )
    writer.write(response.encode("ascii"))
    await writer.drain()

    # 连接总数上限：握手已完成，先回既有 error 控制消息再关闭（不新增消息类型），
    # 客户端 WebSocketPeer 能收到并进入 CONNECTION_DISCONNECTED，UI 可正常提示。
    if len(connected_peers) >= MAX_TOTAL_CLIENTS:
        print(
            f"[SERVER LIMIT] reject connection: peers={len(connected_peers)} >= "
            f"{MAX_TOTAL_CLIENTS} remote={writer.get_extra_info('peername')}",
            flush=True,
        )
        payload = json.dumps({"type": "error", "message": "Server full"}, separators=(",", ":")).encode("utf-8")
        writer.write(encode_frame(0x1, payload))
        await writer.drain()
        writer.close()
        try:
            await asyncio.wait_for(writer.wait_closed(), WRITE_TIMEOUT_SEC)
        except Exception:
            pass
        return

    peer = Peer(reader=reader, writer=writer)
    peer.last_seen = time.time()
    remote = writer.get_extra_info("peername")
    # peername 形如 (ip, port)；取出 IP 供每 IP 的 join 限速使用。
    if isinstance(remote, (tuple, list)) and remote:
        peer.ip = str(remote[0])
    elif remote:
        peer.ip = str(remote)
    connected_peers.add(peer)
    print(f"[CONNECT] websocket remote={remote}", flush=True)

    try:
        while not reader.at_eof():
            remaining = PEER_TIMEOUT_MSEC / 1000.0
            now = time.monotonic()
            if peer.room is None:
                remaining = min(remaining, JOIN_TIMEOUT_SEC - (now - peer.connected_at))
            if peer.joined_at is not None and not peer.admitted:
                remaining = min(remaining, ADMIT_TIMEOUT_SEC - (now - peer.joined_at))
            if peer.frame_started is not None:
                remaining = min(remaining, FRAME_TIMEOUT_SEC - (now - peer.frame_started))
            if remaining <= 0:
                break
            try:
                chunk = await asyncio.wait_for(reader.read(65536), remaining)
            except asyncio.TimeoutError:
                # 到点由 wait_for 抛出，走的是通用 except 分支；这里单独识别准入超时并留痕，
                # 否则日志里只有一条 DISCONNECT，排查时看不出是「等不到 client_ready」。
                if (
                    peer.joined_at is not None
                    and not peer.admitted
                    and time.monotonic() - peer.joined_at >= ADMIT_TIMEOUT_SEC
                ):
                    print(f"[ADMIT] timeout peer={peer.id or '?'}; closing", flush=True)
                break
            if not chunk:
                break

            peer.last_seen = time.time()
            if len(peer.buffer) - peer.read_pos + len(chunk) > MAX_BUFFER_BYTES:
                raise ValueError("receive buffer too large")
            if peer.frame_started is None:
                peer.frame_started = time.monotonic()
            peer.buffer.extend(chunk)
            while True:
                frame = try_parse_frame(peer)
                if not frame:
                    break

                opcode, payload = frame
                peer.rx_bytes += len(payload)
                global stat_rx_bytes
                stat_rx_bytes += len(payload)
                peer.frame_started = time.monotonic() if len(peer.buffer) > peer.read_pos else None
                if DEBUG:
                    opcode_name = {0x0: "CONTINUATION", 0x1: "TEXT", 0x2: "BINARY", 0x8: "CLOSE", 0x9: "PING", 0xA: "PONG"}.get(opcode, f"UNKNOWN({opcode})")
                    debug_log(f"[RECV FRAME] peer={peer.id or '?'} opcode={opcode_name} bytes={len(payload)}")
                if opcode == 0x8:
                    writer.write(encode_frame(0x8, payload))
                    await writer.drain()
                    return

                if opcode == 0x9:
                    await send(peer, 0xA, payload)
                    continue

                if opcode == 0xA:
                    peer.last_seen = time.time()
                    continue

                if opcode == 0x1:
                    await handle_control(peer, payload)
                elif opcode == 0x2 or opcode == 0x0:
                    if payload[:1] in (b"{", b"["):
                        preview = payload[:500].decode("utf-8", errors="replace")
                        debug_log(f"[PROTOCOL WARNING] JSON-looking payload arrived as BINARY/CONTINUATION: {preview}")
                    await route_packet(peer, payload)
            compact_buffer(peer)
    except Exception:
        writer.close()
    finally:
        connected_peers.discard(peer)
        print(f"[DISCONNECT] peer={peer.id or '?'} role={peer.role or '?'} ver={peer.ver} room={peer.room.code if peer.room else '-'} admitted={peer.admitted}", flush=True)
        await remove_peer(peer)
        writer.close()
        try:
            # 关闭阶段同样加超时：卡死的对端不该让本协程（含 remove_peer 后的收尾）无限挂住。
            await asyncio.wait_for(writer.wait_closed(), WRITE_TIMEOUT_SEC)
        except Exception:
            pass


async def handle_connection(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
    # 关掉 Nagle：游戏数据是 20Hz 左右的小帧，Nagle 会把小段合并/延迟最多一个 RTT，
    # 表现为所有人的抖动底噪（与 mod 版本无关，属服务端可消除项）。
    try:
        _sock = writer.get_extra_info("socket")
        if _sock is not None:
            _sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
    except (OSError, AttributeError):
        pass
    try:
        _, headers = await read_http_headers(reader)
    except Exception:
        writer.close()
        return

    if headers.get("upgrade", "").lower() == "websocket":
        await handle_websocket(reader, writer, headers)
        return

    body = b"Enter The Nyangeon relay is running.\n"
    writer.write(
        b"HTTP/1.1 200 OK\r\n"
        b"content-type: text/plain\r\n"
        + f"content-length: {len(body)}\r\n".encode("ascii")
        + b"\r\n"
        + body
    )
    await writer.drain()
    writer.close()


async def cleanup_rooms():
    while True:
        await asyncio.sleep(30)
        now = time.time() * 1000
        mono = time.monotonic()
        # 建房限速表的过期条目回收（长期运行不留每个 IP 的无限增长列表）
        for ip in list(ip_create_times.keys()):
            kept = [t for t in ip_create_times[ip] if mono - t <= CREATE_WINDOW_SEC]
            if kept:
                ip_create_times[ip] = kept
            else:
                ip_create_times.pop(ip, None)
        for room in list(rooms.values()):
            # 兜底泄漏检测：正常情况下 remove_peer 已即时删除无主空房，
            # 走到这里说明有未覆盖的路径，记一条 [ROOM GC] 便于发现。
            if room.host is None and not room.clients and not room.pending:
                print(
                    f"[ROOM GC] code={room.code} reason=hostless ip={room.owner_ip}",
                    flush=True,
                )
                rooms.pop(room.code, None)
                continue
            if now - room.last_active <= ROOM_TIMEOUT_MS:
                continue
            for peer in all_peers(room):
                peer.writer.close()
            rooms.pop(room.code, None)


async def heartbeat_peers():
    global stat_rx_bytes, stat_tx_bytes, stat_kicks_bp, stat_kicks_timeout, _last_budget_kib
    # 主动发 WebSocket PING，客户端 WebSocketPeer 会自动回 PONG；无任何数据超过
    # PEER_TIMEOUT_MSEC 即判定半开连接并关闭（finally -> remove_peer 回收名额）。
    # 每轮并发发送：peer 多时不再让心跳周期被逐个 await 拉长（send 本身已不阻塞）。
    # 同一循环里每 STATS_INTERVAL_SEC 打一次带宽统计，用于定位「谁在灌、灌多少」。
    stats_elapsed = 0.0
    summary_elapsed = 0.0
    while True:
        await asyncio.sleep(HEARTBEAT_INTERVAL_SEC)
        now = time.time()
        alive = []
        for peer in list(connected_peers):
            if peer.last_seen > 0 and (now - peer.last_seen) * 1000 > PEER_TIMEOUT_MSEC:
                print(f"[HEARTBEAT] timeout peer={peer.id or '?'}; closing", flush=True)
                stat_kicks_timeout += 1
                peer.writer.close()
                continue
            alive.append(peer)
        if alive:
            await asyncio.gather(
                *(send(peer, 0x9) for peer in alive), return_exceptions=True
            )

        # 房间数变化时按房间数重新分摊出口预算，并下发 budget 给所有房内连接
        cur_budget = room_egress_kib()
        if _last_budget_kib <= 0.0:
            _last_budget_kib = cur_budget
        elif abs(cur_budget - _last_budget_kib) > _last_budget_kib * 0.05:
            _last_budget_kib = cur_budget
            print(f"[BUDGET] rooms={len(rooms)} egress={cur_budget:.0f}KiB/s", flush=True)
            await asyncio.gather(
                *(
                    send_control(p, {"type": "budget", "egress_kib": round(cur_budget, 1), "link_mbps": LINK_MBPS})
                    for p in list(connected_peers)
                    if p.room is not None
                ),
                return_exceptions=True,
            )

        stats_elapsed += HEARTBEAT_INTERVAL_SEC
        if stats_elapsed >= STATS_INTERVAL_SEC:
            stats_elapsed = 0.0
            mono = time.monotonic()
            for peer in list(connected_peers):
                if peer.room is None:
                    continue
                base_at = peer.stats_at if peer.stats_at > 0.0 else peer.connected_at
                dt = max(0.001, mono - base_at)
                rx_kb = (peer.rx_bytes - peer.stats_rx) / dt / 1024.0
                tx_kb = (peer.tx_bytes - peer.stats_tx) / dt / 1024.0
                peer.stats_at = mono
                peer.stats_rx = peer.rx_bytes
                peer.stats_tx = peer.tx_bytes
                print(
                    f"[STATS] room={peer.room.code} peer={peer.id or '?'} role={peer.role or '?'} "
                    f"ver={peer.ver} proto={peer.proto} "
                    f"rx={rx_kb:.1f}KB/s tx={tx_kb:.1f}KB/s buffered_max={peer.buffered_max // 1024}KB",
                    flush=True,
                )
                peer.buffered_max = 0

        summary_elapsed += HEARTBEAT_INTERVAL_SEC
        if summary_elapsed >= SUMMARY_INTERVAL_SEC:
            elapsed = summary_elapsed
            summary_elapsed = 0.0
            max_buf = 0
            for peer in connected_peers:
                if peer.buffered_max > max_buf:
                    max_buf = peer.buffered_max
            congested = sum(1 for p in connected_peers if p.congest_level > 0)
            print(
                f"[SUMMARY] rooms={len(rooms)} peers={len(connected_peers)} "
                f"rx={stat_rx_bytes / elapsed / 1024.0:.1f}KB/s "
                f"tx={stat_tx_bytes / elapsed / 1024.0:.1f}KB/s "
                f"kicks_bp={stat_kicks_bp} kicks_timeout={stat_kicks_timeout} "
                f"buffered_max={max_buf // 1024}KB congested={congested} "
                f"link={LINK_MBPS:.1f}Mbps egress={LINK_EGRESS_KIB:.0f}KiB/s",
                flush=True,
            )
            stat_rx_bytes = 0
            stat_tx_bytes = 0
            stat_kicks_bp = 0
            stat_kicks_timeout = 0


async def main():
    asyncio.create_task(cleanup_rooms())
    asyncio.create_task(heartbeat_peers())
    server = await asyncio.start_server(handle_connection, RELAY_BIND_ADDRESS, PORT)
    print(f"Relay server listening on ws://{RELAY_BIND_ADDRESS}:{PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
