%option noyywrap nounput noinput yylineno
%option reentrant bison-bridge bison-locations
%option warn

%{
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Must come before parser.tab.h so Loc / yyscan_t are known everywhere. */
#include "common.h"
#include "parser.tab.h"

/* IMPORTANT:
   - Do NOT use the name `yycolumn` (Flex may define it as a macro).
   - We keep our own column counter. */
static int lex_col = 1;

static void lex_error(Loc *loc, const char *msg);

#define YY_USER_ACTION do { \
  yylloc->first_line   = yylineno; \
  yylloc->last_line    = yylineno; \
  yylloc->first_column = lex_col;  \
  yylloc->last_column  = lex_col + (int)yyleng - 1; \
  lex_col += (int)yyleng; \
} while(0);

%}

%x COMMENT

DIGIT      [0-9]
INT        {DIGIT}+
EXP        ([eE][+-]?{DIGIT}+)
FRAC       ({DIGIT}+"."{DIGIT}*|{DIGIT}*"."{DIGIT}+)
NUMBER     ({FRAC}|{INT}){EXP}?
ID         [A-Za-z_][A-Za-z0-9_]*

%%

[ \t\r]+                 { /* ignorer */ }

"//".*                   { /* commentaire ligne */ }
"/*"                     { BEGIN(COMMENT); }

<COMMENT>"*/"            { BEGIN(INITIAL); }
<COMMENT>\n              { lex_col = 1; }
<COMMENT>.               { /* ignorer */ }
<COMMENT><<EOF>>         {
                           lex_error(yylloc, "commentaire non terminé");
                           return LEX_ERROR;
                         }

\n                       { lex_col = 1; }

","                      { return ','; }
"("                      { return '('; }
")"                      { return ')'; }
"+"                      { return '+'; }
"-"                      { return '-'; }
"*"                      { return '*'; }
"/"                      { return '/'; }

"somme"                  { return SOMME; }
"produit"                { return PRODUIT; }
"moyenne"                { return MOYENNE; }
"variance"               { return VARIANCE; }
"ecart-type"             { return ECART_TYPE; }
"ecart_type"             { return ECART_TYPE; }
"ecarttype"              { return ECART_TYPE; }

{NUMBER}                 {
                           yylval->dval = strtod(yytext, NULL);
                           return NUMBER;
                         }

{ID}                     {
                           lex_error(yylloc, "identificateur/fonction inconnue");
                           return LEX_ERROR;
                         }

.                        {
                           char buf[128];
                           snprintf(buf, sizeof(buf), "caractère illégal '%s'", yytext);
                           lex_error(yylloc, buf);
                           return LEX_ERROR;
                         }

%%

static void lex_error(Loc *loc, const char *msg) {
  fprintf(stderr, "Erreur lexicale ligne %d, colonne %d: %s\n",
          loc->first_line, loc->first_column, msg);
}
