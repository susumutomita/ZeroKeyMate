// SHA-256 padding and byte packing are constrained directly. Only the standard
// SHA-256 compression black box is used; there is no unconstrained padding hint.
pub fn digest<let N: u32>(bytes: [u8;N]) -> [u8;32] { sha256_var(bytes,N) }

pub fn sha256_var<let N: u32>(bytes: [u8;N], length: u32) -> [u8;32] {
    assert(length <= N);
    let block_count = (length + 72) / 64;
    let padded_length = block_count * 64;
    let bit_length = length * 8;
    let mut state: [u32;8] = [
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    ];
    for block in 0..((N+72)/64) {
        let mut words: [u32;16] = [0;16];
        for offset in 0..64 {
            let index = block*64+offset;
            let mut byte: u8 = 0;
            if index < N { if index < length {byte = bytes[index];} }
            if index == length {byte = 128;}
            for i in 0..8 {
                if index == padded_length-8+i {
                    byte = if i < 4 {0} else {((bit_length >> ((7-i)*8)) & 255) as u8};
                }
            }
            words[offset/4] = (words[offset/4] << 8) | (byte as u32);
        }
        let next = std::hash::sha256_compression(words,state);
        if block < block_count {state = next;}
    }
    let mut output: [u8;32] = [0;32];
    for i in 0..32 {
        output[i] = ((state[i/4] >> (((3-i%4)*8) as u32)) & 255) as u8;
    }
    output
}
