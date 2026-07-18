import SwiftUI
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject var configManager: ConfigManager
    @State private var logs: [LogEntry] = []
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        Form {
            Section("全局") {
                Toggle("启用推送转发", isOn: Binding(
                    get: { configManager.config.masterEnabled },
                    set: { configManager.setMasterEnabled($0) }
                ))
                Toggle("调试日志", isOn: Binding(
                    get: { configManager.config.debugLogging },
                    set: { configManager.setDebugLogging($0) }
                ))
            }

            Section("App Group 状态") {
                statusRow("App Group ID", value: AppConstants.appGroupID)
                statusRow("共享容器", value: ConfigStore.shared.sharedContainerURL?.path ?? "❌ 不可用")
                statusRow("配置文件", value: ConfigStore.shared.configFileURL?.path ?? "❌")
                statusRow("目标数", value: "\(configManager.config.targets.count)")
                statusRow("规则数", value: "\(configManager.config.rules.count)")
            }

            Section("推送权限") {
                Button("检查通知权限") {
                    UNUserNotificationCenter.current().getNotificationSettings { settings in
                        let msg: String
                        switch settings.authorizationStatus {
                        case .authorized:      msg = "已授权"
                        case .denied:          msg = "已被拒绝，请到系统设置开启"
                        case .notDetermined:   msg = "未请求"
                        case .provisional:     msg = "临时授权"
                        case .ephemeral:       msg = "临时（App Clip）"
                        @unknown default:      msg = "未知"
                        }
                        DispatchQueue.main.async {
                            alertMessage = msg
                            showingAlert = true
                        }
                    }
                }
                Button("请求通知权限") {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { ok, _ in
                        DispatchQueue.main.async {
                            alertMessage = ok ? "已授权" : "已拒绝"
                            showingAlert = true
                        }
                    }
                }
            }

            Section {
                Button("发送模拟推送（无附件）") {
                    PushSimulator.shared.sendSimulated(title: "模拟推送", body: "这是一条本地模拟的推送，用于验证转发链路。", attachmentURL: nil) { msg in
                        alertMessage = msg
                        showingAlert = true
                    }
                }
                Button("发送模拟推送（带图片附件）") {
                    PushSimulator.shared.sendSimulated(title: "模拟推送·带图", body: "用于验证附件下载与上传链路。", attachmentURL: URL(string: "https://www.gstatic.com/webp/gallery/1.jpg")) { msg in
                        alertMessage = msg
                        showingAlert = true
                    }
                }
            } header: {
                Text("本地模拟推送（无需 APNs 证书）")
            } footer: {
                Text("触发本地通知（带 mutable-content）让 Extension 跑起来。即便 TrollStore 无法收到真实 APNs，也能用此入口验证转发是否生效。")
            }

            if configManager.config.debugLogging {
                Section("调试日志") {
                    Button("刷新") { logs = SharedLogger.shared.readAll() }
                    Button("清空日志", role: .destructive) {
                        SharedLogger.shared.clear()
                        logs = []
                    }
                    if logs.isEmpty {
                        Text("暂无日志").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(logs) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(entry.level.rawValue.uppercased())
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .background(levelColor(entry.level).opacity(0.2))
                                        .foregroundStyle(levelColor(entry.level))
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                    Text(entry.timestamp.formatted(.dateTime))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.message).font(.caption)
                                Text("\(entry.file):\(entry.line)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section("关于") {
                LabeledContent("版本", value: "1.0")
                Link("Apple 文档：Notification Service Extension",
                     destination: URL(string: "https://developer.apple.com/documentation/usernotifications/unnotificationserviceextension")!)
            }
        }
        .navigationTitle("设置")
        .onAppear {
            if configManager.config.debugLogging {
                logs = SharedLogger.shared.readAll()
            }
        }
        .alert("提示", isPresented: $showingAlert) {
            Button("好") {}
        } message: {
            Text(alertMessage)
        }
    }

    private func statusRow(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption2).textSelection(.enabled)
        }
    }

    private func levelColor(_ level: LogLevel) -> Color {
        switch level {
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}
