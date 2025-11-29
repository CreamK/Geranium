//
//  MapViewModel.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import Foundation
import MapKit
import CoreLocation
import Combine
import SwiftUI

@MainActor
final class MapViewModel: ObservableObject {
    @Published var selectedLocation: LocationPoint?
    @Published var mapRegion: MKCoordinateRegion
    @Published var editorMode: BookmarkEditorMode?
    @Published var errorMessage: String?
    @Published var showErrorAlert: Bool = false
    @Published var lastMapCenter: CLLocationCoordinate2D?
    @Published var searchText: String = ""
    @Published var searchResults: [SearchResult] = []
    @Published var isSearching: Bool = false
    @Published var showSearchResults: Bool = false
    @Published var showBookmarkSuccess: Bool = false
    @Published var bookmarkSuccessMessage: String = ""
    @Published var isAddingBookmark: Bool = false
    @Published var mapType: MKMapType = .standard

    var statusInfo: MapStatus {
        if let active = engine.session.activePoint {
            return MapStatus(
                title: "定位模拟已开启",
                detail: active.label ?? active.coordinateDescription,
                isActive: true
            )
        }

        return MapStatus(
            title: "定位模拟已关闭",
            detail: "点击地图即可放置定位点",
            isActive: false
        )
    }

    var activeLocation: LocationPoint? {
        engine.session.activePoint
    }

    private let engine: LocationSpoofingEngine
    private let settings: LocSimSettings
    private unowned let bookmarkStore: BookmarkStore
    private var cancellables = Set<AnyCancellable>()
    private let locationAuthorizer = LocationModel()
    private var hasCenteredOnUser = false
    private var shouldRestoreToRealLocation = false
    private var searchTask: Task<Void, Never>?

    init(engine: LocationSpoofingEngine, settings: LocSimSettings, bookmarkStore: BookmarkStore) {
        self.engine = engine
        self.settings = settings
        self.bookmarkStore = bookmarkStore

        let defaultCenter = CLLocationCoordinate2D(latitude: 39.9042, longitude: 116.4074)
        self.mapRegion = MKCoordinateRegion(center: defaultCenter,
                                            span: MKCoordinateSpan(latitudeDelta: settings.mapSpanDegrees,
                                                                   longitudeDelta: settings.mapSpanDegrees))

        engine.$session
            .receive(on: RunLoop.main)
            .sink { [weak self] session in
                guard let self else { return }
                if !session.isActive {
                    bookmarkStore.markAsLastUsed(nil)
                }
                objectWillChange.send()
            }
            .store(in: &cancellables)

        locationAuthorizer.$currentLocation
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { [weak self] location in
                guard let self else { return }
                if shouldRestoreToRealLocation {
                    // 恢复定位：强制移动到真实位置，并确保用户位置图标显示
                    shouldRestoreToRealLocation = false
                    centerMap(on: location.coordinate)
                    // 触发视图更新以确保用户位置图标正确显示
                    objectWillChange.send()
                } else if !hasCenteredOnUser {
                    // 首次启动：移动到用户位置
                    hasCenteredOnUser = true
                    centerMap(on: location.coordinate)
                }
            }
            .store(in: &cancellables)
    }

    func requestLocationPermission() {
        locationAuthorizer.requestAuthorisation(always: true)
    }

    func handleMapTap(_ coordinate: CLLocationCoordinate2D) {
        let locationPoint = LocationPoint(coordinate: coordinate, label: nil)
        selectedLocation = locationPoint
        
        if settings.autoCenterOnSelection {
            centerMap(on: coordinate)
        }
        
        // 自动开始模拟选中的位置
        startSpoofing(point: locationPoint, bookmark: nil)
    }

    func updateMapCenter(_ coordinate: CLLocationCoordinate2D) {
        lastMapCenter = coordinate
    }

    func openBookmarkCreator() {
        if let selectedLocation {
            editorMode = .create(selectedLocation)
        } else if let center = lastMapCenter {
            editorMode = .create(LocationPoint(coordinate: center))
        } else {
            errorMessage = "请先在地图上选择一个位置"
            showErrorAlert = true
        }
    }

    func completeEditorFlow() {
        editorMode = nil
    }

    func focus(on bookmark: Bookmark, autoStartOverride: Bool? = nil) {
        let point = bookmark.locationPoint
        selectedLocation = point
        centerMap(on: point.coordinate)

        // 始终自动开始模拟，除非明确指定不启动
        let shouldAutoStart = autoStartOverride ?? true
        if shouldAutoStart {
            startSpoofing(point: point, bookmark: bookmark)
        }
    }

    func stopSpoofing() {
        engine.stopSpoofing()
        bookmarkStore.markAsLastUsed(nil)
    }

    func restoreLocation() {
        // 恢复真实定位：停止模拟
        engine.restoreLocation()
        bookmarkStore.markAsLastUsed(nil)
        
        // 不清除选中的位置，保留"已选择"图标
        
        // 设置标志，等待位置更新后移动到真实位置
        shouldRestoreToRealLocation = true
        
        // 重新请求位置更新以确保获取最新位置
        locationAuthorizer.requestAuthorisation(always: true)
        
        // 如果已有真实定位，立即移动到该位置（用户位置图标会自动更新）
        if let currentLocation = locationAuthorizer.currentLocation {
            centerMap(on: currentLocation.coordinate)
        }
    }

    func performSearch() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            searchResults = []
            showSearchResults = false
            return
        }

        isSearching = true
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            guard let self else { return }
            
            // 创建搜索请求 - 使用扩大的搜索区域以获得更多结果
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            
            // 扩大搜索区域：使用当前地图中心但扩大搜索范围
            // 这样可以获得更多模糊匹配的结果
            var searchRegion = mapRegion
            let expandedSpan = MKCoordinateSpan(
                latitudeDelta: min(max(mapRegion.span.latitudeDelta * 30, 5.0), 50.0),
                longitudeDelta: min(max(mapRegion.span.longitudeDelta * 30, 5.0), 50.0)
            )
            searchRegion.span = expandedSpan
            request.region = searchRegion
            
            // 设置结果类型以包含更多地点类型
            request.resultTypes = [.pointOfInterest, .address]
            
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                
                // 去重：基于坐标和名称，避免显示重复的结果
                var seenItems = Set<String>()
                var mapped = response.mapItems.compactMap { mapItem -> SearchResult? in
                    let coordinate = mapItem.placemark.coordinate
                    let coordKey = String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)
                    let nameKey = mapItem.name ?? ""
                    let uniqueKey = "\(coordKey)-\(nameKey)"
                    
                    if seenItems.contains(uniqueKey) {
                        return nil
                    }
                    seenItems.insert(uniqueKey)
                    return SearchResult(mapItem: mapItem)
                }
                
                // 按相关性进行模糊匹配排序：完全匹配 > 开头匹配 > 包含匹配
                let queryLower = query.lowercased()
                let queryWords = queryLower.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
                
                mapped.sort { first, second in
                    let firstTitle = first.title.lowercased()
                    let secondTitle = second.title.lowercased()
                    let firstSubtitle = first.subtitle.lowercased()
                    let secondSubtitle = second.subtitle.lowercased()
                    
                    // 完全匹配优先
                    let firstExact = firstTitle == queryLower
                    let secondExact = secondTitle == queryLower
                    if firstExact != secondExact { return firstExact }
                    
                    // 开头匹配其次
                    let firstStarts = firstTitle.hasPrefix(queryLower)
                    let secondStarts = secondTitle.hasPrefix(queryLower)
                    if firstStarts != secondStarts { return firstStarts }
                    
                    // 包含匹配再次
                    let firstContains = firstTitle.contains(queryLower) || firstSubtitle.contains(queryLower)
                    let secondContains = secondTitle.contains(queryLower) || secondSubtitle.contains(queryLower)
                    if firstContains != secondContains { return firstContains }
                    
                    // 多词匹配：计算匹配的词数
                    let firstWordMatches = queryWords.filter { firstTitle.contains($0) || firstSubtitle.contains($0) }.count
                    let secondWordMatches = queryWords.filter { secondTitle.contains($0) || secondSubtitle.contains($0) }.count
                    if firstWordMatches != secondWordMatches { return firstWordMatches > secondWordMatches }
                    
                    // 最后按字母顺序
                    return firstTitle < secondTitle
                }
                
                // 显示更多结果（最多30个）
                let maxResults = min(mapped.count, 30)
                
                await MainActor.run {
                    self.searchResults = Array(mapped.prefix(maxResults))
                    self.showSearchResults = !self.searchResults.isEmpty
                    self.isSearching = false
                }
            } catch {
                await MainActor.run {
                    self.isSearching = false
                }
            }
        }
    }

    func selectSearchResult(_ result: SearchResult) {
        let coordinate = result.mapItem.placemark.coordinate
        let locationPoint = LocationPoint(coordinate: coordinate, label: result.title, note: result.subtitle)
        selectedLocation = locationPoint
        centerMap(on: coordinate)
        showSearchResults = false
        searchResults = []
        searchText = result.title
        
        // 自动开始模拟选中的位置
        startSpoofing(point: locationPoint, bookmark: nil)
    }

    func clearSearch() {
        searchText = ""
        searchResults = []
        showSearchResults = false
        isSearching = false
        searchTask?.cancel()
    }

    func quickAddBookmark() {
        guard let selectedLocation = selectedLocation else {
            errorMessage = "请先在地图上选择一个位置"
            showErrorAlert = true
            return
        }

        // Check if this location is already bookmarked
        let existingBookmark = bookmarkStore.bookmarks.first { bookmark in
            abs(bookmark.coordinate.latitude - selectedLocation.coordinate.latitude) < 0.00001 &&
            abs(bookmark.coordinate.longitude - selectedLocation.coordinate.longitude) < 0.00001
        }

        if existingBookmark != nil {
            errorMessage = "此位置已在收藏列表中"
            showErrorAlert = true
            return
        }

        isAddingBookmark = true

        // Use existing label if available, otherwise reverse geocode
        if let label = selectedLocation.label, !label.isEmpty {
            // Use the existing label (e.g., from search result)
            _ = bookmarkStore.addBookmark(
                name: label,
                coordinate: selectedLocation.coordinate,
                note: selectedLocation.note
            )
            bookmarkSuccessMessage = "已收藏：\(label)"
            showBookmarkSuccess = true
            isAddingBookmark = false
        } else {
            // Reverse geocode to get location name
            Task {
                await reverseGeocodeAndAddBookmark(coordinate: selectedLocation.coordinate)
            }
        }
    }

    private func reverseGeocodeAndAddBookmark(coordinate: CLLocationCoordinate2D) async {
        let geocoder = CLGeocoder()
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)

        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            await MainActor.run {
                let bookmarkName: String
                if let placemark = placemarks.first {
                    // Try to get a meaningful name from the placemark
                    if let name = placemark.name, !name.isEmpty {
                        bookmarkName = name
                    } else if let thoroughfare = placemark.thoroughfare, !thoroughfare.isEmpty {
                        bookmarkName = thoroughfare
                    } else if let locality = placemark.locality, !locality.isEmpty {
                        bookmarkName = locality
                    } else {
                        bookmarkName = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                    }
                } else {
                    bookmarkName = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                }

                _ = bookmarkStore.addBookmark(
                    name: bookmarkName,
                    coordinate: coordinate,
                    note: nil
                )
                bookmarkSuccessMessage = "已收藏：\(bookmarkName)"
                showBookmarkSuccess = true
                isAddingBookmark = false
            }
        } catch {
            await MainActor.run {
                // If reverse geocoding fails, use coordinates as name
                let bookmarkName = String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude)
                _ = bookmarkStore.addBookmark(
                    name: bookmarkName,
                    coordinate: coordinate,
                    note: nil
                )
                bookmarkSuccessMessage = "已收藏：\(bookmarkName)"
                showBookmarkSuccess = true
                isAddingBookmark = false
            }
        }
    }

    private func startSpoofing(point: LocationPoint, bookmark: Bookmark?) {
        engine.startSpoofing(point: point)
        if let bookmark {
            bookmarkStore.markAsLastUsed(bookmark)
        } else {
            bookmarkStore.markAsLastUsed(nil)
        }
    }

    private func centerMap(on coordinate: CLLocationCoordinate2D) {
        withAnimation(settings.dampedAnimations ? .spring(response: 0.45, dampingFraction: 0.75) : .default) {
            mapRegion = MKCoordinateRegion(center: coordinate, span: mapRegion.span)
        }
        lastMapCenter = coordinate
    }
}

struct MapStatus {
    var title: String
    var detail: String
    var isActive: Bool
}

struct SearchResult: Identifiable {
    let id = UUID()
    let mapItem: MKMapItem

    init(mapItem: MKMapItem) {
        self.mapItem = mapItem
    }

    var title: String {
        mapItem.name ?? "未知地点"
    }

    var subtitle: String {
        mapItem.placemark.title ?? ""
    }
}
