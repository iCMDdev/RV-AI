import Vapor
import Foundation
import SwiftSerial
import NIO
import Foundation

struct MotorsState: Content {
    var speed: Double      // positive = frontwards, negative = backwards
    var rotation: Double   // positive = clockwise, negative = counterclockwise
}

struct LightsMessage: Content {
    var frontlights: Bool
    var message: String
}

struct TargetLocation: Content {
    var latitude: String
    var longitude: String
}

var targetLocations: [TargetLocation] = []

enum RVState: String {
    case operational = "All Systems Operational"
    case batterylow = "Battery low"
}
var rvstate: RVState = .operational

final class MyHandler: ChannelInboundHandler {
    public typealias InboundIn = ByteBuffer
    public typealias OutboundOut = ByteBuffer
    var response: String = ""
    var message: String = ""
    
    public func channelActive(context: ChannelHandlerContext) {
        var buff = context.channel.allocator.buffer(capacity: 1024)
        buff.writeString(message)
        context.writeAndFlush(self.wrapOutboundOut(buff), promise: nil)
    }
    
    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let inBuff = self.unwrapInboundIn(data)
        response = inBuff.getString(at: inBuff.readerIndex, length: inBuff.readableBytes)!
        //print(response)
    }
}


func runServer(message: String) throws -> String {
    var handler = MyHandler()
    handler.message = message
    
    let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)

    defer {
        try! group.syncShutdownGracefully()
    }
    let bootstrap = ClientBootstrap(group: group)
    .channelInitializer { channel in
        channel.pipeline.addHandlers([handler])
    }
    let serverChannel = try bootstrap.connect(host: "127.0.0.1", port: 2222).wait()
    guard serverChannel.localAddress != nil else {
        return "Unable to bind to AICore."
    }
    print("Client started on \(serverChannel.localAddress!)")
    try serverChannel.closeFuture.wait()

    return handler.response
}

func routes(_ app: Application) throws {
    app.get { req async in
        let date = Date()
        // Create a DateFormatter instance
        let dateFormatter = DateFormatter()

        // Set the date format
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        // Convert the date to a string
        let dateString = dateFormatter.string(from: date)

        return "{\"name\": \"RV-AI API\", \"version\": \"v0.1\", \"date\": \"\(dateString)\"}"
    }

    app.get("hello") { req async -> String in
        "Hello, world!"
    }

    app.get("status") { req async -> String in
        return rvstate.rawValue
    }

    app.get("location") { req async -> String in
        
        return "{latitude: \" N\", longitude: \" E\", altitude: \" m\", latitudeError: \"\", longitudeError: \"\"}"
    }

    app.post("motors") { req async -> String in 
        let response = try? req.content.decode(MotorsState.self)
        guard let response = response else {
            return "{\"message\": \"Error parsing JSON data.\"}"
        }
        
        do {
            let serialPort = SerialPort(path: "/dev/ttyACM0")
            serialPort.setSettings(receiveRate: .baud115200, transmitRate: .baud115200, minimumBytesToRead: 0)
            try serialPort.openPort()

            let speed: Double = response.speed
            let rotation: Double = response.rotation
            print(speed, rotation)
            if speed != nil && rotation != nil {
                let motorA: Int = (Int(round(speed)) + Int(round(rotation)))%65026
                let motorB: Int = (Int(round(speed)) - Int(round(rotation)))%65026
                print(motorA, motorB, try serialPort.writeString("motors \(motorA) \(motorB)\n"))
            }
            serialPort.closePort()
        } catch {
            print("\(error)")
        }
        return "{\"message\": \"sent\"}"
    }

    app.get("batteryvoltage") { req async -> String in 
        do {
            let serialPort = SerialPort(path: "/dev/ttyACM0")
            serialPort.setSettings(receiveRate: .baud115200, transmitRate: .baud115200, minimumBytesToRead: 1)
            try serialPort.openPort()
            print(try serialPort.writeString("battery\n\n"))
            try await Task.sleep(nanoseconds: UInt64(1 * Double(100000000)))
            try serialPort.readLine()
            try serialPort.readLine()
            var level: String = try serialPort.readLine()
            serialPort.closePort()
            return "{\"voltage\": \(level)}"
        } catch {
            print("\(error)")
        }
        return "{\"Error\": \"Something went wrong.\"}"
    }

    app.post("lights") { req async -> String in 
        let response = try? req.content.decode(LightsMessage.self)
        print(req.content)
        guard let response = response else {
            return "{\"message\": \"Error parsing JSON data.\"}"
        }

        do {
            let serialPort = SerialPort(path: "/dev/ttyACM0")
            serialPort.setSettings(receiveRate: .baud115200, transmitRate: .baud115200, minimumBytesToRead: 1)
            try serialPort.openPort()
            if response.frontlights == true {
                print(try serialPort.writeString("frontlights "+response.message))
            } else {
                print(try serialPort.writeString("backlights "+response.message))
            }
        } catch {
            print("\(error)")
            return "{\"Error\": \"Something went wrong.\"}"
        }
        return "{\"message\": \"sent\"}"
    }

    app.post("aianalysis") { req async -> String in
        var response = ""
        do {
            response = try runServer(message: "GET /ai HTTP/1.1\nHost: 127.0.0.1\n\n")
            print(response, "endl")
            if response.split(separator: "\r\n").count >= 4 {
                response = String(response.split(separator: "\r\n")[3])
                //print(response)
            } else {
               return  "Error: Received corrupted response from AICore. Please try again."
            }
            return response
        } catch {
            print("not available")
            return "Error: AICore is not available."
            
        }
        return "{\"message\": \"sent\"}"

        //return "{\"message\": \"Motors set.\", \"speed\": \(response.speed), \"rotation\": \(response.rotation)}"
    }
    

    app.get("location") { req async -> String in 
        var response = ""
        do {
            response = try runServer(message: "GET /gps HTTP/1.1\nHost: 127.0.0.1\n\n")
            if response.split(separator: "\r\n").count >= 4 {
                response = String(response.split(separator: "\r\n")[3])
            } else {
                "Error: Received corrupted response from AICore. Please try again."
            }
            //print(response)
        } catch {
            return "Error: AICore is not available."
        }
        return "\(response)"
    }

    app.post("targetLocations") { req async -> String in 
        let response = try? req.content.decode(TargetLocation.self)
        guard let response = response else {
            return "{\"message\": \"Error parsing JSON data.\"}"
        }
        targetLocations.append(response)
        return "{\"message\": \"Target location added.\"}"
    }
}
