#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$SCRIPT_DIR/.."

docker compose run --rm certbot renew
docker compose exec nginx nginx -s reload
