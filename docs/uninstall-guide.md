# Gỡ ZaDark Helper

## Bước 1 — Gỡ ZaDark khỏi Zalo

Mở ZaDarkHelper → nhấn **Settings** → cuộn xuống, hoặc chạy trong Terminal:

```bash
zadark uninstall
```

Lệnh này khôi phục `app.asar.bak` → `app.asar`, trả Zalo về trạng thái gốc.

## Bước 2 — Gỡ binary ZaDark

```bash
brew uninstall zadark
brew untap quaric/zadark
```

## Bước 3 — Gỡ ZaDarkHelper

1. Thoát app từ menu bar (**Thoát**).
2. Kéo `ZaDarkHelper.app` từ `/Applications` vào Thùng rác.
3. Gỡ login item (nếu đã bật):
   - System Settings → General → Login Items → xoá ZaDarkHelper.
4. (Tuỳ chọn) Xoá settings đã lưu:
   ```bash
   defaults delete com.chou.zadarkhelper
   rm -rf ~/Library/Containers/com.chou.zadarkhelper
   rm -rf ~/Library/Application\ Support/ZaDarkHelper
   ```

## Gỡ hoàn toàn trong một dòng

```bash
zadark uninstall 2>/dev/null; \
brew uninstall zadark 2>/dev/null; \
brew untap quaric/zadark 2>/dev/null; \
rm -rf /Applications/ZaDarkHelper.app; \
defaults delete com.chou.zadarkhelper 2>/dev/null; \
echo "Done."
```
