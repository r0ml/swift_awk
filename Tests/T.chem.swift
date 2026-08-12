
import ShellTesting

extension awkTest {

  @Suite("T.chem") struct Tchem : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let lsdl = try inFile("lsd1.p")
      let chem = try inFile("chem.awk")
      let out = try fileContents("chem.lsd1.out")
      try await run(output: out, args: "-f", chem, lsdl)
    }

    @Test("second") func second() async throws {
      let lsdl = try inFile("penicil.p")
      let chem = try inFile("chem.awk")
      let out = try fileContents("chem.penicil.out")
      try await run(output: out, args: "-f", chem, lsdl)
    }

    @Test("third") func third() async throws {
      let lsdl = try inFile("res.p")
      let chem = try inFile("chem.awk")
      let out = try fileContents("chem.res.out")
      try await run(output: out, args: "-f", chem, lsdl)
    }

  }
}
