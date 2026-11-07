#!/usr/bin/env python3
import asyncio
import base64
import hashlib
import json
import os
import random
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
WRITE_SOFT_WATER = 256 * 1024
WRITE_HARD_WATER = int(os.environ.get("RELAY_WRITE_HARD_WATER", str(4 * 1024 * 1024)))
WRITE_GRACE_SEC = float(os.environ.get("RELAY_WRITE_GRACE_SEC", "5"))
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

rooms = {}
connected_peers: set["Peer"] = set()
# 每 IP 的 join 失败时间戳（滑动窗口）；仅保留窗口内的记录，条目在无近期失败时被回收。
ip_join_fails: dict[str, list[float]] = {}


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


@dataclass
class Room:
    code: str
    host: Peer | None
    clients: set[Peer] = field(default_factory=set)
    pending: set[Peer] = field(default_factory=set)
    next_peer_id: int = 2
    last_active: float = field(default_factory=lambda: time.time() * 1000)


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
    transport = writer.transport
    if transport is not None:
        buffered = transport.get_write_buffer_size()
        if buffered >= WRITE_HARD_WATER:
            print(
                f"[BACKPRESSURE] closing peer={peer.id or '?'} role={peer.role or '?'} "
                f"buffered={buffered} hard",
                flush=True,
            )
            writer.close()
            return False
        if buffered >= WRITE_SOFT_WATER:
            now = time.monotonic()
            if peer.over_since == 0.0:
                peer.over_since = now
            elif now - peer.over_since >= WRITE_GRACE_SEC:
                print(
                    f"[BACKPRESSURE] closing peer={peer.id or '?'} role={peer.role or '?'} "
                    f"buffered={buffered} over={now - peer.over_since:.1f}s",
                    flush=True,
                )
                writer.close()
                return False
        else:
            peer.over_since = 0.0
    writer.write(encode_frame(opcode, payload))
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

    if msg_type == "create_room":
        if peer.room:
            await send_control(peer, {"type": "error", "message": "Already in room"})
            return

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
        rooms[code] = room
        peer.room = room
        peer.role = "host"
        peer.id = 1
        peer.name = name
        peer.token = token
        peer.admitted = True

        print(f"[{code}] created by {name}; host peer_id=1", flush=True)
        await send_control(peer, {
            "type": "room_created",
            "room_code": code,
            "peer_id": 1,
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
            f"assigned_peer_id={peer.id} existing_peers={peers}",
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
        await send_control(peer, {"type": "join_admitted"})

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
        print(f"[DISCONNECT] peer={peer.id or '?'} role={peer.role or '?'} room={peer.room.code if peer.room else '-'} admitted={peer.admitted}", flush=True)
        await remove_peer(peer)
        writer.close()
        try:
            # 关闭阶段同样加超时：卡死的对端不该让本协程（含 remove_peer 后的收尾）无限挂住。
            await asyncio.wait_for(writer.wait_closed(), WRITE_TIMEOUT_SEC)
        except Exception:
            pass


async def handle_connection(reader: asyncio.StreamReader, writer: asyncio.StreamWriter):
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
        for room in list(rooms.values()):
            if now - room.last_active <= ROOM_TIMEOUT_MS:
                continue
            for peer in all_peers(room):
                peer.writer.close()
            rooms.pop(room.code, None)


async def heartbeat_peers():
    # 主动发 WebSocket PING，客户端 WebSocketPeer 会自动回 PONG；无任何数据超过
    # PEER_TIMEOUT_MSEC 即判定半开连接并关闭（finally -> remove_peer 回收名额）。
    # 每轮并发发送：peer 多时不再让心跳周期被逐个 await 拉长（send 本身已不阻塞）。
    while True:
        await asyncio.sleep(HEARTBEAT_INTERVAL_SEC)
        now = time.time()
        alive = []
        for peer in list(connected_peers):
            if peer.last_seen > 0 and (now - peer.last_seen) * 1000 > PEER_TIMEOUT_MSEC:
                print(f"[HEARTBEAT] timeout peer={peer.id or '?'}; closing", flush=True)
                peer.writer.close()
                continue
            alive.append(peer)
        if alive:
            await asyncio.gather(
                *(send(peer, 0x9) for peer in alive), return_exceptions=True
            )


async def main():
    asyncio.create_task(cleanup_rooms())
    asyncio.create_task(heartbeat_peers())
    server = await asyncio.start_server(handle_connection, RELAY_BIND_ADDRESS, PORT)
    print(f"Relay server listening on ws://{RELAY_BIND_ADDRESS}:{PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
