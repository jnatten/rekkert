// Does a session code work as a TLS pre-shared key?
//
//     swift scripts/psk-spike.swift
//
// Answers the one question the shared-scoreboard design could not be reasoned into: whether
// Network.framework will authenticate two peers from a short secret alone, with no
// certificates and no server. Run on macOS over loopback; no simulator, no devices.
//
// What it found, and why the transport is configured the way it is:
//
//     pinned to TLS 1.3     matching code FAILS  -9810 errSSLInternal
//     version negotiated    matching code READY (TLS 1.2)   wrong code -9846 bad MAC
//     TLS 1.2 + 0x00AB      matching code READY             wrong code -9846 bad MAC
//     TLS 1.2 + 0x00AA      matching code READY             wrong code -9846 bad MAC
//
// External PSK is not available under TLS 1.3, so the minimum must not be pinned there.
// 0x00AA is TLS_DHE_PSK_WITH_AES_128_GCM_SHA256, which is a PSK suite that also gives
// forward secrecy. A wrong code is refused during the handshake, before a byte of the match
// moves.
import CryptoKit
import Foundation
import Network
import Security

func parameters(secret: String, pinTo13: Bool) -> NWParameters {
    let tls = NWProtocolTLS.Options()
    let options = tls.securityProtocolOptions
    sec_protocol_options_set_min_tls_protocol_version(options, pinTo13 ? .TLSv13 : .TLSv12)
    if !pinTo13 {
        for suite in [0x00AA, 0x00AB] {
            if let value = tls_ciphersuite_t(rawValue: UInt16(suite)) {
                sec_protocol_options_append_tls_ciphersuite(options, value)
            }
        }
    }
    let key = SymmetricKey(data: SHA256.hash(data: Data(secret.utf8)))
    sec_protocol_options_add_pre_shared_key(
        options,
        key.withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData,
        Data("rekkert".utf8).withUnsafeBytes { DispatchData(bytes: $0) } as __DispatchData
    )
    return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
}

func attempt(hostCode: String, guestCode: String, pinTo13: Bool, label: String) async {
    let queue = DispatchQueue(label: "psk-spike")
    guard let listener = try? NWListener(using: parameters(secret: hostCode, pinTo13: pinTo13)) else {
        print("\(label): could not listen"); return
    }
    let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
        let lock = NSLock()
        var settled = false
        func finish(_ value: String) {
            lock.lock(); let already = settled; settled = true; lock.unlock()
            if !already { continuation.resume(returning: value) }
        }
        listener.newConnectionHandler = { incoming in
            incoming.stateUpdateHandler = { if case .failed(let error) = $0 { finish("refused — \(error)") } }
            incoming.start(queue: queue)
        }
        listener.stateUpdateHandler = { state in
            guard case .ready = state, let port = listener.port else { return }
            let client = NWConnection(
                host: .ipv4(.loopback), port: port,
                using: parameters(secret: guestCode, pinTo13: pinTo13)
            )
            client.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    let metadata = client.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata
                    let version = metadata.map {
                        sec_protocol_metadata_get_negotiated_tls_protocol_version($0.securityProtocolMetadata)
                    }
                    finish("connected — \(version == .TLSv13 ? "TLS 1.3" : "TLS 1.2")")
                case .failed(let error): finish("refused — \(error)")
                default: break
                }
            }
            client.start(queue: queue)
        }
        listener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 8) { finish("timed out") }
    }
    listener.cancel()
    print("\(label): \(outcome)")
}

await attempt(hostCode: "H7K3MR", guestCode: "H7K3MR", pinTo13: true, label: "pinned to 1.3, same code ")
await attempt(hostCode: "H7K3MR", guestCode: "H7K3MR", pinTo13: false, label: "PSK suites,   same code ")
await attempt(hostCode: "H7K3MR", guestCode: "WRONG1", pinTo13: false, label: "PSK suites,   wrong code")
