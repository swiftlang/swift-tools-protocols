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

import Foundation
import Testing
@_spi(SourceKitLSP) import ToolsProtocolsSwiftExtensions

struct FileModificationDateTests {
  private func withScratchDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appending(component: "FileModificationDateTests-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
  }

  private func createFile(at url: URL, modificationDate: Date) throws {
    try Data().write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modificationDate], ofItemAtPath: url.path)
  }

  private func fileManagerModificationDate(of url: URL) throws -> Date {
    return try #require(FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date)
  }

  /// The modification date of a regular file is the one reported by `FileManager`, including sub-second precision.
  @Test(arguments: [800_000_000.123_456_789, 800_000_018.002_222_18, 800_000_020.002_469_182])
  func regularFileMatchesFileManager(timeIntervalSinceReferenceDate: TimeInterval) throws {
    try withScratchDirectory { directory in
      let file = directory.appending(component: "file.swift")
      try createFile(at: file, modificationDate: Date(timeIntervalSinceReferenceDate: timeIntervalSinceReferenceDate))
      #expect(try file.fileModificationDate == fileManagerModificationDate(of: file))
    }
  }

  /// For a symlink, the result is the most recent modification date of the symlink and its destination.
  @Test func symlinkReturnsMostRecentDateInChain() throws {
    try withScratchDirectory { directory in
      let target = directory.appending(component: "target.swift")
      let link = directory.appending(component: "link.swift")

      try createFile(at: target, modificationDate: Date(timeIntervalSinceReferenceDate: 100_000_000))
      try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
      #expect(try link.fileModificationDate == fileManagerModificationDate(of: link))

      let newerDate = Date(timeIntervalSinceNow: 3600)
      try FileManager.default.setAttributes([.modificationDate: newerDate], ofItemAtPath: target.path)
      #expect(try link.fileModificationDate == fileManagerModificationDate(of: target))
    }
  }

  /// Relative symlink destinations are resolved relative to the symlink's directory.
  @Test func relativeSymlinkIsResolvedRelativeToLink() throws {
    try withScratchDirectory { directory in
      let subdirectory = directory.appending(component: "sub")
      try FileManager.default.createDirectory(at: subdirectory, withIntermediateDirectories: true)
      let target = directory.appending(component: "target.swift")
      let link = subdirectory.appending(component: "link.swift")

      try createFile(at: target, modificationDate: Date(timeIntervalSinceNow: 3600))
      try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "../target.swift")
      #expect(try link.fileModificationDate == fileManagerModificationDate(of: target))
    }
  }

  /// A missing file produces the same error as reading its attributes through `FileManager`.
  @Test func missingFileThrowsNoSuchFileError() throws {
    try withScratchDirectory { directory in
      let missing = directory.appending(component: "missing.swift")
      #expect {
        _ = try missing.fileModificationDate
      } throws: { error in
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
      }
    }
  }

  /// A symlink whose destination doesn't exist produces the same error as a missing file.
  @Test func danglingSymlinkThrowsNoSuchFileError() throws {
    try withScratchDirectory { directory in
      let link = directory.appending(component: "link.swift")
      try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: "missing.swift")
      #expect {
        _ = try link.fileModificationDate
      } throws: { error in
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError
      }
    }
  }

  /// A symlink cycle is reported instead of being followed forever.
  @Test func circularSymlinkThrows() throws {
    try withScratchDirectory { directory in
      let first = directory.appending(component: "first.swift")
      let second = directory.appending(component: "second.swift")
      try FileManager.default.createSymbolicLink(atPath: first.path, withDestinationPath: "second.swift")
      try FileManager.default.createSymbolicLink(atPath: second.path, withDestinationPath: "first.swift")
      #expect {
        _ = try first.fileModificationDate
      } throws: { error in
        guard case .circularSymlink = error as? FilePathError else {
          return false
        }
        return true
      }
    }
  }
}
