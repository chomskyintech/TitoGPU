# CGRA baseline run request

## Purpose
Trigger the repository's `.github/workflows/cgra-baseline.yml` on a pull request so the existing CGRA simulation and generic Yosys synthesis can be evaluated in GitHub Actions.

## Scope
- No RTL changes are included in this branch.
- The workflow is expected to run `make sim` and `make synth`.
- The workflow should upload `cgra-sim.log` and `cgra-synth.log` as the `cgra-baseline-logs` artifact.

## Review checklist
- [ ] Simulation job completes and the directed dot-product test passes.
- [ ] Synthesis job completes and Yosys reports no fatal errors.
- [ ] Tool versions and logs are retained.
- [ ] Any failures or warnings are triaged before the baseline is called reproducible.

## Evidence status
No simulation or synthesis result is asserted by this document. Results must come from the actual GitHub Actions run.
