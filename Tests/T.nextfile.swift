
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
        let h = try FileDescriptor(forReading: j.string + "/" + i).bytes.lines(true, encoding: .latin1)
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
      let (o, f) = try await buildReferenceFile(1)

      let prog = """
        { print $0; 
          for (i = 1; i < 10; i++)
          if (i == 1)
            nextfile
          print "nextfile for error"
        }  # print first line, quit
        
        """
      try await run(output: o, args: [prog] + f)
    }
    
    @Test("second") func second() async throws {
      let (o, f) = try await buildReferenceFile(1)
      let prog = """
        { print $0; 
          i = 1
          while (i < 10)
          if (i++ == 1)
            nextfile
          print "nextfile while error"
        }  # print first line, quit
        
        """
      try await run(output: o, args: [prog] + f)   
    }

    @Test("third") func third() async throws {
      let (o, f) = try await buildReferenceFile(1)
      let prog = """
        { print $0; 
          i = 1
          do {
          if (i++ == 1)
            nextfile  # print first line, quit
          } while (i < 10)
          print "nextfile do error"
        }

        """
      try await run(output: o, args: [prog] + f)   
    }

    @Test("sixth") func sixth() async throws {
      let prog = """
        { print }
        FNR == 10 { nextfile }  # print first line, quit
        """
      let (o, f) = try await buildReferenceFile(10)
      try await run(output: o, args: [prog]+f)
    }

    @Test("seventh") func seventh() async throws {
      let prog = """
        { print $0; nextfile }  # print first line, quit
        """
      let (o, f) = try await buildReferenceFile(1)
      try await run(output: o, args: [prog] + f)
    }
  }
}
