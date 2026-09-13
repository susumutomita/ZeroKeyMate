// Gregorian calendar arithmetic. All dates are complete, with no unknown digits.
pub fn leap(year: u32) -> bool { (year % 4 == 0) & ((year % 100 != 0) | (year % 400 == 0)) }
pub fn month_days(year: u32, month: u32) -> u32 {
    assert((month >= 1) & (month <= 12));
    let lengths: [u32; 12] = [31,28,31,30,31,30,31,31,30,31,30,31];
    lengths[month - 1] + if (month == 2) & leap(year) { 1 } else { 0 }
}
pub fn ordinal(year: u32, month: u32, day: u32) -> u64 {
    assert((year >= 1) & (year <= 9999));
    assert((day >= 1) & (day <= month_days(year, month)));
    let y = year - 1;
    let mut days = 365 * y + y / 4 - y / 100 + y / 400 + day - 1;
    for m in 1..12 { if m < month { days += month_days(year, m); } }
    days as u64
}
pub fn number<let N: u32>(bytes: [u8; N]) -> u32 {
    let mut n: u32 = 0;
    for b in bytes { assert((b >= 48) & (b <= 57)); n = n * 10 + (b - 48) as u32; }
    n
}
pub fn adult(dob: [u8; 8], reference_time: u64) {
    let year = number([dob[0],dob[1],dob[2],dob[3]]);
    let month = number([dob[4],dob[5]]); let day = number([dob[6],dob[7]]);
    assert((year >= 1900) & (year <= 2099));
    let _ = ordinal(year, month, day);
    // March 1 is a conservative boundary for a leap-day twentieth anniversary
    // in a non-leap year. This prototype does not claim legal age-policy advice.
    let non_leap_anniversary = (month == 2) & (day == 29) & !leap(year + 20);
    let anniversary = ordinal(year + 20, if non_leap_anniversary {3} else {month}, if non_leap_anniversary {1} else {day});
    assert(anniversary <= (reference_time + 32400) / 86400 + 719162, "Under twenty");
}
pub fn utc_time(bytes: [u8; 13]) -> u64 {
    assert(bytes[12] == 90);
    let yy = number([bytes[0],bytes[1]]);
    let year = if yy < 50 {2000 + yy} else {1900 + yy};
    let month = number([bytes[2],bytes[3]]); let day = number([bytes[4],bytes[5]]);
    let hour = number([bytes[6],bytes[7]]); let minute = number([bytes[8],bytes[9]]); let second = number([bytes[10],bytes[11]]);
    assert((hour < 24) & (minute < 60) & (second < 60));
    ordinal(year,month,day) * 86400 + (hour * 3600 + minute * 60 + second) as u64
}
