# swift-tools-protocols

`swift-tools-protocols` provides basic model types and a transport implementation for the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/) (LSP) and [Build Server Protocol](https://build-server-protocol.github.io) (BSP). 

This package is intended to be a reusable component suitable for adoption by other projects as a semantically versioned dependency. Clients can build on this foundation to implement a client or server for either protocol, like [SourceKit-LSP](https://github.com/swiftlang/sourcekit-lsp) or a BSP which integrates with it. The implementation is optimized for the Swift toolchain's use cases rather than attempting to serve as a canonical implenentation of LSP or BSP in Swift.

## Getting Started

Build the package using `swift build` and run the unit tests using `swift test`.

## Reporting Issues

If you should hit any issues while using the package, we appreciate bug reports on [GitHub Issue](https://github.com/swiftlang/swift-tools-protocols/issues/new/).

## Contributing

If you want to contribute, see [CONTRIBUTING.md](CONTRIBUTING.md) for more information.
