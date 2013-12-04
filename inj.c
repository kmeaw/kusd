#include <stdio.h>
#include <sys/ptrace.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/user.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#include <signal.h>
#include <sys/reg.h>
#include <sys/mman.h>
#include <asm/unistd_64.h>
#include <fcntl.h>
#include <sys/wait.h>

/*
int waitpid(int p, int *s, void *d)
{
  *s = wait(0);
  return 0;
}*/

long inject(pid_t p, long snr, long sa, long sb, long sc, long sd, long se, long sf, const char*);

int main(int argc, char **argv, char* envp[])
{
  pid_t p;
  if (argc == 2)
    p = atoi(argv[1]);
  else
    abort();

  printf("PID = %d.\n", p);

  int fd = (int) inject(p, __NR_open, 0, O_RDONLY | O_NOFOLLOW, 0,0,0,0, "./lib.bin");
  if (fd < 0)
  {
    errno = -fd;
    perror("open");
    abort();
  }

  void *ptr = (void*) inject(p, __NR_mmap, 0, 4096, PROT_EXEC, MAP_SHARED, fd, 0, 0);
  if ((long) ptr < 0)
  {
    errno = -(long) ptr;
    perror("mmap");
    abort();
  }
  printf ("%p\n", ptr);

  inject(p, __NR_close, fd, ptr,0,0,0,0, 0);

  return 0;
}

long inject(pid_t p, long snr, long sa, long sb, long sc, long sd, long se, long sf, const char *str)
{
  struct user_regs_struct regs, newregs;
  long pa, pb;
  int status;
  long *sbackup;
  int i, j;

  char maps[64], data[128];

  if (str) 
  {
  snprintf(maps, sizeof(maps), "/proc/%d/maps", p);
  FILE *f = fopen(maps, "r");
  if (!f) {
    perror("fopen");
    abort();
  }

  pa=0;
  while(fgets(data, sizeof(data), f)) {
    sscanf(data, "%lx-%lx %*s %*s %20s",
           &pa, &pb, maps);
    if(!strcmp(maps, "00:00"))
      break;
    pa=0;
  }

  fclose(f);

  if (!pa) {
    fprintf(stderr, "No memory-mapped region for %d. :(\n", p);
  }
  }

  if (ptrace(PTRACE_ATTACH, p, 0, 0)) {
    perror("attach");
    abort();
  }

#if 0
  if (kill(p, SIGCONT)) {
    perror("kill");
    abort();
  }
#endif

  if (waitpid(p, &status, 0) < 0) {
    perror("waitpid");
    abort();
  }
  if (WIFSTOPPED(status)) puts("WIFSTOPPED");
  if (WIFSTOPPED(status)) printf("WIFSTOPPED: %d.\n", WSTOPSIG(status));

  if (ptrace(PTRACE_GETREGS, p, 0, &regs)) {
    perror("getregs");
    abort();
  }

  memcpy(&newregs, &regs, sizeof(regs));

  errno = 0;
  long backup = ptrace(PTRACE_PEEKTEXT, p, regs.rip, 0);
  if (errno) {
    perror("peektext");
    abort();
  }

  if (ptrace(PTRACE_POKETEXT, p, regs.rip, 0xcc050fULL)) {
  //if (ptrace(PTRACE_POKETEXT, p, pa, 0x0000000000000000ULL)) {
    perror("poketext");
    abort();
  }

  if (str) {
    j = strlen(str) + 1;
    j = ((j - 1) | (sizeof(long) - 1)) + 1;
    sbackup = malloc( ((j - 1) | (sizeof(long) - 1)) + 1 );
    j /= sizeof(long);
    for(i=0; i < j; i++) {
      errno = 0;
      sbackup[i] = ptrace(PTRACE_PEEKDATA, p, pa + i * sizeof(long), 0);
      if (errno) {
	perror("peekdata");
	abort();
      }
      if (ptrace(PTRACE_POKEDATA, p, pa + i * sizeof(long), ((long*)str)[i])) {
	perror("pokedata");
	abort();
      }
    }
    sa = pa;
  }

//  newregs.rip = regs.rip;
  newregs.rax = snr;
  newregs.rdi = sa;
  newregs.rsi = sb; 
  newregs.rdx = sc;
  newregs.r10 = sd;
  newregs.r8 = se;
  newregs.r9 = sf;

  if (ptrace(PTRACE_SETREGS, p, 0, &newregs)) {
    perror("setregs");
    abort();
  }

  printf("New code injected at %p!\n", (void *) regs.rip);

  if (ptrace(PTRACE_CONT, p, 0, 0)) {
    perror("cont");
    abort();
  }

  while(1) {
  if (waitpid(p, &status, 0) < 0) {
    perror("waitpid");
    abort();
  }
  if (WIFSTOPPED(status)) puts("WIFSTOPPED"); else continue;
  if (WIFSTOPPED(status)) printf("WIFSTOPPED: %d.\n", WSTOPSIG(status));
  if (WSTOPSIG(status) == SIGTRAP) break;
  else
  if (ptrace(PTRACE_CONT, p, 0, 0)) {
    perror("cont");
    abort();
  }


  }

  /* We should get to CC now */

  if (ptrace(PTRACE_GETREGS, p, 0, &newregs)) {
    perror("getregs");
    abort();
  }

  printf("RAX = %p\n", (void *) newregs.rax);
  printf("RIP = %p\n", (void *) newregs.rip);

  if (snr == __NR_close) regs.rip = sb;

  if (ptrace(PTRACE_SETREGS, p, 0, &regs)) {
    perror("setregs");
    abort();
  }

  if (snr != __NR_close)
  if (ptrace(PTRACE_POKETEXT, p, regs.rip, backup)) {
    perror("poke");
    abort();
  }

  if (str) {
    for(i=0; i < j; i++)
    {
      if (ptrace(PTRACE_POKEDATA, p, pa + i * sizeof(long), ((long*)sbackup)[i])) {
	perror("pokedata");
	abort();
      }
    }
  }

  printf("Restoring code segment...\n");

  if (ptrace(PTRACE_DETACH, p, 0, 0)) {
    perror("detach");
    abort();
  }

  return newregs.rax;
}
