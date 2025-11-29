//
//  BookmarksViewModel.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import Foundation
import CoreLocation
import SwiftUI

@MainActor
final class BookmarksViewModel: ObservableObject {
    @Published var editorMode: BookmarkEditorMode?
    @Published var showImportPrompt: Bool = false
    @Published var importResultMessage: String?
    @Published var showImportResult: Bool = false
    @Published var shareSheetItems: [Any]?
    @Published var showShareSheet: Bool = false
    @Published var showImportFilePicker: Bool = false

    private let store: BookmarkStore
    private unowned let mapViewModel: MapViewModel
    private let settings: LocSimSettings

    init(store: BookmarkStore, mapViewModel: MapViewModel, settings: LocSimSettings) {
        self.store = store
        self.mapViewModel = mapViewModel
        self.settings = settings
        evaluateLegacyState()
    }

    func evaluateLegacyState() {
        showImportPrompt = store.canImportLegacyRecords
    }

    func performLegacyImport() {
        do {
            let imported = try store.importLegacyBookmarks()
            importResultMessage = imported > 0 ?
            String(format: "成功导入 %d 条收藏。", imported) :
            "没有发现可导入的收藏。"
        } catch {
            importResultMessage = "导入失败，请重试。"
        }
        showImportResult = true
        showImportPrompt = false
    }

    func select(_ bookmark: Bookmark) {
        mapViewModel.focus(on: bookmark, autoStartOverride: true)
    }

    func deleteBookmarks(at offsets: IndexSet) {
        store.deleteBookmarks(at: offsets)
    }

    func delete(_ bookmark: Bookmark) {
        if let index = store.bookmarks.firstIndex(of: bookmark) {
            store.deleteBookmarks(at: IndexSet(integer: index))
        }
    }

    func moveBookmarks(from source: IndexSet, to destination: Int) {
        store.moveBookmarks(from: source, to: destination)
    }

    func addBookmark() {
        editorMode = .create(nil)
    }

    func edit(_ bookmark: Bookmark) {
        editorMode = .edit(bookmark)
    }

    func dismissEditor() {
        editorMode = nil
    }

    func saveBookmark(name: String, coordinate: CLLocationCoordinate2D, note: String?) {
        guard let editorMode else { return }
        switch editorMode {
        case .create:
            _ = store.addBookmark(name: name, coordinate: coordinate, note: note)
        case .edit(let bookmark):
            var updated = bookmark
            updated.name = name
            updated.coordinate = coordinate
            updated.note = note
            store.updateBookmark(updated)
        }
        self.editorMode = nil
    }

    func shareBookmarks() {
        guard !store.bookmarks.isEmpty else {
            importResultMessage = "没有可分享的书签。"
            showImportResult = true
            return
        }

        do {
            let jsonData = try store.exportBookmarksAsJSON()
            
            // 创建临时文件
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Geranium书签_\(Date().timeIntervalSince1970).json")
            try jsonData.write(to: tempURL)
            
            shareSheetItems = [tempURL]
            showShareSheet = true
        } catch {
            importResultMessage = "导出失败：\(error.localizedDescription)"
            showImportResult = true
        }
    }

    func importBookmarks(from url: URL) {
        // 在 macOS 上需要访问文件的安全作用域
        #if os(macOS)
        _ = url.startAccessingSecurityScopedResource()
        defer {
            url.stopAccessingSecurityScopedResource()
        }
        #endif
        
        do {
            let jsonData = try Data(contentsOf: url)
            let result = try store.importBookmarksFromJSON(jsonData)
            
            if result.imported > 0 {
                if result.duplicates > 0 {
                    importResultMessage = String(format: "成功导入 %d 条书签，%d 条重复已跳过。", result.imported, result.duplicates)
                } else {
                    importResultMessage = String(format: "成功导入 %d 条书签。", result.imported)
                }
            } else {
                importResultMessage = result.duplicates > 0 ?
                    String(format: "所有 %d 条书签都已存在，已跳过。", result.duplicates) :
                    "没有找到有效的书签数据。"
            }
            showImportResult = true
        } catch {
            importResultMessage = "导入失败：\(error.localizedDescription)"
            showImportResult = true
        }
    }

    func shareBookmark(_ bookmark: Bookmark) {
        do {
            // 创建包含单个书签的 JSON 数据
            let bookmarkDict = bookmark.dictionaryRepresentation
            let jsonData = try JSONSerialization.data(withJSONObject: [bookmarkDict], options: .prettyPrinted)
            
            // 创建临时文件
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(bookmark.name)_\(Date().timeIntervalSince1970).json")
            try jsonData.write(to: tempURL)
            
            shareSheetItems = [tempURL]
            showShareSheet = true
        } catch {
            importResultMessage = "分享失败：\(error.localizedDescription)"
            showImportResult = true
        }
    }

    func startSimulation(_ bookmark: Bookmark) {
        // 检查该书签是否正在被模拟
        let isCurrentlySimulating = store.lastUsedBookmarkID == bookmark.id && 
                                     mapViewModel.activeLocation != nil
        
        if isCurrentlySimulating {
            // 如果正在模拟该书签，则停止模拟
            mapViewModel.stopSpoofing()
        } else {
            // 否则开始模拟该书签
            mapViewModel.focus(on: bookmark, autoStartOverride: true)
        }
    }
}
