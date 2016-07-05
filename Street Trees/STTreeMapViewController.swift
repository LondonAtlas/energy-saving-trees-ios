//
//  STTreeMapViewController.swift
//  Street Trees
//
//  Copyright © 2016 Code for Orlando.
//
//  MIT License
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import CoreLocation
import FBAnnotationClusteringSwift
import MapKit
import StreetTreesPersistentKit
import StreetTreesTransportKit
import UIKit

class STTreeMapViewController: UIViewController, MKMapViewDelegate, CLLocationManagerDelegate {

    @IBOutlet weak var mapView: MKMapView!
    
    let clusteringManager = FBClusteringManager()
    let locationManager = CLLocationManager()
    let regionRadius: CLLocationDistance = 1000
    var foundUser = false
    
    var isInOrlando: Bool {
        if self.foundUser {
            let userCoordinate = self.mapView.userLocation.coordinate
            let userMapPoint = MKMapPointForCoordinate(userCoordinate)
            var isInside = false
            for overlay in self.mapView.overlays {
                if let renderer = self.mapView.rendererForOverlay(overlay) as? MKPolygonRenderer {
                    let polygonPoint = renderer.pointForMapPoint(userMapPoint)
                    isInside = CGPathContainsPoint(renderer.path, nil, polygonPoint, false)
                    if isInside {
                        return isInside
                    }
                }
            }
        }
        
        return false
    }
    
    var selectedAnnotation: STTreeAnnotation?
    
    //******************************************************************************************************************
    // MARK: - Class Overrides
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        super.prepareForSegue(segue, sender: sender)
        
        if let detailVC = segue.destinationViewController as? STTreeDetailsTableViewController
            where segue.identifier == STTreeDetailsSegueIdentifier {
            detailVC.annotation = self.selectedAnnotation
        }
    }
  
    override func viewDidLoad() {
        super.viewDidLoad()
        self.mapView.delegate = self
        self.loadPinsToMap()
        
        STTKDownloadManager.fetch(cityGeoPoints: { (response: [AnyObject]) in
            if let polygons = response as? [MKPolygon] {
                self.mapView.addOverlays(polygons)
            }
        })
        
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        self.mapView.showsScale = true
        self.mapView.showsCompass = true
        self.locationManager.delegate = self
        self.setupLocation()
    }
    
    //******************************************************************************************************************
    // MARK: - MKMapView Delegates

    func mapView(mapView: MKMapView, annotationView view: MKAnnotationView,
                 calloutAccessoryControlTapped control: UIControl) {
        if let treeAnnotation = view.annotation as? STTreeAnnotation {
            self.selectedAnnotation = treeAnnotation
        }
        self.performSegueWithIdentifier(STTreeDetailsSegueIdentifier, sender: self)
    }
    
    func mapView(mapView: MKMapView, didUpdateUserLocation userLocation: MKUserLocation) {
        if !self.foundUser {
            self.foundUser = true
            self.centerMapOnLocation(userLocation.location!)
        }
    }
    
    func mapView(mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        self.loadPins()
    }
    
    func mapView(mapView: MKMapView, rendererForOverlay overlay: MKOverlay) -> MKOverlayRenderer {
        if let polygon = overlay as? MKPolygon {
            
            let renderer = MKPolygonRenderer(polygon: polygon)
            renderer.strokeColor = UIColor.orlandoGreenColor()
            renderer.fillColor = UIColor.orlandoGreenColor(0.2)
            renderer.lineWidth = 3.0
            return renderer
        }
        
        return MKPolygonRenderer()
    }
    
    func mapView(mapView: MKMapView, viewForAnnotation annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        }
        
        var annotationView: MKAnnotationView?
        var reuseId: String
        
        if annotation.isKindOfClass(FBAnnotationCluster) {
            let imageLarge = "clusterLarge"
            let imageMedium = "clusterMedium"
            let imageSmall = "clusterSmall"
            
            let imageSize = FBAnnotationClusterViewOptions(smallClusterImage: imageSmall, mediumClusterImage: imageMedium, largeClusterImage: imageLarge)
            
            annotationView = FBAnnotationClusterView(annotation: annotation, reuseIdentifier: nil, options: imageSize)
            
        } else {
            reuseId = "Pin"
            annotationView = mapView.dequeueReusableAnnotationViewWithIdentifier(reuseId)
            
            if annotationView == nil {
                annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: reuseId)
            }
            
            annotationView?.canShowCallout = true
            let button = UIButton(type: .DetailDisclosure)
            annotationView?.rightCalloutAccessoryView = button
            
            if let treeLocation = annotation as? STTreeAnnotation {
                annotationView?.image = treeLocation.image
            }
        }
        
        return annotationView
    }

    //******************************************************************************************************************
    // MARK: - CLLocationManager Delegates
    
    func locationManager(manager: CLLocationManager, didChangeAuthorizationStatus status: CLAuthorizationStatus) {
        if status == .AuthorizedAlways {
            self.mapView.showsUserLocation = true
        }
    }
    
    //******************************************************************************************************************
    // MARK: - Internal Functions
    
    func centerMapOnLocation(location: CLLocation) {
        let coordinateRegion = MKCoordinateRegionMakeWithDistance(location.coordinate,
                                                                  self.regionRadius * 2.0, self.regionRadius * 2.0)
        self.mapView.setRegion(coordinateRegion, animated: true)
    }
    
    func loadPins() {
        NSOperationQueue().addOperationWithBlock {
            let mapBoundsWidth = Double(self.mapView.bounds.size.width)
            let mapRectWidth:Double = self.mapView.visibleMapRect.size.width
            
            let scale:Double = mapBoundsWidth / mapRectWidth
            
            let annotationArray = self.clusteringManager.clusteredAnnotationsWithinMapRect(self.mapView.visibleMapRect,
                withZoomScale:scale)
            
            self.clusteringManager.displayAnnotations(annotationArray, onMapView:self.mapView)
        }
    }
    
    func loadPinsToMap() {
        var clusters:[FBAnnotation] = []
        for tree in STPKCoreData.sharedInstance.fetchTrees() {
            
            let image = STPKTreeDescription.image(treeName: tree.speciesName ?? "")
            let pin = STTreeAnnotation(tree: tree, image: image)
            
            self.mapView.addAnnotation(pin)
            clusters.append(pin)
        }
        self.clusteringManager.addAnnotations(clusters)
        self.loadPins()
    }
    
    func setupLocation() {
        switch CLLocationManager.authorizationStatus() {
        case .NotDetermined, .Restricted:
            self.locationManager.requestAlwaysAuthorization()
        case .AuthorizedAlways:
            self.mapView.showsUserLocation = true
        default:
            ()
        }
    }
}