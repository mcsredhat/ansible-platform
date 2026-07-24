# nfs_server — molecule note

**nfs_server is intentionally NOT molecule-tested in a container.**

An NFS *server* requires kernel-side components (the `nfsd` kernel module, rpcbind,
kernel RPC) that are not available inside an unprivileged OCI container. `exportfs`
and `rpc.nfsd` cannot function without the host kernel's NFS server support, which
containers do not expose.

This is a well-understood limitation of container-based role testing — an NFS
server is validated by **integration testing on real hardware** (the actual
data-tier node), not by molecule. The role IS exercised on the real platform and
verified via `validate.yml` (which checks `exportfs -s` on data1).

The `nfs_client` role, by contrast, IS molecule-tested and passes.
