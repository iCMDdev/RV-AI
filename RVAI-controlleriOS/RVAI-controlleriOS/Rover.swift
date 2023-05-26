//
//  Robot.swift
//  robovideo
//
//  Created by Cristian-Mihai Dinca on 14.05.2023.
//

import Foundation
import CoreLocation

class Rover: ObservableObject, Identifiable {
    let id: UUID = UUID()
    var address: String = "192.168.100.1"
    
    @Published var location: CLLocation?
    @Published var locationHistory: [CLLocation?] = []
    @Published var batteryLevel: Double?
    @Published var batteryVoltage: Double?
    @Published var online: Bool = false
    @Published var modelOutput: String = "X to run ML analysis"
    @Published var modelAccuracy: Double?
    
    /// Use API to get location history
    func getLocationHistory() {
        
    }
    
    func sendMotors(speed: Double, rotation: Double) async {
        do {
            let url = URL(string: "http://raspberrypi.local:8080/motors")!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "POST"
            let parameters: [String: Double] = [
                "speed": speed,
                "rotation": rotation
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: parameters)

            let _ = try await URLSession.shared.data(for: request)
            self.online = true
        } catch let error {
            if let error = error as? URLError {
                if (error.code == .timedOut) || (error.code == .cannotFindHost) || (error.code == .notConnectedToInternet) {
                    self.online = false
                }
            }
            print("Error: \(error.localizedDescription)")
        }
    }
    
    func aiAnalysisTrigger() async {
        do {
            let url = URL(string: "http://raspberrypi.local:8080/aianalysis")!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "POST"

            let data: Data
            (data, _) = try await URLSession.shared.data(for: request)
            self.online = true
            print(String(data: data, encoding: .utf8))
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let label = json["label"] as? String, let score = json["score"] as? Double {
                    self.modelOutput = label
                    self.modelAccuracy = score
                }
            }
        } catch let error {
            if let error = error as? URLError {
                if (error.code == .timedOut) || (error.code == .cannotFindHost) || (error.code == .notConnectedToInternet) {
                    self.online = false
                }
            }
            print("Error: \(error.localizedDescription)")
        }
    }
    
    /// Use API to get current location
    func getCurrentLocation() async {
        do {
            let url = URL(string: "http://raspberrypi.local:8080/location")!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "GET"

            let data: Data
            
            (data, _) = try await URLSession.shared.data(for: request)
            //JSONSerialization.jsonObject(with: data)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // try to read out a string array
                if let altitude = json["altitude"] as? String, let latitude = json["latitude"] as? String, let longitude = json["longitude"] as? String {
                    print(latitude, longitude)
                    if let latitudeDouble = Double(latitude), let longitudeDouble = Double(longitude) {
                        self.location = CLLocation(latitude: CLLocationDegrees(floatLiteral: latitudeDouble), longitude: CLLocationDegrees(floatLiteral: longitudeDouble))
                    }
                    //print(location)
                }
            }
            self.online = true
        } catch let error {
            if let error = error as? URLError {
                if (error.code == .timedOut) || (error.code == .cannotFindHost) || (error.code == .notConnectedToInternet) {
                    self.online = false
                }
            }
            print("Error: \(error.localizedDescription)")
        }
        //messages = try JSONDecoder().decode([Message].self, from: data)
    }
    
    func getCurrentBattery() async {
        do {
            let url = URL(string: "http://raspberrypi.local:8080/batteryvoltage")!
            var request = URLRequest(url: url)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpMethod = "GET"

            let data: Data
            
            (data, _) = try await URLSession.shared.data(for: request)
            self.online = true
            //JSONSerialization.jsonObject(with: data)
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // try to read out a string array
                if let voltage = json["voltage"] as? Double {
                    print(voltage)
                    let batteryLevel = ((voltage-15)/5.2).truncatingRemainder(dividingBy: 100)*100
                    if batteryLevel < 0 {
                        self.batteryLevel = 0
                    } else if batteryLevel > 0 {
                        self.batteryLevel = 100
                    } else {
                        self.batteryLevel = batteryLevel
                    }
                    self.batteryVoltage = voltage
                    //print(location)
                }
            }
        } catch let error {
            if let error = error as? URLError {
                if (error.code == .timedOut) || (error.code == .cannotFindHost) || (error.code == .notConnectedToInternet) {
                    self.online = false
                }
            }
            print("Error: \(error.localizedDescription)")
        }
        //messages = try JSONDecoder().decode([Message].self, from: data)
    }
}
