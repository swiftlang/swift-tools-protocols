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

import LanguageServerProtocol
import XCTest

final class LSPAnyCodingTests: XCTestCase {

  // MARK: - Fixtures

  private struct Point: Codable, LSPAnyCodable, Equatable {
    var x: Int
    var y: Int
  }

  private struct Line: Codable, LSPAnyCodable, Equatable {
    var start: Point
    var end: Point
  }

  private struct Primitives: Codable, LSPAnyCodable, Equatable {
    var bool: Bool
    var int: Int
    var double: Double
    var string: String
    var null: String?
  }

  private struct WithArray: Codable, LSPAnyCodable, Equatable {
    var points: [Point]
  }

  private struct WithOptional: Codable, LSPAnyCodable, Equatable {
    var required: String
    var optional: String?
  }

  // MARK: - Encoder

  func testEncodeStruct() {
    let lspAny = Point(x: 3, y: 7).encodeToLSPAny()
    XCTAssertEqual(lspAny, .dictionary(["x": .int(3), "y": .int(7)]))
  }

  func testEncodePrimitiveTypes() {
    let lspAny = Primitives(bool: true, int: 42, double: 1.5, string: "hello", null: nil)
      .encodeToLSPAny()
    XCTAssertEqual(
      lspAny,
      .dictionary([
        "bool": .bool(true),
        "int": .int(42),
        "double": .double(1.5),
        "string": .string("hello"),
      ])
    )
  }

  func testEncodeNestedStruct() {
    let line = Line(start: Point(x: 0, y: 0), end: Point(x: 10, y: 20))
    let lspAny = line.encodeToLSPAny()
    XCTAssertEqual(
      lspAny,
      .dictionary([
        "start": .dictionary(["x": .int(0), "y": .int(0)]),
        "end": .dictionary(["x": .int(10), "y": .int(20)]),
      ])
    )
  }

  func testEncodeArrayField() {
    let value = WithArray(points: [Point(x: 1, y: 2), Point(x: 3, y: 4)])
    let lspAny = value.encodeToLSPAny()
    XCTAssertEqual(
      lspAny,
      .dictionary([
        "points": .array([
          .dictionary(["x": .int(1), "y": .int(2)]),
          .dictionary(["x": .int(3), "y": .int(4)]),
        ])
      ])
    )
  }

  func testEncodeOptionalPresent() {
    let lspAny = WithOptional(required: "req", optional: "opt").encodeToLSPAny()
    XCTAssertEqual(
      lspAny,
      .dictionary(["required": .string("req"), "optional": .string("opt")])
    )
  }

  func testEncodeOptionalAbsent() {
    let lspAny = WithOptional(required: "req", optional: nil).encodeToLSPAny()
    XCTAssertEqual(
      lspAny,
      .dictionary(["required": .string("req")])
    )
  }

  func testEncodeIntegerTypes() {
    struct IntTypes: Codable, LSPAnyCodable {
      var i8: Int8
      var i16: Int16
      var i32: Int32
      var i64: Int64
      var u8: UInt8
    }
    let lspAny = IntTypes(i8: 1, i16: 2, i32: 3, i64: 4, u8: 5).encodeToLSPAny()
    XCTAssertEqual(
      lspAny,
      .dictionary([
        "i8": .int(1), "i16": .int(2), "i32": .int(3), "i64": .int(4), "u8": .int(5),
      ])
    )
  }

  func testEncodeFloatType() {
    struct FloatType: Codable, LSPAnyCodable {
      var f: Float
    }
    let lspAny = FloatType(f: 2.5).encodeToLSPAny()
    XCTAssertEqual(lspAny, .dictionary(["f": .double(2.5)]))
  }

  func testEncodeEmptyStruct() {
    struct Empty: Codable, LSPAnyCodable {}
    // An empty struct produces an empty keyed container.
    XCTAssertEqual(Empty().encodeToLSPAny(), .dictionary([:]))
  }

  func testEncodeSingleValueType() {
    // A type that uses a single-value container rather than a keyed one.
    struct Wrapper: Codable, LSPAnyCodable {
      var value: Int
      func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
      }
      init(value: Int) { self.value = value }
      init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = try c.decode(Int.self)
      }
    }
    XCTAssertEqual(Wrapper(value: 99).encodeToLSPAny(), .int(99))
  }

  func testEncodeArrayAtTopLevel() {
    struct ArrayWrapper: Codable, LSPAnyCodable {
      var items: [Int]
      func encode(to encoder: any Encoder) throws {
        var c = encoder.unkeyedContainer()
        for item in items { try c.encode(item) }
      }
      init(items: [Int]) { self.items = items }
      init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var result: [Int] = []
        while !c.isAtEnd { result.append(try c.decode(Int.self)) }
        items = result
      }
    }
    XCTAssertEqual(ArrayWrapper(items: [1, 2, 3]).encodeToLSPAny(), .array([.int(1), .int(2), .int(3)]))
  }

  // MARK: - Decoder

  func testDecodeStruct() {
    let lspAny = LSPAny.dictionary(["x": .int(3), "y": .int(7)])
    XCTAssertEqual(Point(fromLSPAny: lspAny), Point(x: 3, y: 7))
  }

  func testDecodePrimitiveTypes() {
    let lspAny = LSPAny.dictionary([
      "bool": .bool(false),
      "int": .int(10),
      "double": .double(3.14),
      "string": .string("world"),
      "null": .null,
    ])
    XCTAssertEqual(
      Primitives(fromLSPAny: lspAny),
      Primitives(bool: false, int: 10, double: 3.14, string: "world", null: nil)
    )
  }

  func testDecodeNestedStruct() {
    let lspAny = LSPAny.dictionary([
      "start": .dictionary(["x": .int(0), "y": .int(0)]),
      "end": .dictionary(["x": .int(5), "y": .int(5)]),
    ])
    XCTAssertEqual(
      Line(fromLSPAny: lspAny),
      Line(start: Point(x: 0, y: 0), end: Point(x: 5, y: 5))
    )
  }

  func testDecodeArrayField() {
    let lspAny = LSPAny.dictionary([
      "points": .array([
        .dictionary(["x": .int(1), "y": .int(2)]),
        .dictionary(["x": .int(3), "y": .int(4)]),
      ])
    ])
    XCTAssertEqual(
      WithArray(fromLSPAny: lspAny),
      WithArray(points: [Point(x: 1, y: 2), Point(x: 3, y: 4)])
    )
  }

  func testDecodeOptionalPresent() {
    let lspAny = LSPAny.dictionary(["required": .string("r"), "optional": .string("o")])
    XCTAssertEqual(WithOptional(fromLSPAny: lspAny), WithOptional(required: "r", optional: "o"))
  }

  func testDecodeOptionalAbsent() {
    // A `.null` value for an optional field should decode as `nil`.
    let lspAny = LSPAny.dictionary(["required": .string("r")])
    XCTAssertEqual(WithOptional(fromLSPAny: lspAny), WithOptional(required: "r", optional: nil))
  }

  func testDecodeFailsWhenNotDictionary() {
    // A non-dictionary LSPAny cannot be decoded into a keyed struct.
    XCTAssertNil(Point(fromLSPAny: .array([.int(1), .int(2)])))
    XCTAssertNil(Point(fromLSPAny: .int(42)))
    XCTAssertNil(Point(fromLSPAny: .null))
  }

  func testDecodeFailsOnTypeMismatch() {
    // Providing wrong value types for fields silently returns nil.
    let lspAny = LSPAny.dictionary(["x": .string("not-an-int"), "y": .int(7)])
    XCTAssertNil(Point(fromLSPAny: lspAny))
  }

  func testDecodeFailsOnMissingKey() {
    let lspAny = LSPAny.dictionary(["x": .int(3)])  // "y" is missing
    XCTAssertNil(Point(fromLSPAny: lspAny))
  }

  func testDecodeNilLSPAnyReturnsNil() {
    XCTAssertNil(Point(fromLSPAny: nil))
  }

  func testDecodeFromDictionary() {
    // `init?(fromLSPDictionary:)` is a convenience wrapper for `.dictionary`.
    let dict: [String: LSPAny] = ["x": .int(3), "y": .int(7)]
    XCTAssertEqual(Point(fromLSPDictionary: dict), Point(x: 3, y: 7))
  }

  func testDecodeUnkeyedContainerDecodeNilDoesNotAdvanceOnNonNull() {
    // `UnkeyedDecodingContainer.decodeNil()` must NOT advance the index when
    // the current element is not nil, so the element can be decoded normally
    // on the next call.
    struct MixedArray: Codable, LSPAnyCodable, Equatable {
      var items: [Int?]
    }
    let lspAny = LSPAny.dictionary([
      "items": .array([.int(1), .null, .int(3)])
    ])
    XCTAssertEqual(MixedArray(fromLSPAny: lspAny), MixedArray(items: [1, nil, 3]))
  }

  // MARK: - Nested containers

  func testNestedKeyedContainerInKeyed() {
    // A type that splits its fields into two named sub-dictionaries using
    // `KeyedEncodingContainer.nestedContainer(keyedBy:forKey:)` /
    // `KeyedDecodingContainer.nestedContainer(keyedBy:forKey:)`.
    struct TaggedPayload: Codable, LSPAnyCodable, Equatable {
      var tag: String
      var value: Int
      init(tag: String, value: Int) { self.tag = tag; self.value = value }

      private enum OuterKeys: CodingKey { case meta, data }
      private enum MetaKeys: CodingKey { case tag }
      private enum DataKeys: CodingKey { case value }

      init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: OuterKeys.self)
        let meta = try outer.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
        tag = try meta.decode(String.self, forKey: .tag)
        let data = try outer.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        value = try data.decode(Int.self, forKey: .value)
      }

      func encode(to encoder: any Encoder) throws {
        var outer = encoder.container(keyedBy: OuterKeys.self)
        var meta = outer.nestedContainer(keyedBy: MetaKeys.self, forKey: .meta)
        try meta.encode(tag, forKey: .tag)
        var data = outer.nestedContainer(keyedBy: DataKeys.self, forKey: .data)
        try data.encode(value, forKey: .value)
      }
    }

    let original = TaggedPayload(tag: "hello", value: 42)

    XCTAssertEqual(
      original.encodeToLSPAny(),
      .dictionary([
        "meta": .dictionary(["tag": .string("hello")]),
        "data": .dictionary(["value": .int(42)]),
      ])
    )

    let lspAny = LSPAny.dictionary([
      "meta": .dictionary(["tag": .string("world")]),
      "data": .dictionary(["value": .int(99)]),
    ])
    XCTAssertEqual(TaggedPayload(fromLSPAny: lspAny), TaggedPayload(tag: "world", value: 99))

    XCTAssertEqual(TaggedPayload(fromLSPAny: original.encodeToLSPAny()), original)
  }

  func testNestedUnkeyedContainerInKeyed() {
    // A type that stores an array under a key by obtaining it via
    // `KeyedEncodingContainer.nestedUnkeyedContainer(forKey:)` /
    // `KeyedDecodingContainer.nestedUnkeyedContainer(forKey:)`.
    struct NumberList: Codable, LSPAnyCodable, Equatable {
      var items: [Int]
      init(items: [Int]) { self.items = items }

      private enum CodingKeys: CodingKey { case items }

      init(from decoder: any Decoder) throws {
        let outer = try decoder.container(keyedBy: CodingKeys.self)
        var list = try outer.nestedUnkeyedContainer(forKey: .items)
        var result: [Int] = []
        while !list.isAtEnd { result.append(try list.decode(Int.self)) }
        items = result
      }

      func encode(to encoder: any Encoder) throws {
        var outer = encoder.container(keyedBy: CodingKeys.self)
        var list = outer.nestedUnkeyedContainer(forKey: .items)
        for item in items { try list.encode(item) }
      }
    }

    let original = NumberList(items: [10, 20, 30])

    XCTAssertEqual(
      original.encodeToLSPAny(),
      .dictionary(["items": .array([.int(10), .int(20), .int(30)])])
    )

    let lspAny = LSPAny.dictionary(["items": .array([.int(1), .int(2)])])
    XCTAssertEqual(NumberList(fromLSPAny: lspAny), NumberList(items: [1, 2]))

    XCTAssertEqual(NumberList(fromLSPAny: original.encodeToLSPAny()), original)
  }

  func testNestedKeyedContainerInUnkeyed() {
    // A type that encodes as a top-level array of dictionaries by using
    // `UnkeyedEncodingContainer.nestedContainer(keyedBy:)` /
    // `UnkeyedDecodingContainer.nestedContainer(keyedBy:)` per element.
    struct Entry: Equatable {
      var key: String
      var value: Int
    }
    struct EntryList: Codable, LSPAnyCodable, Equatable {
      var entries: [Entry]
      init(entries: [Entry]) { self.entries = entries }

      private enum EntryCodingKeys: CodingKey { case key, value }

      init(from decoder: any Decoder) throws {
        var list = try decoder.unkeyedContainer()
        var result: [Entry] = []
        while !list.isAtEnd {
          let nested = try list.nestedContainer(keyedBy: EntryCodingKeys.self)
          result.append(
            Entry(
              key: try nested.decode(String.self, forKey: .key),
              value: try nested.decode(Int.self, forKey: .value)
            )
          )
        }
        entries = result
      }

      func encode(to encoder: any Encoder) throws {
        var list = encoder.unkeyedContainer()
        for entry in entries {
          var nested = list.nestedContainer(keyedBy: EntryCodingKeys.self)
          try nested.encode(entry.key, forKey: .key)
          try nested.encode(entry.value, forKey: .value)
        }
      }
    }

    let original = EntryList(entries: [Entry(key: "a", value: 1), Entry(key: "b", value: 2)])

    XCTAssertEqual(
      original.encodeToLSPAny(),
      .array([
        .dictionary(["key": .string("a"), "value": .int(1)]),
        .dictionary(["key": .string("b"), "value": .int(2)]),
      ])
    )

    let lspAny = LSPAny.array([.dictionary(["key": .string("x"), "value": .int(9)])])
    XCTAssertEqual(EntryList(fromLSPAny: lspAny), EntryList(entries: [Entry(key: "x", value: 9)]))

    XCTAssertEqual(EntryList(fromLSPAny: original.encodeToLSPAny()), original)
  }

  func testNestedUnkeyedContainerInUnkeyed() {
    // A type that encodes as a nested array (array of arrays) by using
    // `UnkeyedEncodingContainer.nestedUnkeyedContainer()` /
    // `UnkeyedDecodingContainer.nestedUnkeyedContainer()` per row.
    struct Matrix: Codable, LSPAnyCodable, Equatable {
      var rows: [[Int]]
      init(rows: [[Int]]) { self.rows = rows }

      init(from decoder: any Decoder) throws {
        var outer = try decoder.unkeyedContainer()
        var result: [[Int]] = []
        while !outer.isAtEnd {
          var inner = try outer.nestedUnkeyedContainer()
          var row: [Int] = []
          while !inner.isAtEnd { row.append(try inner.decode(Int.self)) }
          result.append(row)
        }
        rows = result
      }

      func encode(to encoder: any Encoder) throws {
        var outer = encoder.unkeyedContainer()
        for row in rows {
          var inner = outer.nestedUnkeyedContainer()
          for val in row { try inner.encode(val) }
        }
      }
    }

    let original = Matrix(rows: [[1, 2], [3, 4], [5]])

    XCTAssertEqual(
      original.encodeToLSPAny(),
      .array([
        .array([.int(1), .int(2)]),
        .array([.int(3), .int(4)]),
        .array([.int(5)]),
      ])
    )

    let lspAny = LSPAny.array([.array([.int(7), .int(8)]), .array([.int(9)])])
    XCTAssertEqual(Matrix(fromLSPAny: lspAny), Matrix(rows: [[7, 8], [9]]))

    XCTAssertEqual(Matrix(fromLSPAny: original.encodeToLSPAny()), original)
  }

  // MARK: - Roundtrip

  func testRoundtripSimpleStruct() {
    let original = Point(x: 42, y: -7)
    let decoded = Point(fromLSPAny: original.encodeToLSPAny())
    XCTAssertEqual(decoded, original)
  }

  func testRoundtripNestedStruct() {
    let original = Line(start: Point(x: 1, y: 2), end: Point(x: 3, y: 4))
    let decoded = Line(fromLSPAny: original.encodeToLSPAny())
    XCTAssertEqual(decoded, original)
  }

  func testRoundtripAllPrimitives() {
    let original = Primitives(bool: true, int: -1, double: 2.718, string: "swift", null: nil)
    let decoded = Primitives(fromLSPAny: original.encodeToLSPAny())
    XCTAssertEqual(decoded, original)
  }

  func testRoundtripArrayField() {
    let original = WithArray(points: [Point(x: 0, y: 0), Point(x: 1, y: 1), Point(x: 2, y: 2)])
    let decoded = WithArray(fromLSPAny: original.encodeToLSPAny())
    XCTAssertEqual(decoded, original)
  }

  func testRoundtripOptionalPresent() {
    let original = WithOptional(required: "a", optional: "b")
    XCTAssertEqual(WithOptional(fromLSPAny: original.encodeToLSPAny()), original)
  }

  func testRoundtripOptionalAbsent() {
    let original = WithOptional(required: "a", optional: nil)
    XCTAssertEqual(WithOptional(fromLSPAny: original.encodeToLSPAny()), original)
  }
}
