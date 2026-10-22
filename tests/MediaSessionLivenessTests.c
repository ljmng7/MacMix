#include <assert.h>
#include <stdio.h>
#include <sys/wait.h>
#include <unistd.h>

int main(void) {
    assert(processIsRunning(getpid()) && "own process is running");
    assert(processIsRunning(1) && "launchd is running even when signalling is not permitted");
    pid_t child = fork();
    if (child == 0) _exit(0);
    assert(child > 0);
    waitpid(child, NULL, 0);
    assert(!processIsRunning(child) && "reaped process has expired");
    printf("Media session liveness: own process, unsignalable launchd and expired child passed.\n");
    return 0;
}
