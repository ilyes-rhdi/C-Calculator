%code requires {
  /* Shared types for header + lexer. */
  #include "common.h"
}

%code provides {
  /* Prototypes so parser.tab.c sees them before yyparse uses them. */
  int yylex(YYSTYPE* yylval, Loc* yylloc, yyscan_t scanner);
  void yyerror(Loc *loc, yyscan_t scanner, const char *msg);
}

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>

#include "common.h"

/* Forward-declare YYSTYPE so we can prototype yylex before Bison defines it. */
typedef union YYSTYPE YYSTYPE;
int yylex(YYSTYPE* yylval, Loc* yylloc, yyscan_t scanner);
void yyerror(Loc *loc, yyscan_t scanner, const char *msg);

typedef struct yy_buffer_state *YY_BUFFER_STATE;

/* AST structures (full definitions stay in the .c, not in the header). */
typedef enum { N_NUM = 1, N_BIN, N_UN, N_FUNC } NodeType;

struct NodeList { Node *expr; struct NodeList *next; };

struct Node {
  NodeType type;
  Loc loc;
  double num;
  int op;
  Node *left;
  Node *right;
  int fkind;
  NodeList *args;
};

static Node* mk_num(double v, Loc loc);
static Node* mk_bin(int op, Node* a, Node* b, Loc loc);
static Node* mk_un(int op, Node* a, Loc loc);
static Node* mk_func(int fkind, NodeList* args, Loc loc);

static NodeList* list_single(Node* e);
static NodeList* list_append(NodeList* lst, Node* e);

static void free_node(Node* n);
static void free_list(NodeList* l);

static int eval_node(Node* n, double* out);
static int eval_func(int fkind, NodeList* args, double* out);

static void print_postfix(Node* n);
static char* gen_tac(Node* n, int* temp_id);

static int had_error = 0;
static void sem_error(Loc loc, const char* msg);

Node* root = NULL;

/* Flex (reentrant) prototypes */
int yylex_init(yyscan_t* scanner);
int yylex_destroy(yyscan_t scanner);
YY_BUFFER_STATE yy_scan_string(const char* str, yyscan_t scanner);
void yy_delete_buffer(YY_BUFFER_STATE b, yyscan_t scanner);
void yyset_in(FILE* in_str, yyscan_t scanner);
%}

/* Tell Bison to use our custom location type. */
%define api.location.type {Loc}
%define api.pure full
%define parse.error verbose
%locations
%parse-param { yyscan_t scanner }
%lex-param   { yyscan_t scanner }

%union {
  double dval;
  Node*  node;
  NodeList* list;
  int fkind;
}

%token <dval> NUMBER
%token SOMME PRODUIT MOYENNE VARIANCE ECART_TYPE
%token LEX_ERROR

%type <node> expr term factor funcall
%type <list> arglist arglist_opt
%type <fkind> funcname

%start program

%%

program : expr { root = $1; } ;

expr
  : expr '+' term { $$ = mk_bin('+', $1, $3, @1); }
  | expr '-' term { $$ = mk_bin('-', $1, $3, @1); }
  | term          { $$ = $1; }
  ;

term
  : term '*' factor { $$ = mk_bin('*', $1, $3, @1); }
  | term '/' factor { $$ = mk_bin('/', $1, $3, @1); }
  | factor          { $$ = $1; }
  ;

factor
  : '-' factor            { $$ = mk_un('n', $2, @1); }
  | '(' expr ')'          { $$ = $2; }
  | NUMBER                { $$ = mk_num($1, @1); }
  | funcall               { $$ = $1; }
  | LEX_ERROR             { $$ = mk_num(0.0, @1); had_error = 1; }
  ;

funcall
  : funcname '(' arglist_opt ')'
      {
        if ($3 == NULL) {
          sem_error(@1, "appel de fonction sans arguments");
          $$ = mk_num(0.0, @1);
        } else {
          $$ = mk_func($1, $3, @1);
        }
      }
  ;

funcname
  : SOMME      { $$ = SOMME; }
  | PRODUIT    { $$ = PRODUIT; }
  | MOYENNE    { $$ = MOYENNE; }
  | VARIANCE   { $$ = VARIANCE; }
  | ECART_TYPE { $$ = ECART_TYPE; }
  ;

arglist_opt
  : %empty     { $$ = NULL; }
  | arglist    { $$ = $1; }
  ;

arglist
  : expr              { $$ = list_single($1); }
  | arglist ',' expr  { $$ = list_append($1, $3); }
  ;

%%

void yyerror(Loc *loc, yyscan_t scanner, const char *msg) {
  (void)scanner;
  had_error = 1;
  fprintf(stderr, "Erreur syntaxique ligne %d, colonne %d: %s\n",
          loc->first_line, loc->first_column, msg);
}

static Node* alloc_node(NodeType t, Loc loc) {
  Node* n = (Node*)calloc(1, sizeof(Node));
  if (!n) { fprintf(stderr, "Erreur: mémoire insuffisante\n"); exit(1); }
  n->type = t;
  n->loc  = loc;
  return n;
}

static Node* mk_num(double v, Loc loc) {
  Node* n = alloc_node(N_NUM, loc);
  n->num = v;
  return n;
}

static Node* mk_bin(int op, Node* a, Node* b, Loc loc) {
  Node* n = alloc_node(N_BIN, loc);
  n->op = op;
  n->left = a;
  n->right = b;
  return n;
}

static Node* mk_un(int op, Node* a, Loc loc) {
  Node* n = alloc_node(N_UN, loc);
  n->op = op;
  n->left = a;
  return n;
}

static Node* mk_func(int fkind, NodeList* args, Loc loc) {
  Node* n = alloc_node(N_FUNC, loc);
  n->fkind = fkind;
  n->args = args;
  return n;
}

static NodeList* list_single(Node* e) {
  NodeList* l = (NodeList*)calloc(1, sizeof(NodeList));
  if (!l) { fprintf(stderr, "Erreur: mémoire insuffisante\n"); exit(1); }
  l->expr = e;
  l->next = NULL;
  return l;
}

static NodeList* list_append(NodeList* lst, Node* e) {
  if (!lst) return list_single(e);
  NodeList* p = lst;
  while (p->next) p = p->next;
  p->next = list_single(e);
  return lst;
}

static void free_list(NodeList* l) {
  while (l) {
    NodeList* n = l->next;
    free_node(l->expr);
    free(l);
    l = n;
  }
}

static void free_node(Node* n) {
  if (!n) return;
  if (n->type == N_BIN) {
    free_node(n->left);
    free_node(n->right);
  } else if (n->type == N_UN) {
    free_node(n->left);
  } else if (n->type == N_FUNC) {
    free_list(n->args);
  }
  free(n);
}

static void sem_error(Loc loc, const char* msg) {
  had_error = 1;
  fprintf(stderr, "Erreur sémantique ligne %d, colonne %d: %s\n",
          loc.first_line, loc.first_column, msg);
}

static int count_args(NodeList* a) {
  int k = 0;
  for (; a; a = a->next) k++;
  return k;
}

static int eval_node(Node* n, double* out) {
  if (!n) return 0;

  if (n->type == N_NUM) { *out = n->num; return 1; }

  if (n->type == N_UN) {
    double v;
    if (!eval_node(n->left, &v)) return 0;
    if (n->op == 'n') { *out = -v; return 1; }
    sem_error(n->loc, "opérateur unaire inconnu");
    return 0;
  }

  if (n->type == N_BIN) {
    double a, b;
    if (!eval_node(n->left, &a)) return 0;
    if (!eval_node(n->right, &b)) return 0;

    switch (n->op) {
      case '+': *out = a + b; return 1;
      case '-': *out = a - b; return 1;
      case '*': *out = a * b; return 1;
      case '/':
        if (b == 0.0) { sem_error(n->loc, "division par zéro"); return 0; }
        *out = a / b; return 1;
      default:
        sem_error(n->loc, "opérateur binaire inconnu");
        return 0;
    }
  }

  return eval_func(n->fkind, n->args, out);
}

static int eval_func(int fkind, NodeList* args, double* out) {
  int n = count_args(args);
  if (n <= 0) { sem_error((Loc){0}, "fonction sans arguments"); return 0; }

  double* v = (double*)calloc((size_t)n, sizeof(double));
  if (!v) { fprintf(stderr, "Erreur: mémoire insuffisante\n"); exit(1); }

  int i = 0;
  for (NodeList* p = args; p; p = p->next, i++) {
    if (!eval_node(p->expr, &v[i])) { free(v); return 0; }
  }

  double res = 0.0;

  if (fkind == SOMME) {
    for (i = 0; i < n; i++) res += v[i];
  } else if (fkind == PRODUIT) {
    res = 1.0;
    for (i = 0; i < n; i++) res *= v[i];
  } else if (fkind == MOYENNE) {
    for (i = 0; i < n; i++) res += v[i];
    res /= (double)n;
  } else if (fkind == VARIANCE || fkind == ECART_TYPE) {
    double mean = 0.0;
    for (i = 0; i < n; i++) mean += v[i];
    mean /= (double)n;

    double var = 0.0;
    for (i = 0; i < n; i++) {
      double d = v[i] - mean;
      var += d * d;
    }
    var /= (double)n;

    res = (fkind == VARIANCE) ? var : sqrt(var);
  } else {
    free(v);
    sem_error((Loc){0}, "fonction inconnue");
    return 0;
  }

  free(v);
  *out = res;
  return 1;
}

static const char* fname(int f) {
  switch (f) {
    case SOMME: return "somme";
    case PRODUIT: return "produit";
    case MOYENNE: return "moyenne";
    case VARIANCE: return "variance";
    case ECART_TYPE: return "ecart-type";
    default: return "f?";
  }
}

static void print_postfix(Node* n) {
  if (!n) return;

  if (n->type == N_NUM) { printf("%.10g ", n->num); return; }

  if (n->type == N_UN) {
    print_postfix(n->left);
    printf("neg ");
    return;
  }

  if (n->type == N_BIN) {
    print_postfix(n->left);
    print_postfix(n->right);
    printf("%c ", n->op);
    return;
  }

  for (NodeList* p = n->args; p; p = p->next) print_postfix(p->expr);
  printf("%s[%d] ", fname(n->fkind), count_args(n->args));
}

static char* str_dup(const char* s) {
  size_t n = strlen(s);
  char* d = (char*)malloc(n + 1);
  if (!d) { fprintf(stderr, "Erreur: mémoire insuffisante\n"); exit(1); }
  memcpy(d, s, n + 1);
  return d;
}

static char* new_temp(int* id) {
  char b[32];
  snprintf(b, sizeof(b), "t%d", (*id)++);
  return str_dup(b);
}

static char* gen_tac(Node* n, int* id) {
  if (n->type == N_NUM) {
    char* t = new_temp(id);
    printf("%s = %.10g\n", t, n->num);
    return t;
  }

  if (n->type == N_UN) {
    char* a = gen_tac(n->left, id);
    char* t = new_temp(id);
    printf("%s = - %s\n", t, a);
    free(a);
    return t;
  }

  if (n->type == N_BIN) {
    char* a = gen_tac(n->left, id);
    char* b = gen_tac(n->right, id);
    char* t = new_temp(id);
    printf("%s = %s %c %s\n", t, a, n->op, b);
    free(a);
    free(b);
    return t;
  }

  int narg = count_args(n->args);
  char** names = (char**)calloc((size_t)narg, sizeof(char*));
  if (!names) { fprintf(stderr, "Erreur: mémoire insuffisante\n"); exit(1); }

  int i = 0;
  for (NodeList* p = n->args; p; p = p->next, i++) {
    names[i] = gen_tac(p->expr, id);
  }

  char* t = new_temp(id);
  printf("%s = %s(", t, fname(n->fkind));
  for (i = 0; i < narg; i++) {
    printf("%s%s", (i ? ", " : ""), names[i]);
    free(names[i]);
  }
  free(names);
  printf(")\n");
  return t;
}

static int parse_from_string(const char* s) {
  yyscan_t sc;
  if (yylex_init(&sc)) return 1;

  YY_BUFFER_STATE b = yy_scan_string(s, sc);
  int rc = yyparse(sc);
  yy_delete_buffer(b, sc);

  yylex_destroy(sc);
  return rc;
}

static int parse_from_file(const char* path) {
  FILE* f = fopen(path, "rb");
  if (!f) {
    fprintf(stderr, "Erreur: impossible d'ouvrir '%s' (%s)\n", path, strerror(errno));
    return 1;
  }

  yyscan_t sc;
  if (yylex_init(&sc)) { fclose(f); return 1; }

  yyset_in(f, sc);
  int rc = yyparse(sc);

  yylex_destroy(sc);
  fclose(f);
  return rc;
}

static void usage(const char* a0) {
  fprintf(stderr, "Usage:\n  %s \"expression\"\n  %s -f fichier.txt\n", a0, a0);
}

int main(int argc, char** argv) {
  int rc = 0;

  if (argc < 2) { usage(argv[0]); return 1; }

  if (argc == 3 && strcmp(argv[1], "-f") == 0) rc = parse_from_file(argv[2]);
  else if (argc == 2) rc = parse_from_string(argv[1]);
  else { usage(argv[0]); return 1; }

  if (rc != 0 || had_error || !root) {
    if (root) free_node(root);
    return 1;
  }

  printf("Postfix: ");
  print_postfix(root);
  printf("\n");

  printf("TAC:\n");
  int tid = 1;
  char* r = gen_tac(root, &tid);
  printf("result = %s\n", r);

  double val = 0.0;
  if (eval_node(root, &val)) printf("Valeur = %.10g\n", val);

  free(r);
  free_node(root);
  return 0;
}
