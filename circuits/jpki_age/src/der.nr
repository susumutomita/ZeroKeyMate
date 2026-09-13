pub struct Node { pub content: u32, pub end: u32, pub tag: u8 }
pub fn node(bytes: [u8; 2048], offset: u32, limit: u32) -> Node {
    assert(limit <= 2048); assert(offset + 2 <= limit);
    let tag = bytes[offset]; assert((tag & 31) != 31, "High tag unsupported");
    let first = bytes[offset + 1];
    let mut content = offset + 2; let mut length = first as u32;
    if first == 129 {
        assert(content < limit); length = bytes[content] as u32; content += 1;
        assert(length >= 128, "Nonminimal length");
    } else if first == 130 {
        assert(content + 2 <= limit);
        length = bytes[content] as u32 * 256 + bytes[content + 1] as u32; content += 2;
        assert(length >= 256, "Nonminimal length");
    } else { assert(first < 128, "Unsupported DER length"); }
    assert(content + length <= limit, "Truncated DER");
    Node {content, end: content + length, tag}
}
pub fn expect(bytes: [u8; 2048], offset: u32, limit: u32, tag: u8) -> Node {
    let value = node(bytes,offset,limit); assert(value.tag == tag, "Unexpected DER tag"); value
}
pub fn take<let N: u32>(bytes: [u8; 2048], start: u32, limit: u32) -> [u8; N] {
    assert(start + N <= limit); assert(limit <= 2048);
    let mut out = [0; N]; for i in 0..N {out[i] = bytes[start+i];} out
}
pub fn same<let N: u32>(bytes: [u8; 2048], value: Node, expected: [u8; N]) -> bool {
    let mut equal = value.end - value.content == N;
    for i in 0..N {
        if value.content + i < value.end {equal = equal & (bytes[value.content+i] == expected[i]);}
        else {equal = false;}
    }
    equal
}
