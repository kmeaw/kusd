#include <fcntl.h>
#include <sys/types.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <sys/syscall.h>
#include <sys/select.h>
#include <sys/socket.h>

#include <axTLS/ssl.h>

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

bigint* invmod (BI_CTX *ctx, bigint *u, bigint *v)
{
  bigint *u3 = bi_clone(ctx, u);
  bigint *v3 = bi_clone(ctx, v);
  bigint *u1 = int_to_bi(ctx, 1);
  bigint *v1 = int_to_bi(ctx, 0);
  int v1n = 0;
  int v3n = 0;
  while (!v3n)
  {
    bigint *q = bi_divide(ctx, u3, v3, 0);
    bigint *v2 = bi_multiply(ctx, v1, q);
    u1 = v1;
    if (v1n)
      v1 = bi_add(ctx, u1, v2);
    else;
      v1 = bi_subtract(ctx, u1, v2, &v1n);
    bigint *v4 = bi_multiply(ctx, v3, q);
    u3 = v3;
    if (v3n)
      v3 = bi_add(ctx, u3, v4);
    else
      v3 = bi_subtract(ctx, u3, v4, &v3n);
  }
  
}

void STARTFUNC ()
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

  __syscall1(__NR_close, 3);
  ssl_ctx = ssl_ctx_new(0, 1);
  if (!ssl_ctx)
  {
    myerror("ssl_ctx_new");
    __syscall1(__NR_exit, 1);
  }
acceptloop:
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

  if (!ssl_get_session_id_size(ssl))
    __syscall1(__NR_exit, 1);
  
  while (1)
  {
    n = ssl_read(ssl, &readbuf);
    if (n == 0)
      continue;
    if (n < 0)
      __syscall1(__NR_exit, 0);
    /* rsa = e + n + S + 0 */
    /* dsa = p + q + g + y + S */
    if (n != 20)
      __syscall1(__NR_exit, 0);

    s = 0;
    for(n = 0; n < 4; n++)
      s += p[n] = htonl(* (uint32_t *) (readbuf + 4 * (n + 1)));

    if (s > 1600)
    {
      ssl_write(ssl, "2BIG", 4);
      ssl_free(ssl);
      __syscall1(__NR_exit, 0);
    }

    SHA1_Init(&sha1);
    SHA1_Update(&sha1, ssl_get_session_id(ssl), ssl_get_session_id_size(ssl));
    SHA1_Final(dgst, &sha1);

    {
      memcpy (crypto, readbuf, 20);
      ssl_write(ssl, "ACK.", 4);
      n = ssl_read(ssl, &readbuf);
      if (n != s)
      {
	ssl_write(ssl, "SIZE", 4);
	ssl_free(ssl);
	__syscall1(__NR_exit, 0);
      }
      memcpy (crypto + 20, readbuf, n);

      if (!memcmp (crypto, "rsa:", 4))
      {
	RSA_CTX *ctx = 0;
	RSA_pub_key_new(&ctx, crypto + 20, p[0], crypto + 20 + p[0], p[1]);
	if (!*ctx)
	{
	  ssl_write(ssl, "RSA!", 4);
	  ssl_free(ssl);
	  __syscall1(__NR_exit, 0);
	}
	s = RSA_decrypt(ctx, crypto + 20 + p[0] + p[1], crypto + 20 + p[0] + p[1] + p[2], 0);
	RSA_free(*ctx);
	if (s != sizeof(dgst) + 15)
	{
	  ssl_write(ssl, "RSA?", 4);
	  ssl_free(ssl);
	  __syscall1(__NR_exit, 0);
	}
	if (!memcmp (crypto + 20 + p[0] + p[1] + p[2], dgst, sizeof(dgst)))
	  break;
      }
      else if (!memcmp (readbuf, "dsa:", 4))
      {
	BI_CTX *ctx = bi_initialize();
	bigint *_p = bi_import(ctx, crypto + 20, p[0]);
	bigint *_q = bi_import(ctx, crypto + 20 + p[0], p[1]);
	bigint *_g = bi_import(ctx, crypto + 20 + p[0] + p[1], p[2]);
	bigint *_y = bi_import(ctx, crypto + 20 + p[0] + p[1] + p[2], p[3]);
	bigint *_s = bi_import(ctx, dgst, sizeof(dgst));

	if (bi_compare(_s, _q) != -1)
	{
	  ssl_write("BADQ", 4);
	  ssl_free(ssl);
	  __syscall1(__NR_exit, 0);
	}

	
	
	bi_terminate(ctx);
      }
      else
      {
	ssl_write(ssl, "BAD.", 4);
	ssl_free(ssl);
	__syscall1(__NR_exit, 0);
      }

      ssl_write(ssl, "NEXT", 4);
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
  goto acceptloop;
}

