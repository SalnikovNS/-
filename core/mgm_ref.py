from kuznechik_ref import expand_key, encrypt_block, TEST_KEY

MASK128 = (1 << 128) - 1

def gf128_mul(a, b):
    r = 0
    for i in range(127, -1, -1):
        r <<= 1
        if r >> 128:
            r = (r & MASK128) ^ 0x87
        if (b >> i) & 1:
            r ^= a
    return r

def _incr_r(x):
    return (x & ~((1 << 64) - 1)) | ((x + 1) & ((1 << 64) - 1))

def _incr_l(x):
    return ((((x >> 64) + 1) & ((1 << 64) - 1)) << 64) | (x & ((1 << 64) - 1))

def mgm_encrypt(key, icn, aad, plaintext, tag_len=16):
    assert len(icn) == 16 and icn[0] < 0x80
    rk = expand_key(key)
    E = lambda x: int.from_bytes(encrypt_block(rk, x.to_bytes(16, "big")), "big")
    n = int.from_bytes(icn, "big")

    y = E(n)
    ct = bytearray()
    for off in range(0, len(plaintext), 16):
        g = E(y).to_bytes(16, "big")
        ct += bytes(p ^ k for p, k in zip(plaintext[off:off + 16], g))
        y = _incr_r(y)
    ct = bytes(ct)
    return ct, _mgm_tag(E, n, aad, ct, tag_len)

def _mgm_tag(E, n, aad, ct, tag_len):
    z = E(n | (1 << 127))
    acc = 0
    for data in (aad, ct):
        for off in range(0, len(data), 16):
            blk = data[off:off + 16].ljust(16, b"\x00")
            acc ^= gf128_mul(E(z), int.from_bytes(blk, "big"))
            z = _incr_l(z)
    lens = ((len(aad) * 8) << 64) | (len(ct) * 8)
    acc ^= gf128_mul(E(z), lens)
    return E(acc).to_bytes(16, "big")[:tag_len]

def mgm_decrypt(key, icn, aad, ciphertext, tag):
    rk = expand_key(key)
    E = lambda x: int.from_bytes(encrypt_block(rk, x.to_bytes(16, "big")), "big")
    n = int.from_bytes(icn, "big")
    if _mgm_tag(E, n, aad, ciphertext, len(tag)) != tag:
        return None
    y = E(n)
    pt = bytearray()
    for off in range(0, len(ciphertext), 16):
        g = E(y).to_bytes(16, "big")
        pt += bytes(c ^ k for c, k in zip(ciphertext[off:off + 16], g))
        y = _incr_r(y)
    return bytes(pt)

V_ICN = bytes.fromhex("1122334455667700FFEEDDCCBBAA9988")
V_AAD = bytes.fromhex(
    "0202020202020202" "0101010101010101" "0404040404040404" "0303030303030303"
    "EA0505050505050505")
V_PT = bytes.fromhex(
    "1122334455667700FFEEDDCCBBAA9988" "00112233445566778899AABBCCEEFF0A"
    "112233445566778899AABBCCEEFF0A00" "2233445566778899AABBCCEEFF0A0011" "AABBCC")
V_CT = bytes.fromhex(
    "A9757B8147956E9055B8A33DE89F42FC" "8075D2212BF9FD5BD3F7069AADC16B39"
    "497AB15915A6BA85936B5D0EA9F6851C" "C60C14D4D3F883D0AB94420695C76DEB" "2C7552")
V_TAG = bytes.fromhex("CF5D656F40C34F5C46E8BB0E29FCDB4C")

def self_test():
    ct, tag = mgm_encrypt(TEST_KEY, V_ICN, V_AAD, V_PT)
    assert ct == V_CT, ct.hex()
    assert tag == V_TAG, tag.hex()
    assert mgm_decrypt(TEST_KEY, V_ICN, V_AAD, ct, tag) == V_PT
    assert mgm_decrypt(TEST_KEY, V_ICN, V_AAD, ct[:-1] + bytes([ct[-1] ^ 1]), tag) is None

if __name__ == "__main__":
    self_test()
    print("mgm_ref self-test: OK (RFC 9058 A.1, Kuznyechik MGM)")
