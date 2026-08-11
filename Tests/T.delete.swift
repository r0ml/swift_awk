
import ShellTesting

extension awkTest {

  @Suite("T.delete") struct Tdelete : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
