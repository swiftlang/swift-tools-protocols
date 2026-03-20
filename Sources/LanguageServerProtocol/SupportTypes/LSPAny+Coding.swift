//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2026 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

extension LSPAnyCodable where Self: Encodable {
  public func encodeToLSPAny() -> LSPAny {
    let encoder = LSPAnyEncoder()
    // `LSPAnyEncoder` itself should never throws.
    // It's implementers responsibility not to throw in `encode(to:)`.
    try! self.encode(to: encoder)
    return encoder.reference.toLSPAny()
  }
}

extension LSPAnyCodable where Self: Decodable {
  public init?(fromLSPAny lspAny: LSPAny?) {
    guard let lspAny else {
      return nil
    }
    let decoder = LSPAnyDecoder(value: lspAny)
    // Silently return nil on failure, as per the default `LSPAnyCodable.init?(fromLSPAny:)`
    try? self.init(from: decoder)
  }

  public init?(fromLSPDictionary dictionary: [String: LSPAny]) {
    self.init(fromLSPAny: .dictionary(dictionary))
  }
}

/// Integer-index `CodingKey` for `UnkeyedContainer` coding paths.
private struct IndexCodingKey: CodingKey {
  private let index: Int

  var stringValue: String { "\(index)" }
  var intValue: Int? { index }

  init(_ index: Int) {
    self.index = index
  }
  init?(intValue: Int) {
    self.index = intValue
  }
  init?(stringValue: String) {
    return nil
  }
}

private final class LSPAnyEncoder: Encoder {
  // Mutable node in the encoding tree. Containers hold a reference to a node
  // in their parent so that values encoded through nested containers propagate
  // back up to the root.
  final class LSPAnyReference {
    private enum Storage {
      case single(LSPAny)
      case keyed([String: LSPAnyReference])
      case unkeyed([LSPAnyReference])
    }

    // Encoded value; nil means nothing has been encoded yet.
    private var storage: Storage? = nil {
      willSet { precondition(storage == nil || newValue == nil, "storage overwritten") }
    }

    init() {}

    // MARK: - .single

    func set(value: LSPAny) {
      storage = .single(value)
    }

    // MARK: - .keyed

    func prepareKeyed() {
      storage = .keyed([:])
    }
    func set(key: String, value: LSPAnyReference) {
      guard case .keyed(var dictionary)? = storage else {
        preconditionFailure("set(key:value:) only available for .keyed")
      }
      storage = nil  // Nil out first so `dictionary` is uniquely referenced (COW).
      dictionary[key] = value
      storage = .keyed(dictionary)
    }

    // MARK: - .unkeyed

    func prepareUnkeyed() {
      storage = .unkeyed([])
    }
    func append(value: LSPAnyReference) {
      guard case .unkeyed(var array)? = storage else {
        preconditionFailure("append(value:) only available for .unkeyed")
      }
      storage = nil  // Nil out first so `array` is uniquely referenced (COW).
      array.append(value)
      storage = .unkeyed(array)
    }
    func count() -> Int {
      guard case .unkeyed(let array)? = storage else {
        preconditionFailure("count() only available for .unkeyed")
      }
      return array.count
    }

    // MARK: - Finalize

    /// Finalize the encoding result.
    func toLSPAny() -> LSPAny {
      switch self.storage {
      case .single(let value):
        return value
      case .keyed(let dictionary):
        return .dictionary(
          dictionary.reduce(into: [:]) { dict, pair in
            dict[pair.key] = pair.value.toLSPAny()
          }
        )
      case .unkeyed(let array):
        return .array(
          array.map { element in
            element.toLSPAny()
          }
        )
      case nil:
        // defaults to '.dictionary([:])' following 'Foundation.JSONEncoder'.
        return .dictionary([:])
      }
    }
  }

  private struct SingleValueContainer: SingleValueEncodingContainer {
    private let reference: LSPAnyReference
    let codingPath: [any CodingKey]

    init(reference: LSPAnyReference, codingPath: [any CodingKey]) {
      self.reference = reference
      self.codingPath = codingPath
    }

    func encodeNil() throws {
      reference.set(value: .null)
    }
    func encode(_ value: Bool) throws {
      reference.set(value: .bool(value))
    }
    func encode(_ value: String) throws {
      reference.set(value: .string(value))
    }
    func encode<T: BinaryInteger & Encodable>(_ value: T) throws {
      reference.set(value: .int(Int(truncatingIfNeeded: value)))
    }
    func encode<T: BinaryFloatingPoint & Encodable>(_ value: T) throws {
      reference.set(value: .double(Double(value)))
    }
    func encode<T: Encodable>(_ value: T) throws {
      if let lspAny = value as? LSPAny {
        return reference.set(value: lspAny)
      }
      let encoder = LSPAnyEncoder(reference: reference, codingPath: codingPath)
      try value.encode(to: encoder)
    }
  }

  private struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    private let reference: LSPAnyReference
    let codingPath: [any CodingKey]

    init(reference: LSPAnyReference, codingPath: [any CodingKey]) {
      reference.prepareKeyed()
      self.reference = reference
      self.codingPath = codingPath
    }

    private func withValueReference<T>(
      forKey key: Key,
      encode: (LSPAnyReference, [any CodingKey]) throws -> T
    ) rethrows -> T {
      let valueRef = LSPAnyReference()
      let valueCodingPath = self.codingPath + [key]
      reference.set(key: key.stringValue, value: valueRef)
      return try encode(valueRef, valueCodingPath)
    }

    private func withValueContainer(forKey key: Key, encode: (SingleValueContainer) throws -> Void) throws {
      try withValueReference(forKey: key) {
        try encode(SingleValueContainer(reference: $0, codingPath: $1))
      }
    }

    func encodeNil(forKey key: Key) throws {
      try withValueContainer(forKey: key) { try $0.encodeNil() }
    }
    func encode(_ value: Bool, forKey key: Key) throws {
      try withValueContainer(forKey: key) { try $0.encode(value) }
    }
    func encode(_ value: String, forKey key: Key) throws {
      try withValueContainer(forKey: key) { try $0.encode(value) }
    }
    func encode<T: BinaryInteger & Encodable>(_ value: T, forKey key: Key) throws {
      try withValueContainer(forKey: key) { try $0.encode(value) }
    }
    func encode<T: BinaryFloatingPoint & Encodable>(_ value: T, forKey key: Key) throws {
      try withValueContainer(forKey: key) { try $0.encode(value) }
    }
    func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
      try withValueContainer(forKey: key) { try $0.encode(value) }
    }
    func nestedContainer<NestedKey: CodingKey>(
      keyedBy keyType: NestedKey.Type,
      forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
      withValueReference(forKey: key) {
        KeyedEncodingContainer(KeyedContainer<NestedKey>(reference: $0, codingPath: $1))
      }
    }
    func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
      withValueReference(forKey: key) {
        UnkeyedContainer(reference: $0, codingPath: $1)
      }
    }
    func superEncoder() -> any Encoder {
      fatalError("unimplemented")
    }
    func superEncoder(forKey key: Key) -> any Encoder {
      fatalError("unimplemented")
    }
  }

  private struct UnkeyedContainer: UnkeyedEncodingContainer {
    private let reference: LSPAnyReference
    let codingPath: [any CodingKey]

    init(reference: LSPAnyReference, codingPath: [any CodingKey]) {
      reference.prepareUnkeyed()
      self.reference = reference
      self.codingPath = codingPath
    }

    var count: Int {
      reference.count()
    }

    private func withAppendingReference<T>(encode: (LSPAnyReference, [any CodingKey]) throws -> T) rethrows -> T {
      let valueRef = LSPAnyReference()
      let valueCodingPath = self.codingPath + [IndexCodingKey(count)]
      reference.append(value: valueRef)
      return try encode(valueRef, valueCodingPath)
    }
    private func withAppendingContainer(encode: (SingleValueContainer) throws -> Void) rethrows {
      try withAppendingReference {
        try encode(SingleValueContainer(reference: $0, codingPath: $1))
      }
    }

    func encodeNil() throws {
      try withAppendingContainer { try $0.encodeNil() }
    }
    func encode(_ value: Bool) throws {
      try withAppendingContainer { try $0.encode(value) }
    }
    func encode(_ value: String) throws {
      try withAppendingContainer { try $0.encode(value) }
    }
    func encode<T: BinaryInteger & Encodable>(_ value: T) throws {
      try withAppendingContainer { try $0.encode(value) }
    }
    func encode<T: BinaryFloatingPoint & Encodable>(_ value: T) throws {
      try withAppendingContainer { try $0.encode(value) }
    }
    func encode<T: Encodable>(_ value: T) throws {
      try withAppendingContainer { try $0.encode(value) }
    }
    func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> {
      withAppendingReference {
        KeyedEncodingContainer(KeyedContainer<NestedKey>(reference: $0, codingPath: $1))
      }
    }
    func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
      withAppendingReference {
        UnkeyedContainer(reference: $0, codingPath: $1)
      }
    }
    func superEncoder() -> any Encoder {
      fatalError("unimplemented")
    }
  }

  let reference: LSPAnyReference
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  init(reference: LSPAnyReference = .init(), codingPath: [any CodingKey] = []) {
    self.reference = reference
    self.codingPath = codingPath
  }

  func singleValueContainer() -> any SingleValueEncodingContainer {
    SingleValueContainer(reference: reference, codingPath: codingPath)
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
    KeyedEncodingContainer(KeyedContainer<Key>(reference: reference, codingPath: codingPath))
  }
  func unkeyedContainer() -> any UnkeyedEncodingContainer {
    UnkeyedContainer(reference: reference, codingPath: codingPath)
  }
}

private final class LSPAnyDecoder: Decoder {
  private static func typeMismatch(_ type: Any.Type, expectedKind: String, codingPath: [CodingKey]) -> any Error {
    return DecodingError.typeMismatch(type, .init(codingPath: codingPath, debugDescription: "not a \(expectedKind)"))
  }

  private struct SingleValueContainer: SingleValueDecodingContainer {
    private let value: LSPAny
    let codingPath: [any CodingKey]

    init(value: LSPAny, codingPath: [any CodingKey]) {
      self.value = value
      self.codingPath = codingPath
    }

    func decodeNil() -> Bool {
      return value == .null
    }
    func decode(_ type: Bool.Type) throws -> Bool {
      guard case .bool(let result) = value else {
        throw typeMismatch(Bool.self, expectedKind: "bool", codingPath: codingPath)
      }
      return result
    }
    func decode(_ type: String.Type) throws -> String {
      guard case .string(let result) = value else {
        throw typeMismatch(String.self, expectedKind: "string", codingPath: codingPath)
      }
      return String.init(result)
    }
    func decode<T: BinaryInteger & Decodable>(_ type: T.Type) throws -> T {
      guard case .int(let result) = value else {
        throw typeMismatch(T.self, expectedKind: "int", codingPath: codingPath)
      }
      return T.init(truncatingIfNeeded: result)
    }
    func decode<T: BinaryFloatingPoint & Decodable>(_ type: T.Type) throws -> T {
      guard case .double(let result) = value else {
        throw typeMismatch(T.self, expectedKind: "double", codingPath: codingPath)
      }
      return T.init(result)
    }
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
      if let lspAny = value as? T {
        return lspAny
      }
      let decoder = LSPAnyDecoder(value: value, codingPath: codingPath)
      return try T(from: decoder)
    }
  }

  private struct KeyedContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    private let dictionary: [String: LSPAny]
    let codingPath: [any CodingKey]

    init(value: LSPAny, codingPath: [any CodingKey]) throws {
      guard case .dictionary(let dictionary) = value else {
        throw typeMismatch(Self.self, expectedKind: "dictionary", codingPath: codingPath)
      }
      self.dictionary = dictionary
      self.codingPath = codingPath
    }

    var allKeys: [Key] {
      dictionary.keys.compactMap(Key.init(stringValue:))
    }

    func contains(_ key: Key) -> Bool {
      dictionary[key.stringValue] != nil
    }

    private func withValue<T>(forKey key: Key, decode: (LSPAny, [any CodingKey]) throws -> T) throws -> T {
      guard let value = dictionary[key.stringValue] else {
        throw DecodingError.keyNotFound(key, .init(codingPath: codingPath, debugDescription: "missing key"))
      }
      return try decode(value, codingPath + [key])
    }
    private func withValueContainer<T>(forKey key: Key, decode: (SingleValueContainer) throws -> T) throws -> T {
      try withValue(forKey: key) {
        try decode(SingleValueContainer(value: $0, codingPath: $1))
      }
    }

    func decodeNil(forKey key: Key) throws -> Bool {
      try withValueContainer(forKey: key) { $0.decodeNil() }
    }
    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool {
      try withValueContainer(forKey: key) { try $0.decode(Bool.self) }
    }
    func decode(_ type: String.Type, forKey key: Key) throws -> String {
      try withValueContainer(forKey: key) { try $0.decode(String.self) }
    }
    func decode<T: BinaryInteger & Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
      try withValueContainer(forKey: key) { try $0.decode(T.self) }
    }
    func decode<T: BinaryFloatingPoint & Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
      try withValueContainer(forKey: key) { try $0.decode(T.self) }
    }
    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
      try withValueContainer(forKey: key) { try $0.decode(T.self) }
    }
    func nestedContainer<NestedKey: CodingKey>(
      keyedBy type: NestedKey.Type,
      forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
      try withValue(forKey: key) {
        try KeyedDecodingContainer(KeyedContainer<NestedKey>(value: $0, codingPath: $1))
      }
    }
    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
      try withValue(forKey: key) {
        try UnkeyedContainer(value: $0, codingPath: $1)
      }
    }
    func superDecoder() throws -> any Decoder {
      fatalError("unimplemented")
    }
    func superDecoder(forKey key: Key) throws -> any Decoder {
      fatalError("unimplemented")
    }
  }

  private struct UnkeyedContainer: UnkeyedDecodingContainer {
    private let array: [LSPAny]
    private(set) var currentIndex: Int
    let codingPath: [any CodingKey]

    init(value: LSPAny, codingPath: [any CodingKey]) throws {
      guard case .array(let array) = value else {
        throw typeMismatch(Self.self, expectedKind: "array", codingPath: codingPath)
      }
      self.array = array
      self.currentIndex = 0
      self.codingPath = codingPath
    }

    var count: Int? { array.count }
    var isAtEnd: Bool { currentIndex >= array.count }

    private mutating func withCurrentValueAndAdvance<T>(_ decode: (LSPAny, [any CodingKey]) throws -> T) throws -> T {
      let valueCodingPath = codingPath + [IndexCodingKey(currentIndex)]
      guard !isAtEnd else {
        throw DecodingError.valueNotFound(T.self, .init(codingPath: valueCodingPath, debugDescription: "out of index"))
      }
      defer {
        currentIndex += 1
      }
      return try decode(array[currentIndex], valueCodingPath)
    }

    private mutating func withCurrentValueContainerAndAdvance<T>(
      _ decode: (SingleValueContainer) throws -> T
    ) throws -> T {
      try withCurrentValueAndAdvance {
        try decode(SingleValueContainer(value: $0, codingPath: $1))
      }
    }

    mutating func decodeNil() throws -> Bool {
      let isNil = try withCurrentValueContainerAndAdvance { $0.decodeNil() }
      if !isNil {
        // 'UnkeyedDecodingContainer.decodeNil()' must not advance the index unless it's 'nil'.
        currentIndex -= 1
      }
      return isNil
    }
    mutating func decode(_ type: Bool.Type) throws -> Bool {
      try withCurrentValueContainerAndAdvance { try $0.decode(type) }
    }
    mutating func decode(_ type: String.Type) throws -> String {
      try withCurrentValueContainerAndAdvance { try $0.decode(String.self) }
    }
    mutating func decode<T: BinaryInteger & Decodable>(_ type: T.Type) throws -> T {
      try withCurrentValueContainerAndAdvance { try $0.decode(T.self) }
    }
    mutating func decode<T: BinaryFloatingPoint & Decodable>(_ type: T.Type) throws -> T {
      try withCurrentValueContainerAndAdvance { try $0.decode(T.self) }
    }
    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
      try withCurrentValueContainerAndAdvance { try $0.decode(type) }
    }
    mutating func nestedContainer<NestedKey: CodingKey>(
      keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
      try withCurrentValueAndAdvance {
        try KeyedDecodingContainer(KeyedContainer<NestedKey>(value: $0, codingPath: $1))
      }
    }
    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
      try withCurrentValueAndAdvance {
        try UnkeyedContainer(value: $0, codingPath: $1)
      }
    }
    func superDecoder() throws -> any Decoder {
      fatalError("unimplemented")
    }
  }

  private let value: LSPAny
  let codingPath: [any CodingKey]
  var userInfo: [CodingUserInfoKey: Any] { [:] }

  init(value: LSPAny, codingPath: [any CodingKey] = []) {
    self.value = value
    self.codingPath = codingPath
  }

  func singleValueContainer() throws -> any SingleValueDecodingContainer {
    SingleValueContainer(value: value, codingPath: codingPath)
  }
  func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
    try KeyedDecodingContainer(KeyedContainer<Key>(value: value, codingPath: codingPath))
  }
  func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
    try UnkeyedContainer(value: value, codingPath: codingPath)
  }
}
