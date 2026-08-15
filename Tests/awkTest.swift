// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026


import ShellTesting

@Suite("awkTest", .serialized) struct awkTest : ShellTest {
  var cmd = "awk"
  var suiteBundle = "awk_awkTest"

}
