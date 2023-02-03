//
//  DataConvertible.swift
//  Reach Sample
//
//  Created by Conner Christianson on 2/3/23.
//  Copyright © 2023 i3pd. All rights reserved.
//

import Foundation

protocol DataConvertible {
    init?(data: Data)
    var data: Data { get }
}

extension DataConvertible where Self: ExpressibleByIntegerLiteral{
    init?(data: Data) {
        var value: Self = 0
        guard data.count == MemoryLayout.size(ofValue: value) else { return nil }
        _ = withUnsafeMutableBytes(of: &value, { data.copyBytes(to: $0)} )
        self = value
    }

    var data: Data {
        return withUnsafeBytes(of: self) { Data($0) }
    }
}

extension UInt8: DataConvertible {}
extension UInt16: DataConvertible {}
extension UInt32: DataConvertible {}
extension UInt64: DataConvertible {}
extension Int8: DataConvertible {}
extension Int16: DataConvertible {}
extension Int32: DataConvertible {}
extension Int64: DataConvertible {}
extension Float32: DataConvertible {}
extension Float64: DataConvertible {}
extension Bool: DataConvertible {
    init?(data: Data) {
        let bytes = [UInt8](data)
        guard bytes.count == 1 else { return nil }
        self.init(bytes[0] == 1)
    }
    
    var data: Data {
        return Data(repeating: self ? 1 : 0, count: 1)
    }
}
