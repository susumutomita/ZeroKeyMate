use crate::der::{expect,node,take,same,Node};
use crate::date::utc_time;

// This is a deliberately narrow JPKI signing-certificate profile parser, not a
// general X.509 implementation. Every extraction is anchored in the signed TBS.
pub fn fields(bytes: [u8; 2048], length: u32, reference_time: u64, expires_at: u64) -> ([u8;256],[u8;8]) {
    let outer = expect(bytes,0,length,48); assert(outer.end == length);
    let version = expect(bytes,outer.content,outer.end,160);
    assert(same(bytes,version,[2,1,2]), "Version 3 required");
    let serial = expect(bytes,version.end,outer.end,2);
    assert((serial.end > serial.content) & (serial.end - serial.content <= 20));
    assert(bytes[serial.content] < 128);
    assert((serial.end-serial.content > 1) | (bytes[serial.content] != 0));
    if serial.end - serial.content > 1 {assert((bytes[serial.content] != 0) | (bytes[serial.content+1] >= 128));}
    let algorithm = expect(bytes,serial.end,outer.end,48);
    assert(same(bytes,algorithm,[6,9,42,134,72,134,247,13,1,1,11,5,0]), "RSA SHA256 required");
    let issuer = expect(bytes,algorithm.end,outer.end,48);
    let validity = expect(bytes,issuer.end,outer.end,48);
    let before = expect(bytes,validity.content,validity.end,23); assert(before.end-before.content == 13);
    let after = expect(bytes,before.end,validity.end,23); assert(after.end-after.content == 13); assert(after.end == validity.end);
    assert(utc_time(take::<13>(bytes,before.content,before.end)) <= reference_time + 62135596800);
    assert(utc_time(take::<13>(bytes,after.content,after.end)) >= expires_at + 62135596800);
    let subject = expect(bytes,validity.end,outer.end,48);
    let spki = expect(bytes,subject.end,outer.end,48);
    let key_algorithm = expect(bytes,spki.content,spki.end,48);
    assert(same(bytes,key_algorithm,[6,9,42,134,72,134,247,13,1,1,1,5,0]));
    let key_bits = expect(bytes,key_algorithm.end,spki.end,3); assert(key_bits.end == spki.end);
    assert(bytes[key_bits.content] == 0);
    let key = expect(bytes,key_bits.content+1,key_bits.end,48); assert(key.end == key_bits.end);
    let modulus = expect(bytes,key.content,key.end,2); assert(modulus.end-modulus.content == 257);
    assert(bytes[modulus.content] == 0); assert(bytes[modulus.content+1] >= 128);
    let exponent = expect(bytes,modulus.end,key.end,2); assert(exponent.end == key.end);
    assert(same(bytes,exponent,[1,0,1]), "Exponent 65537 required");
    let card_key = take::<256>(bytes,modulus.content+1,modulus.end);
    let extensions = expect(bytes,spki.end,outer.end,163); assert(extensions.end == outer.end);
    let sequence = expect(bytes,extensions.content,extensions.end,48); assert(sequence.end == extensions.end);
    let mut cursor = sequence.content; let mut found_san = false; let mut found_usage = false;
    let mut birth_date: [u8;8] = [0;8];
    let mut seen_oid: [u128;24] = [0;24];
    let mut seen_length: [u32;24] = [0;24];
    for extension_index in 0..24 {
        if cursor < sequence.end {
            let extension = expect(bytes,cursor,sequence.end,48);
            let oid = expect(bytes,extension.content,extension.end,6);
            let oid_length = oid.end-oid.content;
            assert((oid_length > 0) & (oid_length <= 16), "Unsupported extension OID");
            let mut oid_value: u128 = 0;
            for i in 0..16 { if i < oid_length {oid_value = oid_value * 256 + (bytes[oid.content+i] as u128);} }
            for i in 0..24 { if i < extension_index {
                assert((seen_length[i] != oid_length) | (seen_oid[i] != oid_value), "Duplicate extension");
            } }
            seen_length[extension_index] = oid_length; seen_oid[extension_index] = oid_value;
            let mut value = node(bytes,oid.end,extension.end); let mut critical = false;
            if value.tag == 1 {
                assert(same(bytes,value,[255]), "DER default false must be omitted"); critical = true;
                value = node(bytes,value.end,extension.end);
            }
            assert(value.tag == 4); assert(value.end == extension.end);
            if same(bytes,oid,[85,29,17]) {
                assert(!found_san, "Duplicate SAN"); found_san = true;
                birth_date = san(bytes,value);
            } else if same(bytes,oid,[85,29,15]) {
                assert(!found_usage, "Duplicate key usage"); found_usage = true;
                assert(critical); assert(same(bytes,value,[3,2,6,192]), "Signing key usage required");
            } else {assert(!critical, "Unknown critical extension");}
            cursor = extension.end;
        }
    }
    assert(cursor == sequence.end, "Too many extensions");
    assert(found_san & found_usage, "Missing age or key usage");
    (card_key,birth_date)
}

fn san(bytes: [u8;2048], extension: Node) -> [u8;8] {
    let names = expect(bytes,extension.content,extension.end,48); assert(names.end == extension.end);
    let mut cursor = names.content; let mut found = false; let mut dob: [u8;8] = [0;8];
    for _ in 0..16 {
        if cursor < names.end {
            let name = expect(bytes,cursor,names.end,160);
            let oid = expect(bytes,name.content,name.end,6);
            let wrapped = expect(bytes,oid.end,name.end,160); assert(wrapped.end == name.end);
            let value = node(bytes,wrapped.content,wrapped.end); assert(value.end == wrapped.end);
            // 1.2.392.200149.8.5.5.4, from the official J-LIS profile.
            if same(bytes,oid,[42,131,8,140,155,85,8,5,5,4]) {
                assert(!found, "Duplicate birth date"); found = true;
                assert(value.tag == 12); assert(value.end-value.content == 9);
                // E is the era-code digit (0...5), not a literal ASCII E.
                assert((bytes[value.content] >= 48) & (bytes[value.content] <= 53));
                dob = take::<8>(bytes,value.content+1,value.end);
            }
            cursor = name.end;
        }
    }
    assert(cursor == names.end); assert(found, "Missing signed birth date"); dob
}
