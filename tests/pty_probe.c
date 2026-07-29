/* pty_probe.c — proves the Mac app's console can hold a conversation.
 *
 * The app runs programs on a pseudo-terminal so interactive prompts work
 * (an ssh password, or SlopNet's own "continue? [y]"). Piped stdin cannot
 * do that: ssh reads the terminal device directly, and a program that
 * detects no terminal often skips the question entirely.
 *
 * This mirrors SlopNetConsole's forkpty/read/write logic exactly, drives a
 * script that asks a question, answers it, and checks the answer arrived.
 *
 *   cc -o /tmp/pty_probe tests/pty_probe.c && /tmp/pty_probe
 *
 * Exit 0 = the console can run a program, be asked a question, and reply.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <util.h>
#include <sys/ioctl.h>
#include <sys/wait.h>

int main(void) {
    const char *script =
        "printf 'may I continue? [y] '; read -r answer; "
        "test \"$answer\" = y && echo GOT_YES || echo GOT_NO; "
        "test -t 0 && echo HAS_TTY";

    struct winsize size = {0};
    size.ws_col = 100;
    size.ws_row = 30;

    int master = -1;
    pid_t child = forkpty(&master, NULL, NULL, &size);
    if (child < 0) {
        fprintf(stderr, "FAIL: no pseudo-terminal available\n");
        return 1;
    }
    if (child == 0) {
        execl("/bin/bash", "bash", "-c", script, (char *)NULL);
        _exit(127);
    }

    char seen[8192];
    size_t used = 0;
    int answered = 0;
    seen[0] = '\0';

    for (;;) {
        char buffer[1024];
        ssize_t got = read(master, buffer, sizeof(buffer) - 1);
        if (got <= 0) break;
        buffer[got] = '\0';
        if (used + (size_t)got < sizeof(seen)) {
            memcpy(seen + used, buffer, (size_t)got);
            used += (size_t)got;
            seen[used] = '\0';
        }
        /* Answer the question the moment it appears, as a person would. */
        if (!answered && strstr(seen, "may I continue?")) {
            if (write(master, "y\n", 2) != 2) {
                fprintf(stderr, "FAIL: could not type into the terminal\n");
                return 1;
            }
            answered = 1;
        }
    }

    int raw = 0;
    waitpid(child, &raw, 0);
    close(master);

    int ok = 1;
    if (!answered) { fprintf(stderr, "FAIL: the question never appeared\n"); ok = 0; }
    if (!strstr(seen, "GOT_YES")) { fprintf(stderr, "FAIL: the answer did not arrive\n"); ok = 0; }
    if (!strstr(seen, "HAS_TTY")) { fprintf(stderr, "FAIL: the program saw no terminal\n"); ok = 0; }

    if (ok) {
        printf("PASS: prompt shown, answer delivered, program had a real terminal\n");
        return 0;
    }
    fprintf(stderr, "--- what the console saw ---\n%s\n", seen);
    return 1;
}
