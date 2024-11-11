//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#if swift(>=6)
import SwiftBasicFormat
import SwiftParser
@_spi(RawSyntax) public import SwiftSyntax
import SwiftSyntaxBuilder
#else
import SwiftBasicFormat
import SwiftParser
@_spi(RawSyntax) import SwiftSyntax
import SwiftSyntaxBuilder
#endif

/// Expands an editor placeholder, taking into accounts its provided type
/// information (if any).
///
/// Placeholders must start with '<#' and end with
/// '#>'. They can be one of the following formats:
/// ```
///   'T##' display-string '##' type-string ('##' type-for-expansion-string)?
///   'T##' display-and-type-string
///   display-string
/// ```
/// It is required that '##' is not a valid substring of display-string or
/// type-string. If this ends up not the case for some reason, we can consider
/// adding escaping for '##'.
///
/// The type string provided in the placeholder (preferring
/// `type-for-expansion-string`), is parsed into a syntax node. If that node is
/// a `FunctionTypeSyntax` then the placeholder is expanded into a
/// `ClosureExprSyntax`. Otherwise it is expanded as is, which is also the case
/// for when only a display string is provided.
///
/// ## Function Typed Placeholder
/// ### Before
/// ```swift
/// <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>
/// ```
///
/// ### After
/// ```swift
/// <#{ <#someInt#> in <#T##String#> }#>
/// ```
///
/// ## Other Type Placeholder
/// ### Before
/// ```swift
/// <#T##Int#>
/// ```
///
/// ### After
/// ```swift
/// Int
/// ```
///
/// ## No Type Placeholder
/// ### Before
/// ```swift
/// <#anything here#>
/// ```
///
/// ## After
/// ```swift
/// anything here
/// ```
struct ExpandSingleEditorPlaceholder: EditRefactoringProvider {
  struct Context {
    let indentationWidth: Trivia?
    let initialIndentation: Trivia

    init(indentationWidth: Trivia? = nil, initialIndentation: Trivia = []) {
      self.indentationWidth = indentationWidth
      self.initialIndentation = initialIndentation
    }
  }

  static func textRefactor(syntax token: TokenSyntax, in context: Context = Context()) -> [SourceEdit] {
    guard let placeholder = EditorPlaceholderExpansionData(token: token) else {
      return []
    }

    let expanded: String
    if let functionType = placeholder.typeForExpansion?.as(FunctionTypeSyntax.self) {
      let format = ClosureLiteralFormat(
        indentationWidth: context.indentationWidth,
        initialIndentation: context.initialIndentation
      )
      var formattedExpansion = functionType.closureExpansion.formatted(using: format).description
      // Strip the initial indentation from the placeholder itself. We only introduced the initial indentation to
      // format consecutive lines. We don't want it at the front of the initial line because it replaces an expression
      // that might be in the middle of a line.
      if formattedExpansion.hasPrefix(context.initialIndentation.description) {
        formattedExpansion = String(formattedExpansion.dropFirst(context.initialIndentation.description.count))
      }
      expanded = wrapInPlaceholder(formattedExpansion)
    } else {
      expanded = placeholder.displayText
    }

    return [
      SourceEdit.replace(token, with: token.leadingTrivia.description + expanded + token.trailingTrivia.description)
    ]
  }
}

/// If a function-typed placeholder is the argument to a non-trailing closure
/// call, expands it and any adjacent function-typed placeholders to literal
/// closures with inner placeholders on that call. All other placeholders will
/// expand as per `ExpandEditorPlaceholder`.
///
/// ## Before
/// ```swift
/// foo(
///   closure1: <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>,
///   normalArg: <#T##Int#>,
///   closure2: { ... },
///   closure3: <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>,
///   closure4: <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>
/// )
/// ```
///
/// ## `closure3` or `closure4` Expansion
/// ```swift
/// foo(
///   closure1: <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>,
///   normalArg: <#T##Int#>,
///   closure2: { ... },
///   closure3: { <#someInt#> in <#T##String#> },
///   closure4: { <#someInt#> in <#T##String#> }
/// )
/// ```
///
/// Expansion on `closure1` and `normalArg` is the same as `ExpandSingleEditorPlaceholder`.
public struct ExpandEditorPlaceholder: EditRefactoringProvider {
  public struct Context {
    public let indentationWidth: Trivia?

    public init(indentationWidth: Trivia? = nil) {
      self.indentationWidth = indentationWidth
    }
  }

  public static func textRefactor(syntax token: TokenSyntax, in context: Context = Context()) -> [SourceEdit] {
    guard let placeholder = token.parent?.as(DeclReferenceExprSyntax.self),
      placeholder.baseName.isEditorPlaceholder,
      let arg = placeholder.parent?.as(LabeledExprSyntax.self),
      let argList = arg.parent?.as(LabeledExprListSyntax.self),
      let call = argList.parent?.as(FunctionCallExprSyntax.self),
      let expandedClosures = ExpandEditorPlaceholdersToLiteralClosures.expandClosurePlaceholders(
        in: call,
        ifIncluded: arg,
        indentationWidth: context.indentationWidth
      )
    else {
      return ExpandSingleEditorPlaceholder.textRefactor(syntax: token)
    }

    return [SourceEdit.replace(call, with: expandedClosures.description)]
  }
}

/// Expand all the editor placeholders in the function call to literal closures.
///
/// ## Before
/// ```swift
/// foo(
///   arg: <#T##Int#>,
///   firstClosure: <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>,
///   secondClosure: <#T##(Int) -> String##(Int) -> String##(_ someInt: Int) -> String#>
/// )
/// ```
///
/// ## Expansion of `foo`
/// ```swift
/// foo(
///   arg: <#T##Int#>,
///   firstClosure: { <#someInt#> in <#T##String#> },
///   secondClosure: { <#someInt#> in <#T##String#> }
/// )
/// ```
public struct ExpandEditorPlaceholdersToLiteralClosures: SyntaxRefactoringProvider {
  public struct Context {
    public let indentationWidth: Trivia?

    public init(indentationWidth: Trivia? = nil) {
      self.indentationWidth = indentationWidth
    }
  }

  public static func refactor(
    syntax call: FunctionCallExprSyntax,
    in context: Context = Context()
  ) -> FunctionCallExprSyntax? {
    return Self.expandClosurePlaceholders(in: call, ifIncluded: nil, indentationWidth: context.indentationWidth
    )
  }

  /// If the given argument is `nil` or one of the last arguments that are all
  /// function-typed placeholders and this call doesn't have a trailing
  /// closure, then return a replacement of this call with one that uses
  /// closures based on the function types provided by each editor placeholder.
  /// Otherwise return nil.
  fileprivate static func expandClosurePlaceholders(
    in call: FunctionCallExprSyntax,
    ifIncluded arg: LabeledExprSyntax?,
    indentationWidth: Trivia?
  ) -> FunctionCallExprSyntax? {
    return call.expandClosurePlaceholders(ifIncluded: arg, indentationWidth: indentationWidth)
  }
}

extension FunctionTypeSyntax {
  /// Return a closure expression for this function type, eg.
  /// ```
  ///   (_ someInt: Int) -> String
  /// ```
  /// would become
  /// ```
  /// { <#someInt#> in <#T##String#> }
  /// ```
  fileprivate var closureExpansion: ClosureExprSyntax {
    let closureSignature: ClosureSignatureSyntax?
    if !parameters.isEmpty {
      let args = ClosureShorthandParameterListSyntax {
        for arg in parameters {
          ClosureShorthandParameterSyntax(name: arg.expansionNameToken())
        }
      }
      closureSignature = ClosureSignatureSyntax(parameterClause: .simpleInput(args))
    } else {
      closureSignature = nil
    }

    // Single statement for the body - the placeholder-ed type if non-void and
    // 'code' otherwise.
    let ret = returnClause.type.description
    let placeholder: String
    if ret == "Void" || ret == "()" {
      placeholder = wrapInTypePlaceholder("code", type: "Void")
    } else {
      placeholder = wrapInTypePlaceholder(ret, type: ret)
    }

    let statementPlaceholder = DeclReferenceExprSyntax(
      baseName: .identifier(placeholder)
    )
    let closureStatement = CodeBlockItemSyntax(
      item: .expr(ExprSyntax(statementPlaceholder))
    )

    return ClosureExprSyntax(
      leftBrace: .leftBraceToken(),
      signature: closureSignature,
      statements: CodeBlockItemListSyntax([closureStatement]),
      rightBrace: .rightBraceToken()
    )
  }
}

extension TupleTypeElementSyntax {
  /// Return a token to use as the parameter name in the expanded closure.
  /// We prefer the argument name if there is one and it isn't a wildcard,
  /// falling back to the label with the same conditions, and finally just the
  /// placeholder-ed type otherwise.
  fileprivate func expansionNameToken() -> TokenSyntax {
    if let secondName = secondName, secondName.tokenKind != .wildcard {
      return secondName
    }

    if let firstName, firstName.tokenKind != .wildcard {
      return firstName
    }

    return .identifier(wrapInPlaceholder(type.description))
  }
}

extension FunctionCallExprSyntax {
  /// If the given argument is `nil` or one of the last arguments that are all
  /// function-typed placeholders and this call doesn't have a trailing
  /// closure, then return a replacement of this call with one that uses
  /// closures based on the function types provided by each editor placeholder.
  /// Otherwise return nil.
  fileprivate func expandClosurePlaceholders(
    ifIncluded: LabeledExprSyntax?,
    indentationWidth: Trivia?
  ) -> FunctionCallExprSyntax? {
    var includedArg = false
    var argsToExpand = 0
    for arg in arguments.reversed() {
      guard let expr = arg.expression.as(DeclReferenceExprSyntax.self),
        expr.baseName.isEditorPlaceholder,
        let data = EditorPlaceholderExpansionData(token: expr.baseName),
        let type = data.typeForExpansion,
        type.is(FunctionTypeSyntax.self)
      else {
        break
      }
      if arg == ifIncluded {
        includedArg = true
      }
      argsToExpand += 1
    }

    guard includedArg || ifIncluded == nil else {
      return nil
    }

    let lineIndentation = self.firstToken(viewMode: .sourceAccurate)?.indentationOfLine ?? []

    var expandedArgs = [LabeledExprSyntax]()
    for arg in arguments.suffix(argsToExpand) {
      let edits = ExpandSingleEditorPlaceholder.textRefactor(
        syntax: arg.expression.cast(DeclReferenceExprSyntax.self).baseName,
        in: ExpandSingleEditorPlaceholder.Context(
          indentationWidth: indentationWidth,
          initialIndentation: lineIndentation
        )
      )
      guard edits.count == 1, let edit = edits.first, !edit.replacement.isEmpty else {
        return nil
      }

      var parser = Parser(edit.replacement)
      let expr = ExprSyntax.parse(from: &parser)
      expandedArgs.append(
        arg.detached.with(\.expression, expr)
      )
    }

    let originalArgs = arguments.dropLast(argsToExpand)
    return detached.with(\.arguments, LabeledExprListSyntax(originalArgs + expandedArgs))
  }
}

private struct EditorPlaceholderExpansionData {
  let displayText: String
  let typeForExpansion: TypeSyntax?

  init?(token: TokenSyntax) {
    guard let rawData = token.rawEditorPlaceHolderData else {
      return nil
    }

    if let typeText = rawData.typeForExpansionText, !typeText.isEmpty {
      self.displayText = String(syntaxText: typeText)
      var parser = Parser(UnsafeBufferPointer(start: typeText.baseAddress, count: typeText.count))
      let type: TypeSyntax = TypeSyntax.parse(from: &parser)
      self.typeForExpansion = type.hasError ? nil : type
    } else {
      self.displayText = String(syntaxText: rawData.displayText)
      self.typeForExpansion = nil
    }
  }
}

@_spi(Testing)
public func wrapInPlaceholder(_ str: String) -> String {
  return placeholderStart + str + placeholderEnd
}

@_spi(Testing)
public func wrapInTypePlaceholder(_ str: String, type: String) -> String {
  return wrapInPlaceholder("T##" + str + "##" + type)
}

fileprivate let placeholderStart: String = "<#"
fileprivate let placeholderEnd: String = "#>"
