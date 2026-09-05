use dep::sha256::sha256;

// Public statements are extracted from the VERIFIED proof by the execution
// service, never trusted from the transport envelope. All integers are unsigned.
fn main(
    policy_hash: pub [u8; 32],
    action_hash: pub [u8; 32],
    spent: pub u64,
    amount: pub u64,
    service: pub u8,
    budget: u64,
    services: u8,
    salt: [u8; 32],
    context: [u8; 160],
) {
    assert(budget > 0);
    assert(amount > 0);
    assert(spent <= budget);
    // Subtract first: addition must not wrap before the range check.
    assert(amount <= budget - spent);
    assert(service < 2);
    assert((services & (1 << service)) != 0);
    assert(services > 0);
    assert(services <= 3);

    // ZKM-POL1 || budget:u64be || services:u8 || random-salt:32.
    let mut policy = [0 as u8; 49];
    let policy_domain = [90, 75, 77, 45, 80, 79, 76, 49];
    for i in 0..8 { policy[i] = policy_domain[i]; }
    for i in 0..8 { policy[8 + i] = ((budget >> ((7 - i) * 8)) & 255) as u8; }
    policy[16] = services;
    for i in 0..32 { policy[17 + i] = salt[i]; }
    assert(sha256(policy) == policy_hash);

    // context = ZKM-ACT1 || chain:u64be || vault:20 || mandate-id:32 ||
    // recipient:20 || action-nonce:32 || expires:u64be || payload-sha256:32.
    // Bind the spent snapshot, amount and service to the exact execution.
    let expected_domain = [90, 75, 77, 45, 65, 67, 84, 49];
    for i in 0..8 { assert(context[i] == expected_domain[i]); }
    let mut action = [0 as u8; 177];
    for i in 0..160 { action[i] = context[i]; }
    for i in 0..8 {
        action[160 + i] = ((spent >> ((7 - i) * 8)) & 255) as u8;
        action[168 + i] = ((amount >> ((7 - i) * 8)) & 255) as u8;
    }
    action[176] = service;
    assert(sha256(action) == action_hash);
}
