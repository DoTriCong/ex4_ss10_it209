# Bài 4: Custom Network & Named Volume bằng Docker CLI

## Mục tiêu
- Tạo **Custom Bridge Network** `app-net` để các container giao tiếp qua tên (DNS nội bộ của Docker).
- Tạo **Named Volume** `db-data` để lưu dữ liệu PostgreSQL bền vững, không phụ thuộc vòng đời container.

## Kiến trúc

```
            app-net (custom bridge)
   ┌──────────────────┐      ┌──────────────────────┐
   │  app-container   │ ───► │      db-server       │
   │ (Backend API)    │ DNS  │ postgres:15-alpine   │
   │ DB_HOST=db-server│      │                      │
   └──────────────────┘      └──────────┬───────────┘
                                        │ mount
                                 volume db-data
                           (/var/lib/postgresql/data)
```

## Cách chạy

```bash
chmod +x commands.sh
./commands.sh
```

Script có tính idempotent: tự dọn container/volume/network cũ trước khi chạy lại.

## Các bước trong `commands.sh`

| Bước | Lệnh chính |
|------|-----------|
| Tạo network | `docker network create --driver bridge app-net` |
| Tạo volume | `docker volume create db-data` |
| Chạy DB | `docker run -d --name db-server --network app-net -v db-data:/var/lib/postgresql/data -e POSTGRES_USER=... -e POSTGRES_PASSWORD=... -e POSTGRES_DB=... postgres:15-alpine` |
| Chạy Backend | `docker run -d --name app-container --network app-net -e DB_HOST=db-server ... python:3.12-alpine` |
| Test persistence | Insert dữ liệu → `docker rm -f db-server` → chạy lại DB cùng volume → `SELECT` |

> **Lưu ý:** Đề không chỉ định image Backend nên script dùng `python:3.12-alpine` (chạy `http.server`) làm backend giả lập. Có thể thay bằng image Backend thật của bạn; chỉ cần giữ `--network app-net` và `DB_HOST=db-server`.

## Kiểm tra

```bash
docker network ls | grep app-net
docker volume ls | grep db-data
docker network inspect app-net
docker exec -it app-container ping -c 2 db-server
```

### Kết quả mong đợi

1. `docker network inspect app-net` liệt kê cả `db-server` và `app-container` trong mục `Containers`, mỗi container có một IP nội bộ (ví dụ `172.x.0.2`, `172.x.0.3`).
2. `ping -c 2 db-server` từ `app-container` phân giải tên thành IP của DB và nhận 2 gói phản hồi, 0% packet loss.
3. Sau khi `docker rm -f db-server` và tạo lại container DB với cùng volume, câu `SELECT * FROM students;` vẫn trả về 2 dòng:

```
 id |     name
----+--------------
  1 | Nguyen Van A
  2 | Tran Thi B
(2 rows)
```

## Giải thích

- **Vì sao dùng custom bridge network?** Network `bridge` mặc định không có DNS theo tên container. Custom bridge network có DNS nội bộ nên `app-container` gọi được `db-server` bằng tên, không cần hard-code IP (IP đổi khi container được tạo lại).
- **Vì sao dữ liệu không mất?** Dữ liệu Postgres nằm trong Named Volume `db-data` do Docker quản lý, tách rời khỏi writable layer của container. Xóa container không xóa volume; container mới mount lại cùng volume sẽ đọc lại data cũ. Khi đó Postgres phát hiện thư mục data đã khởi tạo nên bỏ qua bước init.
- **Lưu ý:** `docker rm -f` không xóa volume. Chỉ `docker volume rm db-data` hoặc `docker rm -v` (với anonymous volume) hoặc `docker compose down -v` mới xóa dữ liệu.

## Dọn dẹp

```bash
docker rm -f app-container db-server
docker volume rm db-data
docker network rm app-net
```
