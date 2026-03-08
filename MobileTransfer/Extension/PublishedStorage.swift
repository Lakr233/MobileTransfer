//
//  PublishedStorage.swift
//  App
//
//  Created by Lakr Aream on 2023/6/5.
//  Copyright © 2023 Lakr Aream. All rights reserved.
//

import Foundation
import Observation

private let encoder = JSONEncoder()
private let decoder = JSONDecoder()

// MARK: - Observable-compatible PublishedStorage

/// A macro-friendly property storage that persists values to UserDefaults via JSON encoding.
/// Works with `@Observable` classes by using `@ObservationIgnored` and manual access/mutation tracking.
///
/// Usage inside an `@Observable` class:
/// ```
/// @ObservationIgnored
/// private var _myValue = StoredValue(key: "myKey", defaultValue: 42)
/// var myValue: Int {
///     get { access(keyPath: \.myValue); return _myValue.get() }
///     set { withMutation(keyPath: \.myValue) { _myValue.set(newValue) } }
/// }
/// ```
struct StoredValue<Value: Codable> {
    let key: String
    let defaultValue: Value
    let storage: UserDefaults

    init(key: String, defaultValue: Value, storage: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.storage = storage
    }

    func get() -> Value {
        if let read = storage.value(forKey: key) as? Data,
           let object = try? decoder.decode(Value.self, from: read)
        {
            return object
        }
        return defaultValue
    }

    func set(_ newValue: Value) {
        do {
            let data = try encoder.encode(newValue)
            storage.setValue(data, forKey: key)
        } catch {
            storage.setValue(nil, forKey: key)
        }
    }
}
