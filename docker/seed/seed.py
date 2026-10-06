"""Popula o Synapse local com os usuários, salas e mensagens de seed.json.

Usa o appservice de seed para agir em nome dos usuários e enviar mensagens
com timestamps no passado. Se o primeiro usuário já existe, não faz nada.
"""

import json
import os
import re
import sys
import time
import uuid
from html import escape
from urllib.parse import quote

import requests

HOMESERVER = os.environ["HOMESERVER_URL"].rstrip("/")
AS_TOKEN = os.environ["AS_TOKEN"]
SERVER_NAME = "localhost"
API = f"{HOMESERVER}/_matrix/client/v3"
SEED_FILE = os.path.join(os.path.dirname(__file__), "seed.json")


def user_id(username):
    return f"@{username}:{SERVER_NAME}"


def parse_ago(text):
    units = {"d": 86400, "h": 3600, "m": 60}
    seconds = sum(
        int(amount) * units[unit] for amount, unit in re.findall(r"(\d+)\s*([dhm])", text)
    )
    return int((time.time() - seconds) * 1000)


def call(method, path, username, body=None, ts=None):
    params = {"user_id": user_id(username)}
    if ts is not None:
        params["ts"] = ts
    response = requests.request(
        method,
        f"{API}{path}",
        params=params,
        json=body,
        headers={"Authorization": f"Bearer {AS_TOKEN}"},
        timeout=30,
    )
    if not response.ok:
        sys.exit(f"{method} {path} como {username} falhou: {response.status_code} {response.text}")
    return response.json()


def user_exists(username):
    response = requests.get(
        f"{API}/register/available", params={"username": username}, timeout=30
    )
    return response.status_code == 400 and response.json().get("errcode") == "M_USER_IN_USE"


def register(user):
    response = requests.post(
        f"{API}/register",
        json={
            "username": user["username"],
            "password": user["password"],
            "auth": {"type": "m.login.dummy"},
            "inhibit_login": True,
        },
        timeout=30,
    )
    if not response.ok:
        sys.exit(f"registro de {user['username']} falhou: {response.status_code} {response.text}")
    call(
        "PUT",
        f"/profile/{quote(user_id(user['username']))}/displayname",
        user["username"],
        {"displayname": user["display_name"]},
    )


def to_html(lines):
    """Converte linhas que começam com "- " em listas <ul>."""
    html, in_list = [], False
    for line in lines:
        is_item = line.startswith("- ")
        if is_item and not in_list:
            html.append("<ul>")
        elif not is_item and in_list:
            html.append("</ul>")
        in_list = is_item
        html.append(f"<li>{escape(line[2:])}</li>" if is_item else f"<p>{escape(line)}</p>")
    if in_list:
        html.append("</ul>")
    return "".join(html)


def message_content(message, display_names):
    # `text` pode ser uma string ou uma lista de linhas.
    lines = message["text"] if isinstance(message["text"], list) else [message["text"]]
    mentions = message.get("mentions", [])
    content = {"msgtype": "m.text", "body": "\n".join(lines)}
    if mentions or any(line.startswith("- ") for line in lines):
        html = to_html(lines) if len(lines) > 1 else escape(lines[0])
        for username in mentions:
            pill = f'<a href="https://matrix.to/#/{user_id(username)}">{display_names[username]}</a>'
            html = html.replace(f"@{username}", pill)
        content["format"] = "org.matrix.custom.html"
        content["formatted_body"] = html
    if mentions:
        content["m.mentions"] = {"user_ids": [user_id(u) for u in mentions]}
    return content


def create_room(room, display_names, direct_rooms):
    members = room["members"]
    creator = room.get("creator", members[0])
    invitees = [m for m in members if m != creator]
    body = {
        "preset": "trusted_private_chat" if room.get("direct") else "private_chat",
        "invite": [user_id(m) for m in invitees],
        "is_direct": bool(room.get("direct")),
    }
    for key in ("name", "topic"):
        if key in room:
            body[key] = room[key]

    room_id = call("POST", "/createRoom", creator, body)["room_id"]
    for member in invitees:
        call("POST", f"/join/{quote(room_id)}", member, {})

    if room.get("direct"):
        for member in members:
            other = next(m for m in members if m != member)
            direct_rooms.setdefault(member, {}).setdefault(user_id(other), []).append(room_id)

    for message in room.get("messages", []):
        event_id = call(
            "PUT",
            f"/rooms/{quote(room_id)}/send/m.room.message/{uuid.uuid4().hex}",
            message["from"],
            message_content(message, display_names),
            ts=parse_ago(message["ago"]),
        )["event_id"]
        # Quem escreve já leu a sala até ali, como num cliente de verdade.
        call(
            "POST",
            f"/rooms/{quote(room_id)}/receipt/m.read/{quote(event_id)}",
            message["from"],
            {},
        )
    print(f"sala criada: {room.get('name', ' e '.join(members))}")


def main():
    with open(SEED_FILE, encoding="utf-8") as file:
        seed = json.load(file)

    if user_exists(seed["users"][0]["username"]):
        print("seed já aplicado; nada a fazer.")
        return

    for user in seed["users"]:
        register(user)
        print(f"usuário criado: {user['username']}")

    display_names = {u["username"]: u["display_name"] for u in seed["users"]}
    direct_rooms = {}
    for room in seed["rooms"]:
        create_room(room, display_names, direct_rooms)

    for username, content in direct_rooms.items():
        call(
            "PUT",
            f"/user/{quote(user_id(username))}/account_data/m.direct",
            username,
            content,
        )
    print("seed concluído.")


if __name__ == "__main__":
    main()
