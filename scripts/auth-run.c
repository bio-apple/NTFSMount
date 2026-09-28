/* Ask for administrator authorization, then run argv as root.
   AuthorizationExecuteWithPrivileges is deprecated; this is the same ad-hoc
   fallback the app uses. No sudo, no AppleScript. */
#include <Security/Authorization.h>
#include <Security/AuthorizationTags.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/wait.h>
#include <unistd.h>

int main(int argc, char **argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: auth-run tool [args...]\n");
    return 2;
  }

  AuthorizationRef auth = NULL;
  OSStatus status = AuthorizationCreate(NULL, NULL, 0, &auth);
  if (status != errAuthorizationSuccess || auth == NULL) {
    fprintf(stderr, "authorization failed (%d)\n", (int)status);
    return 1;
  }

  AuthorizationItem item = {kAuthorizationRightExecute, 0, NULL, 0};
  AuthorizationRights rights = {1, &item};
  AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                             kAuthorizationFlagExtendRights |
                             kAuthorizationFlagPreAuthorize;
  status = AuthorizationCopyRights(auth, &rights, NULL, flags, NULL);
  if (status != errAuthorizationSuccess) {
    fprintf(stderr, "administrator authorization was not granted (%d)\n", (int)status);
    AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
    return 1;
  }

  FILE *pipe = NULL;
  status = AuthorizationExecuteWithPrivileges(auth, argv[1], kAuthorizationFlagDefaults,
                                               argv + 2, &pipe);
  if (status != errAuthorizationSuccess) {
    fprintf(stderr, "privileged execution failed (%d)\n", (int)status);
    AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
    return 1;
  }

  if (pipe != NULL) {
    char buf[4096];
    size_t n = 0;
    while ((n = fread(buf, 1, sizeof buf, pipe)) > 0) {
      fwrite(buf, 1, n, stdout);
    }
    fclose(pipe);
  }

  int st = 0;
  if (wait(&st) < 0) {
    AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
    return 1;
  }
  AuthorizationFree(auth, kAuthorizationFlagDestroyRights);
  if (WIFEXITED(st)) {
    return WEXITSTATUS(st);
  }
  return 1;
}
