
import ShellTesting

extension awkTest {

  @Suite("T.nextfile") struct Tnextfile : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"

    func buildReferenceFile(_ n : Int) async throws -> (String, [FilePath]) {
      let j = try geturl("ttests")
//      let k = try j.listDirectory()
  let k = ["expected.t.printf2"]    
      var res : String = ""
      var res2 : [FilePath] = []
      for i in k {
        let z = FilePath(j.string + "/" + i)
        res2.append(z)
        var h = try await FileDescriptor(forReading: j.string + "/" + i).bytes.lines(true, encoding: ISOLatin1.self)
        var x = n
        for try await j in h {
          if x <= 0 { break }
          x -= 1
          res.append(j)
        }
      }
      return (res, res2)
    }

    @Test("first") func first() async throws {
      let prog = """
        
        """
    }
    
    @Test("second") func second() async throws {
      let prog = """
        
        """
    }

    @Test("third") func third() async throws {
      let prog = """
        
        """
    }

    @Test("fourth") func fourth() async throws {
      let prog = """
        
        """
    }

    @Test("fifth") func fifth() async throws {
      let prog = """
        
        """
    }

    @Test("sixth") func sixth() async throws {
      let prog = """
        { print }
        FNR == 10 { nextfile }  # print first line, quit
        """
      let (o, f) = try await buildReferenceFile(10)
      try await run(output: o, args: [prog]+f,
                    env: ["LC_ALL":"en_US.UTF-8"])
    }

    @Test("seventh") func seventh() async throws {
      let prog = """
        { print $0; nextfile }  # print first line, quit
        """
      let (o, f) = try await buildReferenceFile(1)
      try await run(output: o, args: [prog]+f,
                    env: ["LC_CTYPE":"en_US.UTF-8"])
    }
  }
}
