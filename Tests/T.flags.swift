
import ShellTesting

extension Tag {
    @Tag static var flags : Self
}

extension awkTest {
  @Suite("T.argv") struct Tflags : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("flags: no q4tw", .tags(.flags)) public func Tflags_1() async throws {
      try await run(status: 2, error: /[Uu]sage/, args: [])
    }

    @Test("flags: no program file", .tags(.flags)) public func Tflags_2() async throws {
      try await run(status: 1, error: /option requires an argument/, args: "-f")
    }

    @Test("flags: bad program file", .tags(.flags)) public func Tflags_3() async throws {
      try await run(status: 1, error: /[Nn]o such file/, args: "-f", "glop/glop")
    }

    @Test("flags: bad program file 2", .tags(.flags)) public func Tflags_4() async throws {
      try await run(status: 1, error: /[Nn]o such file/, args: "-fglop/glop")
    }

    @Test("flags: illegal option", .tags(.flags)) public func Tflags_5() async throws {
      try await run(status: 1, error: /illegal option/, args: "-zz", "BEGIN{}")
    }

    @Test("flags: missing file separator", .tags(.flags)) public func Tflags_6() async throws {
      try await run(status: 1, error: /option requires an argument/, args: "-F")
    }

    @Test("flags: empty file separator", .tags(.flags)) public func Tflags_7() async throws {
      try await run(status: 1, error: /field separator FS is empty/, args: "-F", "")
    }
  }
}
