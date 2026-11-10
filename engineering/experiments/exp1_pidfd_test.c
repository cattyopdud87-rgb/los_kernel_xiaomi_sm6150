#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <sys/types.h>
#include <errno.h>
#include <string.h>

#ifndef __NR_pidfd_open
#define __NR_pidfd_open 434
#endif

#ifndef P_PIDFD
#define P_PIDFD 3
#endif

int main(void) {
    printf("=== PIDFD & WAITID P_PIDFD REPRODUCTION BENCHMARK ===\n");

    pid_t child = fork();
    if (child < 0) {
        perror("fork");
        return 1;
    }

    if (child == 0) {
        // Child process sleeps briefly and exits
        usleep(50000); // 50ms
        _exit(42);
    }

    // Parent creates pidfd
    int pidfd = syscall(__NR_pidfd_open, child, 0);
    printf("1. pidfd_open(pid=%d) returned: fd=%d (errno=%d: %s)\n",
           child, pidfd, errno, strerror(errno));

    if (pidfd < 0) {
        printf("FAILED: pidfd_open is not supported!\n");
        waitpid(child, NULL, 0);
        return 1;
    }

    // Now test waitid with P_PIDFD
    siginfo_t info;
    memset(&info, 0, sizeof(info));

    printf("2. Calling waitid(P_PIDFD=%d, pidfd=%d, WEXITED)...\n", P_PIDFD, pidfd);
    int ret = waitid(P_PIDFD, pidfd, &info, WEXITED);
    int saved_errno = errno;

    printf("3. waitid(P_PIDFD) returned: %d (errno=%d: %s)\n",
           ret, saved_errno, strerror(saved_errno));

    if (ret != 0 && saved_errno == EINVAL) {
        printf(">>> CONFIRMED DEFECT: Kernel returned EINVAL (22)! P_PIDFD is missing in kernel_waitid!\n");
        printf(">>> This is the root cause of GLib child reaping failures and zombie leaks in container rootfs.\n");
    } else if (ret == 0) {
        printf(">>> SUCCESS: P_PIDFD is supported and successfully reaped child exit_status=%d!\n",
               info.si_status);
    }

    // Cleanup child with standard waitpid if waitid failed
    if (ret != 0) {
        int st;
        waitpid(child, &st, 0);
        printf("4. Fallback waitpid(pid=%d) cleaned up child (exit code=%d)\n", child, WEXITSTATUS(st));
    }

    close(pidfd);
    return 0;
}
