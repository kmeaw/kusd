#include <fcntl.h>
#include <sys/types.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include <axTLS/ssl.h>

#ifndef BUILTIN_SERVER
#include "arch.h"
#endif

#include "malloc.h"
#include "lib.h"

struct __attribute__((packed)) sysreq
{
  long snr, sa, sb, sc, sd, se, sf;
};

#ifdef BUILTIN_SERVER
#define STARTFUNC child
#else
#define STARTFUNC _start
#endif

#define SSL_FAIL do { ssl_ctx_free(ssl_ctx); goto acceptloop; } while(0)

/*
 * Delete any leading 0's (and allow for 0).
 */
static bigint *trim(bigint *bi)
{
    while (bi->comps[bi->size-1] == 0 && bi->size > 1)
    {
        bi->size--;
    }

    return bi;
}

bigint* invmod (BI_CTX *ctx, bigint *a, bigint *b)
{
  bigint *x, *y, *u, *v, *A, *B, *C, *D, *zero, *one;
  int low = 0;

  /* x = a, y = b */
  x = bi_divide(ctx, a, b, 1);
  y = bi_clone(ctx, b);

  /* 2. [modified] if x,y are both even then return an error! */
  if (x->comps[0] & 1 == 0 && y->comps[0] & 1 == 0)
    return 0;

  /* 3. u=x, v=y, A=1, B=0, C=0,D=1 */
  u = bi_clone(ctx, x);
  v = bi_clone(ctx, y);
  A = int_to_bi(ctx, 1);
  B = int_to_bi(ctx, 0);
  C = int_to_bi(ctx, 0);
  D = int_to_bi(ctx, 1);
  zero = trim(int_to_bi(ctx, 0));
  one = int_to_bi(ctx, 1);

top:
  /* 4.  while u is even do */
  while (u->comps[0] & 1 == 0) {
    /* 4.1 u = u/2 */
    u = bi_int_divide(ctx, u, 2);
    /* 4.2 if A or B is odd then */
    if (A->comps[0] & 1 == 1 || B->comps[0] & 1 == 1) {
      /* A = (A+y)/2, B = (B-x)/2 */
      A = bi_int_divide(ctx, bi_add(ctx, A, y), 2);
      B = bi_int_divide(ctx, bi_sub(ctx, B, x, 0), 2);
    }
    /* A = A/2, B = B/2 */
    A = bi_int_divide(ctx, A, 2);
    B = bi_int_divide(ctx, B, 2);
  }

  /* 5.  while v is even do */
  while (v->comps[0] & 1 == 0) {
    /* 5.1 v = v/2 */
    v = bi_int_divide(ctx, v, 2);
    /* 5.2 if C or D is odd then */
    if (C->comps[0] & 1 == 1 || D->comps[0] & 1 == 1) {
      /* C = (C+y)/2, D = (D-x)/2 */
      C = mp_int_div(ctx, mp_add(ctx, C, y), 2);
      D = mp_int_div(ctx, bi_sub(ctx, D, x, 0), 2);
    }
    /* C = C/2, D = D/2 */
    C = mp_int_div(ctx, C, 2);
    D = mp_int_div(ctx, D, 2);
  }

  /* 6.  if u >= v then */
  if (bi_compare (u, v) >= 0) {
    /* u = u - v, A = A - C, B = B - D */
    u = bi_subtract(ctx, u, v, 0);
    A = bi_subtract(ctx, A, C, 0);
    B = bi_subtract(ctx, B, D, 0);
  } else {
    /* v = v - u, C = C - A, D = D - B */
    v = bi_subtract(ctx, v, u, 0);
    C = bi_subtract(ctx, C, A, &low);
    D = bi_subtract(ctx, D, B, 0);
  }

  if (bi_compare (trim(u), zero))
    goto top;

  /* now a = C, b = D, gcd == g*v */

  /* if v != 1 then there is no inverse */
  if (bi_compare (v, one) == 0)
    return 0;

  /* if its too low */
  while (low)
    C = bi_subtract(ctx, b, C, &low);

  /* too big */
  while (bi_compare(C, b) >= 0)
    C = bi_subtract(ctx, C, b, 0);
  
  /* C is now the inverse */
  return C;
}

void __attribute__ ((naked)) STARTFUNC (void)
{
     asm(" xorl %ebp, %ebp\n"
	 " movq %rdx, %r9\n"
	 " popq %rsi\n"
	 " movq %rsp, %rdx\n"
	 " andq $~15, %rsp\n"
	 " pushq %rax\n"
	 " pushq %rsp\n"
	 " call go\n"
	 " hlt\n"
         );
}

void go(void __attribute__((unused)) *zero, int argc, char**argv)
{
  struct sysreq r;
  int fd;
  long n, s;
  uint64_t sslid[] = SSLIDENT;
  uint64_t id[] = IDENT;
  SSL *ssl;
  SSL_CTX *ssl_ctx;
  uint8_t *readbuf;
  int pid;
  int sv[2];
  uint8_t *crypto;
  int p[5];
  SHA1_CTX sha1;
  uint8_t dgst[SHA1_SIZE];
  char *keyscan, *keyprev, *keynext, *keywrite, *keymove;
  static char *keybuf[32] = { 0, };
  uint32_t value, *vptr;
  const char alpha[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
  char *keys = 0;

  if (argv)
    keys = argv[argc + 1];
  if (keys)
  {
    keyscan = keys + 5;
    n = 0;
    while (*keyscan)
    {
      keyprev = keyscan;
      keynext = strchr(keyscan, ' ');
      if (keynext)
	keynext++;
      else
	keynext = keyscan + strlen(keyscan);
      keybuf[n] = malloc(3220);
      memset (keybuf[n], 0, 3220);
      keywrite = keybuf[n] + 28;

      while(*keyscan && *keyscan != ' ')
      {
	value   = 0;
	value  |= strchr(alpha, *keyscan++) - alpha;
	value <<= 6;
	value  |= strchr(alpha, *keyscan++) - alpha;
	value <<= 6;
	if (*keyscan != '=')
	  value  |= strchr(alpha, *keyscan++) - alpha;
	else
	  keyscan++;
	value <<= 6;
	if (*keyscan != '=')
	  value  |= strchr(alpha, *keyscan++) - alpha;
	else
	  keyscan++;

	*keywrite++ = (value >> 16) & 0xFF;
	if (keyscan[-2] != '=')
	  *keywrite++ = (value >> 8) & 0xFF;
	if (keyscan[-1] != '=')
	  *keywrite++ = value & 0xFF;
      }

      s = 0;
      vptr = (uint32_t*) (keybuf[n] + 4);
      for (keyscan = keymove = keybuf[n] + 28; 
	   keyscan < keywrite && (char*) vptr < keybuf[n] + 28; 
	   s++)
      { 
	value = htonl(* ((uint32_t *) keyscan));
	if (!s && value && keyscan == keybuf[n] + 28)
	{
	  if (value > 3 && value < 32)
	  {
	    memcpy (keybuf[n], keyscan + 4 + value - 3, 3);
	    keybuf[n][3] = ':';
          }
	  keyscan = keymove + 4 + value;
	}
	else if (value)
	{
	  *vptr++ = value;
	  keyscan += 4;
	  memcpy (keymove, keyscan, value);
	  keymove += value;
	  keyscan += value;
	}
	else
	  break;
      }
      if (keymove < keybuf[n] + 3220)
        memset (keymove, 0, keybuf[n] + 3220 - keymove);
      if ((char*) vptr < keybuf[n] + 24)
	*vptr = 44;
      keyscan = keynext;

      n++;
    }
    keybuf[n] = 0;
  }

  __syscall1(__NR_close, 3);
acceptloop:
  ssl_ctx = ssl_ctx_new(0, 1);
  if (!ssl_ctx)
  {
    myerror("ssl_ctx_new");
    __syscall1(__NR_exit, 1);
  }
  fd = __syscall3(__NR_accept, 0, 0, 0);
  if (fd < 0)
  {
    myerror("accept");
    __syscall1(__NR_exit, 1);
  }
  if (write(fd, sslid, sizeof(sslid)) != sizeof(sslid))
  {
    myerror("write");
    __syscall1(__NR_exit, 1);
  }
  ssl = ssl_server_new(ssl_ctx, fd);
  if (!ssl)
  {
    myerror("ssl_server_new");
    __syscall1(__NR_exit, 1);
  }
  crypto = malloc (3220);
  memset (crypto, 0, 3220);

  while (1)
  {
    n = ssl_read(ssl, &readbuf);
    if (n == 0)
      continue;
    if (n < 0)
      SSL_FAIL;
    /* rsa = e + n + 0 + 0 + S */
    /* dsa = p + q + g + y + S */
    if (n != 24)
      SSL_FAIL;

    s = 0;
    for(n = 0; n < 5; n++)
      s += p[n] = htonl(* (uint32_t *) (readbuf + 4 * (n + 1)));

    if (s > 1600)
    {
      ssl_write(ssl, "2BIG", 4);
      SSL_FAIL;
    }

    if (!ssl_get_session_id_size(ssl))
      SSL_FAIL;

    SHA1_Init(&sha1);
    SHA1_Update(&sha1, ssl_get_session_id(ssl), ssl_get_session_id_size(ssl));
    SHA1_Final(dgst, &sha1);

    {
      memcpy (crypto, readbuf, 20);
      ssl_write(ssl, "ACK.", 4);
      do
      {
        n = ssl_read(ssl, &readbuf);
        if (n && n != s)
        {
	  ssl_write(ssl, "SIZE", 4);
	  SSL_FAIL;
        }
      } while (!n);
      memcpy (crypto + 20, readbuf, n);
      s = -1;
      for(n = 0; n < sizeof(keybuf) / sizeof(keybuf[0]) - 1; n++)
      {
	if (!keybuf[n])
	  continue;
	if (!memcmp (keybuf[n] + 28, crypto + 20, p[0] + p[1] + p[2] + p[3]))
	{
	  s = n;
	  break;
	}
      }
      if (s == -1)
      {
	if (keybuf[0])
	  ssl_write(ssl, "NEXT", 4);
	else
	  ssl_write(ssl, "KEYS", 4);
      }
      else if (!memcmp (crypto, "rsa:", 4))
      {
	RSA_CTX *ctx = 0;
	for(s=0; s < p[1] && !crypto[20 + p[0] + s]; s++);
	RSA_pub_key_new(&ctx, crypto + 20 + p[0] + s, p[1] - s, crypto + 20, p[0]);
	if (!ctx)
	{
	  ssl_write(ssl, "RSA!", 4);
	  SSL_FAIL;
	}
	s = RSA_decrypt(ctx, crypto + 20 + p[0] + p[1], crypto + 20 + p[0] + p[1] + p[4], 0);
	RSA_free(ctx);
	if (s != sizeof(dgst) + 15)
	{
	  ssl_write(ssl, "RSA?", 4);
	  SSL_FAIL;
	}
	if (!memcmp (crypto + 20 + p[0] + p[1] + p[4] + 15, dgst, sizeof(dgst)))
	  break;
      }
      else if (!memcmp (readbuf, "dss:", 4))
      {
	BI_CTX *ctx = bi_initialize();
	bigint *_p = trim(bi_import(ctx, crypto + 20, p[0]));
	bigint *_q = trim(bi_import(ctx, crypto + 20 + p[0], p[1]));
	bigint *_g = trim(bi_import(ctx, crypto + 20 + p[0] + p[1], p[2]));
	bigint *_y = trim(bi_import(ctx, crypto + 20 + p[0] + p[1] + p[2], p[3]));
	bigint *_s = trim(bi_import(ctx, dgst, sizeof(dgst)));
	bigint *zero = trim(int_to_bi(ctx, 0));
	bigint *one = int_to_bi(ctx, 1);

	if (bi_compare(_s, _q) != -1 || bi_compare(_s, zero) == 0)
	{
	  ssl_write(ssl, "BADQ", 4);
	  SSL_FAIL;
	}
	
	bi_terminate(ctx);
      }
      else
      {
	ssl_write(ssl, "BAD.", 4);
	SSL_FAIL;
      }
    }
  }
  free (crypto);
  ssl_write(ssl, "OKAY", 4);

  if (__syscall4(__NR_socketpair, PF_LOCAL, SOCK_STREAM, 0, (long) sv) < 0)
  {
    myerror("socketpair");
    __syscall1(__NR_exit, 1);
  }
  pid = __syscall0(__NR_fork);
  if (pid < 0)
  {
    myerror("fork");
    __syscall1(__NR_exit, 1);
  }
  if (pid == 0)
  {
    __syscall1(__NR_close, sv[0]);
    fd_set read_set;
    while(1)
    {
      FD_ZERO(&read_set);
      FD_SET(fd, &read_set);
      if (ssl_handshake_status (ssl) == SSL_OK)
        FD_SET(sv[1], &read_set);
      if ((n = __syscall5(__NR_select, (fd>sv[1])?(fd+1):(sv[1]+1), (long) &read_set, 0,0,0)) > 0)
      {
	uint8_t buf[1024];
	if (FD_ISSET(sv[1], &read_set))
	{
	  n = __syscall3(__NR_read, sv[1], (long) buf, sizeof(buf));
	  if (n > 0)
	    n = ssl_write(ssl, buf, n);
	  else if (n < 0)
	    break;
	}
	if (FD_ISSET(fd, &read_set))
	{
	  n = ssl_read(ssl, &readbuf);
	  if (n > 0)
	    n = __syscall3(__NR_write, sv[1], (long) readbuf, n);
	  else if (n < 0)
	    break;
	  n = 1;
	}
      }
      if (n < 0) break;
    }
    __syscall1(__NR_exit, 0);
  }
//  __syscall1(__NR_close, fd);
  fd = sv[0];
  __syscall1(__NR_close, sv[1]);
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
  ssl_free(ssl);
  goto acceptloop;
}

