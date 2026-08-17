
import ShellTesting

extension awkTest {

  @Suite("T.latin1") struct Tlatin1 : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
      let latin1 = try inFile("latin1")
      let latc = try latin1.readAsString(encoding: ISOLatin1.self)
      try await run(output: latc,
                    args: "{ print $0 }", latin1,
                    env: ["LC_ALL":"de_DE.ISO8859-1"] )
//                    env: ["LC_ALL": "de_DE.UTF-8"])
    }
  }
}
