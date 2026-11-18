#!/usr/bin/env python3
"""Serve the CCA RM 140 floor plan and relay phone positions from MQTT.

A browser cannot open the broker's TCP port. This process subscribes to
pi02zigbee.lan:1883 and gives room.html a same-origin event stream.

    python3 serve.py
    open http://127.0.0.1:8768/
"""

from __future__ import annotations

import json
import os
import queue
import socket
import struct
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

BROKER_HOST = "pi02zigbee.lan"
BROKER_PORT = 1883
TOPIC = "/cca/r140/iphone/#"
PAGE = Path(__file__).with_name("room.html")

clients: list[queue.Queue[str]] = []
latest: dict[str, str] = {}
broker_status = "Connecting to pi02zigbee.lan"
lock = threading.Lock()


def encode_remaining(value: int) -> bytes:
    out = bytearray()
    remaining = value
    while True:
        digit = remaining % 128
        remaining //= 128
        if remaining > 0:
            digit |= 0x80
        out.append(digit)
        if remaining == 0:
            break
    return bytes(out)


def encode_string(text: str) -> bytes:
    body = text.encode()
    return struct.pack("!H", len(body)) + body


def packet(packet_type: int, body: bytes) -> bytes:
    return bytes([packet_type]) + encode_remaining(len(body)) + body


def connect_packet(client_id: str) -> bytes:
    # MQTT 3.1.1, clean session, keepalive 30 s. No will and no credentials.
    header = encode_string("MQTT") + bytes([0x04, 0x02]) + struct.pack("!H", 30)
    return packet(0x10, header + encode_string(client_id))


def subscribe_packet(packet_id: int, topic: str) -> bytes:
    body = struct.pack("!H", packet_id) + encode_string(topic) + bytes([0])
    return packet(0x82, body)


def take_packets(buf: bytearray) -> tuple[list[dict], bytearray]:
    packets: list[dict] = []
    offset = 0
    data = bytes(buf)
    while offset < len(data):
        length = read_remaining(data, offset + 1)
        if length is None:
            return packets, bytearray(data[offset:])
        if length < 0 or length > 262_144:
            return packets, bytearray()
        consumed = remaining_size(data, offset + 1)
        total = 1 + consumed + length
        if offset + total > len(data):
            return packets, bytearray(data[offset:])
        packet_type = data[offset] >> 4
        flags = data[offset] & 0x0F
        body = data[offset + 1 + consumed : offset + total]
        packets.append(interpret(packet_type, flags, body))
        offset += total
    return packets, bytearray()


def remaining_size(data: bytes, start: int) -> int:
    consumed = 0
    while consumed < 4:
        if start + consumed >= len(data):
            return consumed
        consumed += 1
        if data[start + consumed - 1] & 0x80 == 0:
            return consumed
    return consumed


def read_remaining(data: bytes, start: int) -> int | None:
    value = 0
    multiplier = 1
    consumed = 0
    while consumed < 4:
        index = start + consumed
        if index >= len(data):
            return None
        byte = data[index]
        consumed += 1
        value += (byte & 0x7F) * multiplier
        if byte & 0x80 == 0:
            return value
        multiplier *= 128
    return -1


def interpret(packet_type: int, flags: int, body: bytes) -> dict:
    if packet_type == 2 and len(body) >= 2:
        return {"type": "connack", "code": body[1]}
    if packet_type == 3:
        return decode_publish(flags, body)
    return {"type": "other", "code": packet_type}


def decode_publish(flags: int, body: bytes) -> dict:
    if len(body) < 2:
        return {"type": "other", "code": 3}
    length = struct.unpack("!H", body[:2])[0]
    topic_end = 2 + length
    if topic_end > len(body):
        return {"type": "other", "code": 3}
    topic = body[2:topic_end].decode("utf-8", "replace")
    payload_start = topic_end + (2 if ((flags >> 1) & 0x03) else 0)
    if payload_start > len(body):
        return {"type": "other", "code": 3}
    payload = body[payload_start:].decode("utf-8", "replace")
    return {"type": "publish", "topic": topic, "payload": payload}


def sse(event: str, data: str) -> str:
    return f"event: {event}\ndata: {data}\n\n"


def publish(chunk: str) -> None:
    with lock:
        targets = list(clients)
    for target in targets:
        target.put(chunk)


def set_broker(text: str) -> None:
    global broker_status
    with lock:
        broker_status = text
    publish(sse("status", text))


def relay(topic: str, payload: str) -> None:
    chunk = sse("position", json.dumps({"topic": topic, "payload": payload}))
    with lock:
        latest[topic] = chunk
        targets = list(clients)
    for target in targets:
        target.put(chunk)


def snapshot() -> list[str]:
    with lock:
        items = list(latest.items())
        status = broker_status
    positions = [chunk for topic, chunk in items if topic.endswith("/position")]
    statuses = [chunk for topic, chunk in items if topic.endswith("/status")]
    others = [chunk for topic, chunk in items if not topic.endswith("/position") and not topic.endswith("/status")]
    return [sse("status", status), *positions, *statuses, *others]


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path in ("/", "/room.html"):
            body = PAGE.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        if path != "/stream":
            self.send_error(404)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        inbox: queue.Queue[str] = queue.Queue()
        with lock:
            clients.append(inbox)
        try:
            for chunk in snapshot():
                self.wfile.write(chunk.encode())
            self.wfile.flush()
            while True:
                try:
                    chunk = inbox.get(timeout=15)
                except queue.Empty:
                    chunk = ": keepalive\n\n"
                self.wfile.write(chunk.encode())
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            return
        finally:
            with lock:
                if inbox in clients:
                    clients.remove(inbox)

    def log_message(self, fmt: str, *args: object) -> None:
        if self.path.split("?", 1)[0] == "/stream":
            return
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))


def run_session() -> None:
    set_broker(f"Connecting to {BROKER_HOST}")
    sock = socket.create_connection((BROKER_HOST, BROKER_PORT), timeout=8)
    sock.settimeout(20)
    try:
        sock.sendall(connect_packet(f"room-plan-{os.getpid()}"))
        buf = bytearray()
        live = False
        while True:
            try:
                chunk = sock.recv(4096)
            except socket.timeout:
                sock.sendall(bytes([0xC0, 0x00]))
                continue
            if not chunk:
                raise ConnectionError("connection closed")
            buf.extend(chunk)
            packets, buf = take_packets(buf)
            for item in packets:
                if item["type"] == "connack":
                    if item["code"] != 0:
                        raise ConnectionError(f"broker refused ({item['code']})")
                    sock.sendall(subscribe_packet(1, TOPIC))
                    live = True
                    set_broker("Live")
                elif item["type"] == "publish" and live:
                    relay(item["topic"], item["payload"])
    finally:
        sock.close()


def mqtt_loop() -> None:
    while True:
        try:
            run_session()
        except Exception as exc:
            set_broker(f"Broker unreachable: {exc}")
        time.sleep(3)


def serve(port: int) -> None:
    threading.Thread(target=mqtt_loop, name="mqtt", daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"CCA RM 140 floor plan  http://127.0.0.1:{port}/")
    print(f"MQTT {BROKER_HOST}:{BROKER_PORT}  {TOPIC}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print()
        server.shutdown()


def check() -> None:
    encoded = connect_packet("room-plan-1")
    assert encoded[0] == 0x10
    assert encoded[2:8] == b"\x00\x04MQTT"
    assert encoded[8] == 0x04 and encoded[9] == 0x02
    topic = "/cca/r140/iphone/AA:BB:CC:DD:EE:FF/position"
    body = encode_string(topic) + b'{"region":"K01"}'
    packets, rest = take_packets(bytearray(packet(0x30, body) + bytes([0x20, 0x02, 0x00, 0x00, 0x30, 0x0A])))
    assert rest == bytearray([0x30, 0x0A])
    assert packets[0]["topic"] == topic
    assert packets[0]["payload"] == '{"region":"K01"}'
    assert packets[1] == {"type": "connack", "code": 0}
    malformed, empty = take_packets(bytearray([0x30, 0xFF, 0xFF, 0xFF, 0xFF]))
    assert malformed == [] and empty == bytearray()
    relay(topic, '{"region":"K02"}')
    assert any("K02" in chunk for chunk in snapshot())


if __name__ == "__main__":
    if len(sys.argv) == 2 and sys.argv[1] == "--check":
        check()
        print("ok")
    else:
        listen = int(sys.argv[1]) if len(sys.argv) == 2 else 8768
        serve(listen)
