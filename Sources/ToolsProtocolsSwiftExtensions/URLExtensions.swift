//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2024 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

public import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

#if os(Windows)
import WinSDK
#endif

@_spi(SourceKitLSP) @frozen
public enum FilePathError: Error, CustomStringConvertible {
  case noFileSystemRepresentation(URL)
  case noFileURL(URL)
  case circularSymlink(URL)
  case fileAttributesDontHaveModificationDate(URL)

  public var description: String {
    switch self {
    case .noFileSystemRepresentation(let url):
      return "\(url.description) cannot be represented as a file system path"
    case .noFileURL(let url):
      return "\(url.description) is not a file URL"
    case .circularSymlink(let url):
      return "Circular symlink at \(url)"
    case .fileAttributesDontHaveModificationDate(let url):
      return "File attributes don't contain a modification date: \(url)"
    }
  }
}

extension URL {
  /// Assuming this is a file URL, resolves all symlinks in the path.
  ///
  /// - Note: We need this because `URL.resolvingSymlinksInPath()` not only resolves symlinks but also standardizes the
  ///   path by stripping away `private` prefixes. Since sourcekitd is not performing this standardization, using
  ///   `resolvingSymlinksInPath` can lead to slightly mismatched URLs between the sourcekit-lsp response and the test
  ///   assertion.
  @_spi(SourceKitLSP)
  public var realpath: URL {
    get throws {
      #if canImport(Darwin)
      return try self.filePath.withCString { path in
        guard let realpath = Darwin.realpath(path, nil) else {
          return self
        }
        defer {
          free(realpath)
        }
        return URL(fileURLWithPath: String(cString: realpath))
      }
      #else
      // Non-Darwin platforms don't have the `/private` stripping issue, so we can just use `self.resolvingSymlinksInPath`
      // here.
      return self.resolvingSymlinksInPath()
      #endif
    }
  }

  /// Assuming that this is a file URL, the path with which the file system refers to the file. This is similar to
  /// `path` but has two differences:
  /// - It uses backslashes as the path separator on Windows instead of forward slashes
  /// - It throws an error when called on a non-file URL.
  ///
  /// `filePath` should generally be preferred over `path` when dealing with file URLs.
  @_spi(SourceKitLSP)
  public var filePath: String {
    get throws {
      guard self.isFileURL else {
        throw FilePathError.noFileURL(self)
      }
      return try self.withUnsafeFileSystemRepresentation { filePathPtr in
        guard let filePathPtr else {
          throw FilePathError.noFileSystemRepresentation(self)
        }
        let filePath = String(cString: filePathPtr)
        #if os(Windows)
        // VS Code spells file paths with a lowercase drive letter, while the rest of Windows APIs use an uppercase
        // drive letter. Normalize the drive letter spelling to be uppercase.
        if filePath.first?.isASCII ?? false, filePath.first?.isLetter ?? false, filePath.first?.isLowercase ?? false,
          filePath.count > 1, filePath[filePath.index(filePath.startIndex, offsetBy: 1)] == ":"
        {
          return filePath.first!.uppercased() + filePath.dropFirst()
        }
        #endif
        return filePath
      }
    }
  }

  /// Assuming this URL is a file URL, checks if it looks like a root path. This is a string check, ie. the return
  /// value for a path of `"/foo/.."` would be `false`. An error will be thrown is this is a non-file URL.
  @_spi(SourceKitLSP)
  public var isRoot: Bool {
    get throws {
      let checkPath = try filePath
      #if os(Windows)
      return checkPath.withCString(encodedAs: UTF16.self, PathCchIsRoot)
      #else
      return checkPath == "/"
      #endif
    }
  }

  /// Returns true if the path of `self` starts with the path in `other`.
  @_spi(SourceKitLSP) @inlinable
  public func isDescendant(of other: URL) -> Bool {
    return self.pathComponents.dropLast().starts(with: other.pathComponents)
  }

  /// Assuming this URL is a file URL, returns the modification date of the file.
  ///
  /// For symbolic links, returns the most recent modification date in the symlink chain, which updates when
  /// either the symlink or the target file is modified.
  @_spi(SourceKitLSP)
  public var fileModificationDate: Date {
    get throws {
      var mtime = Date.distantPast
      var visitedURLs: Set<URL> = []
      var url = self
      while true {
        let (fileModTime, symLinkPath) = try url.modificationDateAndSymlinkDestination()
        mtime = max(mtime, fileModTime)

        // Follow the symlink and find the most recent mtime.
        if let symLinkPath {
          url = URL(filePath: symLinkPath, relativeTo: url)
          guard visitedURLs.insert(url).inserted else {
            throw FilePathError.circularSymlink(url)
          }
        } else {
          break
        }
      }
      return mtime
    }
  }

  /// Assuming this URL is a file URL, returns the modification date of the file without following symlinks and, if
  /// the file is a symlink, its destination.
  private func modificationDateAndSymlinkDestination() throws -> (modificationDate: Date, symlinkDestination: String?) {
    #if os(Windows)
    return try modificationDateAndSymlinkDestinationUsingFileManager()
    #else
    guard self.isFileURL else {
      throw FilePathError.noFileURL(self)
    }
    // A single `lstat` is much cheaper than reading all file attributes and trying to read a symlink destination for
    // every file through `FileManager`.
    let result = try self.withUnsafeFileSystemRepresentation { path -> (Date, String?)? in
      guard let path else {
        throw FilePathError.noFileSystemRepresentation(self)
      }
      var fileInfo = stat()
      guard lstat(path, &fileInfo) == 0 else {
        return nil
      }
      #if canImport(Darwin)
      let modificationTime = fileInfo.st_mtimespec
      #else
      let modificationTime = fileInfo.st_mtim
      #endif
      // Same computation as `FileManager` so that the dates are equal to the ones it returns.
      let modificationDate = Date(
        timeIntervalSinceReferenceDate: TimeInterval(modificationTime.tv_sec)
          - Date.timeIntervalBetween1970AndReferenceDate + TimeInterval(modificationTime.tv_nsec) / 1_000_000_000.0
      )
      guard (fileInfo.st_mode & S_IFMT) == S_IFLNK else {
        return (modificationDate, nil)
      }
      // For symlinks, `st_size` is the length of the destination path.
      let bufferSize = Int(fileInfo.st_size) + 1
      let destination = withUnsafeTemporaryAllocation(of: CChar.self, capacity: bufferSize) { buffer -> String? in
        let length = readlink(path, buffer.baseAddress!, bufferSize)
        guard length >= 0, length < bufferSize else {
          return nil
        }
        return String(decoding: UnsafeRawBufferPointer(start: buffer.baseAddress!, count: length), as: UTF8.self)
      }
      guard let destination else {
        return nil
      }
      return (modificationDate, destination)
    }
    if let result {
      return result
    }
    // If the file couldn't be inspected, use `FileManager` so that callers get the same errors as from it.
    return try modificationDateAndSymlinkDestinationUsingFileManager()
    #endif
  }

  private func modificationDateAndSymlinkDestinationUsingFileManager() throws -> (
    modificationDate: Date, symlinkDestination: String?
  ) {
    let path = try self.filePath
    let fileAttrs = try FileManager.default.attributesOfItem(atPath: path)
    guard let fileModTime = fileAttrs[FileAttributeKey.modificationDate] as? Date else {
      throw FilePathError.fileAttributesDontHaveModificationDate(self)
    }
    return (fileModTime, try? FileManager.default.destinationOfSymbolicLink(atPath: path))
  }
}
