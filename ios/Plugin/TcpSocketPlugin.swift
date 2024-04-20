import Foundation
import Capacitor
import SwiftSocket

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(TcpSocketPlugin)
public class TcpSocketPlugin: CAPPlugin {
    var clients: [TCPClient] = []
    
    @objc func connect(_ call: CAPPluginCall) {
        guard let ip = call.getString("ipAddress") else {
            call.reject("Must provide ip address to connect")
            return
        }
        let port = Int32(call.getInt("port", 9100))
        
        let client = TCPClient(address: ip, port: port)
        switch client.connect(timeout: 10) {
          case .success:
            clients.append(client);
            call.resolve(["client": clients.count - 1])
          case .failure(let error):
            call.reject(error.localizedDescription)
        }
    }
    
    @objc func send(_ call: CAPPluginCall) {
        let clientIndex = call.getInt("client", -1)
        if (clientIndex == -1)    {
            call.reject("No client specified")
        }
        let client = clients[clientIndex]
        let data = call.getString("data", "")
        
        var byteArray = [Byte]()
        for char in data.utf8{
            byteArray += [char]
        }
        
        switch client.send(data: byteArray) {
          case .success:
            call.resolve()
          case .failure(let error):
            call.reject(error.localizedDescription)
        }
    }
    
    @objc func read(_ call: CAPPluginCall) {
        let clientIndex = call.getInt("client", -1)
        if (clientIndex == -1)    {
            call.reject("No client specified")
        }
        let client = clients[clientIndex]
        
        let expectLen = call.getInt("expectLen", 1024)
        let timeout = call.getInt("timeout", 10)
        
        guard let response = client.read(expectLen, timeout: timeout),
                let data = String(bytes: response, encoding: .utf8) else {
            call.resolve(["result": ""])
            return
        }
        
        call.resolve(["result": data])
    }
    
    @objc func disconnect(_ call: CAPPluginCall) {
        let clientIndex = call.getInt("client") ?? -1
        if (clientIndex == -1)  {
            call.reject("No client specified")
        }
        if (clients.indices.contains(clientIndex))   {
            clients[clientIndex].close()
        }
        call.resolve(["client": clientIndex])
    }
}
