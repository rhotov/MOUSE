import SwiftUI

private let accent = Color(red: 0.08, green: 0.53, blue: 0.49)

struct PanelView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            VStack(alignment: .leading, spacing: 6) {
                Text("滚动，各有方向。")
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                Text("触控板照常，鼠标反过来。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            devices

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: Binding(get: { model.isEnabled }, set: model.setEnabled)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("鼠标反向滚动").font(.system(size: 14, weight: .semibold))
                        Text("相对于 macOS 的滚动方向")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(accent)
                .accessibilityIdentifier("reverseMouseToggle")

                if !model.accessibilityGranted {
                    permissionCard
                } else if model.serviceFailed && model.isEnabled {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("暂时无法处理滚动事件", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 12, weight: .medium))
                        Text("请检查系统权限，并退出其他修改滚动方向的工具后重试。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("重新连接") { model.restartService() }
                            .controlSize(.small)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                Divider()
                Toggle("登录时启动", isOn: Binding(get: { model.launchAtLogin }, set: model.setLaunchAtLogin))
                    .font(.system(size: 12))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .tint(accent)
                    .accessibilityIdentifier("launchAtLoginToggle")

                if model.loginNeedsApproval {
                    Button("在系统设置中允许登录项…") { model.openLoginSettings() }
                        .font(.system(size: 11))
                }
                if let error = model.loginError {
                    Text(error).font(.system(size: 11)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                DisclosureGroup("设备兼容说明", isExpanded: $model.showCompatibility) {
                    Text("支持普通滚轮和 MX Master 3 等精细滚轮。触控板及惯性滚动保持系统方向；Magic Mouse 和模拟触控手势的驱动仍可能保持原方向。")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                HStack {
                    Text("MOUSE 1.0.1").font(.system(size: 10, weight: .medium, design: .monospaced))
                    Spacer()
                    Button("退出") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .help("退出后立即恢复系统滚动方向")
                }
                .foregroundStyle(.tertiary)
            }
        }
        .padding(24)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { model.refresh(forceRetry: true) }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(accent)
            Text("MOUSE")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(2)
            Spacer()
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 5, height: 5)
                Text(model.statusText).font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(statusColor.opacity(0.09), in: Capsule())
            .foregroundStyle(statusColor)
            .accessibilityElement(children: .combine)
        }
    }

    private var statusColor: Color {
        if !model.isEnabled { return .secondary }
        return model.isRunning ? accent : .orange
    }

    private var devices: some View {
        HStack(spacing: 12) {
            deviceCard(symbol: "rectangle.and.hand.point.up.left", title: "触控板", detail: "系统方向", reversed: false)
            Image(systemName: model.isEnabled ? "arrow.left.arrow.right" : "equal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            deviceCard(symbol: "computermouse", title: "鼠标", detail: model.isEnabled ? "反向滚动" : "系统方向", reversed: model.isEnabled)
        }
        .accessibilityElement(children: .combine)
    }

    private func deviceCard(symbol: String, title: String, detail: String, reversed: Bool) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 27, weight: .light))
                Image(systemName: reversed ? "arrow.down" : "arrow.up")
                    .font(.system(size: 15, weight: .medium))
            }
            .frame(height: 36)
            .foregroundStyle(reversed ? accent : Color.secondary)
            VStack(spacing: 4) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 17)
        .frame(maxWidth: .infinity)
        .background(reversed ? accent.opacity(0.07) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(reversed ? accent.opacity(0.16) : Color.primary.opacity(0.04)))
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("还差一步：允许辅助功能", systemImage: "hand.raised")
                .font(.system(size: 12, weight: .semibold))
            Text("在系统设置中允许 MOUSE 调整滚动事件。授权后会自动开始运行。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: model.requestPermission) {
                HStack {
                    Text("打开系统设置")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 11, weight: .medium))
                .padding(.vertical, 2)
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .accessibilityIdentifier("grantPermissionButton")
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }
}
