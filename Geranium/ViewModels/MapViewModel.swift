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

    var primaryButtonTitle: String {
        engine.session.isActive ? "停止模拟" : "开始模拟"
    }

    var primaryButtonDisabled: Bool {
        if engine.session.isActive { return false }
        return selectedLocation == nil
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
                if !hasCenteredOnUser {
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
        selectedLocation = LocationPoint(coordinate: coordinate, label: nil)
        if settings.autoCenterOnSelection {
            centerMap(on: coordinate)
        }
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

    func toggleSpoofing() {
        if engine.session.isActive {
            stopSpoofing()
        } else {
            startSpoofingSelected()
        }
    }

    func startSpoofingSelected() {
        guard let selectedLocation else {
            engine.recordError(.invalidCoordinate)
            errorMessage = "请先在地图上选择一个有效的位置"
            showErrorAlert = true
            return
        }
        startSpoofing(point: selectedLocation, bookmark: nil)
    }

    func focus(on bookmark: Bookmark, autoStartOverride: Bool? = nil) {
        let point = bookmark.locationPoint
        selectedLocation = point
        centerMap(on: point.coordinate)

        let shouldAutoStart = autoStartOverride ?? settings.autoStartFromBookmarks
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
        
        // 如果已有真实定位，将地图中心移到真实定位
        if let currentLocation = locationAuthorizer.currentLocation {
            centerMap(on: currentLocation.coordinate)
        } else {
            // 请求获取真实定位
            locationAuthorizer.requestAuthorisation(always: true)
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
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = query
            let search = MKLocalSearch(request: request)
            do {
                let response = try await search.start()
                let mapped = response.mapItems.map(SearchResult.init)
                await MainActor.run {
                    self.searchResults = mapped
                    self.showSearchResults = !mapped.isEmpty
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
        selectedLocation = LocationPoint(coordinate: coordinate, label: result.title, note: result.subtitle)
        centerMap(on: coordinate)
        showSearchResults = false
        searchResults = []
        searchText = result.title
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
            let bookmark = bookmarkStore.addBookmark(
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

                let bookmark = bookmarkStore.addBookmark(
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
                let bookmark = bookmarkStore.addBookmark(
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
