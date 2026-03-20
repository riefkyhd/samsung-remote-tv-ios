import BigInt
import CommonCrypto
import Foundation

// SPC (SmartView2 Crypto) - Diffie-Hellman key exchange
// Reverse-engineered from Samsung Smart View 2.0

private enum SpcKeys {
    static let publicKey = "2cb12bb2cbf7cec713c0fff7b59ae68a96784ae517f41d259a45d20556177c0ffe951ca60ec03a990c9412619d1bee30adc7773088c5721664cffcedacf6d251cb4b76e2fd7aef09b3ae9f9496ac8d94ed2b262eee37291c8b237e880cc7c021fb1be0881f3d0bffa4234d3b8e6a61530c00473ce169c025f47fcc001d9b8051"
    static let privateKey = "2fd6334713816fae018cdee4656c5033a8d6b00e8eaea07b3624999242e96247112dcd019c4191f4643c3ce1605002b2e506e7f1d1ef8d9b8044e46d37c0d5263216a87cd783aa185490436c4a0cb2c524e15bc1bfeae703bcbc4b74a0540202e8d79cadaae85c6f9c218bc1107d1f5b4b9bd87160e782f4e436eeb17485ab4d"
    static let prime = "b361eb0ab01c3439f2c16ffda7b05e3e320701ebee3e249123c3586765fd5bf6c1dfa88bb6bb5da3fde74737cd88b6a26c5ca31d81d18e3515533d08df619317063224cf0943a2f29a5fe60c1c31ddf28334ed76a6478a1122fb24c4a94c8711617ddfe90cf02e643cd82d4748d6d4a7ca2f47d88563aa2baf6482e124acd7dd"
    static let wbKey = "abbb120c09e7114243d1fa0102163b27"
    static let transKey = "6c9474469ddf7578f3e5ad8a4c703d99"
}

enum SpcCrypto {
    struct ServerHelloResult {
        let serverHello: Data
        let hash: Data
        let aesKey: Data
    }

    struct ClientHelloResult {
        let ctx: Data
        let skPrime: Data
    }

    static func generateServerHello(userId: String, pin: String) throws -> ServerHelloResult {
        let aesKey = Data(sha1(Data(pin.utf8)).prefix(16))

        let pubKeyData = Data(hex: SpcKeys.publicKey)
        let encrypted = try aesCbcEncrypt(key: aesKey, iv: Data(count: 16), data: pubKeyData)
        let swapped = try wbKeyEncrypt(encrypted)

        let userIdData = Data(userId.utf8)
        var data = Data()
        data += uint32BE(userIdData.count)
        data += userIdData
        data += swapped

        let hash = sha1(data)

        var serverHello = Data([0x01, 0x02])
        serverHello += Data(count: 5)
        serverHello += uint32BE(userIdData.count + 132)
        serverHello += data
        serverHello += Data(count: 5)

        return ServerHelloResult(serverHello: serverHello, hash: hash, aesKey: aesKey)
    }

    static func parseClientHello(
        clientHelloHex: String,
        hash: Data,
        aesKey: Data,
        userId: String
    ) throws -> ClientHelloResult? {
        guard let data = Data(hexString: clientHelloHex) else { return nil }
        guard data.count >= 15 else { throw TVError.encryptionFailed }

        let userIdLen = readUInt32BE(data, offset: 11)
        let userIdPos = 15
        let gxSize = 128

        let gxStart = userIdPos + userIdLen
        let gxEnd = gxStart + gxSize
        guard data.count >= gxEnd + 20 else {
            throw TVError.encryptionFailed
        }

        let pEncWBGx = Data(data[gxStart..<gxEnd])
        let pEncGx = try wbKeyDecrypt(pEncWBGx)
        let pGx = try aesCbcDecrypt(key: aesKey, iv: Data(count: 16), data: pEncGx)

        let bnPGx = BigUInt(pGx)
        let bnPrivate = BigUInt(Data(hex: SpcKeys.privateKey))
        let bnPrime = BigUInt(Data(hex: SpcKeys.prime))
        let secretInt = bnPGx.power(bnPrivate, modulus: bnPrime)
        var secretBytes = secretInt.serialize()
        while secretBytes.count < 128 { secretBytes.insert(0, at: 0) }
        let secret = Data(secretBytes.prefix(128))

        let dataHash2Range = gxEnd..<(gxEnd + 20)
        let dataHash2 = Data(data[dataHash2Range])
        var pinCheck = Data(userId.utf8)
        pinCheck += secret
        guard sha1(pinCheck) == dataHash2 else {
            print("[TVDBG][SPC] PIN incorrect - parseClientHello returning nil")
            return nil
        }

        var finalBuf = Data(userId.utf8)
        finalBuf += Data(userId.utf8)
        finalBuf += pGx
        finalBuf += Data(hex: SpcKeys.publicKey)
        finalBuf += secret
        let skPrime = sha1(finalBuf)

        var skPrimeInput = skPrime
        skPrimeInput.append(0x00)
        let skPrimeHash = Data(sha1(skPrimeInput).prefix(16))
        let ctx = applySamyGOKeyTransform(skPrimeHash)

        return ClientHelloResult(ctx: ctx, skPrime: skPrime)
    }

    static func generateServerAcknowledge(skPrime: Data) -> String {
        var input = skPrime
        input.append(0x01)
        let hash = sha1(input)
        return "0103000000000000000014" + hash.hexString.uppercased() + "0000000000"
    }

    static func generateCommand(ctxUpperHex: String, sessionId: Int, keyCode: String) throws -> String {
        guard let keyData = Data(hexString: ctxUpperHex) else {
            throw TVError.encryptionFailed
        }

        let inner = try JSONSerialization.data(withJSONObject: [
            "method": "POST",
            "body": [
                "plugin": "RemoteControl",
                "param1": "uuid:12345",
                "param2": "Click",
                "param3": keyCode,
                "param4": false,
                "api": "SendRemoteKey",
                "version": "1.000"
            ] as [String: Any]
        ])

        let encrypted = try aesEcbEncrypt(key: keyData, data: pkcs7Pad(inner))
        let intArray = encrypted.map { Int($0) }

        let payload = try JSONSerialization.data(withJSONObject: [
            "name": "callCommon",
            "args": [["Session_Id": sessionId, "body": intArray]]
        ])

        return "5::/com.samsung.companion:" + (String(data: payload, encoding: .utf8) ?? "{}")
    }

    static func aesCbcEncrypt(key: Data, iv: Data, data: Data) throws -> Data {
        try crypt(op: kCCEncrypt, options: 0, key: key, iv: iv, data: data)
    }

    static func aesCbcDecrypt(key: Data, iv: Data, data: Data) throws -> Data {
        try crypt(op: kCCDecrypt, options: 0, key: key, iv: iv, data: data)
    }

    static func aesEcbEncrypt(key: Data, data: Data) throws -> Data {
        try crypt(op: kCCEncrypt, options: kCCOptionECBMode, key: key, iv: nil, data: data)
    }

    private static func crypt(op: Int, options: Int, key: Data, iv: Data?, data: Data) throws -> Data {
        var outLen = 0
        var outBuf = [UInt8](repeating: 0, count: data.count + kCCBlockSizeAES128)
        let status = key.withUnsafeBytes { kPtr in
            (iv ?? Data(count: 16)).withUnsafeBytes { ivPtr in
                data.withUnsafeBytes { dPtr in
                    CCCrypt(
                        CCOperation(op),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(options),
                        kPtr.baseAddress,
                        key.count,
                        ivPtr.baseAddress,
                        dPtr.baseAddress,
                        data.count,
                        &outBuf,
                        outBuf.count,
                        &outLen
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw TVError.encryptionFailed }
        return Data(outBuf.prefix(outLen))
    }

    private static func applySamyGOKeyTransform(_ input: Data) -> Data {
        let transKey = Data(hex: SpcKeys.transKey)
        let rij = SpcRijndael(key: transKey)
        return rij.encrypt(input)
    }

    private static func wbKeyEncrypt(_ input: Data) throws -> Data {
        let key = Data(hex: SpcKeys.wbKey)
        var out = Data()
        for i in stride(from: 0, to: input.count, by: 16) {
            let block = Data(input[i..<(i + 16)])
            out += try aesCbcEncrypt(key: key, iv: Data(count: 16), data: block)
        }
        return out
    }

    private static func wbKeyDecrypt(_ input: Data) throws -> Data {
        let key = Data(hex: SpcKeys.wbKey)
        var out = Data()
        for i in stride(from: 0, to: input.count, by: 16) {
            let block = Data(input[i..<(i + 16)])
            out += try aesCbcDecrypt(key: key, iv: Data(count: 16), data: block)
        }
        return out
    }

    static func pkcs7Pad(_ data: Data) -> Data {
        let pad = 16 - (data.count % 16)
        var d = data
        d.append(contentsOf: [UInt8](repeating: UInt8(pad), count: pad))
        return d
    }

    private static func sha1(_ data: Data) -> Data {
        var digest = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { bytes in
            _ = CC_SHA1(bytes.baseAddress, CC_LONG(data.count), &digest)
        }
        return Data(digest)
    }

    private static func uint32BE(_ value: Int) -> Data {
        withUnsafeBytes(of: UInt32(value).bigEndian) { Data($0) }
    }

    private static func readUInt32BE(_ data: Data, offset: Int) -> Int {
        let b0 = UInt32(data[offset])
        let b1 = UInt32(data[offset + 1])
        let b2 = UInt32(data[offset + 2])
        let b3 = UInt32(data[offset + 3])
        return Int((b0 << 24) | (b1 << 16) | (b2 << 8) | b3)
    }
}

// Custom Rijndael implementation matching py3rijndael used by SmartCrypto
// Key: 16 bytes, Block: 16 bytes, Rounds: 4 (not standard AES-10)
struct SpcRijndael {
    private static let numRounds = 3  // num_rounds[16][16]
    private let ke: [[Int]]

    init(key: Data) {
        precondition(key.count == 16)
        let rounds = SpcRijndael.numRounds
        let bc = 4
        let kc = 4
        var ke = [[Int]](repeating: [Int](repeating: 0, count: bc), count: rounds + 1)
        var tk = [Int](repeating: 0, count: kc)

        for i in 0..<kc {
            tk[i] = (Int(key[i * 4]) << 24)
                | (Int(key[i * 4 + 1]) << 16)
                | (Int(key[i * 4 + 2]) << 8)
                | Int(key[i * 4 + 3])
        }

        let roundKeyCount = (rounds + 1) * bc
        var t = 0
        var j = 0
        while j < kc && t < roundKeyCount {
            ke[t / bc][t % bc] = tk[j] & 0xFFFFFFFF
            j += 1
            t += 1
        }

        var rconPointer = 0
        while t < roundKeyCount {
            let tt = tk[kc - 1]
            tk[0] ^= ((SpcRijndael.S[(tt >> 16) & 0xFF]) << 24)
                ^ ((SpcRijndael.S[(tt >> 8) & 0xFF]) << 16)
                ^ ((SpcRijndael.S[tt & 0xFF]) << 8)
                ^ (SpcRijndael.S[(tt >> 24) & 0xFF])
                ^ (SpcRijndael.rcon[rconPointer] << 24)
            rconPointer += 1

            for i in 1..<kc {
                tk[i] ^= tk[i - 1]
            }

            j = 0
            while j < kc && t < roundKeyCount {
                ke[t / bc][t % bc] = tk[j]
                j += 1
                t += 1
            }
        }

        self.ke = ke
    }

    func encrypt(_ source: Data) -> Data {
        precondition(source.count == 16)
        let rounds = ke.count - 1  // ke has 4 entries, rounds = 3
        let bc = 4
        let s1 = 1
        let s2 = 2
        let s3 = 3

        var t = [Int](repeating: 0, count: bc)
        for i in 0..<bc {
            t[i] = ((
                (Int(source[i * 4]) << 24)
                    | (Int(source[i * 4 + 1]) << 16)
                    | (Int(source[i * 4 + 2]) << 8)
                    | Int(source[i * 4 + 3])
            ) ^ ke[0][i]) & 0xFFFFFFFF
        }

        var a = [Int](repeating: 0, count: bc)
        for r in 1..<rounds {
            for i in 0..<bc {
                a[i] = (
                    (SpcRijndael.T1[(t[i] >> 24) & 0xFF]
                     ^ SpcRijndael.T2[(t[(i + s1) % bc] >> 16) & 0xFF]
                     ^ SpcRijndael.T3[(t[(i + s2) % bc] >> 8) & 0xFF]
                     ^ SpcRijndael.T4[t[(i + s3) % bc] & 0xFF]) ^ ke[r][i]
                ) & 0xFFFFFFFF
            }
            t = a
        }

        var result = [UInt8](repeating: 0, count: 16)
        for i in 0..<bc {
            let tt = ke[rounds][i]
            result[i * 4] = UInt8((SpcRijndael.S[(t[i] >> 24) & 0xFF] ^ (tt >> 24)) & 0xFF)
            result[i * 4 + 1] = UInt8((SpcRijndael.S[(t[(i + s1) % bc] >> 16) & 0xFF] ^ (tt >> 16)) & 0xFF)
            result[i * 4 + 2] = UInt8((SpcRijndael.S[(t[(i + s2) % bc] >> 8) & 0xFF] ^ (tt >> 8)) & 0xFF)
            result[i * 4 + 3] = UInt8((SpcRijndael.S[t[(i + s3) % bc] & 0xFF] ^ tt) & 0xFF)
        }
        return Data(result)
    }

    static let S: [Int] = [
        99, 124, 119, 123, 242, 107, 111, 197, 48, 1, 103, 43, 254, 215, 171, 118,
        202, 130, 201, 125, 250, 89, 71, 240, 173, 212, 162, 175, 156, 164, 114, 192,
        183, 253, 147, 38, 54, 63, 247, 204, 52, 165, 229, 241, 113, 216, 49, 21,
        4, 199, 35, 195, 24, 150, 5, 154, 7, 18, 128, 226, 235, 39, 178, 117,
        9, 131, 44, 26, 27, 110, 90, 160, 82, 59, 214, 179, 41, 227, 47, 132,
        83, 209, 0, 237, 32, 252, 177, 91, 106, 203, 190, 57, 74, 76, 88, 207,
        208, 239, 170, 251, 67, 77, 51, 133, 69, 249, 2, 127, 80, 60, 159, 168,
        81, 163, 64, 143, 146, 157, 56, 245, 188, 182, 218, 33, 16, 255, 243, 210,
        205, 12, 19, 236, 95, 151, 68, 23, 196, 167, 126, 61, 100, 93, 25, 115,
        96, 129, 79, 220, 34, 42, 144, 136, 70, 238, 184, 20, 222, 94, 11, 219,
        224, 50, 58, 10, 73, 6, 36, 92, 194, 211, 172, 98, 145, 149, 228, 121,
        231, 200, 55, 109, 141, 213, 78, 169, 108, 86, 244, 234, 101, 122, 174, 8,
        186, 120, 37, 46, 28, 166, 180, 198, 232, 221, 116, 31, 75, 189, 139, 138,
        112, 62, 181, 102, 72, 3, 246, 14, 97, 53, 87, 185, 134, 193, 29, 158,
        225, 248, 152, 17, 105, 217, 142, 148, 155, 30, 135, 233, 206, 85, 40, 223,
        140, 161, 137, 13, 191, 230, 66, 104, 65, 153, 45, 15, 176, 84, 187, 22
    ]

    static let T1: [Int] = [
        0xc66363a5, 0xf87c7c84, 0xee777799, 0xf67b7b8d, 0xfff2f20d, 0xd66b6bbd, 0xde6f6fb1, 0x91c5c554,
        0x60303050, 0x02010103, 0xce6767a9, 0x562b2b7d, 0xe7fefe19, 0xb5d7d762, 0x4dababe6, 0xec76769a,
        0x8fcaca45, 0x1f82829d, 0x89c9c940, 0xfa7d7d87, 0xeffafa15, 0xb25959eb, 0x8e4747c9, 0xfbf0f00b,
        0x41adadec, 0xb3d4d467, 0x5fa2a2fd, 0x45afafea, 0x239c9cbf, 0x53a4a4f7, 0xe4727296, 0x9bc0c05b,
        0x75b7b7c2, 0xe1fdfd1c, 0x3d9393ae, 0x4c26266a, 0x6c36365a, 0x7e3f3f41, 0xf5f7f702, 0x83cccc4f,
        0x6834345c, 0x51a5a5f4, 0xd1e5e534, 0xf9f1f108, 0xe2717193, 0xabd8d873, 0x62313153, 0x2a15153f,
        0x0804040c, 0x95c7c752, 0x46232365, 0x9dc3c35e, 0x30181828, 0x379696a1, 0x0a05050f, 0x2f9a9ab5,
        0x0e070709, 0x24121236, 0x1b80809b, 0xdfe2e23d, 0xcdebeb26, 0x4e272769, 0x7fb2b2cd, 0xea75759f,
        0x1209091b, 0x1d83839e, 0x582c2c74, 0x341a1a2e, 0x361b1b2d, 0xdc6e6eb2, 0xb45a5aee, 0x5ba0a0fb,
        0xa45252f6, 0x763b3b4d, 0xb7d6d661, 0x7db3b3ce, 0x5229297b, 0xdde3e33e, 0x5e2f2f71, 0x13848497,
        0xa65353f5, 0xb9d1d168, 0x00000000, 0xc1eded2c, 0x40202060, 0xe3fcfc1f, 0x79b1b1c8, 0xb65b5bed,
        0xd46a6abe, 0x8dcbcb46, 0x67bebed9, 0x7239394b, 0x944a4ade, 0x984c4cd4, 0xb05858e8, 0x85cfcf4a,
        0xbbd0d06b, 0xc5efef2a, 0x4faaaae5, 0xedfbfb16, 0x864343c5, 0x9a4d4dd7, 0x66333355, 0x11858594,
        0x8a4545cf, 0xe9f9f910, 0x04020206, 0xfe7f7f81, 0xa05050f0, 0x783c3c44, 0x259f9fba, 0x4ba8a8e3,
        0xa25151f3, 0x5da3a3fe, 0x804040c0, 0x058f8f8a, 0x3f9292ad, 0x219d9dbc, 0x70383848, 0xf1f5f504,
        0x63bcbcdf, 0x77b6b6c1, 0xafdada75, 0x42212163, 0x20101030, 0xe5ffff1a, 0xfdf3f30e, 0xbfd2d26d,
        0x81cdcd4c, 0x180c0c14, 0x26131335, 0xc3ecec2f, 0xbe5f5fe1, 0x359797a2, 0x884444cc, 0x2e171739,
        0x93c4c457, 0x55a7a7f2, 0xfc7e7e82, 0x7a3d3d47, 0xc86464ac, 0xba5d5de7, 0x3219192b, 0xe6737395,
        0xc06060a0, 0x19818198, 0x9e4f4fd1, 0xa3dcdc7f, 0x44222266, 0x542a2a7e, 0x3b9090ab, 0x0b888883,
        0x8c4646ca, 0xc7eeee29, 0x6bb8b8d3, 0x2814143c, 0xa7dede79, 0xbc5e5ee2, 0x160b0b1d, 0xaddbdb76,
        0xdbe0e03b, 0x64323256, 0x743a3a4e, 0x140a0a1e, 0x924949db, 0x0c06060a, 0x4824246c, 0xb85c5ce4,
        0x9fc2c25d, 0xbdd3d36e, 0x43acacef, 0xc46262a6, 0x399191a8, 0x319595a4, 0xd3e4e437, 0xf279798b,
        0xd5e7e732, 0x8bc8c843, 0x6e373759, 0xda6d6db7, 0x018d8d8c, 0xb1d5d564, 0x9c4e4ed2, 0x49a9a9e0,
        0xd86c6cb4, 0xac5656fa, 0xf3f4f407, 0xcfeaea25, 0xca6565af, 0xf47a7a8e, 0x47aeaee9, 0x10080818,
        0x6fbabad5, 0xf0787888, 0x4a25256f, 0x5c2e2e72, 0x381c1c24, 0x57a6a6f1, 0x73b4b4c7, 0x97c6c651,
        0xcbe8e823, 0xa1dddd7c, 0xe874749c, 0x3e1f1f21, 0x964b4bdd, 0x61bdbddc, 0x0d8b8b86, 0x0f8a8a85,
        0xe0707090, 0x7c3e3e42, 0x71b5b5c4, 0xcc6666aa, 0x904848d8, 0x06030305, 0xf7f6f601, 0x1c0e0e12,
        0xc26161a3, 0x6a35355f, 0xae5757f9, 0x69b9b9d0, 0x17868691, 0x99c1c158, 0x3a1d1d27, 0x279e9eb9,
        0xd9e1e138, 0xebf8f813, 0x2b9898b3, 0x22111133, 0xd26969bb, 0xa9d9d970, 0x078e8e89, 0x339494a7,
        0x2d9b9bb6, 0x3c1e1e22, 0x15878792, 0xc9e9e920, 0x87cece49, 0xaa5555ff, 0x50282878, 0xa5dfdf7a,
        0x038c8c8f, 0x59a1a1f8, 0x09898980, 0x1a0d0d17, 0x65bfbfda, 0xd7e6e631, 0x844242c6, 0xd06868b8,
        0x824141c3, 0x299999b0, 0x5a2d2d77, 0x1e0f0f11, 0x7bb0b0cb, 0xa85454fc, 0x6dbbbbd6, 0x2c16163a
    ]
    static let T2: [Int] = [
        0xa5c66363, 0x84f87c7c, 0x99ee7777, 0x8df67b7b, 0x0dfff2f2, 0xbdd66b6b, 0xb1de6f6f, 0x5491c5c5,
        0x50603030, 0x03020101, 0xa9ce6767, 0x7d562b2b, 0x19e7fefe, 0x62b5d7d7, 0xe64dabab, 0x9aec7676,
        0x458fcaca, 0x9d1f8282, 0x4089c9c9, 0x87fa7d7d, 0x15effafa, 0xebb25959, 0xc98e4747, 0x0bfbf0f0,
        0xec41adad, 0x67b3d4d4, 0xfd5fa2a2, 0xea45afaf, 0xbf239c9c, 0xf753a4a4, 0x96e47272, 0x5b9bc0c0,
        0xc275b7b7, 0x1ce1fdfd, 0xae3d9393, 0x6a4c2626, 0x5a6c3636, 0x417e3f3f, 0x02f5f7f7, 0x4f83cccc,
        0x5c683434, 0xf451a5a5, 0x34d1e5e5, 0x08f9f1f1, 0x93e27171, 0x73abd8d8, 0x53623131, 0x3f2a1515,
        0x0c080404, 0x5295c7c7, 0x65462323, 0x5e9dc3c3, 0x28301818, 0xa1379696, 0x0f0a0505, 0xb52f9a9a,
        0x090e0707, 0x36241212, 0x9b1b8080, 0x3ddfe2e2, 0x26cdebeb, 0x694e2727, 0xcd7fb2b2, 0x9fea7575,
        0x1b120909, 0x9e1d8383, 0x74582c2c, 0x2e341a1a, 0x2d361b1b, 0xb2dc6e6e, 0xeeb45a5a, 0xfb5ba0a0,
        0xf6a45252, 0x4d763b3b, 0x61b7d6d6, 0xce7db3b3, 0x7b522929, 0x3edde3e3, 0x715e2f2f, 0x97138484,
        0xf5a65353, 0x68b9d1d1, 0x00000000, 0x2cc1eded, 0x60402020, 0x1fe3fcfc, 0xc879b1b1, 0xedb65b5b,
        0xbed46a6a, 0x468dcbcb, 0xd967bebe, 0x4b723939, 0xde944a4a, 0xd4984c4c, 0xe8b05858, 0x4a85cfcf,
        0x6bbbd0d0, 0x2ac5efef, 0xe54faaaa, 0x16edfbfb, 0xc5864343, 0xd79a4d4d, 0x55663333, 0x94118585,
        0xcf8a4545, 0x10e9f9f9, 0x06040202, 0x81fe7f7f, 0xf0a05050, 0x44783c3c, 0xba259f9f, 0xe34ba8a8,
        0xf3a25151, 0xfe5da3a3, 0xc0804040, 0x8a058f8f, 0xad3f9292, 0xbc219d9d, 0x48703838, 0x04f1f5f5,
        0xdf63bcbc, 0xc177b6b6, 0x75afdada, 0x63422121, 0x30201010, 0x1ae5ffff, 0x0efdf3f3, 0x6dbfd2d2,
        0x4c81cdcd, 0x14180c0c, 0x35261313, 0x2fc3ecec, 0xe1be5f5f, 0xa2359797, 0xcc884444, 0x392e1717,
        0x5793c4c4, 0xf255a7a7, 0x82fc7e7e, 0x477a3d3d, 0xacc86464, 0xe7ba5d5d, 0x2b321919, 0x95e67373,
        0xa0c06060, 0x98198181, 0xd19e4f4f, 0x7fa3dcdc, 0x66442222, 0x7e542a2a, 0xab3b9090, 0x830b8888,
        0xca8c4646, 0x29c7eeee, 0xd36bb8b8, 0x3c281414, 0x79a7dede, 0xe2bc5e5e, 0x1d160b0b, 0x76addbdb,
        0x3bdbe0e0, 0x56643232, 0x4e743a3a, 0x1e140a0a, 0xdb924949, 0x0a0c0606, 0x6c482424, 0xe4b85c5c,
        0x5d9fc2c2, 0x6ebdd3d3, 0xef43acac, 0xa6c46262, 0xa8399191, 0xa4319595, 0x37d3e4e4, 0x8bf27979,
        0x32d5e7e7, 0x438bc8c8, 0x596e3737, 0xb7da6d6d, 0x8c018d8d, 0x64b1d5d5, 0xd29c4e4e, 0xe049a9a9,
        0xb4d86c6c, 0xfaac5656, 0x07f3f4f4, 0x25cfeaea, 0xafca6565, 0x8ef47a7a, 0xe947aeae, 0x18100808,
        0xd56fbaba, 0x88f07878, 0x6f4a2525, 0x725c2e2e, 0x24381c1c, 0xf157a6a6, 0xc773b4b4, 0x5197c6c6,
        0x23cbe8e8, 0x7ca1dddd, 0x9ce87474, 0x213e1f1f, 0xdd964b4b, 0xdc61bdbd, 0x860d8b8b, 0x850f8a8a,
        0x90e07070, 0x427c3e3e, 0xc471b5b5, 0xaacc6666, 0xd8904848, 0x05060303, 0x01f7f6f6, 0x121c0e0e,
        0xa3c26161, 0x5f6a3535, 0xf9ae5757, 0xd069b9b9, 0x91178686, 0x5899c1c1, 0x273a1d1d, 0xb9279e9e,
        0x38d9e1e1, 0x13ebf8f8, 0xb32b9898, 0x33221111, 0xbbd26969, 0x70a9d9d9, 0x89078e8e, 0xa7339494,
        0xb62d9b9b, 0x223c1e1e, 0x92158787, 0x20c9e9e9, 0x4987cece, 0xffaa5555, 0x78502828, 0x7aa5dfdf,
        0x8f038c8c, 0xf859a1a1, 0x80098989, 0x171a0d0d, 0xda65bfbf, 0x31d7e6e6, 0xc6844242, 0xb8d06868,
        0xc3824141, 0xb0299999, 0x775a2d2d, 0x111e0f0f, 0xcb7bb0b0, 0xfca85454, 0xd66dbbbb, 0x3a2c1616,
    ]

    static let T3: [Int] = T1.map { (($0 << 16) & 0xFFFFFFFF) | (($0 >> 16) & 0xFFFF) }
    static let T4: [Int] = [
        0x6363a5c6, 0x7c7c84f8, 0x777799ee, 0x7b7b8df6, 0xf2f20dff, 0x6b6bbdd6, 0x6f6fb1de, 0xc5c55491,
        0x30305060, 0x01010302, 0x6767a9ce, 0x2b2b7d56, 0xfefe19e7, 0xd7d762b5, 0xababe64d, 0x76769aec,
        0xcaca458f, 0x82829d1f, 0xc9c94089, 0x7d7d87fa, 0xfafa15ef, 0x5959ebb2, 0x4747c98e, 0xf0f00bfb,
        0xadadec41, 0xd4d467b3, 0xa2a2fd5f, 0xafafea45, 0x9c9cbf23, 0xa4a4f753, 0x727296e4, 0xc0c05b9b,
        0xb7b7c275, 0xfdfd1ce1, 0x9393ae3d, 0x26266a4c, 0x36365a6c, 0x3f3f417e, 0xf7f702f5, 0xcccc4f83,
        0x34345c68, 0xa5a5f451, 0xe5e534d1, 0xf1f108f9, 0x717193e2, 0xd8d873ab, 0x31315362, 0x15153f2a,
        0x04040c08, 0xc7c75295, 0x23236546, 0xc3c35e9d, 0x18182830, 0x9696a137, 0x05050f0a, 0x9a9ab52f,
        0x0707090e, 0x12123624, 0x80809b1b, 0xe2e23ddf, 0xebeb26cd, 0x2727694e, 0xb2b2cd7f, 0x75759fea,
        0x09091b12, 0x83839e1d, 0x2c2c7458, 0x1a1a2e34, 0x1b1b2d36, 0x6e6eb2dc, 0x5a5aeeb4, 0xa0a0fb5b,
        0x5252f6a4, 0x3b3b4d76, 0xd6d661b7, 0xb3b3ce7d, 0x29297b52, 0xe3e33edd, 0x2f2f715e, 0x84849713,
        0x5353f5a6, 0xd1d168b9, 0x00000000, 0xeded2cc1, 0x20206040, 0xfcfc1fe3, 0xb1b1c879, 0x5b5bedb6,
        0x6a6abed4, 0xcbcb468d, 0xbebed967, 0x39394b72, 0x4a4ade94, 0x4c4cd498, 0x5858e8b0, 0xcfcf4a85,
        0xd0d06bbb, 0xefef2ac5, 0xaaaae54f, 0xfbfb16ed, 0x4343c586, 0x4d4dd79a, 0x33335566, 0x85859411,
        0x4545cf8a, 0xf9f910e9, 0x02020604, 0x7f7f81fe, 0x5050f0a0, 0x3c3c4478, 0x9f9fba25, 0xa8a8e34b,
        0x5151f3a2, 0xa3a3fe5d, 0x4040c080, 0x8f8f8a05, 0x9292ad3f, 0x9d9dbc21, 0x38384870, 0xf5f504f1,
        0xbcbcdf63, 0xb6b6c177, 0xdada75af, 0x21216342, 0x10103020, 0xffff1ae5, 0xf3f30efd, 0xd2d26dbf,
        0xcdcd4c81, 0x0c0c1418, 0x13133526, 0xecec2fc3, 0x5f5fe1be, 0x9797a235, 0x4444cc88, 0x1717392e,
        0xc4c45793, 0xa7a7f255, 0x7e7e82fc, 0x3d3d477a, 0x6464acc8, 0x5d5de7ba, 0x19192b32, 0x737395e6,
        0x6060a0c0, 0x81819819, 0x4f4fd19e, 0xdcdc7fa3, 0x22226644, 0x2a2a7e54, 0x9090ab3b, 0x8888830b,
        0x4646ca8c, 0xeeee29c7, 0xb8b8d36b, 0x14143c28, 0xdede79a7, 0x5e5ee2bc, 0x0b0b1d16, 0xdbdb76ad,
        0xe0e03bdb, 0x32325664, 0x3a3a4e74, 0x0a0a1e14, 0x4949db92, 0x06060a0c, 0x24246c48, 0x5c5ce4b8,
        0xc2c25d9f, 0xd3d36ebd, 0xacacef43, 0x6262a6c4, 0x9191a839, 0x9595a431, 0xe4e437d3, 0x79798bf2,
        0xe7e732d5, 0xc8c8438b, 0x3737596e, 0x6d6db7da, 0x8d8d8c01, 0xd5d564b1, 0x4e4ed29c, 0xa9a9e049,
        0x6c6cb4d8, 0x5656faac, 0xf4f407f3, 0xeaea25cf, 0x6565afca, 0x7a7a8ef4, 0xaeaee947, 0x08081810,
        0xbabad56f, 0x787888f0, 0x25256f4a, 0x2e2e725c, 0x1c1c2438, 0xa6a6f157, 0xb4b4c773, 0xc6c65197,
        0xe8e823cb, 0xdddd7ca1, 0x74749ce8, 0x1f1f213e, 0x4b4bdd96, 0xbdbddc61, 0x8b8b860d, 0x8a8a850f,
        0x707090e0, 0x3e3e427c, 0xb5b5c471, 0x6666aacc, 0x4848d890, 0x03030506, 0xf6f601f7, 0x0e0e121c,
        0x6161a3c2, 0x35355f6a, 0x5757f9ae, 0xb9b9d069, 0x86869117, 0xc1c15899, 0x1d1d273a, 0x9e9eb927,
        0xe1e138d9, 0xf8f813eb, 0x9898b32b, 0x11113322, 0x6969bbd2, 0xd9d970a9, 0x8e8e8907, 0x9494a733,
        0x9b9bb62d, 0x1e1e223c, 0x87879215, 0xe9e920c9, 0xcece4987, 0x5555ffaa, 0x28287850, 0xdfdf7aa5,
        0x8c8c8f03, 0xa1a1f859, 0x89898009, 0x0d0d171a, 0xbfbfda65, 0xe6e631d7, 0x4242c684, 0x6868b8d0,
        0x4141c382, 0x9999b029, 0x2d2d775a, 0x0f0f111e, 0xb0b0cb7b, 0x5454fca8, 0xbbbbd66d, 0x16163a2c,
    ]

    static let rcon: [Int] = [
        0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36,
        0x6c, 0xd8, 0xab, 0x4d, 0x9a, 0x2f, 0x5e, 0xbc, 0x63, 0xc6,
        0x97, 0x35, 0x6a, 0xd4, 0xb3, 0x7d, 0xfa, 0xef, 0xc5, 0x91
    ]
}

extension Data {
    init(hex: String) {
        self = Data(hexString: hex) ?? Data()
    }

    init?(hexString: String) {
        let s = hexString.replacingOccurrences(of: " ", with: "")
        guard s.count % 2 == 0 else { return nil }
        var d = Data()
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let b = UInt8(s[i..<j], radix: 16) else { return nil }
            d.append(b)
            i = j
        }
        self = d
    }

    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
