#include <fcntl.h>
#include <sys/types.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/syscall.h>

#ifndef BUILTIN_SERVER
#include "arch.h"
#endif

struct __attribute__((packed)) sysreq
{
  long snr, sa, sb, sc, sd, se, sf;
};

#ifdef BUILTIN_SERVER
#define STARTFUNC child
#else
#define STARTFUNC _start
#endif

void STARTFUNC ()
{
  struct sysreq r;
  int fd;
  long n, s;
  uint64_t id[] = IDENT;

  __syscall1(__NR_close, 3);
acceptloop:
  fd = __syscall3(__NR_accept, 0, 0, 0);
  if (fd < 0)
  {
    myerror("accept");
    __syscall1(__NR_exit, 1);
  }
  if (fd != 3)
  {
    __syscall2(__NR_dup2, fd, 3);
    __syscall1(__NR_close, fd);
    fd = 3;
  }
  __syscall3 (__NR_write, fd, (long) id, sizeof(id));
  while (__syscall3(__NR_read, fd, (long) &r, sizeof(r)) > 0)
  {
//    fprintf (stderr, "(%x, %x, %x, %x, %x, %x, %x);\n", r.snr, r.sa, r.sb, r.sc, r.sd, r.se, r.sf);
    if (r.snr == 0 && r.sa == fd)
    {
      for (s = 0; r.sc && (n = __syscall3(__NR_read, fd, r.sb, r.sc)) > 0; s += n) { r.sb += n; r.sc -= n; }
      __syscall3(__NR_write, fd, (long) &s, sizeof(s));
    }
    else if (r.snr == 1 && r.sa == fd)
    {
      for (s = 0; r.sc && (n = __syscall3(__NR_write, fd, r.sb, r.sc)) > 0; s += n) { r.sb += n; r.sc -= n; }
      __syscall3(__NR_write, fd, (long) &s, sizeof(s));
    }
    else
    {
      r.sa = __syscall6(r.snr, r.sa, r.sb, r.sc, r.sd, r.se, r.sf);
      __syscall3(__NR_write, fd, (long) &r.sa, sizeof(r.sa));
    }
  }
  goto acceptloop;
}
