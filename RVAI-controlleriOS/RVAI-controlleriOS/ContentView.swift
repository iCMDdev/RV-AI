//
//  ContentView.swift
//  RVAI-controlleriOS
//
//  Created by Cristian-Mihai Dinca on 23.05.2023.
//

import SwiftUI
import GameController
import WebKit

class VirtualController: ObservableObject {
    private var _virtualController: Any?
    @available(iOS 15.0, *)
    public var virtualController: GCVirtualController? {
      get { return self._virtualController as? GCVirtualController }
      set { self._virtualController = newValue }
    }
    
    init() {
        let virtualConfiguration = GCVirtualController.Configuration()
        virtualConfiguration.elements = [GCInputLeftThumbstick, GCInputRightThumbstick, GCInputButtonX]
        virtualController = GCVirtualController(configuration: virtualConfiguration)
        
        // Connect to the virtual controller if no physical controllers are available.
        if GCController.controllers().isEmpty {
            virtualController?.connect()
        }
        virtualController?.controller?.extendedGamepad?.valueChangedHandler = { (gamepad, element) -> Void in
            print("we're in")
            if element == self.virtualController?.controller?.extendedGamepad?.leftThumbstick {
                //print("x:",self.virtualController?.controller?.extendedGamepad?.leftThumbstick.yAxis.value)
            }
            if element == self.virtualController?.controller?.extendedGamepad?.rightThumbstick {
                //print("y:", self.virtualController?.controller?.extendedGamepad?.leftThumbstick.xAxis.value)
            }
        }
        virtualController?.connect()
    }
}

struct MpegView: View {
    @State private var image: UIImage = UIImage()
    @State private var timer = Timer.publish(every: 0.01, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Image(uiImage: image)
            
            .resizable()
            .aspectRatio(contentMode: .fit)
            .onReceive(timer) { _ in
                guard let url = URL(string: "http://raspberrypi.local:2222/stream.jpg") else {
                    return
                }
                URLSession.shared.dataTask(with: url) { data, response, error in
                    guard let data = data, error == nil else {
                        return
                    }
                    
                    DispatchQueue.main.async {
                        self.image = UIImage(data: data)!
                    }
                }.resume()
            }
    }
    
}

struct WebView: UIViewRepresentable {
    let url: URL = URL(string: "http://raspberrypi.local:2222/")!
    @Binding var reloadPage: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
       // webView.scrollView.setZoomScale(2, animated: false)
        //webView.scrollView.zoom(to: CGRect(x: webView.scrollView.contentSize.width/2, y: 0, width: 10000, height: 10000), animated: false)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.load(URLRequest(url: url))
        //webView.scrollView.setZoomScale(2, animated: false)
        if reloadPage == true {
            webView.reload()
            reloadPage = false
        }
    }
}

struct ContentView: View {
    @StateObject var rover = Rover()
    @StateObject var virtualController = VirtualController()
    @State var timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State var timer2 = Timer.publish(every: 10, on: .main, in: .common).autoconnect()
    @State var speed: Double = 0
    @State var rotation: Double = 0
    @State var clickedButton = false
    @State var reloadPage = false
    @State var showModelResults = false
    
    var body: some View {
        ZStack(alignment: .top) {
            WebView(reloadPage: $reloadPage).scaleEffect(1.5)
                .onReceive(timer) { _ in
                    let newSpeed = Double(virtualController.virtualController?.controller?.extendedGamepad?.leftThumbstick.yAxis.value ?? 0)
                    let newRotation = Double(virtualController.virtualController?.controller?.extendedGamepad?.rightThumbstick.xAxis.value ?? 0)
                    let newClicked = virtualController.virtualController?.controller?.extendedGamepad?.buttonX.isPressed ?? false
                    //print(newSpeed)
                    if speed != newSpeed || rotation != newRotation {
                        speed = newSpeed
                        rotation = newRotation
                        Task {
                            await rover.sendMotors(speed: speed*65025, rotation: rotation*65025)
                        }
                    }
                    
                    if clickedButton != newClicked {
                        clickedButton = newClicked
                        if clickedButton == true {
                            print(newClicked)
                            Task {
                                await rover.aiAnalysisTrigger()
                            }
                        }
                    }
                }
                .onReceive(timer2) { _ in
                    Task {
                        await rover.getCurrentLocation()
                    }
                }
            HStack(alignment: .top) {
                //Spacer()
                Spacer()
                HStack {
                    
                        //.padding()
                    if rover.batteryLevel != nil && rover.batteryVoltage != nil {
                        if rover.batteryLevel ?? 0 < 12.5 {
                            Image(systemName: "battery.0")
                                .foregroundColor(.white)
                                .imageScale(.large)
                        } else if rover.batteryLevel ?? 0 < 37.5 {
                            Image(systemName: "battery.25")
                                .foregroundColor(.white)
                                .imageScale(.large)
                        } else if rover.batteryLevel ?? 0 < 62.5 {
                            Image(systemName: "battery.50")
                                .foregroundColor(.white)
                                .imageScale(.large)
                        } else if rover.batteryLevel ?? 0 < 62.5 {
                            Image(systemName: "battery.75")
                                .foregroundColor(.white)
                                .imageScale(.large)
                        } else {
                            Image(systemName: "battery.100")
                                .foregroundColor(.white)
                                .imageScale(.large)
                        }
                        Grid {
                            GridRow {
                                Text("\(rover.batteryLevel ?? 0, specifier: "%.2f" )")
                                Text("%")
                            }
                            .font(.footnote)
                            GridRow {
                                Text("\(rover.batteryVoltage ?? 0, specifier: "%.2f" )")
                                Text("V")
                            }
                            .font(.footnote)
                        }
                        .padding(.horizontal)
                        
                    }
                    
                    
                    Image(systemName: "circle.fill")
                        .foregroundColor(rover.online ? .green : .gray)
                        .imageScale(.small)
                    Text("RV-AI")
                        .padding(.horizontal)
                        .font(.headline.monospaced())
                        .fontWeight(.black)

                    VStack {
                        
                        if rover.location != nil {
                            Button {
                                let url = URL(string: "maps://?address=\(rover.location?.coordinate.latitude ?? 0),\(rover.location?.coordinate.longitude ?? 0)")
                                if UIApplication.shared.canOpenURL(url!) {
                                      UIApplication.shared.open(url!, options: [:], completionHandler: nil)
                                }
                            } label: {
                                Text("\(Double(rover.location?.coordinate.latitude ?? 0)) LAT \(Double(rover.location?.coordinate.longitude ?? 0)) LON")
                                    .font(.body.monospaced())
                            }
                        } else {
                            Text("n/a LAT n/a LON")
                                .font(.body.monospaced())
                        }

                    }
                    Button {
                        reloadPage = true
                        Task {
                            await rover.getCurrentLocation()
                            await rover.getCurrentBattery()
                        }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .foregroundColor(.white)
                            .imageScale(.large)
                            .padding(.horizontal)
                            //.padding()
                    }
                }
                .padding(.top, 15)
                .padding()
                .ignoresSafeArea()
                .foregroundColor(.white)
                .background(Color(white: 0, opacity: 0.55)).cornerRadius(20).padding(.top, -20)
                Spacer()
            }
            
            .onAppear() {
                Task {
                    await rover.getCurrentLocation()
                    await rover.getCurrentBattery()
                }
            }
            .onReceive(rover.$modelAccuracy, perform: { _ in
                withAnimation(.easeInOut) {
                    showModelResults = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    withAnimation(.easeInOut) {
                        self.showModelResults = false
                    }
                }
            })
            
            VStack {
                Spacer()
                HStack {
                    Text("\(rover.modelOutput)")
                        .font(.headline)
                    if rover.modelAccuracy != nil {
                        Text("\((rover.modelAccuracy ?? 0)*100, specifier: "%.2f")")
                            .font(.body.monospaced())
                    }
                }
                .foregroundColor(.white)
                .padding()
                .background(Color(white: 0, opacity: 0.55)).cornerRadius(20)
                .opacity(showModelResults ? 1 : 0)
                .padding()
                
            }
        }
    }
        
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
