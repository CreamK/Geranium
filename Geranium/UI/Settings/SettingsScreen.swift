//
//  SettingsScreen.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import SwiftUI

struct SettingsScreen: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Group {
            if #available(iOS 16.0, *) {
                NavigationStack {
                    settingsList
                        .navigationTitle("设置")
                }
            } else {
                NavigationView {
                    settingsList
                        .navigationTitle("设置")
                }
            }
        }
    }

    private var settingsList: some View {
        List {
            Section(header: Text("模拟行为")) {
                VStack(alignment: .leading) {
                    Text("默认地图缩放（米）")
                        .font(.subheadline)
                    Slider(value: binding(\.defaultZoomLevel), in: 200...2000, step: 50)
                    Text(String(format: "%.0f 米", viewModel.settings.defaultZoomLevel))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.vertical, 6)
            }
            
            Section(header: Text("搜索历史")) {
                Button(action: {
                    viewModel.clearSearchHistory()
                }) {
                    HStack {
                        Text("清除搜索历史")
                            .foregroundColor(.red)
                        Spacer()
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                }
            }

            Section(header: Text("关于")) {
                HStack {
                    Text("版本")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-")
                        .foregroundStyle(.secondary)
                }

                Link(destination: URL(string: "https://github.com/Wtrwx/Geranium")!) {
                    Label("GitHub 项目主页", systemImage: "link")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func binding<Value>(_ keyPath: ReferenceWritableKeyPath<LocSimSettings, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.settings[keyPath: keyPath] },
            set: { viewModel.settings[keyPath: keyPath] = $0 }
        )
    }
}
