# Recovery and rollback

Read this page before changing firmware variables.

## Prepare before the change

- Back up important files to storage that does not depend on the target laptop.
- Save the BitLocker recovery key and verify that the recorded key can be read.
- Record the exact model, BIOS version, Secure Boot state, and storage-encryption state.
- Download the current Dell BIOS installer and record its SHA-256.
- Read the Dell recovery procedure for the exact model.
- Keep the AC adapter connected and battery charged.
- Record every original variable byte before changing it.
- Keep a second computer and a second USB drive available when practical.

The toolkit cannot guarantee that a specific model supports recovery or that recovery will undo an NVRAM-variable change.

## First response to an unstable undervolt

If Windows still starts:

1. stop ThrottleStop from applying the profile;
2. restore voltage, turbo, and package-power controls to the last known-good or stock values;
3. remove automatic startup until validation is complete;
4. check Windows Event Viewer for WHEA events;
5. repeat cold-boot and sleep/resume testing.

If Windows does not start but firmware setup is available, use the platform's normal boot and recovery options before attempting more invasive steps.

## Restore manually changed firmware variables

Use the worksheet to restore only the exact bytes you changed, in the exact variable identity originally recorded. Do not guess an offset from memory. Confirm the current value before writing the recorded original value.

Loading BIOS defaults may or may not restore hidden NVRAM variables. A BIOS update may or may not replace them. Treat either operation as model-specific rather than a guaranteed rollback.

## BitLocker recovery

Firmware, Secure Boot, TPM, or boot-chain changes can cause Windows to request the BitLocker recovery key. Enter only the key that matches the identifier shown by the recovery screen. Do not post recovery keys, key identifiers, or screenshots containing them in a public issue.

## Dell BIOS recovery

Dell publishes model-dependent BIOS recovery procedures. Use the official procedure for the exact computer and do not assume the key combination or recovery-file naming is identical across models. A recovery image may repair firmware code without restoring every variable changed manually.

## When the machine does not POST

Stop repeated speculative writes. Disconnecting power or clearing settings is not a universal fix and can make diagnosis harder. At that point the appropriate path may involve official support, a board-level SPI programmer, or a qualified repair technician. Board-level recovery can require disassembly and carries additional risk.

## Post-recovery verification

After any recovery operation:

- confirm the BIOS version and date;
- restore the intended Secure Boot policy;
- verify BitLocker protection state;
- check boot order and storage mode;
- confirm that every manually edited variable has its expected original value;
- test sleep, resume, shutdown, cold boot, battery operation, and a stock workload.
