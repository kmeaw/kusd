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
const unsigned char data[1000][1000] = {{220, 208, 5, 111, 22, 90, 130, 9, 28, 33, 44, 238, 228, 169, 229, 122, 143, 13, 239, 126, 146, 204, 236, 49, 192, 123, 211, 43, 203, 65, 114, 187, 150, 244, 91, 128, 5, 39, 152, 62, 117, 121, 66, 179, 218, 130, 222, 65, 36, 184, 61, 93, 149, 68, 46, 77, 212, 223, 208, 248, 182, 23, 160, 144, 186, 142, 217, 67, 240, 79, 127, 143, 90, 38, 160, 58, 88, 215, 219, 70, 130, 94, 226, 137, 145, 157, 33, 196, 130, 11, 88, 77, 108, 200, 95, 95, 197, 219, 69, 69, 38, 14, 234, 188, 185, 182, 12, 18, 251, 182, 81, 75, 116, 198, 134, 53, 148, 103, 83, 108, 45, 219, 57, 187, 117, 119, 225, 189}, {157, 3, 173, 95, 172, 63, 145, 255, 255, 187, 38, 81, 71, 173, 9, 84, 46, 5, 188, 9}, {39, 149, 90, 203, 93, 112, 20, 101, 224, 234, 144, 208, 28, 9, 48, 207, 189, 233, 197, 216, 122, 198, 69, 106, 132, 42, 142, 159, 246, 4, 34, 167, 118, 56, 111, 60, 105, 117, 250, 88, 137, 243, 202, 200, 161, 111, 43, 51, 151, 219, 236, 78, 42, 189, 55, 250, 140, 160, 14, 232, 109, 147, 151, 221, 93, 110, 129, 139, 163, 253, 102, 82, 12, 240, 95, 58, 2, 15, 48, 220, 79, 230, 85, 97, 231, 205, 56, 69, 122, 16, 58, 82, 120, 217, 98, 105, 254, 120, 85, 86, 8, 254, 79, 170, 128, 51, 110, 151, 160, 75, 48, 16, 95, 126, 59, 40, 216, 51, 172, 131, 2, 209, 58, 2, 249, 213, 123, 0}, {53, 51, 21, 93, 82, 153, 238, 120, 216, 210, 226, 37, 124, 60, 97, 111, 245, 60, 164, 183, 109, 175, 197, 154, 2, 125, 82, 20, 164, 209, 65, 201, 172, 181, 111, 131, 75, 175, 125, 170, 118, 164, 147, 131, 160, 41, 212, 104, 13, 226, 236, 225, 216, 133, 200, 222, 0, 144, 69, 112, 90, 181, 149, 64, 252, 95, 176, 229, 70, 63, 123, 110, 3, 141, 144, 58, 63, 77, 33, 53, 78, 149, 121, 117, 86, 138, 69, 154, 40, 33, 212, 91, 172, 224, 129, 4, 41, 207, 7, 35, 144, 118, 139, 135, 246, 181, 71, 84, 150, 203, 211, 61, 95, 191, 160, 211, 189, 248, 35, 35, 11, 98, 82, 100, 209, 123, 46, 193}, {155, 241, 17, 35, 34, 43, 134, 59, 86, 23, 50, 62, 74, 83, 219, 170, 70, 83, 228, 65, 69, 179, 120, 195, 157, 68, 238, 31, 153, 238, 62, 102, 220, 77, 28, 213, 212, 185, 145, 5}, {231, 89, 228, 252, 50, 97, 81, 75, 61, 181, 33, 46, 209, 6, 97, 90, 255, 243, 24, 15, 201, 15, 233, 65, 113, 202, 242, 134, 244, 3, 71, 197}};
const int p[] = {128, 20, 128, 128, 40, 32};
const unsigned char dgst[] = {199, 115, 139, 212, 62, 221, 146, 194, 67, 63, 100, 102, 169, 165, 167, 87, 62, 199, 250, 66};
/*
155059868905464315581817197384072666472883203160760378637806631315933324808056172167443075571748093259131411863461622144144895215448901020344107077460521486533655075181545269242772037310403007224936595310770940745664520383427621470658373075872068758362784645330498221926898531457016570064647116883886482121149
896393556236186740394664213415960671045814696969
27796420464295110855808244100672724571252099231336277794258483826984107142730371531899112588085690936269969206457566780668918363466055042882003902185579228657641754566650420839817409662533385913494072690180404628227685972348922367820158042101218120446130419048903571197828000428566438445817841953882464680704
37357990769353243059249912448368176915836335401984106992734923844063374131158044975896896776965612285336709525725468663425848813002653557114761627788866886832461546852473607125897013647208697161131892940140034697530389182016466708500769088627825978220445671984239305508802122725276046982262607009425418563265
"\x9B\xF1\x11#\"+\x86;V\x172>JS\xDB\xAAFS\xE4AE\xB3x\xC3\x9DD\xEE\x1F\x99\xEE>f\xDCM\x1C\xD5\xD4\xB9\x91\x05"
890269541934704431755882991324851975529688196161
397922716615801970768829884261144901186657816837
---
w = 595429597966275761517340460465408556189696769919
u1 = 695254814894326654150232566557759881258553019968
u2 = 383448829151073121005352282655269053025128788540
890269541934704431755882991324851975529688196161
890269541934704431755882991324851975529688196161
*/

#include <stdlib.h>

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

/*
 * Perform an integer divide on a bigint.
 */
static bigint *bi_int_divide(BI_CTX *ctx, bigint *biR, comp denom)
{
    int i = biR->size - 1;
    long_comp r = 0;

    do
    {
        r = (r<<COMP_BIT_SIZE) + biR->comps[i];
        biR->comps[i] = (comp)(r / denom);
        r %= denom;
    } while (--i >= 0);

    return trim(biR);
}

#define ADD(xa,xb,xc) do { if (_##xa == _##xb) { _##xc=_##xa; xc=trim(bi_add(ctx,xa,xb)); } else { \
	int ttt=0; xc=trim(bi_subtract(ctx,xa,xb,&ttt)); _##xc=ttt^_##xa; }} while(0)
#define SUB(xa,xxb,xc) do { bigint *xb = bi_clone(ctx, xxb); if (_##xa != _##xxb) { _##xc=_##xa; xc=trim(bi_add(ctx,xa,xb)); } else { \
	int ttt=0; xc=trim(bi_subtract(ctx,xa,(xb),&ttt)); _##xc=ttt^_##xa; } } while(0)
#define MUL(xa,xb,xc) do { xc=trim(bi_multiply(ctx,xa,xb)); _##xc=_##xa^_##xb; } while(0)
#define DIV(xa,xb,xc) do { bigint *src = bi_clone(ctx,xa); xc=trim(bi_divide(ctx,src,xb,0)); _##xc=_##xa^_##xb; } while(0)
#define CPY(xa,xb) do { trim(xa); xb=bi_clone(ctx, xa); bi_permanent(xb); _##xb=_##xa; } while(0)
#define UDEBUG(x) do { trim(x); printf(#x "=0x"); int i = x->size; if (!i) printf("0"); while(i-- > 0) printf("%08x",x->comps[i]); printf("\n"); } while(0)
#define DEBUG(x) do { trim(x); printf(#x "=%s0x", _##x ? "-" : ""); int i = x->size; if (!i) printf("0"); while(i-- > 0) printf("%08x",x->comps[i]); printf("\n"); } while(0)
#define SWAP(xa,xb) do { bigint *tmp; int _tmp; _tmp = _##xa; tmp = xa; xa = xb; _##xa = _##xb; xb = tmp; _##xb = _##tmp; } while(0)

bigint* invmod (BI_CTX *ctx, bigint *a, bigint *b)
{
  bigint *b0 = bi_clone(ctx, b);
  bigint *t, *q, *t1;

  bigint *x0 = int_to_bi(ctx, 0);
  bigint *x1 = int_to_bi(ctx, 1);
  int _x0 = 0, _x1 = 0;
  int _b0 = 0, _t1 = 0;
  bi_permanent(x0);
//  bi_permanent(x1);
  bigint *one = bi_clone(ctx,x1);
  int _a = 0, _b = 0, _q = 0, _t = 0;
  if (bi_compare(b, x1) == 0)
    return 0;
  while (bi_compare (a, one) > 0)
  {
    trim(a);
    trim(b);
    bigint *src = bi_clone (ctx, a);
    q = bi_divide (ctx, src, b, 0);
    trim(q);
    //DIV(a, b, q);
    bi_copy(q);
    //bi_permanent(q);
    CPY(b, t);
    MUL(t, q, b);
    bi_free(ctx, t);
    CPY(b, t1);
    bi_free(ctx, b);
    SUB(a, t1, b);
    bi_depermanent(t1);
    bi_free(ctx, t1);
    CPY(t, a);
    bi_depermanent(t);
    bi_free(ctx, t);

    CPY(x0, t);
    bi_depermanent(x0);
    bi_free(ctx, x0);
    bi_copy(q);
    MUL(q, t, x0);
    //bi_depermanent(q);
    bi_free(ctx, q);
    if (bi_compare(x0, x1) > 0)
    {
      SUB(x0, x1, t1);
      _t1 ^= 1;
      bi_free(ctx, x0);
//      bi_depermanent(x1);
    }
    else
    {
      SUB(x1, x0, t1);
      bi_free(ctx, x0);
    }
    bi_free(ctx, x1);
    CPY(t1, x0);
    CPY(t, x1);
    bi_depermanent(t);
    bi_free(ctx, t);
  }
  if (_x1)
  {
    CPY(x1, t);
    ADD(b0, t, x1);
  }
  bi_depermanent(x0);
  bi_free(ctx, x0);
  bi_free(ctx, one);
  return x1;
}

#define ssl_write(ctx,data,sz) do { write(1,data,sz); write(1,"\n",1); } while(0)
#define SSL_FAIL abort()

int main() {
	BI_CTX *ctx = bi_initialize();
	bigint *_p = (bi_import(ctx, data[0], p[0]));
	bigint *_q = (bi_import(ctx, data[1], p[1]));
	bigint *_g = (bi_import(ctx, data[2], p[2]));
	bigint *_y = (bi_import(ctx, data[3], p[3]));
	bigint *_r = (bi_import(ctx, data[4], p[4] / 2)); /* 40 */
	bigint *_s = (bi_import(ctx, data[4] + p[4] / 2, p[4] / 2));
	bigint *d = (bi_import(ctx, dgst, sizeof(dgst)));

	bi_permanent(_p);
	bi_permanent(_q);
	bi_permanent(_g);
	bi_permanent(_y);
	bi_permanent(_r);
	bi_permanent(_s);
	bi_permanent(d);

	if (p[4] != 40)
	{
	  ssl_write(ssl, "BADS", 4);
	  SSL_FAIL;
	}

	if (bi_compare(_s, _q) != -1)
	{
	  ssl_write(ssl, "BADQ", 4);
	  SSL_FAIL;
	}

	bigint *w = invmod(ctx, _s, _q);
	if (!w)
	{
	  ssl_write(ssl, "s^-1", 4);
	  SSL_FAIL;
	}
	bi_permanent(w);

	bigint *u1 = bi_multiply(ctx, w, d);
	u1 = bi_divide(ctx, u1, _q, 1);
	bi_permanent(u1);

	bigint *u2 = bi_multiply(ctx, w, _r);
	bi_permanent(u2);
	u2 = bi_divide(ctx, u2, _q, 1);

	bigint *t1 = bi_mod_power2(ctx, _g, _p, u1);
	bigint *t2 = bi_mod_power2(ctx, _y, _p, u2);

	bigint *v = bi_multiply(ctx, t1, t2);
	v = bi_divide(ctx, v, _p, 1);
	v = bi_divide(ctx, v, _q, 1);

	if (bi_compare(v, _r) != 0)
	{
	  ssl_write(ssl, "BADD", 4);
	  SSL_FAIL;
	}

	puts ("OKAY!");

	bi_depermanent(w);
	bi_depermanent(_p);
	bi_depermanent(_q);
	bi_depermanent(_g);
	bi_depermanent(_y);
	bi_depermanent(_r);
	bi_depermanent(_s);
	bi_depermanent(d);
	bi_depermanent(u1);
	bi_depermanent(u2);

	bi_free(ctx, u1);
	bi_free(ctx, u2);
	bi_free(ctx, w);
	bi_free(ctx, _p);
	bi_free(ctx, _q);
	bi_free(ctx, _g);
	bi_free(ctx, _y);
	bi_free(ctx, _r);
	bi_free(ctx, _s);
	bi_free(ctx, d);

	bi_terminate(ctx);
	return 0;
}

