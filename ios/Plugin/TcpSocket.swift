import Foundation

@objc public class TcpSocket: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
