//
//  product.swift
//  GiftMinder
//
//  Created by David Johnson on 1/30/26.
//

import Foundation

struct Product: Codable, Identifiable {
    let id: Int
    let title: String
    let price: Double
    let description: String
    let category: String
    let image: String
}
