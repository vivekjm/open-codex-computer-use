---
name: inspect-simulator
description: Inspect the booted iOS Simulator with simctl, then snapshot guest UI through Computer Use.
---

# Inspect simulator

Use the `ios-simulator` skill. Stay CLI-first.

1. `scripts/computer-use-pip.sh show Simulator`
2. `scripts/simulator.sh status`
3. `scripts/simulator.sh apps`
4. `scripts/simulator.sh screenshot /tmp/simulator-framebuffer.png`
5. `open-computer-use call get_app_state --args '{"app":"Simulator"}'` for the accessibility tree
6. Summarize the booted device, foreground app, and useful `element_index` targets
7. Do not bring Simulator to the front. Do not click Home to switch apps — use `simctl launch` / `terminate`
