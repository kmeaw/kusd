#include <stdarg.h>
#include <fcntl.h>
#include <sys/types.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include "arch.h"

int errno = 0;
int* __errno_location() { 
  return &errno;
}

/* Tiny libc */
void abort()
{
  __syscall1(__NR_exit, 2);
}

void __chk_fail ()
{
  abort();
}

void *
__strcpy_chk (char *dest, char *src, size_t dstlen)
{
  size_t len = strlen (src);

  if (__builtin_expect (dstlen < len, 0))
    __chk_fail ();

  return memcpy (dest, src, len + 1);
}

void *
__memcpy_chk (char *dest, char *src, size_t len, size_t dstlen)
{
  if (__builtin_expect (dstlen < len, 0))
    __chk_fail ();

  return memcpy (dest, src, len);
}

long int
__fdelt_chk (long int d)
{
  if (d >= FD_SETSIZE)
    __chk_fail ();

  return d / __NFDBITS;
}

void *memcpy(void *dest, const void *src, size_t n)
{
  uint8_t *_dest = (uint8_t*) dest, *_src = (uint8_t*) src;
  while (n--)
  {
    *_dest++ = *_src++;
  }
}

void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset)
{
  void *result = __syscall6(__NR_mmap, addr, length, prot, flags, fd, offset);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

int munmap(void *addr, size_t length)
{
  int result = __syscall2(__NR_munmap, addr, length);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

ssize_t read(int fd, void *ptr, size_t count)
{
  ssize_t result = __syscall3(__NR_read, fd, ptr, count);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

time_t time(time_t *t)
{
  time_t result = __syscall1(__NR_time, t);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

ssize_t write(int fd, const void *ptr, size_t count)
{
  ssize_t result = __syscall3(__NR_write, fd, ptr, count);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

void *memset (void *_s, int c, size_t n)
{
  char *s = (char*) _s;
  while (n--)
    *s++ = c;
  return _s;
}

char *strchr(const char *s, int c)
{
  while (*s)
    if (*s == c)
      return s;
    else
      s++;
  return 0;
}

int memcmp(const void *_s1, const void *_s2, size_t n)
{
  const char *s1 = _s1;
  const char *s2 = _s2;

  while (n)
  {
    if (*s1 != *s2)
      return *s1 - *s2;
    s1++;
    s2++;
    n--;
  }

  return 0;
}

void *mremap(void *old_address, size_t old_size,
                        size_t new_size, int flags, void *new_address)
{
  void *result = __syscall5(__NR_mremap, old_address, old_size, new_size, flags, new_address);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

int select (int __nfds, fd_set *__restrict __readfds,
		   fd_set *__restrict __writefds,
		   fd_set *__restrict __exceptfds,
		   struct timeval *__restrict __timeout)
{
  int result = __syscall5(__NR_select, __nfds, (long) __readfds, (long) __writefds, (long) __exceptfds, (long) __timeout);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

FILE* fopen(const char *path, const char *mode)
{
  int fd = __syscall2(__NR_open, (long) path, O_RDONLY);
  if (fd > 0)
  {
    return (FILE*)fd;
  }

  errno = -fd;
  return NULL;
}

int close(int fd)
{
  int res = __syscall1(__NR_close, fd);
  if (res)
  {
    errno = -res;
    return -1;
  }

  return 0;
}

FILE *stderr = (FILE *) 2;

int fclose(FILE *f)
{
  return close((int) f);
}

int fseek(FILE *stream, long offset, int whence)
{
  int res = __syscall3(__NR_lseek, (int)stream, offset, whence);
  if (res < 0)
  {
    errno = -res;
    return -1;
  }
  return 0;
}

long ftell(FILE *stream)
{
  long res = __syscall3(__NR_lseek, (int)stream, 0, SEEK_CUR);
  if (res < 0)
  {
    errno = -res;
    return -1;
  }
  return 0;
}

size_t fread(void *ptr, size_t size, size_t nmemb, FILE *stream)
{
  size_t res = 0;
  int t;
  while(nmemb)
  {
    t = read((int)stream, ptr, size);
    if (t != size)
    {
      if (t >= 0)
	errno = 0;
      return res;
    }
    res++;
    nmemb--;
  }

  return res;
}

int puts(const char *s)
{
  size_t sz = strlen(s);
  sz = write(2, s, sz);
  write(2, "\n", 1);
  return sz;
}

size_t strlen(const char *s)
{
  size_t n = 0;
  while (*s++) n++;
  return n;
}

int rand()
{
  return 111;
}

const char* strstr(const char *haystack, const char *needle)
{
  size_t hsl = strlen(haystack);
  size_t ndl = strlen(needle);
  if (ndl > hsl)
    return 0;
  while (*haystack)
  {
    if (!memcmp (haystack, needle, ndl))
      return haystack;
    haystack++;
  }

  return 0;
}

int __open_2(const char *path, int mode)
{
  int fd = __syscall2(__NR_open, (long) path, mode);
  if (fd > 0)
    return fd;

  errno = -fd;
  return -1;
}

int open(const char *path, int flags, ...) { return __open_2(path, flags); }

int __printf_chk (int __flag, const char *__restrict __format, ...)
{
  puts("printf_chk");
}

int __vfprintf_chk (FILE *__restrict __stream, int __flag,
                    const char *__restrict __format, _G_va_list __ap)
{
  puts("vfprintf_chk");
}

time_t mktime(struct tm *tm)
{
  //FIXME
  return tm->tm_sec + 60 * (tm->tm_min + 60 * (tm->tm_hour + 24 * (tm->tm_yday + 365 * (tm->tm_year - 70)) + 6 * (tm->tm_year - 70)));
}

#if 0
uint32_t ntohl(uint32_t netlong)
{
  return (netlong >> 24) | ( ((netlong >> 16) & 0xFF) << 8) | ( ((netlong >> 8) & 0xFF) << 16) | ((netlong & 0xFF) << 24);
}

uint32_t htonl(uint32_t hostlong)
{
  return (hostlong >> 24) | ( ((hostlong >> 16) & 0xFF) << 8) | ( ((hostlong >> 8) & 0xFF) << 16) | ((hostlong & 0xFF) << 24);
}
#endif

char *strcpy(char *dest, const char *src)
{
  char *d = dest;
  while (*src) *d++ = *src++;
  return d;
}

int putchar(int c)
{
  return write(2, &c, 1);
}

int fcntl(int fd, int cmd, ...)
{
  va_list ap;
  va_start(ap, cmd);
  int arg = va_arg(ap, int);
  va_end(ap);
  int result = __syscall3(__NR_fcntl, fd, cmd, arg);
  if ((int)result < 0 && (int)result > -256)
  {
    errno = -(int)result;
    return -1;
  }
  return result;
}

int printf(const char *fmt, ...) { return puts("printf"); }
int vprintf(const char *fmt, va_list ap) { return puts("vprintf"); }
int sprintf(char *str, const char *fmt, ...) { *str = 0; return puts("sprintf"); }

int strcmp(const char *s1, const char *s2)
{
  while (*s1 == *s2)
  {
    s1++; s2++;
  }
  return *s1 - *s2;
}

int gettimeofday(struct timeval *tv, struct timezone *tz)
{
  if (tv)
  {
    tv->tv_sec = time(0);
    tv->tv_usec = 0;
  }
  if (tz)
  {
    tz->tz_minuteswest = 0;
    tz->tz_dsttime = 0;
  }
  return 0;
}
