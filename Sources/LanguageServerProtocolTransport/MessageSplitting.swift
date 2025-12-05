//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

package import Foundation
import LanguageServerProtocol
@_spi(SourceKitLSP) import SKLogging

/// A stateful JSONRPC message parser. Expects data to be read in chunks of `nextReadLength`, though technically
/// handles any size as long as it doesn't pass header/contents/message boundaries (which `nextReadLength` ensures).
package class JSONMessageParser<MessageType> {
  /// Decoder of the JSON message contents
  private let decoder: (Data) -> MessageType?

  /// Buffer of received bytes that haven't been fully parsed.
  private var requestBuffer: Data = Data()

  /// Current parser state
  private var state: ReadState = .header

  /// The number of bytes to read given the current state of the parser.
  package var nextReadLength: Int {
    switch state {
    case .header:
      // The header and content is split by `\r\n\r\n`. If we had the full separator, then we would be in `.content`
      // state.
      if requestBuffer.last == UInt8(ascii: "\n") {
        // Can always read at least 2 bytes (we're either at `\r\n` or a lone `\n`)
        return 2
      } else if requestBuffer.last == UInt8(ascii: "\r") {
        // Could be at `\r\n\r`, so can only read a single byte
        return 1
      }
      // Don't have any part of the header separator, so can read at least its length
      return 4
    case .content(let remaining):
      // Read up until the end of the message (or anything remaining if we had a partial read)
      return remaining
    }
  }

  package init(decoder: @escaping (Data) -> MessageType?) {
    self.decoder = decoder
  }

  /// Parse the next chunk of data (see `nextReadLength`). Returns a message parsed by `decoder` if read and `nil`
  /// otherwise (including on error). Note that this does not handle being passed a chunk that crosses header+contents
  /// boundaries or whole message boundaries.
  package func parse(chunk: Data) -> MessageType? {
    switch state {
    case .header:
      parseHeader(data: chunk)
      return nil
    case .content(let remaining):
      return parseContent(data: chunk, remaining: remaining)
    }
  }

  private func parseHeader(data: Data) {
    requestBuffer += data
    if requestBuffer.suffix(4) != JSONRPCMessageHeader.headerSeparator {
      return
    }

    let header = orLog("Parsing JSONRPC message") {
      try requestBuffer.jsonrpcParseHeader()
    }
    requestBuffer.removeAll(keepingCapacity: true)

    guard let header,
      let length = header.contentLength,
      length > 0
    else {
      logger.error("Ignoring message due to invalid header")
      return
    }

    state = .content(remaining: length)
  }

  private func parseContent(data: Data, remaining: Int) -> MessageType? {
    precondition(data.count <= remaining, "Received chunk larger than remaining content size")

    if data.count < remaining {
      // Don't have the whole message yet
      requestBuffer += data
      state = .content(remaining: remaining - data.count)
      return nil
    }

    // Two cases here:
    // 1. The whole message was read at once
    // 2. The reads were split
    //
    // For (1), `requestBuffer` will be empty and we can use `data` directly to avoid the extra copy.
    let message: MessageType?
    if requestBuffer.isEmpty {
      message = decoder(data)
    } else {
      requestBuffer += data
      message = decoder(requestBuffer)
    }
    requestBuffer.removeAll(keepingCapacity: true)

    state = .header

    if message == nil {
      logger.error("Ignoring message due to invalid content")
    }
    return message
  }
}

private enum ReadState {
  case header
  case content(remaining: Int)
}

@_spi(Testing)
public struct JSONRPCMessageHeader: Hashable {
  static let contentLengthKey: [UInt8] = [UInt8]("Content-Length".utf8)
  static let separator: [UInt8] = [UInt8]("\r\n".utf8)
  static let colon: UInt8 = UInt8(ascii: ":")
  static let invalidKeyBytes: [UInt8] = [colon] + separator
  static let headerSeparator: [UInt8] = Array("\r\n\r\n".utf8)

  public var contentLength: Int? = nil

  public init(contentLength: Int? = nil) {
    self.contentLength = contentLength
  }
}

extension RandomAccessCollection<UInt8> where Index == Int {
  @_spi(Testing)
  public func jsonrpcParseHeader() throws -> JSONRPCMessageHeader? {
    var header = JSONRPCMessageHeader()
    var slice = self[...]
    while let (kv, rest) = try slice.jsonrpcParseHeaderField() {
      guard let (key, value) = kv else {
        return header
      }
      slice = rest

      if key.elementsEqual(JSONRPCMessageHeader.contentLengthKey) {
        guard let count = Int(ascii: value) else {
          throw MessageDecodingError.parseError(
            "expected integer value in \(String(bytes: value, encoding: .utf8) ?? "<invalid>")"
          )
        }
        header.contentLength = count
      }

      // Unknown field, continue.
    }
    return nil
  }

  @_spi(Testing)
  public func jsonrpcParseHeaderField() throws -> ((key: SubSequence, value: SubSequence)?, SubSequence)? {
    if starts(with: JSONRPCMessageHeader.separator) {
      return (nil, dropFirst(JSONRPCMessageHeader.separator.count))
    } else if first == JSONRPCMessageHeader.separator.first {
      return nil
    }

    guard let keyEnd = firstIndex(where: { JSONRPCMessageHeader.invalidKeyBytes.contains($0) }) else {
      return nil
    }
    if self[keyEnd] != JSONRPCMessageHeader.colon {
      throw MessageDecodingError.parseError("expected ':' in message header")
    }
    let valueStart = index(after: keyEnd)
    guard let valueEnd = self[valueStart...].firstRange(of: JSONRPCMessageHeader.separator)?.startIndex else {
      return nil
    }

    return ((key: self[..<keyEnd], value: self[valueStart..<valueEnd]), self[index(valueEnd, offsetBy: 2)...])
  }
}

extension UInt8 {
  /// *Public for *testing*. Whether this byte is an ASCII whitespace character (isspace).
  @inlinable
  public var isSpace: Bool {
    switch self {
    case UInt8(ascii: " "), UInt8(ascii: "\t"), /*LF*/ 0xa, /*VT*/ 0xb, /*FF*/ 0xc, /*CR*/ 0xd:
      return true
    default:
      return false
    }
  }

  /// *Public for *testing*. Whether this byte is an ASCII decimal digit (isdigit).
  @inlinable
  public var isDigit: Bool {
    return UInt8(ascii: "0") <= self && self <= UInt8(ascii: "9")
  }

  /// *Public for *testing*. The integer value of an ASCII decimal digit.
  @inlinable
  public var asciiDigit: Int {
    precondition(isDigit)
    return Int(self - UInt8(ascii: "0"))
  }
}

extension Int {

  /// Constructs an integer from a buffer of base-10 ascii digits, ignoring any surrounding whitespace.
  ///
  /// This is similar to `atol` but with several advantages:
  /// - no need to construct a null-terminated C string
  /// - overflow will trap instead of being undefined
  /// - does not allow non-whitespace characters at the end
  @inlinable
  public init?<C>(ascii buffer: C) where C: Collection, C.Element == UInt8 {
    guard !buffer.isEmpty else { return nil }

    // Trim leading whitespace.
    var i = buffer.startIndex
    while i != buffer.endIndex, buffer[i].isSpace {
      i = buffer.index(after: i)
    }

    guard i != buffer.endIndex else { return nil }

    // Check sign if any.
    var sign = 1
    if buffer[i] == UInt8(ascii: "+") {
      i = buffer.index(after: i)
    } else if buffer[i] == UInt8(ascii: "-") {
      i = buffer.index(after: i)
      sign = -1
    }

    guard i != buffer.endIndex, buffer[i].isDigit else { return nil }

    // Accumulate the result.
    var result = 0
    while i != buffer.endIndex, buffer[i].isDigit {
      result = result * 10 + sign * buffer[i].asciiDigit
      i = buffer.index(after: i)
    }

    // Trim trailing whitespace.
    while i != buffer.endIndex {
      if !buffer[i].isSpace { return nil }
      i = buffer.index(after: i)
    }
    self = result
  }

  // Constructs an integer from a buffer of base-10 ascii digits, ignoring any surrounding whitespace.
  ///
  /// This is similar to `atol` but with several advantages:
  /// - no need to construct a null-terminated C string
  /// - overflow will trap instead of being undefined
  /// - does not allow non-whitespace characters at the end
  @inlinable
  public init?<S>(ascii buffer: S) where S: StringProtocol {
    self.init(ascii: buffer.utf8)
  }
}
