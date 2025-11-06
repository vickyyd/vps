cat > /etc/sysctl.conf << EOF
fs.file-max = 6815744
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1
vm.min_free_kbytes = 65536
vm.overcommit_ratio = 100
vm.vfs_cache_pressure = 30

# 网络核心参数
net.core.default_qdisc = fq
net.core.rmem_max = 67108864
net.core.wmem_max = 33554432
net.core.netdev_max_backlog = 500000
net.core.somaxconn = 4096

# TCP参数优化（针对CN2 GIA + 单线程优化）
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_mem = 104857600 943718400 1073741824

# 单线程优化：增大初始窗口和最大窗口
net.ipv4.tcp_rmem = 8192 262144 134217728
net.ipv4.tcp_wmem = 8192 131072 67108864

net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 1200
net.ipv4.tcp_keepalive_probes = 9
net.ipv4.tcp_keepalive_intvl = 75
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.ip_local_port_range = 1024 65535

# 单线程性能关键参数
net.ipv4.tcp_pacing_ca_ratio = 120
net.ipv4.tcp_pacing_ss_ratio = 200
net.ipv4.tcp_notsent_lowat = 16384
net.core.netdev_budget = 600
net.core.netdev_budget_usecs = 5000

# BBR单线程优化参数
net.ipv4.tcp_adv_win_scale = 1
net.ipv4.tcp_moderate_rcvbuf = 1

# CPU亲和性和中断优化
kernel.sched_autogroup_enabled = 0
kernel.numa_balancing = 0
net.core.rps_sock_flow_entries = 32768
EOF
sysctl -p && sysctl --system
