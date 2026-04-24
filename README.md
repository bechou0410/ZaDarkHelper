<div align="center">

# ZaDarkHelper

**Menu-bar mini app cho macOS, cài đặt và tự động duy trì ZaDark (dark mode cho Zalo PC) qua mỗi lần Zalo cập nhật.**

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000?logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Swift 5.9](https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white)](https://swift.org)
[![License: MPL 2.0](https://img.shields.io/badge/License-MPL%202.0-brightgreen)](LICENSE)
[![Based on ZaDark](https://img.shields.io/badge/based%20on-ncdai%2Fzadark-purple)](https://github.com/ncdai/zadark)

</div>

---

> **Important:** ZaDarkHelper không phải ZaDark. Đây là wrapper cộng đồng cho CLI **ZaDark** chính thức của [@ncdai](https://github.com/ncdai). Mọi logic patch `app.asar` của Zalo đều do upstream ZaDark xử lý — helper chỉ tự động hoá: cài, phát hiện Zalo update, áp lại, thông báo có bản mới.

## Vì sao có helper này?

Zalo PC trên macOS **tự động cập nhật** và mỗi lần cập nhật sẽ **ghi đè** file `app.asar` mà ZaDark đã patch — khiến dark mode biến mất. Cách xử lý trước kia là mở Terminal chạy `zadark install` lại bằng tay sau mỗi lần Zalo update.

ZaDarkHelper tự động hoá việc đó:

- 🔍 Theo dõi `/Applications/Zalo.app` bằng FSEvents + NSWorkspace observer
- 🧩 Phát hiện Zalo vừa cập nhật (build number đổi) → tự quit Zalo → chạy lại `zadark install` → mở lại Zalo
- ⬆️ Kiểm tra Homebrew tap [`quaric/zadark`](https://github.com/quaric/homebrew-zadark) định kỳ, thông báo khi ZaDark CLI có bản mới
- 🩹 Phát hiện trạng thái hỏng (app.asar mất, backup vẫn còn) → một click "Khôi phục"
- 🛡️ Tất cả chạy với **App Management** TCC grant — không cần sudo

## Cài đặt

### Option A — Tải DMG (khuyên dùng)

Tải `ZaDarkHelper-<version>.dmg` mới nhất từ [Releases](https://github.com/bechou0410/ZaDarkHelper/releases).

```bash
# Sau khi tải, mount + kéo .app vào Applications
open ~/Downloads/ZaDarkHelper-0.1.0.dmg
# Kéo ZaDarkHelper vào Applications, eject DMG
# Right-click → Open (lần đầu, do DMG chưa được Apple ký)
```

### Option B — Build từ source

Yêu cầu: Xcode 15+, `xcodegen`, `create-dmg`.

```bash
# Clone
git clone https://github.com/bechou0410/ZaDarkHelper.git
cd ZaDarkHelper

# Cài toolchain (nếu chưa có)
brew install xcodegen create-dmg

# Dev build (một lần — tạo self-signed cert để TCC grant không mất khi rebuild)
./scripts/create-dev-cert.sh

# Build Debug
cd ZaDarkHelper && xcodegen generate
xcodebuild -scheme ZaDarkHelper -configuration Debug build

# Hoặc full release DMG
cd .. && ./scripts/build-release.sh
# Output: build/ZaDarkHelper-<version>.dmg
```

## Sử dụng

1. Mở app — icon mặt trăng xuất hiện ở menu bar.
2. Lần đầu: onboarding wizard 3 bước (Chào mừng → Cấp quyền App Management → Cài ZaDark).
3. Nhấn **Cài ZaDark** — helper sẽ `brew tap quaric/zadark`, `brew install zadark`, rồi `zadark install`.
4. Zalo mở ra đã có dark mode.
5. Helper chạy ngầm — không cần làm gì thêm.

Xem chi tiết: [docs/install-guide.md](docs/install-guide.md) · [docs/grant-permissions.md](docs/grant-permissions.md) · [docs/uninstall-guide.md](docs/uninstall-guide.md)

## Kiến trúc

```
ZaDarkHelper.app (menu bar, LSUIElement, no sandbox)
│
├── Core services
│   ├── ShellRunner              Process wrapper, streams stdout/stderr
│   ├── HomebrewService          brew tap / install / upgrade / outdated
│   ├── ZaDarkCLI                zadark install / uninstall / -v (lazy-resolve binary)
│   ├── ZaloVersionProbe         Info.plist + app.asar SHA256
│   ├── ZaloBundleWatcher        FSEvents, 2s debounce, build-number diff
│   ├── WorkspaceObserver        NSWorkspace launch + wake notifications
│   ├── ReinstallOrchestrator    actor, re-entry guarded, auto-relaunch logic
│   ├── GitHubReleaseChecker     self-update check via GitHub API
│   └── ZaloLauncher             NSWorkspace.openApplication wrapper (reliable)
│
├── State
│   ├── AppState                 @Observable, session-based log model
│   └── Preferences              Codable, persisted via UserDefaults
│
└── Views (SwiftUI)
    ├── MainPopoverView          inline onboarding + inline settings (no modal sheet)
    ├── StatusHero/*             hero card, gradient backdrop, pulse icon
    ├── VersionChip              compact "ZaDark v26.2" pill
    ├── ActionPillButton         context-aware primary action
    ├── LogDrawerView            session-grouped logs, stdout/stderr filters
    └── Onboarding/*             3-step inline wizard
```

## Kiểm tra cập nhật tự động

ZaDarkHelper kiểm tra GitHub Releases định kỳ (6h + on wake) cho chính nó. Khi có bản mới, banner xuất hiện cuối popover với link tải về. Không auto-download; user tự quyết định.

Tắt trong Settings → "Thông báo khi ZaDark có bản mới" (cùng toggle áp dụng cho cả helper + CLI).

## Đóng góp

Issues + PRs welcome. Vui lòng:

1. Fork repo
2. Tạo branch `feat/xxx` hoặc `fix/xxx`
3. Commit theo conventional commits
4. PR về `main`

Khi sửa code, chạy `./scripts/create-dev-cert.sh` một lần để build Debug không mất App Management TCC grant giữa các lần build.

## Credit & Acknowledgements

Helper này **không tồn tại được** nếu không có:

- **[ZaDark](https://github.com/ncdai/zadark)** của [@ncdai](https://github.com/ncdai) — CLI chính thức cung cấp logic patch `app.asar` của Zalo. Toàn bộ phần tinh tế của dark mode đến từ dự án này.
- **[homebrew-zadark](https://github.com/quaric/homebrew-zadark)** của [@quaric](https://github.com/quaric) — Homebrew formula cho ZaDark, là lớp phân phối chính thức helper này gọi qua.
- **[Zalo PC](https://zalo.me/pc)** của [VNG](https://www.vng.com.vn/) — ứng dụng nền.
- **Apple** — SwiftUI, AppKit, SF Symbols, FSEvents.
- **[Claude](https://claude.ai/code)** (Anthropic) — hỗ trợ code generation, kiến trúc SwiftUI, debugging TCC permission flows.

Helper này là **wrapper**, không re-implement logic patching. Nếu bạn dùng được ZaDark từ Terminal, bạn không cần helper này — nó chỉ tự động hoá cho user ngại dùng CLI.

## Miễn trừ trách nhiệm

**ZaDarkHelper là phần mềm cộng đồng, không chính thức.** Các lưu ý sau mang tính chất bắt buộc:

1. **Không liên kết với Zalo / VNG.** Helper này không được Zalo hay VNG Online Co. Ltd ủng hộ, bảo trợ, hay uỷ quyền.
2. **Không liên kết chính thức với upstream ZaDark.** Đây là wrapper độc lập. Mọi vấn đề với **logic patching** xin báo về [ncdai/zadark](https://github.com/ncdai/zadark/issues). Vấn đề về **helper app** (menu bar UI, auto-relaunch, onboarding) báo về issue của repo này.
3. **Có thể vi phạm ToS của Zalo.** Patch `app.asar` làm thay đổi file trong app của bên thứ ba. Sử dụng helper này có rủi ro vi phạm Terms of Service của Zalo / VNG. Tác giả helper KHÔNG chịu trách nhiệm cho bất kỳ hậu quả nào bao gồm nhưng không giới hạn:
   - Tài khoản Zalo bị khoá / ban
   - Dữ liệu / tin nhắn bị mất
   - Zalo từ chối cập nhật / ngừng hoạt động
   - Xung đột với bản vá bảo mật của Zalo
4. **Không bảo đảm tương thích.** Zalo có thể thay đổi cấu trúc `app.asar` bất kỳ lúc nào, khiến patch của ZaDark fail. Helper sẽ phát hiện trạng thái lỗi nhưng không tự sửa logic patch của upstream.
5. **DMG chưa được Apple notarize.** Bản build hiện tại là dev preview, ad-hoc signed. Gatekeeper sẽ yêu cầu right-click Open lần đầu. Tự chịu trách nhiệm khi mở. Để verify, kiểm tra `codesign -dvvv`.
6. **Cần quyền App Management và chạy không sandbox** để ghi vào `/Applications/Zalo.app`. Điều này hạn chế cho phần mềm mà bạn tin tưởng — xem source code trước khi build/cài.
7. **Backup dữ liệu Zalo trước khi dùng.** Thư mục user data của Zalo ở `~/Library/Application Support/Zalo*`. Copy đi nơi khác trước khi test.

Sử dụng có nghĩa là bạn đồng ý với các điều khoản trên.

## License

[Mozilla Public License 2.0](LICENSE) — tương thích với upstream ZaDark.

---

<div align="center">
<sub>Made with ☕ + SwiftUI — đóng góp chào đón.</sub>
</div>
