all: sslserver manager

.PHONY: clean

clean:
	rm -f server server.o manager manager.o sslserver sslserver.o tiny

dist: dist.tar.gz
	
dist.tar.gz: server manager
	tar zcvf dist.tar.gz server manager

sslserver: sslserver.o malloc.o lib.o
	$(CC) $^ -o $@ $(CFLAGS) $(LDFLAGS) -laxtls

manager: manager.o malloc.o lib.o

tiny: server.c manager.c arch.h
	$(CC) $(CFLAGS) -Os -s $(LDFLAGS) -DBUILTIN_SERVER=1 manager.c -o tiny

test: test.o
	$(CC) $(CFLAGS) $^ -o $@ -laxtls

CFLAGS=-Wall -DSSLIDENT='{0xc1d24ee63f0240c1,0xa19fcd7e1a4098f7}' -DIDENT='{0x5eae544548d7b14b,0x4f545120653ca4e8}' -g -O2 -fno-stack-protector -Wno-pointer-sign
LDFLAGS=-static -nostdlib
