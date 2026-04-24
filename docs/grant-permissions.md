# Cấp quyền App Management

Từ macOS Ventura (13.0) trở đi, Apple chặn mọi app không được ký Developer ID ghi vào `/Applications`. ZaDark cần ghi vào `/Applications/Zalo.app/Contents/Resources/app.asar` để áp dark mode, nên ZaDark Helper phải được cấp quyền **App Management**.

## Các bước

1. Mở **System Settings** (Cài đặt hệ thống).
2. Vào **Privacy & Security** → **App Management**.
   - Hoặc click nút **Mở System Settings** trong banner màu cam trên app.
3. Bật công tắc cạnh **ZaDarkHelper**.
   - Nếu chưa thấy, hãy thử cài ZaDark một lần → macOS sẽ tự thêm vào danh sách.
4. macOS có thể yêu cầu khởi động lại app — làm theo.

## Xác nhận

- Quay lại ZaDarkHelper.
- Banner cam sẽ biến mất.
- Nhấn **Áp lại ZaDark** để test — không còn báo "permission denied".

## Nếu vẫn bị chặn

- Kiểm tra **Full Disk Access** — một số phiên bản macOS đòi thêm quyền này.
- Kiểm tra xem ZaDarkHelper có trong **Login Items → Allowed in Background** không (nếu bật "Chạy cùng macOS").
- Reset TCC:
  ```bash
  tccutil reset SystemPolicyAppBundles com.chou.zadarkhelper
  ```
  Sau đó mở lại app và cấp quyền lại từ đầu.
