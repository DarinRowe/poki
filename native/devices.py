#!/usr/bin/env python3
"""Read the public usbmuxd device inventory without opening pairing records."""
import json
import plistlib
import socket
import struct

with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
    connection.settimeout(5)
    connection.connect('/var/run/usbmuxd')
    body = plistlib.dumps({
        'MessageType': 'ListDevices',
        'ClientVersionString': 'poki-mcp',
        'ProgName': 'poki-mcp',
        'kLibUSBMuxVersion': 3,
    })
    connection.sendall(struct.pack('<IIII', len(body) + 16, 1, 8, 1) + body)

    def receive(length):
        data = bytearray()
        while len(data) < length:
            chunk = connection.recv(length - len(data))
            if not chunk:
                raise RuntimeError('usbmuxd closed before completing its response')
            data.extend(chunk)
        return data

    length, version, kind, tag = struct.unpack('<IIII', receive(16))
    if not 16 <= length <= 8 * 1024 * 1024:
        raise RuntimeError('Invalid usbmuxd response size')
    response = plistlib.loads(receive(length - 16))
    if response.get('Number', 0) != 0:
        raise RuntimeError('usbmuxd rejected ListDevices')
    devices = []
    for device in response.get('DeviceList', []):
        properties = device.get('Properties', {})
        devices.append({
            'id': properties.get('SerialNumber'),
            'connection': properties.get('ConnectionType'),
        })
    print(json.dumps(devices))
