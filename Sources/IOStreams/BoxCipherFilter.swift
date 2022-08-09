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

import Foundation
import CryptoKit

/// Cryptographic box sealing or opening cipher ``Sink``.
///
/// Treats incoming data buffers as an ordered series of
/// cryptographic boxes that will be sealed or opened,
/// depending on the operating mode.
///
public class BoxCipherFilter: Filter {

  /// Box cipher alogorithm type.
  ///
  public enum Algorithm {
    /// AES-GCM
    ///
    /// Uses AES-GCM (with 12 byte nonces) for box operations.
    ///
    case aesGcm
    /// ChaCha20-Poly1305.
    ///
    /// Uses ChaCha20-Poly1305 (as described in RFC 7539 with 96-bit nonces)
    /// for box operations.
    ///
    case chaCha20Poly
  }

  /// Box cipher operation type.
  ///
  public enum Operation {
    /// Seal each data buffer inside a crytographic box.
    case seal
    /// Open each data buffer from a crytographic box.
    case open
  }

  /// Additional authentication data added to each box.
  private struct AAD {
    public let index: UInt64
    public let isFinal: Bool
  }

  /// Size of the tag produced by the seal operation.
  public static let tagSize = 16

  /// Key used to seal or open boxes.
  public let key: SymmetricKey

  /// Overhead size of the sealing operation.
  public var sizeOverhead: Int {
    switch algorthm {
    case .aesGcm: return 12 + Self.tagSize
    case .chaCha20Poly: return 12 + Self.tagSize
    }
  }

  private let operation: (Data, AAD, SymmetricKey) throws -> Data
  private let algorthm: Algorithm
  private var boxIndex: UInt64 = 0
  private var lastBoxData: Data? = nil

  /// Initializes the cipher with the given ``Operation``, ``Algorithm``, and
  /// cryptographic key.
  ///
  /// - Parameters:
  ///   - operation: Operation to perform on the passed in data.
  ///   - algorithm: Box cipher algorithm to use.
  ///
  public init(operation: Operation, algorithm: Algorithm, key: SymmetricKey) {
    self.algorthm = algorithm
    switch (algorithm, operation) {
    case (.aesGcm, .seal):
      self.operation = Self.AESGCMOps.seal(data:aad:key:)
    case (.aesGcm, .open):
      self.operation = Self.AESGCMOps.open(data:aad:key:)
    case (.chaCha20Poly, .seal):
      self.operation = Self.ChaChaPolyOps.seal(data:aad:key:)
    case (.chaCha20Poly, .open):
      self.operation = Self.ChaChaPolyOps.open(data:aad:key:)
    }
    self.key = key
  }

  /// Treats `data` as a cryptographic box of data and seals
  /// or opens the box according to the ``Operation`` initialized
  /// with.
  ///
  public func process(data: Data) async throws -> Data {

    guard let boxData = lastBoxData else {
      lastBoxData = data
      return Data()
    }

    lastBoxData = data

    defer { boxIndex += 1}

    return try operation(boxData, AAD(index: boxIndex, isFinal: false), key)
  }

  /// Finishes processig the sequence of boxes and
  /// returns the last one (if available).
  ///
  public func finish() throws -> Data? {

    guard let boxData = lastBoxData else {
      return nil
    }

    lastBoxData = nil

    return try operation(boxData, AAD(index: boxIndex, isFinal: true), key)
  }

  private enum AESGCMOps {

    fileprivate static func seal(data: Data, aad: AAD, key: SymmetricKey) throws -> Data {

      let aad = withUnsafeBytes(of: aad) { Data($0) }

      guard let sealedData = try AES.GCM.seal(data, using: key, authenticating: aad).combined else {
        fatalError()
      }

      return sealedData
    }

    fileprivate static func open(data: Data, aad: AAD, key: SymmetricKey) throws -> Data {

      let aad = withUnsafeBytes(of: aad) { Data($0) }

      return try AES.GCM.open(AES.GCM.SealedBox(combined: data), using: key, authenticating: aad)
    }

  }

  private enum ChaChaPolyOps {

    fileprivate static func seal(data: Data, aad: AAD, key: SymmetricKey) throws -> Data {

      let aad = withUnsafeBytes(of: aad) { Data($0) }

      return try ChaChaPoly.seal(data, using: key, authenticating: aad).combined
    }

    fileprivate static func open(data: Data, aad: AAD, key: SymmetricKey) throws -> Data {

      let aad = withUnsafeBytes(of: aad) { Data($0) }

      return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key, authenticating: aad)
    }

  }

}

public extension Source {

  /// Applies a box ciphering filter to this stream.
  ///
  /// - Parameters:
  ///   - algorithm: Alogorithm for box ciphering.
  ///   - operation: Operation (seal or open) to apply.
  ///   - key: Key to use for cipher.
  /// - Returns: Box ciphered source stream reading from this stream.
  func boxCiphered(algorithm: BoxCipherFilter.Algorithm, operation: BoxCipherFilter.Operation, key: SymmetricKey) -> Source {
    filtered(filter: BoxCipherFilter(operation: operation, algorithm: algorithm, key: key))
  }

}

public extension Sink {

  /// Applies a box ciphering filter to this stream.
  ///
  /// - Parameters:
  ///   - algorithm: Alogorithm for box ciphering.
  ///   - operation: Operation (seal or open) to apply.
  ///   - key: Key to use for cipher.
  /// - Returns: Box ciphered sink stream writing to this stream.
  func boxCiphered(algorithm: BoxCipherFilter.Algorithm, operation: BoxCipherFilter.Operation, key: SymmetricKey) -> Sink {
    filtered(filter: BoxCipherFilter(operation: operation, algorithm: algorithm, key: key))
  }

}
