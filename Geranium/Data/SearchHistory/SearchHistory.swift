//
//  SearchHistory.swift
//  Geranium
//
//  Created by Assistant on 01.12.2024.
//

import Foundation
import CoreLocation

struct SearchHistoryItem: Identifiable, Codable, Equatable {
    let id: UUID
    let query: String
    let coordinate: CoordinateCodable
    let timestamp: Date
    
    init(id: UUID = UUID(), query: String, coordinate: CLLocationCoordinate2D, timestamp: Date = Date()) {
        self.id = id
        self.query = query
        self.coordinate = CoordinateCodable(coordinate: coordinate)
        self.timestamp = timestamp
    }
    
    var locationCoordinate: CLLocationCoordinate2D {
        coordinate.coordinate
    }
}

// 用于编码 CLLocationCoordinate2D
struct CoordinateCodable: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    
    init(coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }
    
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

