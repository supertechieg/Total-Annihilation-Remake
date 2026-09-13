"""Run original projectile update with one burst source and controlled host edges."""
import json
import random
from pathlib import Path
from native_movement_reference import MovementReference, GAME, UNIT, DEFINITION
from native_cob_reference import EXE_HASH
from cob import signed
from unicorn import UC_HOOK_CODE
from unicorn.x86_const import UC_X86_REG_ESP

POOL = 0x1500000


def main():
    native = MovementReference(Path('local/original/TotalA.exe').read_bytes(), Path('local/viewer-assets/armcom.cob').read_bytes())
    native.mu.mem_map(POOL, 0x10000)
    native.mu.mem_write(0x49ae20, b'\xc3')  # Pool consolidation excluded; inspect removal bit.
    native.mu.mem_write(0x43e240, b'\xc2\x10\x00')
    calls, fresh = [], [0, 0, 0]

    def query(mu, address, _size, _data):
        if address != 0x43e240:
            return
        sp = mu.reg_read(UC_X86_REG_ESP)
        output = native.read(sp + 8)
        calls.append(dict(unit=native.read(sp + 4), slot=native.read(sp + 12) & 255, piece=native.read(sp + 16)))
        for axis, value in enumerate(fresh):
            native.write(output + axis * 4, value)

    native.mu.hook_add(UC_HOOK_CODE, query, begin=0x43e240, end=0x43e240)
    rng = random.Random(0x49b720)
    cases = []
    for index in range(240):
        native.mu.mem_write(POOL, bytes(0x200))
        timestamp = rng.randrange(0x100000000)
        interval = [0, 1, 3, 4, 5, 30][index % 6]
        due = (timestamp + interval) & 0xffffffff
        tick = [due, (due - 1) & 0xffffffff, (due + 1) & 0xffffffff][index % 3]
        remaining = 1 + index % 5
        timer = [0, 30, 65535][index % 3]
        position = [rng.randint(-10000000, 10000000) for _ in range(3)]
        fresh[:] = [rng.randint(-10000000, 10000000) for _ in range(3)]
        speed, distance = 655359, rng.randint(0, 10000000)
        spray = [0, 1024, 5000][(index // 3) % 3]
        seed = rng.randrange(1, 2147483647)
        heading, pitch = rng.randrange(65536), rng.randrange(65536)
        velocity = [rng.randint(-655359, 655359) for _ in range(3)]
        native.write(0x51fc88, seed)
        native.write(GAME + 0x141f7, POOL)
        native.write(GAME + 0x141f3, 1)
        native.write(GAME + 0x142f7, 0)
        native.write(GAME + 0x38a47, tick)
        native.write(UNIT + 0x10, DEFINITION)
        native.write(DEFINITION + 0x111, 0)
        for offset in [0xee, 0xf2]:
            native.short(DEFINITION + offset, 0)
        native.short(DEFINITION + 0xee, spray)
        native.write(DEFINITION + 0x68, speed)
        native.short(DEFINITION + 0xec, interval)
        native.short(DEFINITION + 0xe6, timer)
        native.write(POOL, DEFINITION)
        native.write(POOL + 0x52, UNIT)
        native.write(POOL + 0x42, timestamp)
        native.write(POOL + 0x3a, speed)
        native.write(POOL + 0x3e, distance)
        native.short(POOL + 0x60, remaining)
        native.short(POOL + 0x62, 2)
        native.short(POOL + 0x36, heading)
        native.short(POOL + 0x38, pitch)
        for axis, value in enumerate(velocity):
            native.write(POOL + 0x1c + axis * 4, value)
        for axis, value in enumerate(position):
            native.write(POOL + 4 + axis * 4, value)
        calls.clear()
        native.call(0x49b720, [])

        def state(pointer):
            return dict(position=[signed(native.read(pointer + 4 + axis * 4)) for axis in range(3)],
                        velocity=[signed(native.read(pointer + 0x1c + axis * 4)) for axis in range(3)],
                        heading=native.read(pointer + 0x36) & 65535, pitch=native.read(pointer + 0x38) & 65535,
                        timestamp=native.read(pointer + 0x42), deadline=native.read(pointer + 0x46),
                        remaining=native.read(pointer + 0x60) & 65535, removed=bool(native.read(pointer + 0x69) & 2))

        cases.append(dict(tick=tick, timestamp=timestamp, interval=interval, remaining=remaining, timer=timer,
                          position=position, fresh=fresh[:], speed=speed, distance=distance,
                          spray=spray, seed=seed, expected_seed=native.read(0x51fc88), heading=heading, pitch=pitch, velocity=velocity,
                          source=state(POOL), copy=state(POOL + 0x6b) if native.read(GAME + 0x141f3) == 2 else None,
                          queries=calls[:]))
        # Keep the native source intact across updates. Emitted copies are removed
        # from this fixture's pool so their movement/collision is a separate test.
        steps = []
        for step in range(20):
            if state(POOL)['removed']:
                break
            tick = (tick + max(1, interval // 2)) & 0xffffffff
            fresh[:] = [value + 65536 for value in fresh]
            native.write(GAME + 0x141f3, 1)
            native.write(GAME + 0x38a47, tick)
            native.mu.mem_write(POOL + 0x6b, bytes(0x6b))
            calls.clear()
            native.call(0x49b720, [])
            if any(call != dict(unit=UNIT, slot=0, piece=2) for call in calls):
                raise AssertionError(f'Unexpected cached muzzle query: {calls}')
            steps.append(dict(tick=tick, fresh=fresh[:], source=state(POOL),
                              expected_seed=native.read(0x51fc88),
                              copy=state(POOL + 0x6b) if native.read(GAME + 0x141f3) == 2 else None,
                              queries=calls[:]))
        cases[-1]['steps'] = steps
    folder = Path('local/burst')
    folder.mkdir(exist_ok=True)
    (folder / 'native.json').write_text(json.dumps(dict(exe_sha256=EXE_HASH, cases=cases)))
    print(f'NATIVE_BURST_UPDATE {len(cases)} cases')


if __name__ == '__main__':
    main()
