"""gdb (non-stop): stall only Godot's audio mixing thread at one instruction, every other thread
running on, to reproduce the bus-details race deterministically. On a signal, print the stopped
thread's backtrace and quit.

    sleep 300 | STALL_US=20000 gdb -q -x tools/debug/stall_mixer.py --args \\
        godot --headless --path game --audio-driver Dummy --fixed-fps 60 \\
        --script res://tools_gd/audio_race.gd -- --seconds=60 --churn --players=4

gdb has to keep reading a stdin that stays open (the `sleep |`): in non-stop mode its event loop,
which runs the stalls, only turns while it waits at its prompt.

STALL_AT is the instruction in AudioServer::_mix_step just after
`bus_details_ptr = playback->bus_details.load()` and before the details are copied. In the
official 4.7.2 Linux build (stripped) it is 0x3b19830: `mov 0x360(%r13),%rdi` (the load) at
0x3b19829, the null check at 0x3b19830, the six StringName copies at 0x3b19878-0x3b1988c. Found
by resolving the crash backtrace by the strings each function refers to (string_name.cpp's
"!configured" in the StringName copy constructor; "_driver_process" in the caller). Another build
needs its own address.
"""
import os
import time

import gdb

STALL = float(os.environ.get('STALL_US', '30000')) / 1e6
ADDR = int(os.environ.get('STALL_AT', '0x3b19830'), 16)
hits = [0]


class Stall(gdb.Breakpoint):
    def stop(self):
        hits[0] += 1
        time.sleep(STALL)
        return False


def on_stop(event):
    if isinstance(event, gdb.SignalEvent):
        print('STALL | %d stalls, then %s' % (hits[0], event.stop_signal))
        try:
            gdb.execute('bt 8')
        except gdb.error as e:
            print('bt failed: %s' % e)
        gdb.execute('kill')
        gdb.execute('quit')


def on_exit(event):
    print('STALL | %d stalls, the program exited (%s)' % (hits[0], getattr(event, 'exit_code', '?')))
    gdb.execute('quit')


gdb.execute('set pagination off')
gdb.execute('set confirm off')
gdb.execute('set non-stop on')
gdb.execute('set print thread-events off')
for sig in ('SIGPIPE', 'SIGUSR1', 'SIGUSR2'):
    gdb.execute('handle %s nostop noprint pass' % sig)
gdb.events.stop.connect(on_stop)
gdb.events.exited.connect(on_exit)
Stall('*%#x' % ADDR)
gdb.execute('run &')
