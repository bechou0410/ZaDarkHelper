# Dev TCC Setup — giữ quyền App Management qua các lần build

## Vấn đề

Khi build Debug, Xcode dùng ad-hoc signing (`-` = "Sign to Run Locally"). Mỗi lần code thay đổi, binary bytes đổi → **cdhash** đổi → TCC (Transparency, Consent, Control) xem như một app hoàn toàn khác → hỏi quyền App Management lại từ đầu.

## Giải pháp

Tạo một **self-signed codesigning identity** cố định trong login keychain. TCC key grants theo **signing identity** (stable) thay vì cdhash (bytes-dependent). Build sau khi ký bằng identity này → TCC grant chỉ cần cấp 1 lần, giữ vĩnh viễn.

## Setup (1 lần duy nhất)

```bash
./scripts/create-dev-cert.sh
```

Script sẽ:
1. Tạo key RSA 2048 + self-signed cert hạn 10 năm, EKU = `codeSigning`
2. Import vào login keychain với quyền codesign
3. Trust cert đó cho code signing ở System keychain (yêu cầu sudo password một lần)
4. Verify identity hiện trong `security find-identity -v -p codesigning`

## Build sau khi setup

```bash
cd ZaDarkHelper
xcodegen generate
xcodebuild -scheme ZaDarkHelper -configuration Debug build
```

`project.yml` đã set `CODE_SIGN_IDENTITY: ZaDarkHelperDev` — Xcode tự tìm và dùng.

## Cấp quyền lần cuối

1. Build + mở app lần đầu
2. Khi helper ghi vào Zalo.app → macOS hỏi App Management
3. System Settings → Privacy & Security → App Management → bật **ZaDarkHelper**

**Từ đó về sau:** mọi build mới (vẫn ký bằng `ZaDarkHelperDev`) → quyền được giữ. Không cần cấp lại.

## Verify grant không reset

```bash
# Build code mới, rebuild, relaunch:
xcodebuild -scheme ZaDarkHelper -configuration Debug build
killall ZaDarkHelper; open ~/Library/Developer/Xcode/DerivedData/ZaDarkHelper-*/Build/Products/Debug/ZaDarkHelper.app

# Thử ghi vào Zalo.app qua helper (ví dụ: giả lập broken state rồi bấm "Khôi phục")
# Không có dialog TCC hiện ra nữa = thành công
```

## Troubleshooting

**`xcodebuild` báo "No signing certificate found"**
→ Identity chưa import được. Chạy lại `./scripts/create-dev-cert.sh` và xem:
```bash
security find-identity -v -p codesigning | grep ZaDarkHelperDev
```

**macOS vẫn hỏi quyền sau khi setup**
→ Có thể Xcode rơi về ad-hoc. Kiểm tra:
```bash
codesign -dvvv "$(find ~/Library/Developer/Xcode/DerivedData -name ZaDarkHelper.app -path '*/Debug/*' | head -1)" 2>&1 | grep Authority
```
Phải thấy `Authority=ZaDarkHelperDev`. Nếu thấy `Signature=adhoc` → clean DerivedData rồi build lại.

**Reset TCC (nếu muốn bắt đầu lại)**
```bash
tccutil reset SystemPolicyAppBundles com.chou.zadarkhelper
```

## Cách trở về ad-hoc (nếu không muốn dùng self-signed)

Trong `project.yml`:
```yaml
CODE_SIGN_STYLE: Automatic
CODE_SIGN_IDENTITY: "-"
```

Xoá `DEVELOPMENT_TEAM`. Chấp nhận phải cấp quyền lại mỗi lần binary đổi.
