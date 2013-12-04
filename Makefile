all: server manager

.PHONY: clean

clean:	
	rm -f server server.o manager manager.o

dist: dist.tar.gz
	
dist.tar.gz: server manager
	tar zcvf dist.tar.gz server manager

tiny: server.c manager.c arch.h
	$(CC) $(CFLAGS) $(LDFLAGS) -DBUILTIN_SERVER=1 manager.c -o tiny

CFLAGS=-Wall -DIDENT='{0x5eae544548d7b14b,0x4f545120653ca4e8}' -g -Os
LDFLAGS=-static -nostdlib
