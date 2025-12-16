README – Calculatrice LEX/YACC (Postfix + TAC + Valeur)

1) Prérequis
- gcc (build-essential)
- flex
- bison
- libm (math) via -lm (déjà inclus à la compilation)

Sur Debian/Ubuntu/Kali :
sudo apt update
sudo apt install -y build-essential flex bison

2) Compilation

Option A : avec Makefile
make clean
make

Option B : compilation manuelle (si les fichiers générés existent déjà)
gcc -Wall -Wextra -O2 -o calc lex.yy.c parser.tab.c -lm

3) Utilisation

3.1 Entrée en ligne de commande
./calc "5+3*2"
./calc "(5+3)*2"
./calc "-(2+4) + 10/2"

Fonctions supportées (arguments séparés par des virgules) :
./calc "somme(1,2,3,4)"
./calc "produit(2,3,4)"
./calc "moyenne(2,4)"
./calc "variance(2,4)"
./calc "ecart-type(2,4)"
./calc "somme(1.5,2.25,3)"

Imbrication (exemple) :
./calc "5 + 3 * somme(4, somme(5,7,8), variance(1,1+1, moyenne(2,4),4,6-2))"

3.2 Entrée depuis un fichier
Créer un fichier :
printf "somme(1,2,3,4)*ecart-type(2,4)+5\n" > input.txt

Exécuter :
./calc -f input.txt

4) Sortie du programme
Le programme affiche généralement :
- Postfix : forme postfixée (RPN)
- TAC : code à trois adresses (temporaires t1, t2, …)
- Valeur : résultat numérique final

5) Tests d’erreurs (exemples)

Erreur lexicale (caractère illégal) :
./calc "5 + $"

Erreurs syntaxiques :
./calc "somme(1,2,)"
./calc "(1+2"
./calc "5 + * 3"
