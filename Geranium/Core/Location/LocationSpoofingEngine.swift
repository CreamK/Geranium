//
//  LocationSpoofingEngine.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import Foundation
import CoreLocation

@MainActor
final class LocationSpoofingEngine: ObservableObject {
    enum CoordinateSpace {
        case gcj02
        case wgs84
    }

    @Published private(set) var session = LocationSpoofingSession()

    func startSpoofing(point: LocationPoint, coordinateSpace: CoordinateSpace = .gcj02) {
        let simulationCoordinate: CLLocationCoordinate2D
        let displayPoint: LocationPoint

        switch coordinateSpace {
        case .gcj02:
            simulationCoordinate = CoordTransform.gcj02ToWgs84(point.coordinate)
            displayPoint = point
        case .wgs84:
            simulationCoordinate = point.coordinate
            let displayCoordinate = CoordTransform.wgs84ToGcj02(point.coordinate)
            displayPoint = LocationPoint(coordinate: displayCoordinate,
                                         altitude: point.altitude,
                                         label: point.label,
                                         note: point.note)
        }

        let location = CLLocation(coordinate: simulationCoordinate,
                                  altitude: point.altitude,
                                  horizontalAccuracy: 5,
                                  verticalAccuracy: 5,
                                  timestamp: Date())

        LocSimManager.startLocSim(location: location)
        session.state = .running(displayPoint)
        session.lastError = nil
    }

    func stopSpoofing() {
        LocSimManager.stopLocSim()
        session.state = .idle
    }

    func restoreLocation() {
        // 停止模拟以恢复真实定位
        LocSimManager.stopLocSim()
        session.state = .idle
        session.lastError = nil
    }

    func recordError(_ error: LocationSpoofingError) {
        session.lastError = error
    }
}
