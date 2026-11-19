"""Pack a folder into a VPK with a sorted file tree.

The vpk packer keeps the os.walk order, and that order changes with the filesystem.
A sorted tree makes the same files give the same VPK bytes on each machine.

Usage: pack-vpk.py <folder> <out.vpk>
"""

import sys

import vpk

src, out = sys.argv[1], sys.argv[2]
pak = vpk.new(src)
pak.tree = {
    ext: {rel: sorted(pak.tree[ext][rel]) for rel in sorted(pak.tree[ext])}
    for ext in sorted(pak.tree)
}
pak.save(out)
