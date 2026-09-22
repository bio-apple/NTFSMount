/*
 * Privileged helper daemon. Runs as root via LaunchDaemon.
 * Accepts a Unix socket, pins the caller by CDHash + bundle id + path,
 * then execs the sealed ntfs-rw-helper inside NTFSMount.app.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <Security/Security.h>
#include <arpa/inet.h>
#include <errno.h>
#include <libproc.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

#define SOCK_PATH "/var/run/com.bioapple.ntfsmount.sock"
#define APP_PATH_FILE "/Library/Application Support/NTFSMount/app.path"
#define BUNDLE_ID "com.bioapple.ntfsmount"
#define MAX_ARGS 8
#define MAX_ARG 512
#define MAX_BODY (256 * 1024)

static const char *kAllowed[] = {
    "mount", "unmount", "eject", "format", "automount",
    "enable-automount", "disable-automount", "version", "selftest",
    NULL};

static void die(const char *m) {
  fprintf(stderr, "helperd: %s\n", m);
  exit(1);
}

static int hex_encode(const unsigned char *in, size_t n, char *out, size_t outn) {
  static const char *h = "0123456789abcdef";
  if (outn < n * 2 + 1) return -1;
  for (size_t i = 0; i < n; i++) {
    out[i * 2] = h[(in[i] >> 4) & 0xf];
    out[i * 2 + 1] = h[in[i] & 0xf];
  }
  out[n * 2] = 0;
  return 0;
}

static int cdhash_of_path(const char *path, char *out, size_t outn) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
  if (!url) return -1;
  SecStaticCodeRef code = NULL;
  OSStatus st = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
  CFRelease(url);
  if (st != errSecSuccess || !code) return -1;
  CFDictionaryRef info = NULL;
  st = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
  CFRelease(code);
  if (st != errSecSuccess || !info) return -1;
  CFDataRef unique = CFDictionaryGetValue(info, kSecCodeInfoUnique);
  int rc = -1;
  if (unique) {
    rc = hex_encode(CFDataGetBytePtr(unique), (size_t)CFDataGetLength(unique), out, outn);
  }
  CFRelease(info);
  return rc;
}

static int identifier_of_path(const char *path, char *out, size_t outn) {
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, (CFIndex)strlen(path), false);
  if (!url) return -1;
  SecStaticCodeRef code = NULL;
  OSStatus st = SecStaticCodeCreateWithPath(url, kSecCSDefaultFlags, &code);
  CFRelease(url);
  if (st != errSecSuccess || !code) return -1;
  CFDictionaryRef info = NULL;
  st = SecCodeCopySigningInformation(code, kSecCSSigningInformation, &info);
  CFRelease(code);
  if (st != errSecSuccess || !info) return -1;
  int rc = -1;
  CFStringRef ident = CFDictionaryGetValue(info, kSecCodeInfoIdentifier);
  if (ident && CFStringGetCString(ident, out, (CFIndex)outn, kCFStringEncodingUTF8)) rc = 0;
  CFRelease(info);
  return rc;
}

static int read_app_path(char *out, size_t n) {
  FILE *f = fopen(APP_PATH_FILE, "r");
  if (f) {
    if (!fgets(out, (int)n, f)) {
      fclose(f);
      return -1;
    }
    fclose(f);
    size_t L = strlen(out);
    while (L && (out[L - 1] == '\n' || out[L - 1] == '\r')) out[--L] = 0;
    if (L) return 0;
  }
  char self[PROC_PIDPATHINFO_MAXSIZE];
  if (proc_pidpath(getpid(), self, sizeof(self)) <= 0) return -1;
  char *p = strstr(self, "/Contents/MacOS/");
  if (!p) return -1;
  *p = 0;
  if (strlen(self) >= n) return -1;
  memcpy(out, self, strlen(self) + 1);
  return 0;
}

static int same_app(const char *peer_exe, const char *app) {
  char prefix[4096];
  snprintf(prefix, sizeof(prefix), "%s/Contents/MacOS/NTFSMount", app);
  return strcmp(peer_exe, prefix) == 0;
}

static int peer_ok(int fd, const char *app) {
  pid_t pid = 0;
  socklen_t len = sizeof(pid);
  if (getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &len) < 0 || pid <= 0) return 0;
  char exe[PROC_PIDPATHINFO_MAXSIZE];
  if (proc_pidpath(pid, exe, sizeof(exe)) <= 0) return 0;
  if (!same_app(exe, app)) return 0;
  char ident[256];
  if (identifier_of_path(exe, ident, sizeof(ident)) != 0) return 0;
  if (strcmp(ident, BUNDLE_ID) != 0) return 0;
  char a[128], b[128];
  if (cdhash_of_path(exe, a, sizeof(a)) != 0) return 0;
  if (cdhash_of_path(app, b, sizeof(b)) != 0) return 0;
  return strcasecmp(a, b) == 0;
}

static int allowed_cmd(const char *c) {
  for (int i = 0; kAllowed[i]; i++)
    if (strcmp(c, kAllowed[i]) == 0) return 1;
  return 0;
}

static int read_line(int fd, char *buf, size_t n) {
  size_t i = 0;
  while (i + 1 < n) {
    char c;
    ssize_t r = recv(fd, &c, 1, 0);
    if (r <= 0) return -1;
    if (c == '\n') {
      buf[i] = 0;
      return 0;
    }
    buf[i++] = c;
  }
  return -1;
}

static void write_all(int fd, const char *p, size_t n) {
  while (n) {
    ssize_t w = send(fd, p, n, 0);
    if (w <= 0) return;
    p += (size_t)w;
    n -= (size_t)w;
  }
}

static void handle(int fd, const char *app) {
  if (!peer_ok(fd, app)) {
    const char *m = "ERR\n调用方未通过签名校验。\n";
    write_all(fd, m, strlen(m));
    return;
  }
  char line[64];
  if (read_line(fd, line, sizeof(line)) != 0) return;
  int argc = 0;
  if (sscanf(line, "v1 %d", &argc) != 1 || argc < 1 || argc > MAX_ARGS) {
    const char *m = "ERR\n协议错误。\n";
    write_all(fd, m, strlen(m));
    return;
  }
  char args[MAX_ARGS][MAX_ARG];
  char *argv[MAX_ARGS + 2];
  char helper[4096];
  snprintf(helper, sizeof(helper), "%s/Contents/Resources/ntfs-rw-helper", app);
  argv[0] = helper;
  for (int i = 0; i < argc; i++) {
    if (read_line(fd, args[i], MAX_ARG) != 0) return;
    if (i == 0 && !allowed_cmd(args[i])) {
      const char *m = "ERR\n不允许的命令。\n";
      write_all(fd, m, strlen(m));
      return;
    }
    argv[i + 1] = args[i];
  }
  argv[argc + 1] = NULL;
  if (access(helper, X_OK) != 0) {
    const char *m = "ERR\n找不到挂载助手，请把应用装到「应用程序」。\n";
    write_all(fd, m, strlen(m));
    return;
  }

  int pipefd[2];
  if (pipe(pipefd) != 0) return;
  pid_t pid = fork();
  if (pid < 0) {
    close(pipefd[0]);
    close(pipefd[1]);
    return;
  }
  if (pid == 0) {
    close(pipefd[0]);
    dup2(pipefd[1], STDOUT_FILENO);
    dup2(pipefd[1], STDERR_FILENO);
    close(pipefd[1]);
    execv(helper, argv);
    perror("exec");
    _exit(127);
  }
  close(pipefd[1]);
  char body[MAX_BODY];
  size_t n = 0;
  while (n < sizeof(body) - 1) {
    ssize_t r = read(pipefd[0], body + n, sizeof(body) - 1 - n);
    if (r <= 0) break;
    n += (size_t)r;
  }
  body[n] = 0;
  close(pipefd[0]);
  int st = 0;
  waitpid(pid, &st, 0);
  int ok = WIFEXITED(st) && WEXITSTATUS(st) == 0;
  const char *head = ok ? "OK\n" : "ERR\n";
  write_all(fd, head, strlen(head));
  write_all(fd, body, n);
}

int main(void) {
  if (getuid() != 0) die("need root");
  signal(SIGPIPE, SIG_IGN);
  char app[4096];
  if (read_app_path(app, sizeof(app)) != 0) die("no app.path");

  unlink(SOCK_PATH);
  int s = socket(AF_UNIX, SOCK_STREAM, 0);
  if (s < 0) die("socket");
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);
  if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) < 0) die("bind");
  chmod(SOCK_PATH, 0666);
  if (listen(s, 8) < 0) die("listen");

  for (;;) {
    int c = accept(s, NULL, NULL);
    if (c < 0) {
      if (errno == EINTR) continue;
      break;
    }
    pid_t w = fork();
    if (w == 0) {
      close(s);
      handle(c, app);
      close(c);
      _exit(0);
    }
    close(c);
    if (w > 0) {
      int st;
      waitpid(w, &st, 0);
    }
  }
  return 0;
}
