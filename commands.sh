#!/usr/bin/env bash
# Bài 4: Custom Bridge Network & Named Volume bằng Docker CLI
set -euo pipefail

NETWORK="app-net"
VOLUME="db-data"
DB_CONTAINER="db-server"
APP_CONTAINER="app-container"

DB_IMAGE="postgres:15-alpine"
# Image giả lập Backend Web API (nhẹ, có sẵn ping/nslookup). Có thể thay bằng image backend thật.
APP_IMAGE="python:3.12-alpine"

DB_USER="appuser"
DB_PASSWORD="apppass"
DB_NAME="appdb"

wait_for_db() {
  echo ">> Chờ PostgreSQL sẵn sàng..."
  until docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
    sleep 1
  done
  # Postgres khởi động lần đầu restart nội bộ 1 lần, nên kiểm tra lại cho chắc
  sleep 2
  until docker exec "$DB_CONTAINER" pg_isready -U "$DB_USER" -d "$DB_NAME" >/dev/null 2>&1; do
    sleep 1
  done
}

run_db() {
  docker run -d \
    --name "$DB_CONTAINER" \
    --network "$NETWORK" \
    -v "$VOLUME":/var/lib/postgresql/data \
    -e POSTGRES_USER="$DB_USER" \
    -e POSTGRES_PASSWORD="$DB_PASSWORD" \
    -e POSTGRES_DB="$DB_NAME" \
    "$DB_IMAGE"
}

psql_db() {
  docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$1"
}

echo "===== 0. Dọn dẹp môi trường cũ (nếu có) ====="
docker rm -f "$APP_CONTAINER" "$DB_CONTAINER" >/dev/null 2>&1 || true
docker volume rm "$VOLUME" >/dev/null 2>&1 || true
docker network rm "$NETWORK" >/dev/null 2>&1 || true

echo "===== 1. Tạo Custom Bridge Network: $NETWORK ====="
docker network create --driver bridge "$NETWORK"

echo "===== 2. Tạo Named Volume: $VOLUME ====="
docker volume create "$VOLUME"

echo "===== 3. Chạy Database Container: $DB_CONTAINER ====="
run_db
wait_for_db

echo "===== 4. Chạy Backend Container: $APP_CONTAINER ====="
# DB_HOST dùng hostname 'db-server' -> Docker DNS nội bộ của app-net tự phân giải
docker run -d \
  --name "$APP_CONTAINER" \
  --network "$NETWORK" \
  -p 8000:8000 \
  -e DB_HOST="$DB_CONTAINER" \
  -e DB_PORT=5432 \
  -e DB_USER="$DB_USER" \
  -e DB_PASSWORD="$DB_PASSWORD" \
  -e DB_NAME="$DB_NAME" \
  -e DATABASE_URL="postgresql://$DB_USER:$DB_PASSWORD@$DB_CONTAINER:5432/$DB_NAME" \
  "$APP_IMAGE" python -m http.server 8000

echo "===== 5. Kiểm tra network / volume / DNS ====="
docker network ls | grep "$NETWORK"
docker volume ls | grep "$VOLUME"
docker network inspect "$NETWORK"
docker exec "$APP_CONTAINER" ping -c 2 "$DB_CONTAINER"

echo "===== 6. Test Data Persistence ====="
echo ">> 6.1 Thêm dữ liệu"
psql_db "CREATE TABLE IF NOT EXISTS students (id SERIAL PRIMARY KEY, name TEXT NOT NULL);"
psql_db "INSERT INTO students (name) VALUES ('Nguyen Van A'), ('Tran Thi B');"
echo ">> Dữ liệu trước khi xóa container:"
psql_db "SELECT * FROM students;"

echo ">> 6.2 Xóa cứng container DB"
docker rm -f "$DB_CONTAINER"

echo ">> 6.3 Chạy lại container DB mới, gắn cùng volume $VOLUME"
run_db
wait_for_db

echo ">> 6.4 Xác minh dữ liệu còn nguyên"
psql_db "SELECT * FROM students;"

echo "===== Backend vẫn phân giải được DB container mới ====="
docker exec "$APP_CONTAINER" ping -c 2 "$DB_CONTAINER"

echo "===== HOÀN TẤT ====="
