import SwiftUI
import UIKit

/// 卡密输入框的聚焦控制。
/// 设置页出现后可以主动把键盘调起来 —— iOS 14 上就算第一下点击被吞掉，
/// 用户也能直接开始打字（不用再研究"为什么点不动"）。
final class CardCodeFocus: ObservableObject {
    weak var field: UITextField?

    func focus() {
        guard let f = field else { return }
        if !f.isFirstResponder { f.becomeFirstResponder() }
    }

    func blur() {
        field?.resignFirstResponder()
    }
}

/// 卡密输入框：直接包一层 UITextField。
///
/// 为什么不用 SwiftUI 的 TextField：
/// iOS 14 上它套在「玻璃卡片 + ZStack 占位符」这层结构里点击拿不到第一响应者，
/// 键盘根本不弹 —— 重装或换机的用户根本没法激活。UITextField 走 UIKit 自己的
/// 命中测试，14 到 27 表现一致；顺便把占位符换成原生的，
/// 少一层 ZStack 覆盖，也就少一个吃掉点击的可能。
struct CardCodeField: UIViewRepresentable {

    @Binding var text: String
    var placeholder: String
    var focusBox: CardCodeFocus
    var onCommit: () -> Void

    init(text: Binding<String>,
         placeholder: String,
         focusBox: CardCodeFocus,
         onCommit: @escaping () -> Void = {}) {
        self._text = text
        self.placeholder = placeholder
        self.focusBox = focusBox
        self.onCommit = onCommit
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        tf.textColor = .white
        tf.tintColor = UIColor(red: 0.18, green: 0.84, blue: 1.00, alpha: 1.0)
        tf.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        tf.keyboardType = .asciiCapable
        tf.keyboardAppearance = .dark
        tf.returnKeyType = .done
        tf.autocapitalizationType = .allCharacters
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.smartDashesType = .no
        tf.smartQuotesType = .no
        tf.smartInsertDeleteType = .no
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: UIColor.white.withAlphaComponent(0.36),
                .font: UIFont.systemFont(ofSize: 13, weight: .regular),
            ])
        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.changed(_:)),
                     for: .editingChanged)
        tf.addTarget(context.coordinator,
                     action: #selector(Coordinator.finished(_:)),
                     for: .editingDidEnd)
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        focusBox.field = tf
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        focusBox.field = uiView
        if uiView.text != text { uiView.text = text }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CardCodeField

        init(_ parent: CardCodeField) { self.parent = parent }

        @objc func changed(_ tf: UITextField) {
            let clean = CardCodeField.format(tf.text ?? "")
            if tf.text != clean { tf.text = clean }
            parent.text = clean
        }

        @objc func finished(_ tf: UITextField) {
            parent.text = CardCodeField.format(tf.text ?? "")
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            tf.resignFirstResponder()
            parent.onCommit()
            return true
        }
    }

    /// 只留字母数字，自动补 4-4-4-4 的短横线；多打的符号和超长部分直接吃掉
    static func format(_ raw: String) -> String {
        var letters = ""
        for ch in raw.uppercased() where (ch >= "A" && ch <= "Z") || (ch >= "0" && ch <= "9") {
            letters.append(ch)
        }
        if letters.count > 16 { letters = String(letters.prefix(16)) }
        var out = ""
        for (i, ch) in letters.enumerated() {
            if i > 0 && i % 4 == 0 { out.append("-") }
            out.append(ch)
        }
        return out
    }
}
