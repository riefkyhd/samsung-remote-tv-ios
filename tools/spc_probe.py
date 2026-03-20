#!/usr/bin/env python3
"""
SPC Pairing Probe — Samsung JU FW1550 diagnostic tool
Usage: python3 tools/spc_probe.py <TV_IP>
Runs from laptop on same Wi-Fi as TV. No dependencies beyond stdlib + pycryptodome.
"""

import json
import os
import sys
import urllib.request
import uuid

from Crypto.Cipher import AES

TV_IP = sys.argv[1] if len(sys.argv) > 1 else "192.168.100.21"
APP_ID = "iphone.iapp.samsung"
DEV_ID = str(uuid.uuid4())
BASE = f"http://{TV_IP}:8080/ws/pairing"


def post(step, body):
    url = f"{BASE}?step={step}&app_id={APP_ID}&device_id={DEV_ID}&type=1"
    data = json.dumps(body).encode()
    req = urllib.request.Request(
        url,
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, response.read().decode()


def aes_ecb(key: bytes, data: bytes) -> bytes:
    return AES.new(key, AES.MODE_ECB).encrypt(data)


def generate_hello():
    key = os.urandom(16)
    hash_ = aes_ecb(key, key)
    blob = bytearray(128)
    blob[0] = 0x01
    blob[1:17] = key
    blob[17:33] = hash_
    return bytes(blob), key, hash_


print(f"\n[PROBE] TV: {TV_IP}  device_id: {DEV_ID}\n")

print(">>> Step 0 (expect empty, that is OK on FW1550)")
code, body = post(0, {})
print(f"    HTTP {code}  body: {body}\n")

print(">>> Step 1 — reversed flow (client-generated ServerHello)")
blob, aes_key, hash_ = generate_hello()
_ = aes_key, hash_
hex_blob = blob.hex().upper()
code, body = post(
    1,
    {
        "auth_data": {
            "auth_type": "SPC",
            "GeneratorServerHello": hex_blob,
        }
    },
)
print(f"    HTTP {code}  body: {body}\n")

if '"GeneratorClientHello"' in body:
    print("[SUCCESS] TV returned GeneratorClientHello — reversed flow works on this firmware!")
    print("          Now enter PIN shown on TV and run step2.")
else:
    print("[FAILED]  auth_data still empty after reversed flow.")
    print("          Next step: capture traffic from SmartView 2.0 with Charles Proxy.")

print(">>> Step 1 — reversed flow + user_id field")
code, body = post(
    1,
    {
        "auth_data": {
            "auth_type": "SPC",
            "GeneratorServerHello": hex_blob,
            "user_id": DEV_ID,
        }
    },
)
print(f"    HTTP {code}  body: {body}\n")
if '"GeneratorClientHello"' in body:
    print("[SUCCESS] user_id variant works!")
