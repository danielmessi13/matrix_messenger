#!/usr/bin/env sh
# Cria um usuário no Synapse local. Uso: ./docker/create-user.sh alice senha [--admin]
set -e
user="${1:?informe o usuário}"
password="${2:?informe a senha}"
admin="${3:---no-admin}"
docker compose -f "$(dirname "$0")/docker-compose.yml" exec synapse \
  register_new_matrix_user -c /config/homeserver.yaml \
  -u "$user" -p "$password" "$admin" http://localhost:8008
