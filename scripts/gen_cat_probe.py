#!/usr/bin/env python3
"""Generates and installs the CreateSceneProxy probe for Stray-Mac-Shipping (arm64, unstripped text).

Instrumented points:
  E  0x102fd67a0  entry of USkinnedMeshComponent::CreateSceneProxy (stp x22,x21,[sp,#-0x30]!)
  B  0x102fd68bc  bone-limit compare (cmp w22,w0)
  X  0x102fd6840  common exit, x21 = proxy or 0 (mov x0,x21)
  N  0x102fd6854  early NULL exit (mov x21,#0)

Output: write(2, ...) records "PRB<tag><hex>..." with 16 hex digits per value to stderr.
Bodies live in the zero-filled gap at file offset 0x5d03ec (VA 0x1005d03ec).
"""
import subprocess, sys, struct, os

IMG_BASE = 0x100000000
CAVE = 0x1005D03EC
CAVE_MAX = 3092
WRITE_STUB = 0x103C90460

HOOKS = {
    'E': dict(at=0x102FD67A0, displaced='stp x22, x21, [sp, #-0x30]!', back=0x102FD67A4, orig=0xA9BD57F6),
    'B': dict(at=0x102FD68BC, displaced='cmp w22, w0', back=0x102FD68C0, orig=0x6B0002DF),
    'X': dict(at=0x102FD6840, displaced='mov x0, x21', back=0x102FD6844, orig=0xAA1503E0),
    'N': dict(at=0x102FD6854, displaced='mov x21, #0', back=0x102FD6858, orig=0xD2800015),
}

def body(tag):
    items = []
    I = lambda t: items.append(('i', t))
    L = lambda n: items.append(('l', n))
    BR = lambda op, tgt_label: items.append(('b', op, tgt_label))
    BA = lambda op, tgt_abs: items.append(('ba', op, tgt_abs))
    
    # prologue: save registers on stack
    I('stp x29, x30, [sp, #-0x40]!')
    I('mov x29, sp')
    I('stp x0, x1, [x29, #0x10]')
    I('stp x2, x3, [x29, #0x20]')
    I('sub sp, sp, #0x80')
    I('mov x10, sp')
    I('mov w12, #80'); I('strb w12, [x10], #1')   # 'P'
    I('mov w12, #82'); I('strb w12, [x10], #1')   # 'R'
    I('mov w12, #66'); I('strb w12, [x10], #1')   # 'B'
    I('mov w12, #%d' % ord(tag)); I('strb w12, [x10], #1')
    
    def hx(load):
        for t in load: I(t)
        BA('bl', 'HEXW')
        
    if tag == 'E':
        I('ldr x13, [x29, #0x10]')          # this (USkinnedMeshComponent)
        hx(['mov x9, x13'])
        BR('cbz x13,', 'Le_done')
        hx(['ldr x9, [x13, #0xa8]'])        # SkeletalMesh
        I('ldr x14, [x13, #0x608]')         # MeshObject
        hx(['mov x9, x14'])
        BR('cbz x14,', 'Lz1')
        I('ldr x9, [x14, #0x40]')           # RenderData
        BR('b', 'Lz2')
        L('Lz1'); I('mov x9, #0')
        L('Lz2'); BA('bl', 'HEXW')
        hx(['ldr x9, [x13, #0x5b0]'])       # LOD fields
        hx(['ldr x9, [x13, #0x5f8]'])       # flags word
        L('Le_done')
    elif tag == 'B':
        hx(['mov x9, x19'])                 # this
        hx(['mov w9, w0'])                  # GetMaxGPUSkinBones
        hx(['mov w9, w22'])                 # section bones
    elif tag == 'X':
        hx(['mov x9, x19'])                 # this
        hx(['mov x9, x21'])                 # proxy or 0
    elif tag == 'N':
        hx(['mov x9, x19'])                 # this
        
    # newline + write(2, buf, len)
    I('mov w12, #10'); I('strb w12, [x10], #1')
    I('mov x1, sp')
    I('sub x2, x10, x1')                    # length = x10 - sp
    I('mov w0, #2')                         # fd 2 = stderr
    BA('bl', 'WRITE')
    
    # epilogue: restore registers
    I('mov sp, x29')
    I('ldp x0, x1, [sp, #0x10]')
    I('ldp x2, x3, [sp, #0x20]')
    I('ldp x29, x30, [sp], #0x40')
    return items

def hexw():
    items = []
    I = lambda t: items.append(('i', t))
    L = lambda n: items.append(('l', n))
    BR = lambda op, lab: items.append(('b', op, lab))
    I('mov x11, #16')
    L('H1')
    I('lsr x12, x9, #60')
    I('and x12, x12, #15')
    I('cmp x12, #10')
    BR('b.lo', 'H2')
    I('add x12, x12, #87')
    BR('b', 'H3')
    L('H2'); I('add x12, x12, #48')
    L('H3'); I('strb w12, [x10], #1')
    I('lsl x9, x9, #4')
    I('subs x11, x11, #1')
    BR('b.ne', 'H1')
    I('ret')
    return items

def layout(all_items, base):
    labels = {}
    addr = base
    seq = []
    for it in all_items:
        if it[0] == 'l':
            labels[it[1]] = addr
        else:
            seq.append((addr, it))
            addr += 4
    return labels, seq, addr

def assemble_text(seq, labels, absolute):
    lines = []
    for addr, it in seq:
        if it[0] == 'i':
            lines.append(it[1])
        elif it[0] == 'b':
            tgt = labels[it[2]]
            lines.append('%s #%d' % (it[1], tgt - addr))
        elif it[0] == 'ba':
            tgt = absolute[it[2]]
            lines.append('%s #%d' % (it[1], tgt - addr))
    return '\n'.join(lines) + '\n'

def extract_code(obj_path, expected_size):
    lines = subprocess.check_output(['xcrun', 'otool', '-t', '-X', obj_path]).decode().splitlines()
    words = []
    for line in lines:
        parts = line.strip().split()
        if not parts:
            continue
        # Skip the leading 16-hex address token
        for w in parts[1:]:
            words.append(int(w, 16))
    code = b''.join(struct.pack('<I', w) for w in words)
    if len(code) != expected_size:
        sys.exit(f'Size mismatch in {obj_path}: extracted {len(code)} bytes, expected {expected_size}')
    return code

def main(out_bin, patch_binary=None):
    all_items = []
    for tag in ['E', 'B', 'X', 'N']:
        bi = body(tag)
        all_items.append(('l', 'BODY_' + tag))
        all_items.extend(bi)
        h = HOOKS[tag]
        all_items.append(('i', h['displaced']))
        all_items.append(('ba', 'b', 'BACK_' + tag))
        
    all_items.append(('l', 'HEXW'))
    all_items.extend(hexw())
    
    labels, seq, end = layout(all_items, CAVE)
    entries = {tag: labels['BODY_' + tag] for tag in HOOKS}
    
    absolute = {'WRITE': WRITE_STUB}
    for tag in HOOKS:
        absolute['BACK_' + tag] = HOOKS[tag]['back']
        
    seq2 = []
    for addr, it in seq:
        if it[0] == 'ba' and it[2] == 'HEXW':
            seq2.append((addr, ('b', 'bl', 'HEXW')))
        else:
            seq2.append((addr, it))
    seq = seq2
    
    text = assemble_text(seq, labels, absolute)
    size = end - CAVE
    print(f'Cave payload size: {size} bytes (limit: {CAVE_MAX})')
    if size > CAVE_MAX:
        sys.exit(f'Cave overflow: {size} > {CAVE_MAX}')
        
    asm = '.text\n' + text
    with open(out_bin + '.s', 'w') as f:
        f.write(asm)
        
    subprocess.check_call(['xcrun', '-sdk', 'macosx', 'clang', '-arch', 'arm64', '-c', out_bin + '.s', '-o', out_bin + '.o'])
    code = extract_code(out_bin + '.o', size)
    with open(out_bin, 'wb') as f:
        f.write(code)
    print(f'Wrote {len(code)} bytes to {out_bin}')
    for tag in HOOKS:
        print(f'  Hook {tag}: at 0x{HOOKS[tag]["at"]:x} -> body 0x{entries[tag]:x}')
        
    if patch_binary:
        patch(patch_binary, entries, code, labels)

def patch(path, entries, code, labels):
    with open(path, 'r+b') as f:
        data = bytearray(f.read())
        for tag, h in HOOKS.items():
            off = h['at'] - IMG_BASE
            cur = struct.unpack('<I', data[off:off + 4])[0]
            if cur != h['orig']:
                sys.exit(f"Hook {tag}: unexpected bytes 0x{cur:08x} at 0x{h['at']:x} (expected 0x{h['orig']:08x})")
            delta = entries[tag] - h['at']
            if abs(delta) >= 128 * 1024 * 1024:
                sys.exit(f'Branch out of range for hook {tag}')
            word = 0x14000000 | ((delta >> 2) & 0x3FFFFFF)
            data[off:off + 4] = struct.pack('<I', word)
            print(f'Patched hook {tag} at 0x{h["at"]:x}: instruction 0x{word:08x}')
            
        cave_off = CAVE - IMG_BASE
        region = data[cave_off:cave_off + len(code)]
        if any(region):
            sys.exit('Cave region is not completely zero-filled')
        data[cave_off:cave_off + len(code)] = code
        f.seek(0)
        f.write(data)
    print(f'Successfully patched binary: {path}')

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(f'Usage: {sys.argv[0]} <out_bin> [binary_to_patch]')
    out = sys.argv[1]
    patch_to = sys.argv[2] if len(sys.argv) > 2 else None
    main(out, patch_to)
