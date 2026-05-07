// Joya Runtime - C entry point
#include <stdio.h>

// Windows stack probe function (needed by alloca-generated code)
#ifdef _WIN64
void __chkstk(void) {}
#endif

// Forward declaration of the compiled Joya main function
extern long long Hello_main(void);

// C main — calls Joya main and returns its result
int main(int argc, char* argv[]) {
    (void)argc;
    (void)argv;
    return (int)Hello_main();
}
