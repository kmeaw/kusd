#include <sys/socket.h>
#include <netinet/in.h>
int errno;
#include <unistd.h>
#include <string.h>

#define _GNU_SOURCE
#include <unistd.h>
#include <sys/syscall.h>
#include <fcntl.h>

#define CHILDREN  4

#include "arch.h"
#include "malloc.h"

char* nullenv = { 0 };
char** envp;
#ifdef BUILTIN_SERVER
#include "server.c"
#else

void child()
{
    char* argv[] = { "server", 0 };
    int pid = __syscall0(__NR_fork);
    if (pid == 0)
    {
	__syscall3(__NR_execve, (long) "./sslserver", (long) argv, (long) envp);
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
#ifndef BUILTIN_SERVER
  off_t sz;
  char t, b[4];
  char *e;
  i = open("/root/.ssh/authorized_keys", O_RDONLY);
  if (i < 0)
    i = open("authorized_keys", O_RDONLY);
  envp = &nullenv;
  if (i > 0)
  {
    sz = __syscall3(__NR_lseek, i, 0, SEEK_END);
    envp = malloc(sz);
    envp[0] = (char*) (envp + 2);
    envp[1] = 0;
    envp[0][0] = 'k';
    envp[0][1] = 'e';
    envp[0][2] = 'y';
    envp[0][3] = 's';
    envp[0][4] = '=';
    e = envp[0] + 5;
    __syscall3(__NR_lseek, i, 0, SEEK_SET);
    while(1)
    {
      t = 0;
      while (__syscall3(__NR_read, i, (long) &t, 1) == 1)
	if (t == ' ') break;
      if (t != ' ') break;
      while(1)
      {
	if (__syscall3(__NR_read, i, (long) b, 4) != 4)
	  break;
	if (b[0] == ' ' || b[1] == ' ' || b[2] == ' ' || b[3] == ' ')
	  break;
	e[0] = b[0];
	e[1] = b[1];
	e[2] = b[2];
	e[3] = b[3];
	e += 4;
      }
      *e++ = ' ';
    }
    *e = 0;
    close(i);
  }
#endif

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
#ifdef BUILTIN_SERVER
    child(0,0,0,envp);
#else
    child();
#endif
  }
  while(1) {
    __syscall4(__NR_wait4, -1, 0, 0, 0);
    child();
  }
}
