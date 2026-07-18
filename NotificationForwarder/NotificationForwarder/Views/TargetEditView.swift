import SwiftUI

struct TargetEditView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var target: ForwardTarget
    private let isNew: Bool
    private let onSave: (ForwardTarget) -> Void

    init(target: ForwardTarget?, onSave: @escaping (ForwardTarget) -> Void) {
        if let target {
            _target = State(initialValue: target)
            isNew = false
        } else {
            _target = State(initialValue: ForwardTarget(name: "", type: .webhook))
            isNew = true
        }
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("基本信息") {
                TextField("名称", text: $target.name)
                Picker("类型", selection: $target.type) {
                    ForEach(ForwardTargetType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                Toggle("启用", isOn: $target.enabled)
            }

            Section("配置参数") {
                ForEach(fieldSpecs, id: \.key) { spec in
                    fieldEditor(for: spec)
                }
            }

            Section {
                Button("保存") {
                    onSave(target)
                    dismiss()
                }
                .disabled(target.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle(isNew ? "新建目标" : "编辑目标")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") { dismiss() }
            }
        }
    }

    // MARK: - 字段定义

    private struct FieldSpec {
        let key: String
        let title: String
        let placeholder: String
        let isSecret: Bool
        let keyboardType: UIKeyboardType
    }

    private var fieldSpecs: [FieldSpec] {
        switch target.type {
        case .webhook:
            return [
                .init(key: ForwardTargetKeys.webhookURL, title: "Webhook URL", placeholder: "https://...", isSecret: false, keyboardType: .URL),
                .init(key: ForwardTargetKeys.webhookHeaders, title: "自定义请求头 (JSON)", placeholder: "{\"X-Key\":\"value\"}", isSecret: false, keyboardType: .default),
                .init(key: ForwardTargetKeys.webhookAuthToken, title: "Bearer Token", placeholder: "可选", isSecret: true, keyboardType: .default)
            ]
        case .email:
            return [
                .init(key: ForwardTargetKeys.smtpHost, title: "API Base URL", placeholder: "https://api.mailgun.net/v3/yourdomain", isSecret: false, keyboardType: .URL),
                .init(key: ForwardTargetKeys.smtpUsername, title: "用户名", placeholder: "api", isSecret: false, keyboardType: .default),
                .init(key: ForwardTargetKeys.smtpPassword, title: "API Key / 密码", placeholder: "", isSecret: true, keyboardType: .default),
                .init(key: ForwardTargetKeys.emailFrom, title: "发件邮箱", placeholder: "from@example.com", isSecret: false, keyboardType: .emailAddress),
                .init(key: ForwardTargetKeys.emailTo, title: "收件邮箱", placeholder: "to@example.com", isSecret: false, keyboardType: .emailAddress)
            ]
        case .sms:
            return [
                .init(key: ForwardTargetKeys.smsGatewayBaseURL, title: "网关 Base URL", placeholder: "https://api.twilio.com/2010-04-01", isSecret: false, keyboardType: .URL),
                .init(key: ForwardTargetKeys.smsAccountSID, title: "Account SID", placeholder: "ACxxxx", isSecret: false, keyboardType: .default),
                .init(key: ForwardTargetKeys.smsAuthToken, title: "Auth Token", placeholder: "", isSecret: true, keyboardType: .default),
                .init(key: ForwardTargetKeys.smsFrom, title: "发件号码", placeholder: "+1xxxxxxxxxx", isSecret: false, keyboardType: .phonePad),
                .init(key: ForwardTargetKeys.smsTo, title: "收件号码", placeholder: "+86xxxxxxxxxxx", isSecret: false, keyboardType: .phonePad)
            ]
        case .thirdPartyApp:
            return [
                .init(key: ForwardTargetKeys.appPlatform, title: "平台", placeholder: "telegram / slack / discord", isSecret: false, keyboardType: .default),
                .init(key: ForwardTargetKeys.appBotToken, title: "Bot Token / Webhook URL", placeholder: "", isSecret: true, keyboardType: .default),
                .init(key: ForwardTargetKeys.appChatID, title: "Chat ID（仅 Telegram 需要）", placeholder: "123456789", isSecret: false, keyboardType: .default)
            ]
        }
    }

    @ViewBuilder
    private func fieldEditor(for spec: FieldSpec) -> some View {
        let binding = Binding<String>(
            get: { target.params[spec.key] ?? "" },
            set: { target.params[spec.key] = $0 }
        )
        VStack(alignment: .leading) {
            Text(spec.title).font(.caption).foregroundStyle(.secondary)
            if spec.isSecret {
                SecureField(spec.placeholder, text: binding)
            } else {
                TextField(spec.placeholder, text: binding)
                    #if !os(macOS)
                    .keyboardType(spec.keyboardType)
                    .textInputAutocapitalization(.never)
                    #endif
            }
        }
        .padding(.vertical, 2)
    }
}
