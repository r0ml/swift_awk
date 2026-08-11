
import ShellTesting

extension awkTest {

  @Suite("T.f-f") struct Tf_f : ShellTest {
    var cmd = "awk"
    var suiteBundle = "awk_awkTest"


    @Test("first") func first() async throws {
    }
  }
}
