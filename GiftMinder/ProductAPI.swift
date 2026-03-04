//
//  ProductAPI.swift
//  GiftMinder
//
//  Created by David Johnson on 1/30/26.
//

import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
}

final class ProductAPI {
    private let baseURL = "https://fakestoreapi.com"

    func getAllProducts(completion: @escaping (Result<[Product], Error>) -> Void) {
        guard let url = URL(string: "\(baseURL)/products") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard
                let httpResponse = response as? HTTPURLResponse,
                200..<300 ~= httpResponse.statusCode,
                let data = data
            else {
                completion(.failure(APIError.invalidResponse))
                return
            }

            do {
                let products = try JSONDecoder().decode([Product].self, from: data)
                completion(.success(products))
            } catch {
                completion(.failure(error))
            }
        }.resume()
    }
}
