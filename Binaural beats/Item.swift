//
//  Item.swift
//  Binaural beats
//
//  Created by Tomohiro Hayashi on 2026/07/07.
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
