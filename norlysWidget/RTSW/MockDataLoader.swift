//
//  MockDataLoader.swift
//  norlys
//
//  Created by Hugo Lageneste on 11/03/2025.
//


import Foundation

// MockDataLoader is responsible for loading mock data from a JSON file.
// The mockData.json file has been moved to the Resources folder for better organization.
struct MockDataLoader {
    static func loadMockData() -> [[String]] {
        if let path = Bundle.main.path(forResource: "mockData", ofType: "json", inDirectory: "Resources"),
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let jsonArray = try? JSONDecoder().decode([[String]].self, from: data) {
            return Array(jsonArray.dropFirst()) // Drop header row if present.
        }
        return []
    }
}
