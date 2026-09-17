import Foundation

/// 本地化便捷入口：英文为源语言（key 即英文原文），翻译放在
/// app bundle Resources/<lang>.lproj/Localizable.strings
@inlinable
public func L(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

/// 带格式化参数的本地化
@inlinable
public func LF(_ key: String, _ args: CVarArg...) -> String {
    String(format: NSLocalizedString(key, comment: ""), locale: .current, arguments: args)
}
