# ZaDark Helper — Install Guide

Mini menu-bar utility that installs [ZaDark](https://zadark.com/pc/macos) (dark mode for Zalo) on macOS and keeps it patched whenever Zalo updates.

## Prerequisites

- macOS 14 Sonoma trở lên
- Zalo PC đã cài tại `/Applications/Zalo.app` (tải từ https://zalo.me/pc)
- [Homebrew](https://brew.sh) — app sẽ hướng dẫn cài nếu thiếu

## 1. Tải DMG

Tải `ZaDarkHelper-<version>.dmg` từ trang Releases của repo.

## 2. Mở DMG và kéo vào Applications

Double-click DMG → kéo `ZaDarkHelper.app` sang thư mục `Applications`.

## 3. Mở lần đầu (quan trọng)

Vì DMG **chưa được Apple ký** (dev preview), macOS sẽ chặn lần đầu:

1. Mở `Applications` trong Finder.
2. **Chuột phải** lên `ZaDarkHelper.app` → **Open**.
3. Hộp thoại Gatekeeper hiện ra → chọn **Open** lần nữa.

Từ lần thứ hai trở đi mở bình thường.

## 4. Cấp quyền App Management

macOS Ventura+ yêu cầu quyền riêng để ghi vào `/Applications/Zalo.app`. Xem [grant-permissions.md](grant-permissions.md).

## 5. Cài ZaDark

1. Click icon mặt trăng ở menu bar → popover mở ra.
2. Nếu chưa có Homebrew → nhấn **Cài Homebrew qua Terminal**, làm theo hướng dẫn trong Terminal, quay lại app.
3. Nhấn **Cài ZaDark**.
4. Đợi 10-30s. Khi thấy trạng thái chuyển thành "ZaDark đang hoạt động" là xong.
5. Mở Zalo → giao diện đã chuyển sang tối.

## 6. Tự động hoá

Mặc định:
- App chạy cùng macOS khi đăng nhập.
- Tự động áp lại ZaDark mỗi khi Zalo cập nhật.
- Thông báo khi ZaDark có bản mới.

Có thể bật/tắt từng tuỳ chọn trong **Settings** (icon bánh răng).

## Gỡ bỏ

Xem [uninstall-guide.md](uninstall-guide.md).
