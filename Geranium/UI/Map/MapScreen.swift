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
                                    },
                                    onClearAll: {
                                        viewModel.clearSearchHistory()
                                    })
                        .padding(.horizontal)
                }

                Spacer()
            }
        }
        .overlay(alignment: .bottomLeading) {
            MapStatusBadge(viewModel: viewModel)
                .padding(.leading, 16)
                .padding(.bottom, 24)
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingMapActions(viewModel: viewModel)
                .padding(.trailing, 16)
                .padding(.bottom, 28)
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
            viewModel.handleSearchTextChanged(newValue)
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
            viewModel.centerOnUserLocation()
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
            TextField("搜索地点", text: $viewModel.searchText)
            .textInputAutocapitalization(.never)
            .disableAutocorrection(true)
            .focused($searchFocused)
            .submitLabel(.search)
            .onSubmit {
                dismissKeyboard()
            }
            .onChange(of: searchFocused) { isFocused in
                if isFocused && viewModel.searchText.isEmpty && !viewModel.searchHistory.isEmpty {
                    viewModel.showSearchHistory = true
                }
            }

            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.clearSearch() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            } else if !viewModel.searchHistory.isEmpty {
                Button(action: viewModel.toggleSearchHistory) {
                    Image(systemName: "clock")
                        .foregroundColor(.secondary)
                }
            }

            if searchFocused {
                Button("取消") {
                    dismissKeyboard()
                    viewModel.dismissSearchOverlay()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
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

private struct MapStatusBadge: View {
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if viewModel.activeLocation != nil {
                    Text("模拟中")
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: "location.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                } else {
                    Text(viewModel.selectedLocation != nil ? "已选择" : "当前预览")
                        .font(.subheadline.weight(.semibold))
                    if viewModel.selectedLocation != nil {
                        Image(systemName: "location.fill")
                            .foregroundColor(.blue)
                            .font(.caption)
                    }
                }
            }
            if let coordinate = viewModel.selectedLocation?.coordinateDescription {
                HStack(spacing: 8) {
                    Text(coordinate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    #if canImport(UIKit)
                    Button {
                        UIPasteboard.general.string = coordinate
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    #endif
                }
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
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        }
        .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
    }
}

private struct FloatingMapActions: View {
    @ObservedObject var viewModel: MapViewModel

    var body: some View {
        VStack(spacing: 12) {
            MapActionButton(icon: "location.circle.fill",
                            label: "定位",
                            tint: .blue,
                            isLoading: viewModel.isResolvingCurrentLocation,
                            disabled: viewModel.isResolvingCurrentLocation,
                            action: viewModel.simulateCurrentLocation)

            MapActionButton(icon: "pause.circle.fill",
                            label: "暂停",
                            tint: viewModel.activeLocation != nil ? .orange : .secondary,
                            isLoading: false,
                            disabled: viewModel.activeLocation == nil || viewModel.isResolvingCurrentLocation,
                            action: viewModel.pauseSpoofingAndCenterOnUserLocation)

            MapActionButton(icon: "bookmark.fill",
                            label: "收藏",
                            tint: viewModel.selectedLocation != nil ? .orange : .secondary,
                            isLoading: viewModel.isAddingBookmark,
                            disabled: viewModel.isAddingBookmark || viewModel.selectedLocation == nil,
                            action: viewModel.quickAddBookmark)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
    }
}

private struct MapActionButton: View {
    var icon: String
    var label: String
    var tint: Color
    var isLoading: Bool
    var disabled: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill((disabled ? tint.opacity(0.35) : tint).opacity(0.95))
                        .frame(width: 48, height: 48)
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: icon)
                            .foregroundColor(.white)
                            .font(.body.weight(.semibold))
                    }
                }
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.primary)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.72 : 1)
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
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
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
    var onClearAll: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("搜索记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("清空") {
                    onClearAll()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(history) { item in
                        Button(action: { onSelect(item) }) {
                            HStack(spacing: 10) {
                                Image(systemName: "clock")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.query)
                                        .font(.subheadline)
                                        .foregroundColor(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(String(format: "%.5f, %.5f", item.coordinate.latitude, item.coordinate.longitude))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                // Reserve tap area for the trailing delete button (added as an overlay).
                                Color.clear
                                    .frame(width: 28, height: 28)
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .background(Color(.systemBackground).opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .contentShape(Rectangle())
                        .overlay(alignment: .trailing) {
                            Button(action: { onDelete(item) }) {
                                Image(systemName: "xmark")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxHeight: 240)
        .padding(.bottom, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
