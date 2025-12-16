#ifndef COMMON_H
#define COMMON_H

/* Custom location type shared by Flex and Bison. */
typedef struct {
  int first_line;
  int first_column;
  int last_line;
  int last_column;
} Loc;

/* Flex reentrant scanner handle type (opaque). */
typedef void* yyscan_t;

/* Forward decls so Bison's YYSTYPE can reference Node/NodeList pointers. */
typedef struct Node Node;
typedef struct NodeList NodeList;

#endif /* COMMON_H */
