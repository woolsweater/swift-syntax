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

import SwiftBasicFormat
import SwiftParser
import SwiftSyntax
@_spi(Testing) import SwiftSyntaxBuilder
import XCTest
import _SwiftSyntaxTestSupport

fileprivate func assertFormatted<T: SyntaxProtocol>(
  tree: T,
  expected: String,
  using format: ClosureLiteralFormat = ClosureLiteralFormat(indentationWidth: .spaces(4)),
  file: StaticString = #filePath,
  line: UInt = #line
) {
  assertStringsEqualWithDiff(tree.formatted(using: format).description, expected, file: file, line: line)
}

fileprivate func assertFormatted(
  source: String,
  expected: String,
  using format: ClosureLiteralFormat = ClosureLiteralFormat(indentationWidth: .spaces(4)),
  file: StaticString = #filePath,
  line: UInt = #line
) {
  assertFormatted(
    tree: Parser.parse(source: source),
    expected: expected,
    using: format,
    file: file,
    line: line
  )
}

final class ClosureLiteralFormatTests: XCTestCase {
  func testSingleStatementClosureArg() {
    assertFormatted(
      source: """
        foo(bar: { baz in baz.quux })
        """,
      expected: """
        foo(bar: { baz in baz.quux })
        """
    )
  }

  func testSingleStatementClosureArgAlreadyMultiLine() {
    assertFormatted(
      source: """
        foo(
          bar: { baz in
            baz.quux
          }
        )
        """,
      expected: """
        foo(
          bar: { baz in
            baz.quux
          }
        )
        """
    )
  }

  func testMultiStatmentClosureArg() {
    assertFormatted(
      source: """
        foo(
            bar: { baz in print(baz); return baz.quux }
        )
        """,
      expected: """
        foo(
            bar: { baz in
                print(baz);
                return baz.quux
            }
        )
        """
    )
  }

  func testMultiStatementClosureArgAlreadyMultiLine() {
    assertFormatted(
      source: """
        foo(
            bar: { baz in
                print(baz)
                return baz.quux
            }
        )
        """,
      expected: """
        foo(
            bar: { baz in
                print(baz)
                return baz.quux
            }
        )
        """
    )
  }

  func testFormatClosureWithInitialIndentation() throws {
    assertFormatted(
      tree: ClosureExprSyntax(
        statements: CodeBlockItemListSyntax([
          CodeBlockItemSyntax(item: CodeBlockItemSyntax.Item(IntegerLiteralExprSyntax(integerLiteral: 2)))
        ])
      ),
      expected: """
            { 2 }
        """,
      using: ClosureLiteralFormat(initialIndentation: .spaces(4))
    )
  }
}
