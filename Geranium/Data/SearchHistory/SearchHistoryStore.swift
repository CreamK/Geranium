//
//  SearchHistoryStore.swift
//  Geranium
//
//  Created by Assistant on 01.12.2024.
//

import Foundation
import CoreLocation
import Combine

@MainActor
final class SearchHistoryStore: ObservableObject {
    @Published private(set) var history: [SearchHistoryItem] = []
    
    private let maxHistoryItems = 50 // 最多保存50条记录
    private let defaults: UserDefaults
    private let historyKey = "searchHistory"
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadHistory()
    }
    
    func addSearchItem(query: String, coordinate: CLLocationCoordinate2D) {
        // 检查是否已存在相同的搜索（避免重复）
        if let existingIndex = history.firstIndex(where: { 
            $0.query == query && 
            abs($0.coordinate.latitude - coordinate.latitude) < 0.00001 &&
            abs($0.coordinate.longitude - coordinate.longitude) < 0.00001
        }) {
            // 如果存在，移除旧的，添加新的到最前面
            history.remove(at: existingIndex)
        }
        
        let item = SearchHistoryItem(query: query, coordinate: coordinate)
        history.insert(item, at: 0)
        
        // 限制历史记录数量
        if history.count > maxHistoryItems {
            history = Array(history.prefix(maxHistoryItems))
        }
        
        saveHistory()
    }
    
    func deleteItem(_ item: SearchHistoryItem) {
        history.removeAll { $0.id == item.id }
        saveHistory()
    }
    
    func clearHistory() {
        history.removeAll()
        saveHistory()
    }
    
    private func loadHistory() {
        guard let data = defaults.data(forKey: historyKey),
              let decoded = try? JSONDecoder().decode([SearchHistoryItem].self, from: data) else {
            return
        }
        history = decoded
    }
    
    private func saveHistory() {
        guard let encoded = try? JSONEncoder().encode(history) else { return }
        defaults.set(encoded, forKey: historyKey)
    }
}

