import CryptoKit
import Foundation

// All arguments are public: the embedded public key, archive, and signature.
guard CommandLine.arguments.count == 4,
      let key = Data(base64Encoded: CommandLine.arguments[1]),
      let signature = Data(base64Encoded: CommandLine.arguments[3]),
      let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: key),
      let archive = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe),
      publicKey.isValidSignature(signature, for: archive) else {
    fputs("The update archive does not match the app's trusted signing key.\n", stderr)
    exit(1)
}
print("Verified update archive against the app's public key.")
