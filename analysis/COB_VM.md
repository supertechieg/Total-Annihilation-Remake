# Commander script runtime — 2026-09-13

## Result and scope

The Godot viewer executes the installed `ARMCOM.COB` instructions to animate the original model. This is a COB subset with all 26 instruction kinds used by this Commander, plus selected arithmetic operations. It is not a complete TA simulation or a general replacement for every unit script.

The new runtime matches **464 / 464 snapshots** produced by the original x86 interpreter in an isolated CPU emulator over a 450-tick scenario. Compared state includes every piece's position, rotation, visibility, motion targets and velocities, script statics, exposed construction stance, and active thread slots/PCs/wait categories. This checks the interpreter and motion-update routines; it does not compare the original rendered image, world physics, or full host-game behavior.

## Source audit

`btdata.ccx`, `ccdata.ccx`, `rev31.gp3`, and `totala1.hpi` each contain the identical 7,890-byte Commander COB. No loose `scripts/armcom.cob` override exists in the inspected installation. SHA-256:

`2514431df99863d0c1f4f95effbda442938c4b8e9c5aca7ac3cb5a65846bea32`

The program has 20 functions, 14 named script pieces, four statics, and 1,821 code words. The model has 15 pieces: its extra `ground` piece is not named in the script.

The bundled `scripts/ARMCOM.BOS` supplies useful symbol/behavior context. Source-level bracketed positions must not be naively equated to raw bytecode numbers: compiler unit scaling has not been reconstructed. A numeric difference alone does not establish that the source is outdated. Playback uses the compiled bytecode directly, including the `Create()` visibility commands; the earlier regex-based initialization is no longer used.

## Executable evidence

Addresses refer exclusively to `TotalA.exe` SHA-256 `3b9c0fadabf3dc67ed5f05a70f1e1505a0c65deadd1a3c930adfe30e2a84995e`.

| Address | Observed responsibility |
| --- | --- |
| `0x004b0610` | Script context initialization; eight thread slots; obtains clock divisor |
| `0x004b08c0` | Allocates the first free slot, initializes PC and stack pointer, default signal mask 1 |
| `0x004b0b00` | Host callback invocation with up to four preseeded arguments |
| `0x004b0d60` | Visits slots in ascending order, then advances piece motion |
| `0x004b0da0` | Bytecode interpreter |
| `0x004b1c00` | Piece translation/rotation advancement and target clamping |
| `0x004b62d0` | Clock-rate setter; game startup calls it with `0x1e` (30) |
| `0x004b6330` | Returns the clock divisor used by the script context |
| `0x00485d40` | Unit script/model setup and immediate `Create` invocation |
| `0x0041d4c0` | Registers revision GP3, CCX, UFO, HPI, then disc archives; complete lookup precedence still needs tracing |

## Reproduced semantics

- Eight slots, with separate 32-word stacks. Locals share the bottom of the stack; local creation preserves argument values already placed there.
- Ascending slot scheduling. A child in a higher slot can execute in the same pass; a newly created child in an already-visited lower slot waits for the next pass.
- `CALL_SCRIPT` allocates a child and blocks the parent. Child termination releases the parent. This is not an ordinary nested function stack.
- Started/called children inherit signal masks. Signals terminate matching slots, including the current slot when applicable, and release waiting parents.
- Signed 32-bit arithmetic, 16-bit angle wrapping, shortest-direction target turns, integer per-tick velocities.
- `SLEEP` computes integer `30 * milliseconds / 1000`. Thus 40 ms produces one tick and 100 ms produces three. A sleep or movement wait yields the current scheduling pass.
- Motion is advanced after script scheduling. Waiters see completed motion on a later scheduling pass.
- A native `MOVE` to an already-reached target retains its positive velocity until the next motion update. The native comparison exposed this detail and the new runtime was corrected to match.
- Explicit host read/write allowlists support construction stance, healthy solar inputs and factory yard test inputs. Unknown properties still fault.
- `SPIN` sets turn target to -1, divides target speed and acceleration by 30 with signed truncation, and sets speed immediately if acceleration truncates to zero. Acceleration changes speed before each rotation update and clamps at the requested speed. `STOP_SPIN` sets the speed target to zero and negates the supplied per-tick deceleration. Synthetic native comparisons include signed and sub-tick rounding cases.
- `CACHE`/`DONT_CACHE` and `SHADE`/`DONT_SHADE` retain per-piece flags. The current unshaded mesh renderer does not yet reproduce the original caching or lighting effects.

## Native reference harness

`tools/native_cob_reference.py` loads the recorded executable's sections into Unicorn's x86-32 emulator and calls the original host-invocation, scheduling, interpreter, and motion routines. It supplies a script context, relocated COB pointers, and minimal virtual callbacks that store/retrieve piece transforms, visibility, and value 5.

The harness **does not launch Windows or execute the game startup**. It stops at a synthetic return address, imposes instruction/time limits, and rejects an executable with a different hash. The engine callbacks are test doubles, so matching traces validate script state rather than the rest of the original engine.

The reference scenario covers walking, aiming during walking (including `walklegs`), stopping, primary and D-gun flash callbacks, interrupted aiming, restoring pose, entering/exiting construction stance, and a second start/stop cycle. Native inputs and state traces stay under `local/scripts/`. A compact result is in `native-cob-validation.json`.

## Run validation

Normal checks after asset preparation:

```powershell
.\tools\verify.ps1
```

Optional native comparison (requires the local executable copy from the analysis stage):

```powershell
python -m pip install --target local\python-deps -r requirements-analysis.txt
.\tools\verify.ps1 -Native
```

The standalone native harness also accepts `--exe` to point to the installation's executable and `--cob` to select an extracted script. Its oracle executable hash is intentionally pinned.

Validation currently includes 8 archive/asset parser tests, 6 COB decoder tests, 58 runtime assertions, Godot model/control integration checks, and 464 native state comparisons.

## Remaining limitations

Unsupported opcodes and engine properties fail explicitly. Thread exhaustion also faults instead of imitating every original failure edge case. Random values, explosions, attachment, general get/set engine properties, and other units need further implementation and comparison. The viewer's render-frame accumulator caps long delays for responsiveness; that host policy is not a lockstep simulation scheduler.

COB-to-model axis mapping, rotation order, original camera projection, lighting, UV orientation, and scale still need renderer-level comparisons. The viewer now has controllable Commander movement, provisional terrain navigation and construction/resource accounting; see PLAYABLE_MOVEMENT.md and CONSTRUCTION.md. Simulated projectiles, damage, factory production, saves and multiplayer remain unfinished.

## Factory script prerequisite

`tools/native_factory_reference.py` and `godot/compare_native_factory.gd` compare 2,124 snapshots: 759 each for the original Arm vehicle plant and Kbot lab, plus 606 across six synthetic spin scenarios. Comparison includes transforms, targets, speeds, acceleration, statics, active thread PCs/states, properties, cache and shading flags. The same pinned executable is used as the Commander oracle.

The factory scenario supplies health=100 and construction remaining-percent=100 then 0. Yard property 18 reads back its last written value, representing an immediately available yard; this does not validate native occupancy checks. It invokes Create, Activate, StartBuilding, StopBuilding, Deactivate, reactivation during the five-second closing delay, and final closing. StartBuilding spins the pad; StopBuilding stops it. The opening path writes construction stance 5=1 only after its animation and OpenYard request complete. These verified script states are prerequisites for the upcoming production host, not evidence that factories already produce units in the viewer.

Original world callback timing, yard-map collision changes, QueryBuildInfo placement, resource settlement during production, completed-unit release and construction effects still require integration and validation. Detailed traces and synthetic COB programs stay under ignored local/factory; the compact result is native-factory-validation.json.

## External references

- [COB file structures](https://github.com/MHeasell/rwe/blob/master/src/rwe/io/cob/Cob.h)
- [Opcode identities](https://github.com/MHeasell/rwe/blob/master/src/rwe/cob/CobOpCode.h)
- [Unicorn programming API](https://www.unicorn-engine.org/docs/tutorial.html)

The scheduler implementation and integer-motion details above were investigated against the local original executable, and the native comparison is the stronger check for this selected script.
