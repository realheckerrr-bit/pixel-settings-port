#!/usr/bin/env python3
"""Read the small set of APK manifest fields needed by the port installer."""

from __future__ import annotations

import argparse
import json
import struct
import zipfile
from pathlib import Path


def u16(data: bytes, offset: int) -> int:
    return struct.unpack_from("<H", data, offset)[0]


def u32(data: bytes, offset: int) -> int:
    return struct.unpack_from("<I", data, offset)[0]


def decode_string_pool(data: bytes, chunk_offset: int) -> list[str]:
    string_count = u32(data, chunk_offset + 8)
    flags = u32(data, chunk_offset + 16)
    strings_start = u32(data, chunk_offset + 20)
    offsets_start = chunk_offset + u16(data, chunk_offset + 2)
    utf8 = bool(flags & 0x100)
    offsets = [u32(data, offsets_start + index * 4) for index in range(string_count)]
    values: list[str] = []

    for relative in offsets:
        position = chunk_offset + strings_start + relative
        if utf8:
            first = data[position]
            position += 1
            if first & 0x80:
                position += 1
            length = data[position]
            position += 1
            if length & 0x80:
                length = ((length & 0x7F) << 8) | data[position]
                position += 1
            values.append(data[position : position + length].decode("utf-8", "replace"))
        else:
            length = u16(data, position)
            position += 2
            if length & 0x8000:
                length = ((length & 0x7FFF) << 16) | u16(data, position)
                position += 2
            values.append(data[position : position + length * 2].decode("utf-16le", "replace"))
    return values


def typed_value(data_type: int, value: int, strings: list[str]) -> object:
    if data_type == 0x03 and value < len(strings):
        return strings[value]
    if data_type == 0x10:
        return value
    if data_type == 0x11:
        return f"0x{value:08x}"
    if data_type == 0x12:
        return bool(value)
    if data_type == 0x01:
        return f"@0x{value:08x}"
    if data_type == 0x02:
        return f"?0x{value:08x}"
    return {"type": f"0x{data_type:02x}", "value": value}


def parse_manifest(data: bytes) -> dict[str, object]:
    strings: list[str] = []
    elements: list[dict[str, object]] = []
    offset = 0

    while offset + 8 <= len(data):
        chunk_type = u16(data, offset)
        header_size = u16(data, offset + 2)
        # The chunk header is type (u16), header size (u16), size (u32).
        chunk_size = u32(data, offset + 4)
        if chunk_size < header_size or offset + chunk_size > len(data):
            break

        if offset == 0 and chunk_type == 0x0003:
            offset += header_size
            continue

        if chunk_type == 0x0001:
            strings = decode_string_pool(data, offset)
        elif chunk_type == 0x0102 and strings:
            name_index = u32(data, offset + 20)
            name = strings[name_index] if name_index < len(strings) else f"#{name_index}"
            attribute_start = u16(data, offset + 24)
            attribute_size = u16(data, offset + 26)
            attribute_count = u16(data, offset + 28)
            attributes: dict[str, object] = {}
            attribute_offset = offset + 16 + attribute_start
            for index in range(attribute_count):
                current = attribute_offset + index * attribute_size
                attr_name_index = u32(data, current + 4)
                raw_index = u32(data, current + 8)
                data_type = data[current + 15]
                value = u32(data, current + 16)
                attr_name = strings[attr_name_index] if attr_name_index < len(strings) else f"#{attr_name_index}"
                if raw_index != 0xFFFFFFFF and raw_index < len(strings):
                    attr_value: object = strings[raw_index]
                else:
                    attr_value = typed_value(data_type, value, strings)
                attributes[attr_name] = attr_value
            elements.append({"tag": name, "attributes": attributes})

        offset += chunk_size

    manifest = elements[0] if elements and elements[0]["tag"] == "manifest" else {"attributes": {}}
    attributes = manifest.get("attributes", {})
    result: dict[str, object] = {
        "package": attributes.get("package"),
        "versionCode": attributes.get("versionCode"),
        "versionName": attributes.get("versionName"),
        "minSdk": None,
        "targetSdk": None,
        "permissions": [],
        "components": [],
        "elements": elements,
    }

    for element in elements:
        tag = element["tag"]
        attrs = element["attributes"]
        if tag == "uses-sdk":
            result["minSdk"] = attrs.get("minSdkVersion")
            result["targetSdk"] = attrs.get("targetSdkVersion")
        elif tag == "uses-permission":
            result["permissions"].append(attrs.get("name"))
        elif tag in {"activity", "activity-alias", "receiver", "service", "provider"}:
            result["components"].append({"type": tag, **attrs})
    return result


def inspect(path: Path) -> dict[str, object]:
    with zipfile.ZipFile(path) as archive:
        manifest = parse_manifest(archive.read("AndroidManifest.xml"))
        entries = archive.namelist()
        manifest["apk"] = path.name
        manifest["size"] = path.stat().st_size
        manifest["signatureFiles"] = [
            name for name in entries if name.startswith("META-INF/") and name.lower().endswith((".rsa", ".dsa", ".ec"))
        ]
        manifest["hasNativeLibraries"] = any(name.startswith("lib/") for name in entries)
        return manifest


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", nargs="+", type=Path)
    args = parser.parse_args()
    print(json.dumps([inspect(path) for path in args.apk], indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
