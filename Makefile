CC=gcc
CFLAGS=-Wall -Wextra -O2
LDLIBS=-lm

all: calc

parser.tab.c parser.tab.h: parser.y
	bison -d -Wall parser.y

lex.yy.c: lexer.l parser.tab.h
	flex lexer.l

calc: lex.yy.c parser.tab.c
	$(CC) $(CFLAGS) -o $@ lex.yy.c parser.tab.c $(LDLIBS)

clean:
	rm -f calc lex.yy.c parser.tab.c parser.tab.h

.PHONY: all clean
