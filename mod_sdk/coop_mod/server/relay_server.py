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


PORT = int(os.environ.get("PORT", "7716"))
MAX_CLIENTS_PER_ROOM = int(os.environ.get("MAX_CLIENTS_PER_ROOM", "3"))
ROOM_TIMEOUT_MS = int(os.environ.get("ROOM_TIMEOUT_MS", str(30 * 60 * 1000)))
HEADER_SIZE = 4
MAX_PLAYERS_PER_ROOM = 4
WRITE_HIGH_WATER = 256 * 1024
COMPACT_THRESHOLD = 65536
DEBUG = os.environ.get("RELAY_DEBUG", "").strip().lower() in ("1", "true", "yes", "on")
# 连接级心跳：客户端约每 1s 有游戏数据/心跳包，超过该阈值无任何数据即判定半开连接并回收。
PEER_TIMEOUT_MSEC = int(os.environ.get("PEER_TIMEOUT_MSEC", "20000"))
HEARTBEAT_INTERVAL_SEC = float(os.environ.get("HEARTBEAT_INTERVAL_SEC", "5"))

rooms = {}


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
        if length > (2**53 - 1):
            raise ValueError("frame too large")
        offset += 8

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


async def send(peer: Peer, opcode: int, payload: bytes = b""):
    writer = peer.writer
    if writer.is_closing():
        return
    writer.write(encode_frame(opcode, payload))
    transport = writer.transport
    if transport is None:
        return
    try:
        if transport.get_write_buffer_size() >= WRITE_HIGH_WATER:
            await writer.drain()
    except (ConnectionError, RuntimeError):
        pass


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
        await asyncio.gather(*(
            send_data(receiver, peer.id, game_payload)
            for receiver in peers
            if receiver.id != peer.id
        ))
        return

    if target_id < 0:
        excluded_id = abs(target_id)
        await asyncio.gather(*(
            send_data(receiver, peer.id, game_payload)
            for receiver in peers
            if receiver.id != peer.id and receiver.id != excluded_id
        ))
        return

    for receiver in peers:
        if receiver.id == target_id:
            await send_data(receiver, peer.id, game_payload)
            return


def generate_room_code() -> str:
    alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    for _ in range(1000):
        code = "".join(random.choice(alphabet) for _ in range(4))
        if code not in rooms:
            return code
    raise RuntimeError("room code exhausted")


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

        code = str(message.get("room_code") or "").strip().upper()
        room = rooms.get(code)
        if not room or not room.host:
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

        # 容量含 pending（未完成 client_ready 的连接也占位），沿用量表：clients+pending 上限 = MAX_PLAYERS_PER_ROOM-1
        if len(room.clients) + len(room.pending) + 1 >= MAX_PLAYERS_PER_ROOM:
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
    data = await reader.readuntil(b"\r\n\r\n")
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

    peer = Peer(reader=reader, writer=writer)
    peer.last_seen = time.time()
    remote = writer.get_extra_info("peername")
    print(f"[CONNECT] websocket remote={remote}", flush=True)

    try:
        while not reader.at_eof():
            chunk = await reader.read(65536)
            if not chunk:
                break

            peer.last_seen = time.time()
            peer.buffer.extend(chunk)
            while True:
                frame = try_parse_frame(peer)
                if not frame:
                    break

                opcode, payload = frame
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
        print(f"[DISCONNECT] peer={peer.id or '?'} role={peer.role or '?'} room={peer.room.code if peer.room else '-'} admitted={peer.admitted}", flush=True)
        await remove_peer(peer)
        writer.close()
        try:
            await writer.wait_closed()
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
    while True:
        await asyncio.sleep(HEARTBEAT_INTERVAL_SEC)
        now = time.time()
        for room in list(rooms.values()):
            for peer in all_peers(room):
                if peer.last_seen > 0 and (now - peer.last_seen) * 1000 > PEER_TIMEOUT_MSEC:
                    print(
                        f"[HEARTBEAT] timeout peer={peer.id or '?'} room={room.code}; closing",
                        flush=True,
                    )
                    peer.writer.close()
                    continue
                await send(peer, 0x9)


async def main():
    asyncio.create_task(cleanup_rooms())
    asyncio.create_task(heartbeat_peers())
    server = await asyncio.start_server(handle_connection, "0.0.0.0", PORT)
    print(f"Relay server listening on ws://0.0.0.0:{PORT}", flush=True)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
