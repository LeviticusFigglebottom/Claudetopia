#!/usr/bin/env python3
"""A script profiler for a Godot run without the editor: stands in for the editor's debugger.

    python3 tools/perf/gd_profiler.py --port 6010 --out prof.json [--after-s 0] [--for-s 0]
    godot --path game --remote-debug tcp://127.0.0.1:6010 ...

Godot connects to it, it switches the engine's "scripts" and "servers" profilers on (what the
editor's Profiler tab does), and adds up every frame's script functions: calls, self time and
total time, by function. Script errors that would stop the game at a breakpoint are answered with
"continue". Writes JSON sorted by self time and prints the top of it.

--label-file names a file the game run may write a line to (a phase); frames are then counted
under that phase as well as in the whole (not used by the capture runner; the whole run is one).
"""
import argparse, json, re, socket, struct, sys, time

# Variant types (Godot 4)
NIL, BOOL, INT, FLOAT, STRING = 0, 1, 2, 3, 4
VECTOR2, VECTOR2I, RECT2, RECT2I, VECTOR3, VECTOR3I, TRANSFORM2D, VECTOR4, VECTOR4I = range(5, 14)
PLANE, QUATERNION, AABB, BASIS, TRANSFORM3D, PROJECTION, COLOR, STRING_NAME, NODE_PATH = range(14, 23)
RID, OBJECT, CALLABLE, SIGNAL, DICTIONARY, ARRAY = range(23, 29)
PBYTE, PINT32, PINT64, PFLOAT32, PFLOAT64, PSTRING, PVEC2, PVEC3, PCOLOR, PVEC4 = range(29, 39)
FLAG_64 = 1 << 16
FLOATS = {VECTOR2: 2, VECTOR2I: 2, RECT2: 4, RECT2I: 4, VECTOR3: 3, VECTOR3I: 3, TRANSFORM2D: 6,
          VECTOR4: 4, VECTOR4I: 4, PLANE: 4, QUATERNION: 4, AABB: 6, BASIS: 9, TRANSFORM3D: 12,
          PROJECTION: 16, COLOR: 4}


def _pad(n):
    return (4 - n % 4) % 4


def decode(b, o=0):
    h = struct.unpack_from('<I', b, o)[0]
    o += 4
    t = h & 0xFF
    f64 = bool(h & FLAG_64)
    if t == NIL:
        return None, o
    if t == BOOL:
        return bool(struct.unpack_from('<I', b, o)[0]), o + 4
    if t == INT:
        if f64:
            return struct.unpack_from('<q', b, o)[0], o + 8
        return struct.unpack_from('<i', b, o)[0], o + 4
    if t == FLOAT:
        if f64:
            return struct.unpack_from('<d', b, o)[0], o + 8
        return struct.unpack_from('<f', b, o)[0], o + 4
    if t in (STRING, STRING_NAME):
        n = struct.unpack_from('<I', b, o)[0]
        o += 4
        s = b[o:o + n].decode('utf-8', 'replace')
        return s, o + n + _pad(n)
    if t in FLOATS:
        n = FLOATS[t]
        size = 8 if (f64 and t not in (VECTOR2I, RECT2I, VECTOR3I, VECTOR4I)) else 4
        return None, o + n * size
    if t == NODE_PATH:
        n = struct.unpack_from('<I', b, o)[0]
        o += 4
        if n & 0x80000000:
            names = n & 0x7FFFFFFF
            subs = struct.unpack_from('<I', b, o)[0] & 0x7FFFFFFF
            o += 8
            for _ in range(names + subs):
                ln = struct.unpack_from('<I', b, o)[0]
                o += 4 + ln + _pad(ln)
        return None, o
    if t == RID:
        return None, o + 8
    if t == OBJECT:
        if f64:
            return None, o + 8
        n = struct.unpack_from('<I', b, o)[0]
        o += 4
        if n == 0:
            return None, o
        o += _pad(n) + n
        props = struct.unpack_from('<I', b, o)[0]
        o += 4
        for _ in range(props):
            _, o = decode(b, o)
            _, o = decode(b, o)
        return None, o
    if t in (CALLABLE, SIGNAL):
        return None, o
    if t == DICTIONARY:
        # typed dictionaries carry their key and value types after the header (Godot 4.4+)
        o = _skip_container_types(b, o, h, 2)
        n = struct.unpack_from('<I', b, o)[0] & 0x7FFFFFFF
        o += 4
        d = {}
        for _ in range(n):
            k, o = decode(b, o)
            v, o = decode(b, o)
            try:
                d[k] = v
            except TypeError:
                d[str(k)] = v
        return d, o
    if t == ARRAY:
        o = _skip_container_types(b, o, h, 1)
        n = struct.unpack_from('<I', b, o)[0] & 0x7FFFFFFF
        o += 4
        a = []
        for _ in range(n):
            v, o = decode(b, o)
            a.append(v)
        return a, o
    if t == PBYTE:
        n = struct.unpack_from('<I', b, o)[0]
        return b[o + 4:o + 4 + n], o + 4 + n + _pad(n)
    if t in (PINT32, PFLOAT32):
        n = struct.unpack_from('<I', b, o)[0]
        fmt = '<%d%s' % (n, 'i' if t == PINT32 else 'f')
        return list(struct.unpack_from(fmt, b, o + 4)), o + 4 + 4 * n
    if t in (PINT64, PFLOAT64):
        n = struct.unpack_from('<I', b, o)[0]
        fmt = '<%d%s' % (n, 'q' if t == PINT64 else 'd')
        return list(struct.unpack_from(fmt, b, o + 4)), o + 4 + 8 * n
    if t == PSTRING:
        n = struct.unpack_from('<I', b, o)[0]
        o += 4
        out = []
        for _ in range(n):
            ln = struct.unpack_from('<I', b, o)[0]
            o += 4
            out.append(b[o:o + ln].decode('utf-8', 'replace').rstrip('\0'))
            o += ln + _pad(ln)
        return out, o
    if t in (PVEC2, PVEC3, PCOLOR, PVEC4):
        n = struct.unpack_from('<I', b, o)[0]
        per = {PVEC2: 2, PVEC3: 3, PCOLOR: 4, PVEC4: 4}[t]
        size = 8 if f64 else 4
        return None, o + 4 + n * per * size
    raise ValueError('variant type %d at %d' % (t, o))


def _skip_container_types(b, o, h, count):
    # header bits 16-17 (key) and 18-19 (value / element): 0 none, 1 builtin, 2 class name, 3 script
    for i in range(count):
        kind = (h >> (16 + 2 * i)) & 3
        if kind == 1:
            o += 4
        elif kind in (2, 3):
            n = struct.unpack_from('<I', b, o)[0]
            o += 4 + n + _pad(n)
    return o


def enc_str(s):
    raw = s.encode('utf-8')
    return struct.pack('<II', STRING, len(raw)) + raw + b'\0' * _pad(len(raw))


def enc(v):
    if v is None:
        return struct.pack('<I', NIL)
    if isinstance(v, bool):
        return struct.pack('<II', BOOL, int(v))
    if isinstance(v, int):
        return struct.pack('<Iq', INT | FLAG_64, v)
    if isinstance(v, float):
        return struct.pack('<Id', FLOAT | FLAG_64, v)
    if isinstance(v, str):
        return enc_str(v)
    if isinstance(v, list):
        return struct.pack('<II', ARRAY, len(v)) + b''.join(enc(x) for x in v)
    raise TypeError(v)


def send(sock, name, data):
    body = enc([name, 1, data])
    sock.sendall(struct.pack('<I', len(body)) + body)


def recv_exact(sock, n):
    buf = b''
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', type=int, default=6010)
    ap.add_argument('--out', required=True)
    ap.add_argument('--after-s', type=float, default=0.0, help='start counting this long after connecting')
    ap.add_argument('--raw', action='store_true', help='print the first few profile frames as decoded')
    args = ap.parse_args()
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(('127.0.0.1', args.port))
    srv.listen(1)
    print('gd_profiler: waiting on', args.port, flush=True)
    sock, _ = srv.accept()
    print('gd_profiler: connected', flush=True)
    t0 = time.time()
    enabled = False
    sigs = {}
    funcs = {}
    frames = 0
    shown = 0
    names = {}
    phases = {}
    phase = ['load']

    def dump():
        rows = []
        for sid, (calls, self_t, total_t) in funcs.items():
            rows.append({'function': sigs.get(sid, str(sid)), 'calls': calls,
                         'self_ms': round(self_t * 1000, 3), 'total_ms': round(total_t * 1000, 3),
                         'self_ms_per_frame': round(self_t * 1000 / max(frames, 1), 4)})
        rows.sort(key=lambda r: -r['self_ms'])
        by_phase = {}
        for pname, ph in phases.items():
            pr = []
            for sid, (calls, self_t, total_t) in ph['funcs'].items():
                pr.append({'function': sigs.get(sid, str(sid)), 'calls': calls,
                           'self_ms_per_frame': round(self_t * 1000 / max(ph['frames'], 1), 4),
                           'total_ms_per_frame': round(total_t * 1000 / max(ph['frames'], 1), 4)})
            pr.sort(key=lambda r: -r['self_ms_per_frame'])
            by_phase[pname] = {'frames': ph['frames'],
                               'frame_ms': round(ph['frame_time'] * 1000 / max(ph['frames'], 1), 3),
                               'script_ms': round(ph['script_time'] * 1000 / max(ph['frames'], 1), 3),
                               'functions': pr[:80]}
        json.dump({'frames': frames, 'messages': names, 'phases': by_phase, 'functions': rows},
                  open(args.out, 'w'), indent=1)
        return rows

    try:
        while True:
            n = struct.unpack('<I', recv_exact(sock, 4))[0]
            body = recv_exact(sock, n)
            try:
                msg, _ = decode(body)
            except Exception as e:  # noqa
                continue
            if not isinstance(msg, list) or len(msg) < 3:
                continue
            name, data = msg[0], msg[2]
            names[name] = names.get(name, 0) + 1
            if not enabled and time.time() - t0 >= args.after_s:
                for prof in ('scripts', 'servers'):
                    send(sock, 'profiler:' + prof, [True, []])
                enabled = True
                print('gd_profiler: profilers on', flush=True)
            if name == 'debug_enter':
                send(sock, 'continue', [])
            elif name == 'servers:function_signature' or name == 'profiler:function_signature':
                # [signature, id]
                if isinstance(data, list) and len(data) >= 2:
                    sigs[data[1]] = data[0]
            elif name == 'output':
                for line in _strings(data):
                    m = re.search(r'\[Capture\] (?:walk )?([A-Za-z0-9_]+):', line)
                    if m:
                        phase[0] = m.group(1)
                    elif '[World] ready' in line:
                        phase[0] = 'after_ready'
            elif name == 'servers:profile_frame':
                frames += 1
                if args.raw and shown < 3:
                    print('RAW', data[:40], flush=True)
                    shown += 1
                _add_frame(data, funcs, sigs)
                ph = phases.setdefault(phase[0], {'frames': 0, 'funcs': {}, 'frame_time': 0.0, 'script_time': 0.0})
                ph['frames'] += 1
                try:
                    ph['frame_time'] += float(data[1])
                    ph['script_time'] += float(data[5])
                except Exception:
                    pass
                _add_frame(data, ph['funcs'], sigs)
                if frames % 600 == 0:
                    dump()
    except (EOFError, ConnectionResetError):
        pass
    rows = dump()
    print('gd_profiler: %d frames' % frames)
    for r in rows[:40]:
        print('%9.1f ms self %9.1f total %8d calls  %s' % (r['self_ms'], r['total_ms'], r['calls'], r['function']))


def _strings(v):
    if isinstance(v, str):
        yield v
    elif isinstance(v, list):
        for x in v:
            yield from _strings(x)


def _add_frame(data, funcs, sigs):
    # ServersProfiler frame (Godot 4.7): [frame_number, frame_time, process_time, physics_time,
    #   physics_frame_time, script_time, servers, (server name, values, (item name, time)...)...,
    #   values, (sig_id, calls, self, total, internal)...]
    try:
        i = 6
        nserv = data[i]
        i += 1
        for _ in range(nserv):
            i += 1  # server name
            values = data[i]
            i += 1 + values
        values = data[i]
        i += 1
        for k in range(values // 5):
            sid, calls, self_t, total_t = data[i + 5 * k:i + 5 * k + 4]
            c = funcs.setdefault(sid, [0, 0.0, 0.0])
            c[0] += calls
            c[1] += self_t
            c[2] += total_t
    except Exception:
        pass


if __name__ == '__main__':
    main()
