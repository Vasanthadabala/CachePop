//
//  Item.swift
//  CachePop
//
//  Created by Vasanth on 13/05/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
