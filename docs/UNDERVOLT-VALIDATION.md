# Undervolt validation

Firmware access and undervolt stability are separate questions. Unlocking a control only makes a setting adjustable; it does not establish a safe voltage for the silicon, workload, temperature, battery state, or power adapter.

## Establish a baseline

Before changing voltage or power settings, record:

- room temperature and cooling configuration;
- idle temperatures and package power;
- sustained workload temperatures, clocks, power limits, and throttle flags;
- benchmark score and elapsed time;
- Windows Event Viewer WHEA entries;
- BIOS, driver, ThrottleStop, and monitoring-tool versions.

Use the same workload and approximate conditions for comparisons.

## Change one category at a time

Treat these as separate controls:

- CPU core voltage offset;
- CPU cache voltage offset;
- integrated GPU and unslice voltage offsets;
- turbo ratios;
- long and short package power limits;
- turbo time window;
- fan policy.

Changing several at once makes failures difficult to diagnose. Begin close to stock, use small steps, and keep a written log.

## Minimum test matrix

A candidate profile should survive:

1. repeated idle-to-load transitions;
2. a short benchmark that makes regressions visible;
3. a sustained CPU workload;
4. the real rendering, compilation, simulation, or gaming workload;
5. AC adapter and battery operation;
6. sleep and resume;
7. shutdown and cold boot;
8. restart after the machine has cooled;
9. several normal work sessions, not only one stress test.

Watch for more than crashes. Instability can appear as WHEA warnings, application errors, corrupted output, silent calculation errors, video-driver resets, failed sleep/resume, or a machine that boots only on the second attempt.

## Stop conditions

Return to the last known-good value when any of these occur:

- WHEA hardware-error events;
- freeze, blue screen, spontaneous restart, or application crash;
- visual corruption or GPU reset;
- benchmark result becomes inconsistent without a thermal explanation;
- sleep, resume, shutdown, or cold boot fails;
- a firmware or software update changes behaviour;
- the profile is stable on AC but not battery, or vice versa.

## Tutorial values are not defaults

The video demonstrated approximately `-120 mV` core, `-80 mV` cache, and about `-25 mV` for the integrated graphics-related offsets on one i5-10300H system. Those values are observations from that machine, not a starting point guaranteed for another CPU. Silicon quality and firmware behaviour vary even within one model.

## Keep a stock escape path

Retain a known-stock ThrottleStop profile and know how to prevent the application from starting automatically. Do not enable automatic startup until the profile has survived cold boots and normal workloads. Keep the firmware-variable worksheet and original bytes separately from the laptop.
