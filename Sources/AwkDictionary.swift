// Copyright (c) 1868 Charles Babbage
// Modernized by Robert "r0ml" Lefkowitz <code@liberally.net> in 2026

public class AwkDictionary {
  var theDict : [String: any Cell] = [:]
  var theKeys: [String] = []

  subscript (key: String) -> Cell? {
    get {
      return theDict[key]
    }
    set {
      let k = theDict[key] == nil
      theDict[key] = newValue
      if k { theKeys.append(key) }
    }
  }

  public var keys : [String] {
    return instatOrder(theKeys)
  }

  /// Returns keys in the exact order awk's `instat` (for-in) would visit them.
  ///
  /// Requires keys in insertion order because awk prepends new entries to their
  /// bucket chain; instat then walks each chain newest-first. Without insertion
  /// order, only the bucket-level sort (not within-bucket order) can be guaranteed.
  private func instatOrder(_ keys: [String]) -> [String] {
      var buckets = [[String]](repeating: [], count: 50)  // NSYMTAB = 50
      var size = 50
      var nelem = 0

      for key in keys {
          nelem += 1
          if nelem > 2 * size {                           // FULLTAB = 2
              let newSize = size * 4                      // GROWTAB = 4
              var newBuckets = [[String]](repeating: [], count: newSize)
              for i in 0..<size {
                  for k in buckets[i] {                   // head→tail = newest→oldest
                      newBuckets[awkHash(k, tableSize: newSize)].insert(k, at: 0)
                  }
              }
              buckets = newBuckets
              size = newSize
          }
          buckets[awkHash(key, tableSize: size)].insert(key, at: 0)  // prepend
      }

      return buckets.flatMap { $0 }
  }

  private func awkHash(_ key: String, tableSize: Int) -> Int {
      var hashval: UInt32 = 0
      for byte in key.utf8 {
          hashval = UInt32(byte) &+ 31 &* hashval
      }
      return Int(hashval % UInt32(tableSize))
  }

  public func removeValue(forKey key: String) {
    theDict.removeValue(forKey: key)
    theKeys.removeAll { $0 == key }
  }

  var count : Int { theDict.count }

}
