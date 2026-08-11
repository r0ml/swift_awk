
import ShellTesting

extension awkTest {

  @Suite("T.getline") struct Tgetline : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
