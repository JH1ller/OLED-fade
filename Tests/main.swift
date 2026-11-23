import Foundation

var assertions = 0
func expect(_ actual: IdlePolicy.Change, _ expected: IdlePolicy.Change, _ message: String) {
    assertions += 1
    guard actual == expected else { fatalError("\(message): got \(actual), expected \(expected)") }
}

var policy = IdlePolicy(now: 0)
expect(policy.sample(now: 119.99, idle: 119.99), .none, "Wait two full minutes")
expect(policy.sample(now: 120, idle: 120), .show, "Black out at two minutes")
expect(policy.sample(now: 180, idle: 180), .none, "Stay black with no activity")
expect(policy.sample(now: 180.01, idle: 0.001), .hide, "Wake on new input")
expect(policy.sample(now: 181, idle: 0.991), .none, "Do not immediately black out again")
expect(policy.sample(now: 300.02, idle: 120.011), .show, "Black out after the next idle period")
expect(policy.configure(enabled: false, suspended: false, now: 301), .hide, "Disabling clears overlay")
expect(policy.sample(now: 1000, idle: 800), .none, "Disabled stays clear")
expect(policy.configure(enabled: true, suspended: false, now: 1000), .none, "Enable")
expect(policy.sample(now: 1001, idle: 801), .none, "Enabling restarts countdown")
expect(policy.sample(now: 1120, idle: 920), .show, "Full countdown after enabling")
expect(policy.configure(enabled: true, suspended: true, now: 1121), .hide, "Sleep/lock clears overlay")
expect(policy.sample(now: 2000, idle: 1800), .none, "Suspended stays clear")
expect(policy.configure(enabled: true, suspended: false, now: 2000), .none, "Resume")
expect(policy.sample(now: 2001, idle: 1801), .none, "Resume grants a fresh countdown")
expect(policy.blackOut(now: 2002, idle: 0.01), .show, "Manual blackout")
expect(policy.sample(now: 2002.1, idle: 0.11), .none, "Manual blackout stays until activity")
expect(policy.sample(now: 2002.2, idle: 0.01), .hide, "Manual blackout wakes on input")
expect(policy.blackOut(now: 2003, idle: 0.5), .show, "Manual blackout again")
expect(policy.sample(now: 2003.02, idle: 0.518), .none, "Tolerate query jitter")
expect(policy.sample(now: 2004, idle: .nan), .hide, "Invalid idle query fails open")
expect(policy.blackOut(now: 2005, idle: .infinity), .none, "Reject invalid manual sample")
expect(policy.configure(enabled: false, suspended: false, now: 2006), .none, "Pause")
expect(policy.blackOut(now: 2007, idle: 0), .none, "No manual overlay while paused")

for delay in BlackoutDelay.allCases {
    var preset = IdlePolicy(timeout: delay.seconds, now: 0)
    expect(preset.sample(now: delay.seconds - 0.01, idle: delay.seconds - 0.01), .none,
           "Wait the full \(delay.title)")
    expect(preset.sample(now: delay.seconds, idle: delay.seconds), .show,
           "Black out at \(delay.title)")
    expect(preset.sample(now: delay.seconds + 1, idle: 0), .hide,
           "Wake normally with the \(delay.title) preset")
}

var changing = IdlePolicy(now: 0)
expect(changing.sample(now: 119, idle: 119), .none, "Start with the default countdown")
expect(changing.setTimeout(60, now: 119), .none, "Shorten the delay")
expect(changing.sample(now: 120, idle: 120), .none, "Changing delay starts a fresh countdown")
expect(changing.sample(now: 179, idle: 179), .show, "Use the shorter delay after rearming")
expect(changing.setTimeout(300, now: 180), .hide, "Changing delay clears an existing overlay")
expect(changing.sample(now: 479.99, idle: 479.99), .none, "Wait the full longer delay")
expect(changing.sample(now: 480, idle: 480), .show, "Use the longer delay")
expect(changing.configure(enabled: false, suspended: false, now: 481), .hide, "Pause before changing delay")
expect(changing.setTimeout(180, now: 482), .none, "Change delay while paused")
expect(changing.sample(now: 1000, idle: 1000), .none, "Delay change must not enable monitoring")
expect(changing.configure(enabled: true, suspended: false, now: 1001), .none, "Reenable with saved delay")
expect(changing.sample(now: 1180.99, idle: 1180.99), .none, "Respect changed delay on reenable")
expect(changing.sample(now: 1181, idle: 1181), .show, "Black out at saved delay on reenable")

for savedMinutes in [-1, 0, 4, 999] {
    let restored = BlackoutDelay(savedMinutes: savedMinutes)
    var recovered = IdlePolicy(timeout: restored.seconds, now: 0)
    expect(recovered.sample(now: 119, idle: 119), .none, "Invalid preference uses the two-minute default")
    expect(recovered.sample(now: 120, idle: 120), .show, "Recovered preference blacks out after two minutes")
}

print("Passed \(assertions) idle-policy assertions.")
