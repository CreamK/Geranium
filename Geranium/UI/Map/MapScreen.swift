//
//  MapScreen.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import SwiftUI
import MapKit
#if canImport(UIKit)
import UIKit
#endif

struct MapScreen: View {
    @ObservedObject var viewModel: MapViewModel
    @EnvironmentObject private var bookmarkStore: BookmarkStore
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            MapCanvasView(region: $viewModel.mapRegion,
                          selectedCoordinate: viewModel.selectedLocation?.coordinate,
                          activeCoordinate: viewModel.activeLocation?.coordinate,
                          mapType: viewModel.mapType,
                          onTap: { coordinate in
                              dismissKeyboard()
                              viewModel.handleMapTap(coordinate)
                          },
                          onRegionChange: viewModel.updateMapCenter)
            .ignoresSafeArea(edges: [.top])

            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    searchBar
                    mapTypeButton
                }
                .padding(.top, 50)
                .padding(.horizontal)

                if viewModel.isSearching {
                    ProgressView("正在搜索…")
                        .padding(.horizontal)
                } else if viewModel.showSearchResults && !viewModel.searchResults.isEmpty {
                    SearchResultList(results: viewModel.searchResults, onSelect: { result in
                        dismissKeyboard()
                        viewModel.selectSearchResult(result)
                    })
                        .padding(.horizontal)
                } else if viewModel.showSearchHistory && !viewModel.searchHistory.isEmpty {
                    SearchHistoryList(history: viewModel.searchHistory, 
                                    onSelect: { item in
                                        dismissKeyboard()
                                        viewModel.selectHistoryItem(item)
                                    },
                                    onDelete: { item in
                                        viewModel.deleteHistoryItem(item)
                                    })
                        .padding(.horizontal)
                }

                Spacer()
            }

            VStack {
                Spacer()
                MapControlPanel(viewModel: viewModel)
                    .padding()
            }
        }
        .alert(isPresented: $viewModel.showErrorAlert) {
            Alert(title: Text(""),
                  message: Text(viewModel.errorMessage ?? "发生未知错误"),
                  dismissButton: .default(Text("确定")))
        }
        .alert(isPresented: $viewModel.showBookmarkSuccess) {
            Alert(title: Text("收藏成功"),
                  message: Text(viewModel.bookmarkSuccessMessage),
                  dismissButton: .default(Text("确定")))
        }
        .sheet(item: $viewModel.editorMode, onDismiss: {
            viewModel.completeEditorFlow()
        }) { mode in
            BookmarkEditorView(mode: mode,
                               onSave: { name, coordinate, note in
                                   bookmarkStore.addBookmark(name: name, coordinate: coordinate, note: note)
                                   viewModel.completeEditorFlow()
                               },
                               onCancel: {
                                   viewModel.completeEditorFlow()
                               })
        }
        .onChange(of: viewModel.searchText) { newValue in
            if newValue.isEmpty {
                viewModel.clearSearch()
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    dismissKeyboard()
                }
            }
        }
        .onAppear {
            viewModel.requestLocationPermission()
        }
    }

    private func dismissKeyboard() {
        searchFocused = false
        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil,
                                        from: nil,
                                        for: nil)
        #endif
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索地点", text: $viewModel.searchText, onCommit: {
                dismissKeyboard()
                viewModel.performSearch()
            })
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .focused($searchFocused)
            .submitLabel(.search)
            .onChange(of: searchFocused) { isFocused in
                if isFocused && viewModel.searchText.isEmpty && !viewModel.searchHistory.isEmpty {
                    viewModel.showSearchHistory = true
                }
            }

            if !viewModel.searchText.isEmpty {
                Button(action: viewModel.clearSearch) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            } else if !viewModel.searchHistory.isEmpty {
                Button(action: viewModel.toggleSearchHistory) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var mapTypeButton: some View {
        Menu {
            Button {
                viewModel.mapType = .standard
            } label: {
                HStack {
                    Image(systemName: "map")
                    Text("标准模式")
                    Spacer()
                    if viewModel.mapType == .standard {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Button {
                viewModel.mapType = .satellite
            } label: {
                HStack {
                    Image(systemName: "globe")
                    Text("卫星地图")
                    Spacer()
                    if viewModel.mapType == .satellite {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }

            Button {
                viewModel.mapType = .hybrid
            } label: {
                HStack {
                    Image(systemName: "map.fill")
                    Text("混合模式")
                    Spacer()
                    if viewModel.mapType == .hybrid {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
            }
        } label: {
            Image(systemName: mapTypeIcon)
                .font(.body)
                .foregroundColor(.primary)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
        }
    }

    private var mapTypeIcon: String {
        switch viewModel.mapType {
        case .standard:
            return "map"
        case .satellite:
            return "globe"
        case .hybrid:
            return "map.fill"
        default:
            return "map"
        }
    }
}

private struct MapControlPanel: View {
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    if viewModel.activeLocation != nil {
                        Text("模拟中")
                            .font(.headline)
                        Image(systemName: "location.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                    } else {
                        Text(viewModel.selectedLocation != nil ? "已选择" : "当前预览")
                            .font(.headline)
                        if viewModel.selectedLocation != nil {
                            Image(systemName: "location.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                    }
                }
                if let coordinate = viewModel.selectedLocation?.coordinateDescription {
                    Text(coordinate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("点击地图即可放置定位点")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if viewModel.activeLocation != nil {
                    Text("定位模拟已开启")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            // 暂停模拟按钮 - 始终显示，未模拟时禁用
            Button(action: viewModel.stopSpoofing) {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .font(.body)
                    Text("暂停模拟")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.activeLocation != nil ? Color.orange.opacity(0.9) : Color.secondary.opacity(0.2))
                .foregroundColor(viewModel.activeLocation != nil ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(viewModel.activeLocation == nil)

            // 快速收藏按钮 - 始终显示，未选择位置时禁用
            Button(action: viewModel.quickAddBookmark) {
                HStack {
                    if viewModel.isAddingBookmark {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "bookmark.fill")
                            .font(.body)
                    }
                    Text(viewModel.isAddingBookmark ? "收藏中..." : "快速收藏")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(viewModel.isAddingBookmark ? Color.secondary.opacity(0.3) : 
                           (viewModel.selectedLocation != nil ? Color.orange : Color.secondary.opacity(0.2)))
                .foregroundColor(viewModel.selectedLocation != nil ? .white : .secondary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .disabled(viewModel.isAddingBookmark || viewModel.selectedLocation == nil)

        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
    }
}

private struct SearchResultList: View {
    var results: [SearchResult]
    var onSelect: (SearchResult) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(results) { result in
                    Button(action: { onSelect(result) }) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.title)
                                .font(.headline)
                                .foregroundColor(.primary)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .frame(maxHeight: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct SearchHistoryList: View {
    var history: [SearchHistoryItem]
    var onSelect: (SearchHistoryItem) -> Void
    var onDelete: (SearchHistoryItem) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(history) { item in
                    HStack(spacing: 12) {
                        Button(action: { onSelect(item) }) {
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.query)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.5f, %.5f", item.coordinate.latitude, item.coordinate.longitude))
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                            }
                            .padding(.vertical, 12)
                            .padding(.leading, 16)
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: { onDelete(item) }) {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(8)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 12)
                    }
                    .background(Color(.systemBackground).opacity(0.9), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
        }
        .frame(maxHeight: 240)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
