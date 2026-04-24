import Foundation

/// Typed errors surfaced to UI layer. Raw shell output lives in logs.
enum ZaDarkHelperError: LocalizedError, Equatable {
    case brewNotFound
    case brewBootstrapRequired
    case tapFailed(String)
    case formulaInstallFailed(String)
    case formulaUpgradeFailed(String)
    case zaloNotFound
    case zaloRunning
    case permissionDenied
    case zadarkBinaryMissing
    case commandFailed(exit: Int32, stderr: String)
    case backupMissing
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Không tìm thấy Homebrew trên máy."
        case .brewBootstrapRequired:
            return "Cần cài Homebrew trước khi tiếp tục."
        case .tapFailed(let msg):
            return "Không thêm được tap quaric/zadark: \(msg)"
        case .formulaInstallFailed(let msg):
            return "Cài zadark thất bại: \(msg)"
        case .formulaUpgradeFailed(let msg):
            return "Nâng cấp zadark thất bại: \(msg)"
        case .zaloNotFound:
            return "Không tìm thấy /Applications/Zalo.app. Cài Zalo từ https://zalo.me/pc trước."
        case .zaloRunning:
            return "Zalo đang chạy. Thoát Zalo rồi thử lại."
        case .permissionDenied:
            return "macOS chặn ghi vào Zalo.app. Cấp quyền App Management trong System Settings."
        case .zadarkBinaryMissing:
            return "Không tìm thấy binary `zadark`. Thử cài lại qua Homebrew."
        case .commandFailed(let exit, let stderr):
            let tail = stderr.split(separator: "\n").suffix(3).joined(separator: " | ")
            return "Lệnh thất bại (exit \(exit)): \(tail)"
        case .backupMissing:
            return "Không thấy app.asar.bak. Cài lại Zalo rồi thử ZaDark."
        case .unknown(let msg):
            return msg
        }
    }

    /// Classify raw stderr fragments into typed errors.
    static func classify(exit: Int32, stderr: String) -> ZaDarkHelperError {
        let lower = stderr.lowercased()
        if lower.contains("operation not permitted") || lower.contains("permission denied") {
            return .permissionDenied
        }
        if lower.contains("app.asar.bak") && lower.contains("no such") {
            return .backupMissing
        }
        if lower.contains("zalo.app") && lower.contains("no such") {
            return .zaloNotFound
        }
        return .commandFailed(exit: exit, stderr: stderr)
    }
}
