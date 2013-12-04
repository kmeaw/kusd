Kernel/UserSpace interface network Daemon
==================

Components
---------

- [x] manager
  Listens a socket, forks a few times: children run server, parent restarts children.
- [x] server
  Accepts a connection, fetches a sysreq (syscall NR and 6 arguments), runs it, loops
  until a connection is broken.
- [x] client
  Connects to a manager+server, provides an interface to invoke remote sysreqs,
  optionally raise exceptions; manages a scratch buffer to transfer data from or
  to the remote host.
- [x] bash
  Parses a shell-like grammar.
- [x] eval
  Runs parsed statements.
- [x] interact
  Provides a user interface for the client library as if it is a remote shell client.
- [ ] web
  HTTP-proxy to interface client from the web.

Key Features
----------

- [x] No server-side dynamic-library dependencies, manager+server fits in 4KiB.
- [x] Object-oriented shell commands, passing marshalled data across pipes.
- [x] No need to update server, most features can be implemented by changing
  only the client code.

Future work
------------

- [ ] Manager could be reimplemented to provide encryption and authentication.
- [ ] Client can limit itself by sysreq'ing ulimit.


Some examples
-------------

```
Server (version = ["4bb1d7484554ae5ee8a43c652051544f"]) is ready.
Type :help for help.
(32064)> ps | xargs pstat | grep comm sh | select pid rss comm
[:pid, :rss, :comm]
[416, 1724, "zsh"]
[527, 1647, "zsh"]
[637, 672, "ssh"]
[1310, 1819, "zsh"]
[1691, 1651, "zsh"]
[1698, 1574, "zsh"]
[1938, 196, "sshd"]
[1952, 26, "autossh"]
[1955, 101, "autossh"]
[2603, 340, "ssh"]
[19947, 1856, "zsh"]
[24218, 1431, "zsh"]
[24850, 672, "ssh"]
[31049, 1826, "zsh"]
[31456, 1647, "zsh"]
[31568, 1564, "zsh"]
[31670, 331, "ssh-agent"]
[32090, 1760, "zsh"]
(32064)> uname | select nodename
[:nodename]
["kmeaw"]
(32064)> pstat 1
[:pid, :comm, :state, :ppid, :pgid, :sid, :tty, :tpgid, :flags, :min_flt, :cmin_flt, :maj_flt, :cmaj_flt, :utime, :stime, :cutime, :cstime, :priority, :nice, :timeout, :it_real_value, :start_time, :vsize, :rss, :rss_rlim, :start_code, :end_code, :start_stack, :kstk_esp, :kstk_eip, :signal, :blocked, :sigignore, :sigcatch, :wchan, :nswap, :cnswap, :exit_signal, :cpu_last_seen_on]
[1, "init", "S", 0, 1, 1, 0, -1, 1077960960, 1582, 977427700, 412, 4043917, 398, 1027, 9692207, 1764556, 20, 0, 1, 0, 3, 4337664, 58, 18446744073709551615, 1, 1, 0, 0, 0, 0, 0, 1475401980, 671819267, 18446744073709551615, 0, 0, 17, 0]
(32064)> cd /
nil
(32064)> ls | sort
[:name, :inode, :dtype]
[".", 2, 4]
["..", 2, 4]
["bin", 262145, 4]
["boot", 1048577, 4]
["dev", 393217, 4]
["etc", 1179649, 4]
["home", 1310721, 4]
["lib", 12, 10]
["lib32", 655361, 4]
["lib64", 524289, 4]
["lost+found", 11, 4]
["media", 1835009, 4]
["mnt", 786433, 4]
["opt", 1441793, 4]
["proc", 1572865, 4]
["root", 1703937, 4]
["run", 131073, 4]
["sbin", 1179650, 4]
["src", 1199509, 4]
["sys", 655362, 4]
["tftproot", 1441800, 4]
["tmp", 1572866, 4]
["usr", 524290, 4]
["var", 1703938, 4]
```

