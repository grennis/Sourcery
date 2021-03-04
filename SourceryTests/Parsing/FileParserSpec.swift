import Quick
import Nimble
import PathKit
@testable import Sourcery
@testable import SourceryFramework
@testable import SourceryRuntime

class FileParserSpec: QuickSpec {
    // swiftlint:disable function_body_length
    override func spec() {
        describe("Parser") {
            describe("parse") {
                func parse(_ code: String) -> [Type] {
                    guard let parserResult = try? makeParser(for: code).parse() else { fail(); return [] }
                    return Composer.uniqueTypesAndFunctions(parserResult).types
                }

                describe("regression files") {
                    it("doesnt crash on localized strings") {
                        let templatePath = Stubs.errorsDirectory + Path("localized-error.swift")
                        guard let content = try? templatePath.read(.utf8) else { return fail() }

                        _ = parse(content)
                    }
                }

                context("given it has sourcery annotations") {
                    it("extract annotations from extensions properly") {
                        let result = parse(
                            """
                            // sourcery: forceMockPublisher
                            public extension AnyPublisher {}
                            """
                        )

                        let annotations: [String: NSObject] = [
                                "forceMockPublisher": NSNumber(value: true)
                        ]

                        expect(result.first?.annotations).to(equal(
                            annotations
                        ))
                    }

                    it("extracts annotation block") {
                        let annotations = [
                                ["skipEquality": NSNumber(value: true)],
                                ["skipEquality": NSNumber(value: true), "extraAnnotation": NSNumber(value: Float(2))],
                                [:]
                        ]
                        let expectedVariables = (1...3)
                                .map { Variable(name: "property\($0)", typeName: TypeName("Int"), annotations: annotations[$0 - 1], definedInTypeName: TypeName("Foo")) }
                        let expectedType = Class(name: "Foo", variables: expectedVariables, annotations: ["skipEquality": NSNumber(value: true)])

                        let result = parse("""
                                            // sourcery:begin: skipEquality
                                            class Foo {
                                                var property1: Int
                                                // sourcery: extraAnnotation = 2
                                                var property2: Int
                                                // sourcery:end
                                                var property3: Int
                                            }
                                           """)
                        expect(result).to(equal([expectedType]))
                    }

                    it("extracts file annotation block") {
                        let annotations: [[String: NSObject]] = [
                            ["fileAnnotation": NSNumber(value: true), "skipEquality": NSNumber(value: true)],
                            ["fileAnnotation": NSNumber(value: true), "skipEquality": NSNumber(value: true), "extraAnnotation": NSNumber(value: Float(2))],
                            ["fileAnnotation": NSNumber(value: true)]
                        ]
                        let expectedVariables = (1...3)
                            .map { Variable(name: "property\($0)", typeName: TypeName("Int"), annotations: annotations[$0 - 1], definedInTypeName: TypeName("Foo")) }
                        let expectedType = Class(name: "Foo", variables: expectedVariables, annotations: ["fileAnnotation": NSNumber(value: true), "skipEquality": NSNumber(value: true)])

                        let result = parse("// sourcery:file: fileAnnotation\n" +
                            "// sourcery:begin: skipEquality\n\n\n\n" +
                            "class Foo {\n" +
                            "  var property1: Int\n\n\n" +
                            " // sourcery: extraAnnotation = 2\n" +
                            "  var property2: Int\n\n" +
                            "  // sourcery:end\n" +
                            "  var property3: Int\n" +
                            "}")
                        expect(result.first).to(equal(expectedType))
                    }
                }

                context("given struct") {

                    it("extracts properly") {
                        expect(parse("struct Foo { }"))
                                .to(equal([
                                        Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [])
                                ]))
                    }

                    it("extracts import correctly") {
                        let expectedStruct = Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [])
                        expectedStruct.imports = [
                            Import(path: "SimpleModule"),
                            Import(path: "SpecificModule.ClassName")
                        ]

                        expect(parse("""
                                     import SimpleModule
                                     import SpecificModule.ClassName
                                     struct Foo {}
                                     """).first)
                                .to(equal(expectedStruct))
                    }

                    it("extracts properly with access information") {
                        expect(parse("public struct Foo { }"))
                          .to(equal([
                                        Struct(name: "Foo", accessLevel: .public, isExtension: false, variables: [], modifiers: [Modifier(name: "public")])
                                    ]))
                    }

                    it("extracts properly with access information for extended types via extension") {
                        let foo = Struct(name: "Foo", accessLevel: .public, isExtension: false, variables: [], modifiers: [Modifier(name: "public")])

                        expect(parse(
                                """
                                public struct Foo { }
                                public extension Foo {
                                    struct Boo {}
                                }
                                """
                        ).last)
                          .to(equal(
                            Struct(name: "Boo", parent: foo, accessLevel: .public, isExtension: false, variables: [], modifiers: [])
                       ))
                    }

                    it("extracts properly with access information for extended methods/variables via extension") {
                        let foo = Struct(name: "Foo", accessLevel: .public, isExtension: false, variables: [.init(name: "boo", typeName: .Int, accessLevel: (.public, .none), isComputed: true, definedInTypeName: TypeName("Foo"))], methods: [.init(name: "foo()", selectorName: "foo", accessLevel: .public, definedInTypeName: TypeName("Foo"))], modifiers: [.init(name: "public")])

                        expect(parse(
                                """
                                public struct Foo { }
                                public extension Foo {
                                    func foo() { }
                                    var boo: Int { 0 }
                                }
                                """
                        ).last)
                          .to(equal(
                            foo
                       ))
                    }

                    it("extracts generic struct properly") {
                        expect(parse("struct Foo<Something> { }"))
                                .to(equal([
                                    Struct(name: "Foo", isGeneric: true)
                                          ]))
                    }

                    it("extracts instance variables properly") {
                        expect(parse("struct Foo { var x: Int }"))
                                .to(equal([
                                    Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [Variable(name: "x", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .internal), isComputed: false, definedInTypeName: TypeName("Foo"))])
                                          ]))
                    }

                    it("extracts instance variables with custom accessors properly") {
                        expect(parse("struct Foo { public private(set) var x: Int }"))
                          .to(equal([
                                        Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [
                                                Variable(
                                                    name: "x",
                                                    typeName: TypeName("Int"),
                                                    accessLevel: (read: .public, write: .private),
                                                    isComputed: false,
                                                    modifiers: [
                                                        Modifier(name: "public"),
                                                        Modifier(name: "private", detail: "set")
                                                    ],
                                                    definedInTypeName: TypeName("Foo"))
                                        ])
                                    ]))
                    }

                    it("extracts multi-line instance variables definitions properly") {
                        let defaultValue =
                            """
                            [
                                "This isn't the simplest to parse",
                                // Especially with interleaved comments
                                "but we can deal with it",
                                // pretty well
                                "or so we hope"
                            ]
                            """

                        expect(parse(
                            """
                                struct Foo {
                                    var complicatedArray = \(defaultValue)
                                }
                                """
                        ))
                        .to(equal([
                            Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [
                                    Variable(
                                        name: "complicatedArray",
                                        typeName: TypeName(
                                            "[String]",
                                            array: ArrayType(name: "[String]",
                                                             elementTypeName: TypeName("String")
                                            ),
                                            generic: GenericType(name: "Array", typeParameters: [.init(typeName: TypeName("String"))])
                                        ),
                                        accessLevel: (read: .internal, write: .internal),
                                        isComputed: false,
                                        defaultValue: defaultValue,
                                        definedInTypeName: TypeName("Foo")
                                    )])
                        ]))
                    }

                    it("extracts instance variables with property setters properly") {
                        expect(parse(
                                """
                                struct Foo {
                                var array = [Int]() {
                                    willSet {
                                        print("new value \\(newValue)")
                                    }
                                }

                                }
                                """
                        ))
                        .to(equal([
                            Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [
                                    Variable(
                                        name: "array",
                                        typeName: TypeName(
                                            "[Int]",
                                            array: ArrayType(name: "[Int]",
                                                             elementTypeName: TypeName("Int")
                                            ),
                                            generic: GenericType(name: "Array", typeParameters: [.init(typeName: TypeName("Int"))])
                                        ),
                                        accessLevel: (read: .internal, write: .internal),
                                        isComputed: false,
                                        defaultValue: "[Int]()",
                                        definedInTypeName: TypeName("Foo")
                                    )])
                        ]))
                    }

                    it("extracts computed variables properly") {
                        expect(parse("struct Foo { var x: Int { return 2 } }"))
                          .to(equal([
                                        Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [
                                            Variable(name: "x", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true, isStatic: false, definedInTypeName: TypeName("Foo"))
                                        ])
                                    ]))
                    }

                    it("extracts class variables properly") {
                        expect(parse("struct Foo { static var x: Int { return 2 }; class var y: Int = 0 }"))
                                .to(equal([
                                    Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [
                                        Variable(name: "x",
                                                 typeName: TypeName("Int"),
                                                 accessLevel: (read: .internal, write: .none),
                                                 isComputed: true,
                                                 isStatic: true,
                                                 modifiers: [
                                                    Modifier(name: "static")
                                                 ],
                                                 definedInTypeName: TypeName("Foo")),
                                        Variable(name: "y",
                                                 typeName: TypeName("Int"),
                                                 accessLevel: (read: .internal, write: .internal),
                                                 isComputed: false,
                                                 isStatic: true,
                                                 defaultValue: "0",
                                                 modifiers: [
                                                    Modifier(name: "class")
                                                 ],
                                                 definedInTypeName: TypeName("Foo"))
                                        ])
                                    ]))
                    }

                    context("given nested struct") {
                        it("extracts properly from body") {
                            let innerType = Struct(name: "Bar", accessLevel: .internal, isExtension: false, variables: [])

                            expect(parse("struct Foo { struct Bar { } }"))
                                    .to(equal([
                                            Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], containedTypes: [innerType]),
                                            innerType
                                    ]))
                        }

                        it("extracts properly from extension") {
                            let innerType = Struct(name: "Bar", accessLevel: .internal, isExtension: false, variables: [])

                            expect(parse("struct Foo {}  extension Foo { struct Bar { } }"))
                                .to(equal([
                                    Struct(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], containedTypes: [innerType]),
                                    innerType
                                    ]))
                        }
                    }
                }

                context("given class") {

                    it("extracts variables properly") {
                        expect(parse("class Foo { var x: Int }"))
                          .to(equal([
                                        Class(name: "Foo", accessLevel: .internal, isExtension: false, variables: [Variable(name: "x", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .internal), isComputed: false, definedInTypeName: TypeName("Foo"))])
                                    ]))
                    }

                    it("extracts variables properly from extensions") {
                        expect(parse("class Foo { }; extension Foo { var x: Int { 1 }"))
                                .to(equal([
                                        Class(name: "Foo", accessLevel: .internal, isExtension: false, variables: [Variable(name: "x", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true, definedInTypeName: TypeName("Foo"))])
                                ]))
                    }

                    it("extracts inherited types properly") {
                        expect(parse("class Foo: TestProtocol, AnotherProtocol {}"))
                          .to(equal([
                                        Class(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["TestProtocol", "AnotherProtocol"])
                                    ]))
                    }

                    it("extracts inherited types properly from extensions") {
                        expect(parse("class Foo: TestProtocol { }; extension Foo: AnotherProtocol {}"))
                                .to(equal([
                                        Class(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["TestProtocol", "AnotherProtocol"])
                                ]))
                    }

                    it("extracts annotations correctly") {
                        let expectedType = Class(name: "Foo", accessLevel: .internal, isExtension: false, variables: [], inheritedTypes: ["TestProtocol"])
                        expectedType.annotations["firstLine"] = NSNumber(value: true)
                        expectedType.annotations["thirdLine"] = NSNumber(value: 4543)

                        expect(parse("// sourcery: thirdLine = 4543\n/// comment\n// sourcery: firstLine\nclass Foo: TestProtocol { }"))
                                .to(equal([expectedType]))
                    }
                }

                context("given unknown type") {
                    it("extracts extensions properly") {
                        expect(parse("protocol Foo { }; extension Bar: Foo { var x: Int { return 0 } }"))
                            .to(equal([
                                Type(name: "Bar", accessLevel: .internal, isExtension: true, variables: [Variable(name: "x", typeName: TypeName("Int"), accessLevel: (read: .internal, write: .none), isComputed: true, definedInTypeName: TypeName("Bar"))], inheritedTypes: ["Foo"]).asUnknownException(),
                                Protocol(name: "Foo")
                                ]))
                    }
                }

                context("given typealias") {
                    func parse(_ code: String) -> FileParserResult {
                        guard let parserResult = try? makeParser(for: code).parse() else { fail(); return FileParserResult(path: nil, module: nil, types: [], functions: [], typealiases: []) }
                        return parserResult
                    }

                    context("given global typealias") {
                        it("extracts global typealiases properly") {
                            expect(parse("typealias GlobalAlias = Foo; class Foo { typealias FooAlias = Int; class Bar { typealias BarAlias = Int } }").typealiases)
                                .to(equal([
                                    Typealias(aliasName: "GlobalAlias", typeName: TypeName("Foo"))
                                    ]))
                        }

                        it("extracts typealiases for inner types") {
                            expect(parse("typealias GlobalAlias = Foo.Bar;").typealiases)
                                .to(equal([
                                    Typealias(aliasName: "GlobalAlias", typeName: TypeName("Foo.Bar"))
                                    ]))
                        }

                        it("extracts typealiases of other typealiases") {
                            expect(parse("typealias Foo = Int; typealias Bar = Foo").typealiases)
                                .to(contain([
                                    Typealias(aliasName: "Foo", typeName: TypeName("Int")),
                                    Typealias(aliasName: "Bar", typeName: TypeName("Foo"))
                                    ]))
                        }

                        it("extracts typealias for tuple") {
                            let typealiase = parse("typealias GlobalAlias = (Foo, Bar)").typealiases.first
                            expect(typealiase)
                              .to(equal(
                                Typealias(aliasName: "GlobalAlias",
                                          typeName: TypeName("(Foo, Bar)", tuple: TupleType(name: "(Foo, Bar)", elements: [.init(name: "0", typeName: .init("Foo")), .init(name: "1", typeName: .init("Bar"))]))
                                )
                              ))
                        }

                        it("extracts typealias for closure") {
                            expect(parse("typealias GlobalAlias = (Int) -> (String)").typealiases)
                                .to(equal([
                                        Typealias(aliasName: "GlobalAlias", typeName: TypeName("(Int) -> String", closure: ClosureType(name: "(Int) -> String", parameters: [.init(typeName: TypeName("Int"))], returnTypeName: TypeName("String"))))
                                    ]))
                        }

                        it("extracts typealias for void closure") {
                            let parsed = parse("typealias GlobalAlias = () -> ()").typealiases.first
                            let expected = Typealias(aliasName: "GlobalAlias", typeName: TypeName("() -> ()", closure: ClosureType(name: "() -> ()", parameters: [], returnTypeName: TypeName("()"))))

                            expect(parsed).to(equal(expected))
                        }

                        it("extracts private typealias") {
                            expect(parse("private typealias GlobalAlias = () -> ()").typealiases)
                                .to(equal([
                                    Typealias(aliasName: "GlobalAlias", typeName: TypeName("() -> ()", closure: ClosureType(name: "() -> ()", parameters: [], returnTypeName: TypeName("()"))), accessLevel: .private)
                                    ]))
                        }
                    }

                    context("given local typealias") {
                        it ("extracts local typealiases properly") {
                            let foo = Type(name: "Foo")
                            let bar = Type(name: "Bar", parent: foo)
                            let fooBar = Type(name: "FooBar", parent: bar)

                            let types = parse("class Foo { typealias FooAlias = String; struct Bar { typealias BarAlias = Int; struct FooBar { typealias FooBarAlias = Float } } }").types

                            let fooAliases = types.first?.typealiases
                            let barAliases = types.first?.containedTypes.first?.typealiases
                            let fooBarAliases = types.first?.containedTypes.first?.containedTypes.first?.typealiases

                            expect(fooAliases).to(equal(["FooAlias": Typealias(aliasName: "FooAlias", typeName: TypeName("String"), parent: foo)]))
                            expect(barAliases).to(equal(["BarAlias": Typealias(aliasName: "BarAlias", typeName: TypeName("Int"), parent: bar)]))
                            expect(fooBarAliases).to(equal(["FooBarAlias": Typealias(aliasName: "FooBarAlias", typeName: TypeName("Float"), parent: fooBar)]))
                        }
                    }

                }

                context("given a protocol composition") {

                    context("when used as typeName") {
                        it("is extracted correctly as return type") {
                            let expectedFoo = Method(name: "foo()", selectorName: "foo", returnTypeName: TypeName(name: "ProtocolA & ProtocolB", isProtocolComposition: true), definedInTypeName: TypeName("Foo"))
                            expectedFoo.returnType = ProtocolComposition(name: "ProtocolA & Protocol B")
                            let expectedFooOptional = Method(name: "fooOptional()", selectorName: "fooOptional", returnTypeName: TypeName(name: "(ProtocolA & ProtocolB)", isOptional: true, isProtocolComposition: true), definedInTypeName: TypeName("Foo"))
                            expectedFooOptional.returnType = ProtocolComposition(name: "ProtocolA & Protocol B")

                            let methods = parse("""
                                                protocol Foo {
                                                  func foo() -> ProtocolA & ProtocolB
                                                  func fooOptional() -> (ProtocolA & ProtocolB)?
                                                }
                                                """)[0].methods

                            expect(methods[0]).to(equal(expectedFoo))
                            expect(methods[1]).to(equal(expectedFooOptional))
                        }
                    }

                    context("of two protocols") {
                        it("extracts protocol composition for typealias with ampersand") {
                            expect(parse("typealias Composition = Foo & Bar; protocol Foo {}; protocol Bar {}"))
                                .to(contain([
                                    ProtocolComposition(name: "Composition", inheritedTypes: ["Foo", "Bar"], composedTypeNames: [TypeName("Foo"), TypeName("Bar")])
                                    ]))

                            expect(parse("private typealias Composition = Foo & Bar; protocol Foo {}; protocol Bar {}"))
                                .to(contain([
                                    ProtocolComposition(name: "Composition", accessLevel: .private, inheritedTypes: ["Foo", "Bar"], composedTypeNames: [TypeName("Foo"), TypeName("Bar")])
                                    ]))
                        }
                    }

                    context("of three protocols") {
                        it("extracts protocol composition for typealias with ampersand") {
                            expect(parse("typealias Composition = Foo & Bar & Baz; protocol Foo {}; protocol Bar {}; protocol Baz {}"))
                                .to(contain([
                                    ProtocolComposition(name: "Composition", inheritedTypes: ["Foo", "Bar", "Baz"], composedTypeNames: [TypeName("Foo"), TypeName("Bar"), TypeName("Baz")])
                                    ]))
                        }

                        it("extracts protocol composition for typealias with ampersand") {
                            expect(parse("typealias Composition = Foo & Bar & Baz; protocol Foo {}; protocol Bar {}; protocol Baz {}"))
                              .to(contain([
                                              ProtocolComposition(name: "Composition", inheritedTypes: ["Foo", "Bar", "Baz"], composedTypeNames: [TypeName("Foo"), TypeName("Bar"), TypeName("Baz")])
                                          ]))
                        }
                    }

                    context("of a protocol and a class") {
                        it("extracts protocol composition for typealias with ampersand") {
                            expect(parse("typealias Composition = Foo & Bar; protocol Foo {}; class Bar {}"))
                                .to(contain([
                                    ProtocolComposition(name: "Composition", inheritedTypes: ["Foo", "Bar"], composedTypeNames: [TypeName("Foo"), TypeName("Bar")])
                                    ]))
                        }
                    }

                    context("given local protocol composition") {
                        it("extracts local protocol compositions properly") {
                            let foo = Type(name: "Foo")
                            let bar = Type(name: "Bar", parent: foo)

                            let types = parse("protocol P {}; class Foo { typealias FooComposition = Bar & P; class Bar { typealias BarComposition = FooBar & P; class FooBar {} } }")

                            let fooComposition = types.first?.containedTypes.first
                            let barComposition = types.first?.containedTypes.last?.containedTypes.first

                            expect(fooComposition).to(equal(
                                ProtocolComposition(name: "FooComposition", parent: foo, inheritedTypes: ["Bar", "P"], composedTypeNames: [TypeName("Bar"), TypeName("P")])))
                            expect(barComposition).to(equal(
                                ProtocolComposition(name: "BarComposition", parent: bar, inheritedTypes: ["FooBar", "P"], composedTypeNames: [TypeName("FooBar"), TypeName("P")])))
                        }
                    }
                }

                context("given enum") {

                    it("extracts empty enum properly") {
                        expect(parse("enum Foo { }"))
                                .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [])
                                ]))
                    }

                    it("extracts cases properly") {
                        expect(parse("enum Foo { case optionA; case optionB }"))
                                .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [EnumCase(name: "optionA"), EnumCase(name: "optionB")])
                                ]))
                    }

                    it("extracts cases with special names") {
                        expect(parse("""
                                     enum Foo {
                                       case `default`
                                       case `for`(something: Int, else: Float, `default`: Bool)
                                     }
                                     """))
                          .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [
                                            EnumCase(name: "`default`"),
                                            EnumCase(name: "`for`", associatedValues:
                                            [
                                                AssociatedValue(name: "something", typeName: TypeName("Int")),
                                                AssociatedValue(name: "else", typeName: TypeName("Float")),
                                                AssociatedValue(name: "`default`", typeName: TypeName("Bool"))
                                            ])])
                                    ]))
                    }

                    it("extracts multi-byte cases properly") {
                        expect(parse("enum JapaneseEnum {\ncase アイウエオ\n}"))
                            .to(equal([
                                Enum(name: "JapaneseEnum", cases: [EnumCase(name: "アイウエオ")])
                                ]))
                    }

                    context("given enum cases annotations") {

                        it("extracts cases with annotations properly") {
                            expect(parse("""
                                         enum Foo {
                                             // sourcery:begin: block
                                             // sourcery: first, second=\"value\"
                                             case optionA(/* sourcery: first, second = \"value\" */Int)
                                             // sourcery: third
                                             case optionB
                                             case optionC
                                             // sourcery:end
                                         }
                                         """))
                                .to(equal([
                                    Enum(name: "Foo", cases: [
                                        EnumCase(name: "optionA", associatedValues: [
                                            AssociatedValue(name: nil, typeName: TypeName("Int"), annotations: [
                                                "first": NSNumber(value: true),
                                                "second": "value" as NSString,
                                                "block": NSNumber(value: true)
                                                ])
                                            ], annotations: [
                                                "block": NSNumber(value: true),
                                                "first": NSNumber(value: true),
                                                "second": "value" as NSString
                                            ]
                                        ),
                                        EnumCase(name: "optionB", annotations: [
                                            "block": NSNumber(value: true),
                                            "third": NSNumber(value: true)
                                            ]
                                        ),
                                        EnumCase(name: "optionC", annotations: [
                                            "block": NSNumber(value: true)
                                            ])
                                        ])
                                    ]))
                        }

                        it("extracts cases with inline annotations properly") {
                            expect(parse("""
                                         enum Foo {
                                          //sourcery:begin: block
                                         /* sourcery: first, second = \"value\" */ case optionA(/* sourcery: first, second = \"value\" */Int);
                                         /* sourcery: third */ case optionB
                                          case optionC
                                         //sourcery:end
                                         }
                                         """).first)
                                .to(equal(
                                    Enum(name: "Foo", cases: [
                                        EnumCase(name: "optionA", associatedValues: [
                                            AssociatedValue(name: nil, typeName: TypeName("Int"), annotations: [
                                                "first": NSNumber(value: true),
                                                "second": "value" as NSString,
                                                "block": NSNumber(value: true)
                                                ])
                                            ], annotations: [
                                                "block": NSNumber(value: true),
                                                "first": NSNumber(value: true),
                                                "second": "value" as NSString
                                            ]),
                                        EnumCase(name: "optionB", annotations: [
                                            "block": NSNumber(value: true),
                                            "third": NSNumber(value: true)
                                            ]),
                                        EnumCase(name: "optionC", annotations: [
                                            "block": NSNumber(value: true)
                                            ])
                                        ])
                                    ))
                        }

                        it("extracts one line cases with inline annotations properly") {
                            expect(parse("""
                                         enum Foo {
                                          //sourcery:begin: block
                                         case /* sourcery: first, second = \"value\" */ optionA(Int), /* sourcery: third, fourth = \"value\" */ optionB, optionC
                                         //sourcery:end
                                         }
                                         """).first)
                                .to(equal(
                                    Enum(name: "Foo", cases: [
                                        EnumCase(name: "optionA", associatedValues: [
                                            AssociatedValue(name: nil, typeName: TypeName("Int"), annotations: [
                                                "block": NSNumber(value: true)
                                            ])
                                            ], annotations: [
                                                "block": NSNumber(value: true),
                                                "first": NSNumber(value: true),
                                                "second": "value" as NSString
                                            ]),
                                        EnumCase(name: "optionB", annotations: [
                                            "block": NSNumber(value: true),
                                            "third": NSNumber(value: true),
                                            "fourth": "value" as NSString
                                            ]),
                                        EnumCase(name: "optionC", annotations: [
                                            "block": NSNumber(value: true)
                                            ])
                                        ])
                                    ))
                        }

                        it("extracts cases with annotations and computed variables properly") {
                            expect(parse("""
                                         enum Foo {
                                          // sourcery: var
                                          var first: Int { return 0 }
                                          // sourcery: first, second=\"value\"
                                          case optionA(Int)
                                          // sourcery: var
                                          var second: Int { return 0 }
                                          // sourcery: third
                                          case optionB
                                          case optionC }
                                         """).first)
                                .to(equal(
                                    Enum(name: "Foo", cases: [
                                        EnumCase(name: "optionA", associatedValues: [
                                            AssociatedValue(name: nil, typeName: TypeName("Int"))
                                            ], annotations: [
                                                "first": NSNumber(value: true),
                                                "second": "value" as NSString
                                            ]),
                                        EnumCase(name: "optionB", annotations: [
                                            "third": NSNumber(value: true)
                                            ]),
                                        EnumCase(name: "optionC")
                                        ], variables: [
                                            Variable(name: "first", typeName: TypeName("Int"), accessLevel: (.internal, .none), isComputed: true, annotations: [ "var": NSNumber(value: true) ], definedInTypeName: TypeName("Foo")),
                                            Variable(name: "second", typeName: TypeName("Int"), accessLevel: (.internal, .none), isComputed: true, annotations: [ "var": NSNumber(value: true) ], definedInTypeName: TypeName("Foo"))
                                        ])
                                    ))
                        }
                    }

                    it("extracts associated value annotations properly") {
                        let result = parse("""
                                           enum Foo {
                                               case optionA(
                                                 // sourcery: first
                                                 // sourcery: second, third = "value"
                                                 Int)
                                               case optionB
                                           }
                                           """)
                        expect(result)
                            .to(equal([
                                Enum(name: "Foo",
                                     cases: [
                                        EnumCase(name: "optionA", associatedValues: [
                                            AssociatedValue(name: nil, typeName: TypeName("Int"), annotations: ["first": NSNumber(value: true), "second": NSNumber(value: true), "third": "value" as NSString])
                                            ]),
                                        EnumCase(name: "optionB")
                                    ])
                                ]))
                    }

                    it("extracts associated value inline annotations properly") {
                        let result = parse("enum Foo {\n case optionA(/* sourcery: annotation*/Int)\n case optionB }")
                        expect(result)
                            .to(equal([
                                Enum(name: "Foo",
                                     cases: [
                                        EnumCase(name: "optionA", associatedValues: [
                                            AssociatedValue(name: nil, typeName: TypeName("Int"), annotations: ["annotation": NSNumber(value: true)])
                                            ]),
                                        EnumCase(name: "optionB")
                                    ])
                                ]))
                    }

                    it("extracts variables properly") {
                        expect(parse("enum Foo { var x: Int { return 1 } }"))
                                .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [], variables: [Variable(name: "x", typeName: TypeName("Int"), accessLevel: (.internal, .none), isComputed: true, definedInTypeName: TypeName("Foo"))])
                                ]))
                    }

                    context("given enum without rawType") {
                        it("extracts inherited types properly") {
                            expect(parse("enum Foo: SomeProtocol { case optionA }; protocol SomeProtocol {}"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["SomeProtocol"], rawTypeName: nil, cases: [EnumCase(name: "optionA")]),
                                    Protocol(name: "SomeProtocol")
                                    ]))

                        }

                        it("extracts types inherited in extension properly") {
                            expect(parse("enum Foo { case optionA }; extension Foo: SomeProtocol {}; protocol SomeProtocol {}"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: ["SomeProtocol"], rawTypeName: nil, cases: [EnumCase(name: "optionA")]),
                                    Protocol(name: "SomeProtocol")
                                    ]))
                        }

                        it("does not use extension to infer rawType") {
                            expect(parse("enum Foo { case one }; extension Foo: Equatable {}")).to(equal([
                                Enum(name: "Foo",
                                     inheritedTypes: ["Equatable"],
                                     cases: [EnumCase(name: "one")]
                                )
                                ]))
                        }

                    }

                    it("extracts enums with custom values") {
                        expect(parse("""
                                     enum Foo: String {
                                       case optionA = "Value"
                                     }
                                     """))
                            .to(equal([
                                Enum(name: "Foo", accessLevel: .internal, isExtension: false, rawTypeName: TypeName("String"), cases: [EnumCase(name: "optionA", rawValue: "Value")])
                                ]))

                        expect(parse("""
                                     enum Foo: Int {
                                       case optionA = 2
                                     }
                                     """))
                          .to(equal([
                                        Enum(name: "Foo", accessLevel: .internal, isExtension: false, rawTypeName: TypeName("Int"), cases: [EnumCase(name: "optionA", rawValue: "2")])
                                    ]))
                    }

                    it("extracts enums without rawType") {
                        let expectedEnum = Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases: [EnumCase(name: "optionA")])

                        expect(parse("enum Foo { case optionA }")).to(equal([expectedEnum]))
                    }

                    it("extracts enums with associated types") {
                        expect(parse("enum Foo { case optionA(Observable<Int, Int>); case optionB(Int, named: Float, _: Int); case optionC(dict: [String: String]) }"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases:
                                        [
                                            EnumCase(name: "optionA", associatedValues: [
                                                AssociatedValue(localName: nil, externalName: nil, typeName: TypeName("Observable<Int, Int>", generic: GenericType(
                                                    name: "Observable", typeParameters: [
                                                        GenericTypeParameter(typeName: TypeName("Int")),
                                                        GenericTypeParameter(typeName: TypeName("Int"))
                                                    ])))
                                                ]),
                                            EnumCase(name: "optionB", associatedValues: [
                                                AssociatedValue(localName: nil, externalName: "0", typeName: TypeName("Int")),
                                                AssociatedValue(localName: "named", externalName: "named", typeName: TypeName("Float")),
                                                AssociatedValue(localName: nil, externalName: "2", typeName: TypeName("Int"))
                                                ]),
                                            EnumCase(name: "optionC", associatedValues: [
                                                AssociatedValue(localName: "dict", externalName: nil, typeName: TypeName("[String: String]", dictionary: DictionaryType(name: "[String: String]", valueTypeName: TypeName("String"), keyTypeName: TypeName("String")), generic: GenericType(name: "Dictionary", typeParameters: [GenericTypeParameter(typeName: TypeName("String")), GenericTypeParameter(typeName: TypeName("String"))])))
                                                ])
                                        ])
                                ]))
                    }

                    it("extracts enums with indirect cases") {
                        expect(parse("enum Foo { case optionA; case optionB; indirect case optionC(Foo) }"))
                                .to(equal([
                                    Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases:
                                        [
                                            EnumCase(name: "optionA", indirect: false),
                                            EnumCase(name: "optionB"),
                                            EnumCase(name: "optionC", associatedValues: [AssociatedValue(typeName: TypeName("Foo"))], indirect: true)
                                        ])
                                ]))
                    }

                    it("extracts enums with Void associated type") {
                        expect(parse("enum Foo { case optionA(Void); case optionB(Void) }"))
                                .to(equal([
                                                  Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases:
                                                  [
                                                          EnumCase(name: "optionA", associatedValues: [AssociatedValue(typeName: TypeName("Void"))]),
                                                          EnumCase(name: "optionB", associatedValues: [AssociatedValue(typeName: TypeName("Void"))])
                                                  ])
                                          ]))
                    }

                    it("extracts default values for asssociated values") {
                        expect(parse("enum Foo { case optionA(Int = 1, named: Float = 42.0, _: Bool = false); case optionB(Bool = true) }"))
                        .to(equal([
                            Enum(name: "Foo", accessLevel: .internal, isExtension: false, inheritedTypes: [], cases:
                                [
                                    EnumCase(name: "optionA", associatedValues: [
                                        AssociatedValue(localName: nil, externalName: "0", typeName: TypeName("Int"), defaultValue: "1"),
                                        AssociatedValue(localName: "named", externalName: "named", typeName: TypeName("Float"), defaultValue: "42.0"),
                                        AssociatedValue(localName: nil, externalName: "2", typeName: TypeName("Bool"), defaultValue: "false")
                                        ]),
                                    EnumCase(name: "optionB", associatedValues: [
                                        AssociatedValue(localName: nil, externalName: nil, typeName: TypeName("Bool"), defaultValue: "true")
                                    ])
                                ])
                        ]))
                    }

                    context("given associated value with its type existing") {

                        it("extracts associated value's type") {
                            let associatedValue = AssociatedValue(typeName: TypeName("Bar"), type: Class(name: "Bar", inheritedTypes: ["Baz"]))
                            let item = Enum(name: "Foo", cases: [EnumCase(name: "optionA", associatedValues: [associatedValue])])

                            let parsed = parse("protocol Baz {}; class Bar: Baz {}; enum Foo { case optionA(Bar) }")
                            let parsedItem = parsed.compactMap { $0 as? Enum }.first

                            expect(parsedItem).to(equal(item))
                            expect(associatedValue.type).to(equal(parsedItem?.cases.first?.associatedValues.first?.type))
                        }

                        it("extracts associated value's optional type") {
                            let associatedValue = AssociatedValue(typeName: TypeName("Bar?"), type: Class(name: "Bar", inheritedTypes: ["Baz"]))
                            let item = Enum(name: "Foo", cases: [EnumCase(name: "optionA", associatedValues: [associatedValue])])

                            let parsed = parse("protocol Baz {}; class Bar: Baz {}; enum Foo { case optionA(Bar?) }")
                            let parsedItem = parsed.compactMap { $0 as? Enum }.first

                            expect(parsedItem).to(equal(item))
                            expect(associatedValue.type).to(equal(parsedItem?.cases.first?.associatedValues.first?.type))
                        }

                        it("extracts associated value's typealias") {
                            let associatedValue = AssociatedValue(typeName: TypeName("Bar2"), type: Class(name: "Bar", inheritedTypes: ["Baz"]))
                            let item = Enum(name: "Foo", cases: [EnumCase(name: "optionA", associatedValues: [associatedValue])])

                            let parsed = parse("typealias Bar2 = Bar; protocol Baz {}; class Bar: Baz {}; enum Foo { case optionA(Bar2) }")
                            let parsedItem = parsed.compactMap { $0 as? Enum }.first

                            expect(parsedItem).to(equal(item))
                            expect(associatedValue.type).to(equal(parsedItem?.cases.first?.associatedValues.first?.type))
                        }

                        it("extracts associated value's same (indirect) enum type") {
                            let associatedValue = AssociatedValue(typeName: TypeName("Foo"))
                            let item = Enum(name: "Foo", inheritedTypes: ["Baz"], cases: [EnumCase(name: "optionA", associatedValues: [associatedValue])], modifiers: [
                                Modifier(name: "indirect")
                            ])
                            associatedValue.type = item

                            let parsed = parse("protocol Baz {}; indirect enum Foo: Baz { case optionA(Foo) }")
                            let parsedItem = parsed.compactMap { $0 as? Enum }.first

                            expect(parsedItem).to(equal(item))
                            expect(associatedValue.type).to(equal(parsedItem?.cases.first?.associatedValues.first?.type))
                        }

                    }
                }

                context("given protocol") {
                    it("extracts generic requirements properly") {
                        expect(parse(
                            """
                            protocol SomeGenericProtocol: GenericProtocol {}
                            """
                        ).first).to(equal(
                            Protocol(name: "SomeGenericProtocol", inheritedTypes: ["GenericProtocol"])
                        ))

                        expect(parse(
                            """
                            protocol SomeGenericProtocol: GenericProtocol where LeftType == RightType {}
                            """
                        ).first).to(equal(
                            Protocol(
                                name: "SomeGenericProtocol",
                                inheritedTypes: ["GenericProtocol"],
                                genericRequirements: [
                                    GenericRequirement(leftType: .init(name: "LeftType"), rightType: .init(typeName: .init("RightType")), relationship: .equals)
                                ])
                        ))

                        expect(parse(
                            """
                            protocol SomeGenericProtocol: GenericProtocol where LeftType: RightType {}
                            """
                        ).first).to(equal(
                            Protocol(
                                name: "SomeGenericProtocol",
                                inheritedTypes: ["GenericProtocol"],
                                genericRequirements: [
                                    GenericRequirement(leftType: .init(name: "LeftType"), rightType: .init(typeName: .init("RightType")), relationship: .conformsTo)
                                ])
                        ))

                        expect(parse(
                            """
                            protocol SomeGenericProtocol: GenericProtocol where LeftType == RightType, LeftType2: RightType2 {}
                            """
                        ).first).to(equal(
                            Protocol(
                                name: "SomeGenericProtocol",
                                inheritedTypes: ["GenericProtocol"],
                                genericRequirements: [
                                    GenericRequirement(leftType: .init(name: "LeftType"), rightType: .init(typeName: .init("RightType")), relationship: .equals),
                                    GenericRequirement(leftType: .init(name: "LeftType2"), rightType: .init(typeName: .init("RightType2")), relationship: .conformsTo)
                                ])
                        ))
                    }

                    it("extracts empty protocol properly") {
                        expect(parse("protocol Foo { }"))
                            .to(equal([
                                Protocol(name: "Foo")
                                ]))
                    }

                    it("does not consider protocol variables as computed") {
                        expect(parse("protocol Foo { var some: Int { get } }"))
                            .to(equal([
                                Protocol(name: "Foo", variables: [Variable(name: "some", typeName: TypeName("Int"), accessLevel: (.internal, .none), isComputed: false, definedInTypeName: TypeName("Foo"))])
                                ]))
                    }

                    it("does consider type variables as computed when they are, even if they adhere to protocol") {
                        expect(parse("protocol Foo { var some: Int { get }\nvar some2: Int { get } }\nclass Bar: Foo { var some: Int { return 2 }\nvar some2: Int { get { return 2 } } }").first)
                            .to(equal(
                                Class(name: "Bar", variables: [
                                    Variable(name: "some", typeName: TypeName("Int"), accessLevel: (.internal, .none), isComputed: true, definedInTypeName: TypeName("Bar")),
                                    Variable(name: "some2", typeName: TypeName("Int"), accessLevel: (.internal, .none), isComputed: true, definedInTypeName: TypeName("Bar"))
                                ], inheritedTypes: ["Foo"])
                                ))
                    }

                    it("does not consider type variables as computed when they aren't, even if they adhere to protocol and have didSet blocks") {
                        expect(parse("protocol Foo { var some: Int { get } }\nclass Bar: Foo { var some: Int { didSet { } }").first)
                          .to(equal(
                            Class(name: "Bar", variables: [Variable(name: "some", typeName: TypeName("Int"), accessLevel: (.internal, .internal), isComputed: false, definedInTypeName: TypeName("Bar"))], inheritedTypes: ["Foo"])
                          ))
                    }

                    describe("when dealing with protocol inheritance") {
                        it("flattens protocol with default implementation as expected") {
                            let parsed = parse(
                                """
                                protocol UrlOpening {
                                  func open(
                                    _ url: URL,
                                    options: [UIApplication.OpenExternalURLOptionsKey: Any],
                                    completionHandler completion: ((Bool) -> Void)?
                                  )
                                  func open(_ url: URL)
                                }

                                extension UrlOpening {
                                    func open(_ url: URL) {
                                        open(url, options: [:], completionHandler: nil)
                                    }

                                    func anotherFunction(key: String) {
                                    }
                                }
                                """
                            )

                            expect(parsed).to(haveCount(1))

                            let childProtocol = parsed.last
                            expect(childProtocol?.name).to(equal("UrlOpening"))
                            expect(childProtocol?.allMethods.map { $0.selectorName }).to(equal(["open(_:options:completionHandler:)", "open(_:)", "anotherFunction(key:)"]))
                        }

                        it("flattens inherited protocols with default implementation as expected") {
                            let parsed = parse(
                                """
                                protocol RemoteUrlOpening {
                                  func open(_ url: URL)
                                }

                                protocol UrlOpening: RemoteUrlOpening {
                                  func open(
                                    _ url: URL,
                                    options: [UIApplication.OpenExternalURLOptionsKey: Any],
                                    completionHandler completion: ((Bool) -> Void)?
                                  )
                                }

                                extension UrlOpening {
                                  func open(_ url: URL) {
                                    open(url, options: [:], completionHandler: nil)
                                  }
                                }
                                """
                            )

                            expect(parsed).to(haveCount(2))

                            let childProtocol = parsed.last
                            expect(childProtocol?.name).to(equal("UrlOpening"))
                            expect(childProtocol?.allMethods.filter({ $0.definedInType?.isExtension == false }).map { $0.selectorName }).to(equal(["open(_:options:completionHandler:)", "open(_:)"]))
                        }
                    }
                }
            }
        }
    }
}
