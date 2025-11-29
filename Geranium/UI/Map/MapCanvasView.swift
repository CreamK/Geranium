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
        context.coordinator.syncAnnotations(selected: selectedCoordinate, active: activeCoordinate)
        // 强制刷新标注视图以确保颜色和文字正确更新
        context.coordinator.refreshAnnotationViews()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapCanvasView
        weak var mapView: MKMapView?
        var isUserInteracting = false

        init(parent: MapCanvasView) {
            self.parent = parent
        }

        func syncAnnotations(selected: CLLocationCoordinate2D?, active: CLLocationCoordinate2D?) {
            guard let mapView else { return }
            mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })

            // 优先显示"正在模拟"的标注（绿色）
            if let active {
                let annotation = MKPointAnnotation()
                annotation.title = "正在模拟"
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
            
            // 立即刷新标注视图以确保颜色正确显示
            DispatchQueue.main.async { [weak self] in
                self?.refreshAnnotationViews()
            }
        }
        
        func refreshAnnotationViews() {
            guard let mapView else { return }
            // 刷新所有标注视图，确保颜色和文字正确
            for annotation in mapView.annotations {
                guard !(annotation is MKUserLocation) else { continue }
                if let annotationView = mapView.view(for: annotation) as? MKMarkerAnnotationView {
                    if let title = annotation.title, title == "正在模拟" {
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
            
            // 根据标题设置颜色："正在模拟"为绿色，"已选择"为蓝色
            if let title = annotation.title, title == "正在模拟" {
                annotationView?.markerTintColor = UIColor.systemGreen
            } else {
                annotationView?.markerTintColor = UIColor.systemBlue
            }
            
            return annotationView
        }
    }
}
