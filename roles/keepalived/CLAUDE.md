# keepalived role
- Before changing priorities, state, VIP or peers, explain the failover impact on edge1/edge2 first.
- keepalived truncates auth_pass to 8 characters: both edges must match.
- The nginx track_script has weight -60: keep the priority gap between edge1 and edge2 below 60, or an nginx failure will not move the VIP.
- Priority, not state, decides the MASTER (preemption is on): never give the BACKUP edge a higher priority than the MASTER.
