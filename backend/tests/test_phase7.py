from __future__ import annotations

import asyncio

from chat.api.main import state
from chat.devices.wol import magic_packet, normalize_mac


def test_magic_packet_layout_and_mac_normalization():
    assert normalize_mac("AA-BB-CC-DD-EE-FF") == "aa:bb:cc:dd:ee:ff"
    packet = magic_packet("aa:bb:cc:dd:ee:ff")
    assert len(packet) == 102
    assert packet[:6] == b"\xff" * 6
    assert packet[6:] == bytes.fromhex("aabbccddeeff") * 16


def test_device_registry_and_wake_confirmation(client, monkeypatch):
    sent = []
    monkeypatch.setattr("chat.api.routes_devices.send_magic_packet", lambda mac: sent.append(mac))
    invalid = client.post("/api/devices", json={"name": "laptop", "mac": "not-a-mac"})
    assert invalid.status_code == 422
    invalid_ip = client.post(
        "/api/devices",
        json={"name": "laptop", "mac": "AA-BB-CC-DD-EE-FF", "tailscale_ip": "192.168.1.3"},
    )
    assert invalid_ip.status_code == 422

    created = client.post(
        "/api/devices", json={"name": "Laptop", "mac": "AA-BB-CC-DD-EE-FF"}
    )
    assert created.status_code == 201
    device_id = created.json()["id"]
    assert client.get("/api/devices").json()["devices"][0]["mac"] == "aa:bb:cc:dd:ee:ff"
    assert client.post(f"/api/devices/{device_id}/wake", json={"confirmed": False}).status_code == 403
    assert client.post(f"/api/devices/{device_id}/wake", json={"confirmed": 1}).status_code == 422
    assert not sent

    awakened = client.post(f"/api/devices/{device_id}/wake", json={"confirmed": True})
    assert awakened.status_code == 200
    assert "não confirma" in awakened.json()["message"]
    assert sent == ["aa:bb:cc:dd:ee:ff"]
    audit = asyncio.run(state.db.fetch_one(
        "SELECT action,confirmed_by_user FROM audit_log ORDER BY id DESC LIMIT 1"
    ))
    assert audit == {"action": "device_wake", "confirmed_by_user": 1}
