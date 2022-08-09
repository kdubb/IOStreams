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

import XCTest
@testable import IOStreams

final class FileStreamsTests: XCTestCase {

  var fileURL: URL!

  override func setUp() async throws {

    fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
      throw CocoaError(.fileWriteUnknown)
    }
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: fileURL)
  }

  func disabled_testSourceReadsCompletelyUsingBytes() async throws {

    let fileSize = 50 * 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))

    measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      let completed = DispatchSemaphore(value: 0)

      Task {
        try fileHandle.seek(toOffset: 0)
        let bytes = fileHandle.bytes

        var bytesRead = 0

        startMeasuring()

        var data = Data(capacity: fileSize)
        for try await byte in bytes {
          data.append(byte)
          bytesRead = bytesRead + 1
        }

        stopMeasuring()

        print("Read \(bytesRead) bytes")

        XCTAssertEqual(bytesRead, fileSize)

        completed.signal()
      }

      completed.wait()
    }
  }

  func testSourceReadsCompletely() async throws {

    let fileSize = 50 * 1024 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))

    measureMetrics([.wallClockTime], automaticallyStartMeasuring: false) {
      let completed = DispatchSemaphore(value: 0)

      Task {
        try fileHandle.seek(toOffset: 0)
        let source = try FileSource(fileHandle: fileHandle)

        startMeasuring()

        for try await _ in source.buffers() {}

        stopMeasuring()

        print("Read \(source.bytesRead) bytes")

        XCTAssertEqual(source.bytesRead, fileSize)

        completed.signal()
      }

      completed.wait()
    }
  }

  func testSourceCancels() async throws {

    let fileSize = 256 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))

    let source = try FileSource(url: fileURL)

    let reader = Task {
      for try await data in source.buffers(size: 3079) {
        print("Read \(data.count) bytes of data")
      }
    }

    do {
      reader.cancel()
      try await reader.value
    }
    catch is CancellationError {
    }

    XCTAssertEqual(source.bytesRead, 0)
  }

  func testSourceCancelsAfterStart() async throws {

    let fileSize = 256 * 1024
    let fileHandle = try FileHandle(forUpdating: fileURL)
    try fileHandle.truncate(atOffset: UInt64(fileSize))
    try fileHandle.seek(toOffset: 0)

    let source = try FileSource(fileHandle: fileHandle)

    let reader = Task {
      for try await data in source.buffers(size: 133) {
        print("Read \(data.count) bytes of data")
      }
    }

    try await Task.sleep(nanoseconds: 100_000)

    do {
      reader.cancel()
      try await reader.value
    }
    catch is CancellationError {
    }

    XCTAssert(source.bytesRead > 0, "Data should have been read from source")
    XCTAssert(source.bytesRead < fileSize, "Source should have cancelled iteration")
  }

}
