#include <sys/socket.h>
#include <netinet/in.h>
int errno;
#include <unistd.h>
#include <string.h>

#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>

#define CHILDREN  4

#include "arch.h"

#ifdef BUILTIN_SERVER
#include "server.c"
#else
void child()
{
    char* argv[] = { "server", 0 };
    char* envp[] = { 0 };
    int pid = __syscall0(__NR_fork);
    if (pid == 0)
    {
	__syscall3(__NR_execve, (long) "./server", (long) argv, (long) envp);
        myerror("exec");
        __syscall1(__NR_exit, 1);
    }
    else if (pid < 0)
    {
        errno = -pid;
        myerror("fork");
        __syscall1(__NR_exit, 1);
    }
}
#endif

void mybzero(void *data, size_t sz)
{
  char *ptr = (char *) data;
  while (sz--) *ptr++ = 0;
}

void _start()
{
  struct sockaddr_in6 servaddr;
  int listenfd;
  int optval=1; 
  int i;
  listenfd = __syscall3(__NR_socket,AF_INET6,SOCK_STREAM,0);
  mybzero(&servaddr,sizeof(servaddr));
  servaddr.sin6_family = AF_INET6;
  servaddr.sin6_port=32000;
  servaddr.sin6_port = (servaddr.sin6_port >> 8) | ((servaddr.sin6_port & 0xFF) << 8);
  i=__syscall5(__NR_setsockopt,listenfd,SOL_SOCKET,SO_REUSEADDR,(long) &optval,sizeof(optval));
  if(i<0)
  { 
    errno = -i;
    myerror("setsockopt");
    __syscall1(__NR_exit, 1);
  }
  i = __syscall3(__NR_bind,listenfd,(long)&servaddr,sizeof(servaddr));
  if (i < 0)
  {
    errno = -i;
    myerror("bind");
    __syscall1(__NR_exit, 1);
  }
  __syscall2(__NR_listen, listenfd, 8);
  __syscall1(__NR_close, 0);
  __syscall2(__NR_dup2, listenfd, 0);
  __syscall1(__NR_close, listenfd);

  for(i=0; i<CHILDREN; i++)
  {
    child();
  }
  while(1) {
    __syscall4(__NR_wait4, -1, 0, 0, 0);
    child();
  }
}
