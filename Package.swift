// swift-tools-version: 6.4

/*
  The MIT License (MIT)
  Copyright © 2024 Robert (r0ml) Lefkowitz

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software
  and associated documentation files (the “Software”), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
  and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so,
  subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE
  OR OTHER DEALINGS IN THE SOFTWARE.
 */

import PackageDescription
import Foundation

let WIP = [String]()         // source folders to skip over
let TestWIP = [String]()     // test folders to skip over

let package = Package(
  name: "awk",
  // using v26 because linking with external lzma from brew
  platforms: [.macOS(.v26), .macCatalyst(.v18), .iOS(.v18)],
  dependencies: [
      .package(url: "https://github.com/r0ml/CMigration.git", branch: "main"),
     .package(url: "https://github.com/r0ml/ShellTesting.git" , branch: "main"),
     .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
  ],

  targets:
    [.executableTarget(name: "awk",
                       dependencies: [.product(name: "CMigration", package: "CMigration"), .product(name: "Atomics", package: "swift-atomics")] ),

    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
//   + generateTestTargets()

      .testTarget(name: "awkTest",
                  dependencies: [.product(name: "ShellTesting", package: "ShellTesting"),
                                 .target(name: "awk")
                                 ],
                                 path: nil,
                  resources: [Resource.copy("Resources")])

     ]
)

private func packageRoot() -> URL {
  let manifestURL = URL(fileURLWithPath: #filePath)
  return manifestURL.deletingLastPathComponent()

}

func generateTestTargets() -> [Target] {
  let skipTestsForNow = ["lsTest", "cpTest"]

    var res = [ Target]()

  let testurl = packageRoot().appendingPathComponent("Tests", isDirectory: true)
  let cd = try! FileManager.default.contentsOfDirectory(atPath: testurl.path )
    for i in cd {
      if i == ".DS_Store" { continue }

      if skipTestsForNow.contains(i) { continue }

      if TestWIP.contains(i) { continue }
      let r =  FileManager.default.fileExists(atPath: testurl.appendingPathComponent(i).appendingPathComponent("Resources").path  )
        let rr = r ? [Resource.copy("Resources")] : []
        let t = Target.testTarget(name: i,
                                  dependencies: [.product(name: "ShellTesting", package: "ShellTesting"),
//                                                 .product(name: "Subprocess", package: "swift-subprocess"),
                                                 .target(name: i.replacingOccurrences(of: "Test", with: ""))],
                                  path: nil,
                                  resources: rr
        )
        res.append(t)
    }
    return res
}
