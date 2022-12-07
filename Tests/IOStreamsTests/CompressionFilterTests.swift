/*
 * Copyright 2022 Outfox, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

@testable import IOStreams
import XCTest

final class CompressionFilterTests: XCTestCase {

  func testRoundTrip() async throws {

    let data = Data(repeating: 0x5A, count: (512 * 1024) + 3333)
    let sink = DataSink()

    let decompressingSink = try sink.decompressing(algorithm: .lzfse)
    do {

      let compressingSource = try data.source().compressing(algorithm: .lzfse)
      do {

        try await compressingSource.pipe(to: decompressingSink)

        try await compressingSource.close()
      }
      catch {
        try await compressingSource.close()
        throw error
      }

      try await decompressingSink.close()
    }
    catch {
      try await decompressingSink.close()
      throw error
    }

    XCTAssertEqual(data, sink.data)
  }

}
