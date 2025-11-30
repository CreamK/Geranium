//
//  MapCanvasView.swift
//  Geranium
//
//  Created by Codex on 22.05.2024.
//

import SwiftUI
import MapKit
import UIKit

struct MapCanvasView: UIViewRepresentable {
    @Binding var region: MKCoordinateRegion
    var selectedCoordinate: CLLocationCoordinate2D?
    var activeCoordinate: CLLocationCoordinate2D?
    var mapType: MKMapType
    var onTap: (CLLocationCoordinate2D) -> Void
    var onRegionChange: (CLLocationCoordinate2D) -> Void

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.showsUserLocation = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.mapType = mapType
        mapView.setRegion(region, animated: false)

        let tapRecognizer = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        mapView.addGestureRecognizer(tapRecognizer)
        context.coordinator.mapView = mapView
        context.coordinator.syncAnnotations(selected: selectedCoordinate, active: activeCoordinate)
        return mapView
    }

    func updateUIView(_ uiView: MKMapView, context: Context) {
        if uiView.mapType != mapType {
            uiView.mapType = mapType
        }
        if !context.coordinator.isUserInteracting {
            uiView.setRegion(region, animated: true)
        }
        
        // 检查坐标是否有变化，如果有变化才更新标注
        let previousSelected = context.coordinator.previousSelectedCoordinate
        let previousActive = context.coordinator.previousActiveCoordinate
        let selectedChanged = !MapCanvasView.areCoordinatesEqual(selectedCoordinate, previousSelected)
        let activeChanged = !MapCanvasView.areCoordinatesEqual(activeCoordinate, previousActive)
        
        // 如果坐标发生变化，更新标注
        if selectedChanged || activeChanged || context.coordinator.forceUpdate {
            context.coordinator.previousSelectedCoordinate = selectedCoordinate
            context.coordinator.previousActiveCoordinate = activeCoordinate
            context.coordinator.forceUpdate = false
            context.coordinator.syncAnnotations(selected: selectedCoordinate, active: activeCoordinate)
            // 强制刷新标注视图以确保颜色和文字正确更新
            DispatchQueue.main.async {
                context.coordinator.refreshAnnotationViews()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    // 辅助函数：比较两个可选坐标是否相等
    private static func areCoordinatesEqual(_ coord1: CLLocationCoordinate2D?, _ coord2: CLLocationCoordinate2D?) -> Bool {
        switch (coord1, coord2) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let c1?, let c2?):
            return abs(c1.latitude - c2.latitude) < 0.00001 && abs(c1.longitude - c2.longitude) < 0.00001
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView
        weak var mapView: MKMapView?
        var isUserInteracting = false
        var previousSelectedCoordinate: CLLocationCoordinate2D?
        var previousActiveCoordinate: CLLocationCoordinate2D?
        var forceUpdate = false

        init(parent: MapCanvasView) {
            self.parent = parent
        }

        func syncAnnotations(selected: CLLocationCoordinate2D?, active: CLLocationCoordinate2D?) {
            guard let mapView else { return }
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

            // 优先显示"模拟中"的标注（绿色）
            if let active {
                let annotation = MKPointAnnotation()
                annotation.title = "模拟中"
                annotation.coordinate = active
                mapView.addAnnotation(annotation)
                
                // 只有当已选择的位置和正在模拟的位置不同时，才显示已选择标注
                if let selected {
                    let isSameLocation = abs(selected.latitude - active.latitude) < 0.00001 &&
                                       abs(selected.longitude - active.longitude) < 0.00001
                    if !isSameLocation {
                        let selectedAnnotation = MKPointAnnotation()
                        selectedAnnotation.title = "已选择"
                        selectedAnnotation.coordinate = selected
                        mapView.addAnnotation(selectedAnnotation)
                    }
                }
            } else if let selected {
                // 如果没有正在模拟的，显示已选择标注（蓝色）
                let annotation = MKPointAnnotation()
                annotation.title = "已选择"
                annotation.coordinate = selected
                mapView.addAnnotation(annotation)
            }
            
            // 延迟刷新标注视图以确保标注已添加完成并正确显示颜色
            DispatchQueue.main.async { [weak self] in
                // 使用小的延迟确保 MapKit 已完成标注添加
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                    self?.refreshAnnotationViews()
                }
            }
        }
        
        func refreshAnnotationViews() {
            guard let mapView else { return }
            // 刷新所有标注视图，确保颜色和文字正确
            for annotation in mapView.annotations {
                guard !(annotation is MKUserLocation) else { continue }
                if let annotationView = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                    if let title = annotation.title, title == "模拟中" {
                        annotationView.markerTintColor = UIColor.systemGreen
                    } else {
                        annotationView.markerTintColor = UIColor.systemBlue
                    }
                }
            }
        }

        @objc
        func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let mapView = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            parent.onTap(coordinate)
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            isUserInteracting = true
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            isUserInteracting = false
            parent.region = mapView.region
            parent.onRegionChange(mapView.centerCoordinate)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard !(annotation is MKUserLocation) else { return nil }
            let identifier = "MapAnnotation"
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            }
            
            // 更新标注内容和样式
            annotationView?.annotation = annotation
            annotationView?.glyphImage = UIImage(systemName: "mappin")
            
            // 根据标题设置颜色："模拟中"为绿色，"已选择"为蓝色
            if let title = annotation.title, title == "模拟中" {
                annotationView?.markerTintColor = UIColor.systemGreen
            } else {
                annotationView?.markerTintColor = UIColor.systemBlue
            }
            
            return annotationView
        }
    }
}
