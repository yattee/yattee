//
//  libsmbclient_minimal.h
//  Yattee
//
//  Minimal forward declarations for libsmbclient context-based API to avoid header dependency issues.
//  This uses the modern context API exported by MPVKit-GPL's Libsmbclient.framework.
//

#ifndef libsmbclient_minimal_h
#define libsmbclient_minimal_h

#include <sys/types.h>
#include <sys/stat.h>
#include <time.h>

// SMB entry types (from libsmbclient.h)
#define SMBC_WORKGROUP      1
#define SMBC_SERVER         2
#define SMBC_FILE_SHARE     3
#define SMBC_PRINTER_SHARE  4
#define SMBC_COMMS_SHARE    5
#define SMBC_IPC_SHARE      6
#define SMBC_DIR            7
#define SMBC_FILE           8
#define SMBC_LINK           9

// Forward declarations for context types
typedef struct _SMBCCTX SMBCCTX;
typedef struct _SMBCFILE SMBCFILE;

// Context-specific function pointer types (for true context isolation)
// These allow calling SMB functions on a specific context without using smbc_set_context()
typedef SMBCFILE * (*smbc_opendir_fn)(SMBCCTX *c, const char *fname);
typedef int (*smbc_closedir_fn)(SMBCCTX *c, SMBCFILE *dir);
typedef struct smbc_dirent * (*smbc_readdir_fn)(SMBCCTX *c, SMBCFILE *dir);
typedef off_t (*smbc_lseekdir_fn)(SMBCCTX *c, SMBCFILE *dir, off_t offset);
typedef int (*smbc_stat_fn)(SMBCCTX *c, const char *fname, struct stat *st);
typedef SMBCFILE * (*smbc_open_fn)(SMBCCTX *c, const char *fname, int flags, mode_t mode);
typedef ssize_t (*smbc_read_fn)(SMBCCTX *c, SMBCFILE *file, void *buf, size_t count);
typedef int (*smbc_close_fn)(SMBCCTX *c, SMBCFILE *file);

// Directory entry structure (from libsmbclient.h)
struct smbc_dirent {
    unsigned int smbc_type;
    unsigned int dirlen;
    unsigned int commentlen;
    char *comment;
    unsigned int namelen;
    char name[1];  // Variable length
};

// Auth callback type with context (modern API)
typedef void (*smbc_get_auth_data_with_context_fn)(
    SMBCCTX *ctx,
    const char *server, const char *share,
    char *workgroup, int wgmaxlen,
    char *username, int unmaxlen,
    char *password, int pwmaxlen
);

// Context management (modern context-based API)
extern SMBCCTX *smbc_new_context(void);
extern SMBCCTX *smbc_init_context(SMBCCTX *ctx);
extern int smbc_free_context(SMBCCTX *ctx, int shutdown_ctx);

// Context configuration functions
extern void smbc_setFunctionAuthDataWithContext(SMBCCTX *ctx, smbc_get_auth_data_with_context_fn fn);
extern void smbc_setOptionUserData(SMBCCTX *ctx, void *user_data);
extern void *smbc_getOptionUserData(SMBCCTX *ctx);
extern void smbc_setTimeout(SMBCCTX *ctx, int timeout);
extern void smbc_setWorkgroup(SMBCCTX *ctx, const char *workgroup);
extern void smbc_setUser(SMBCCTX *ctx, const char *user);

// Context-specific function pointer getters (preferred API for multi-context usage)
// These provide true context isolation without affecting global state
extern smbc_opendir_fn smbc_getFunctionOpendir(SMBCCTX *c);
extern smbc_closedir_fn smbc_getFunctionClosedir(SMBCCTX *c);
extern smbc_readdir_fn smbc_getFunctionReaddir(SMBCCTX *c);
extern smbc_lseekdir_fn smbc_getFunctionLseekdir(SMBCCTX *c);
extern smbc_stat_fn smbc_getFunctionStat(SMBCCTX *c);
extern smbc_open_fn smbc_getFunctionOpen(SMBCCTX *c);
extern smbc_read_fn smbc_getFunctionRead(SMBCCTX *c);
extern smbc_close_fn smbc_getFunctionClose(SMBCCTX *c);

// Boolean type for libsmbclient
typedef int smbc_bool;

// Set SMB protocol version (min/max)
extern smbc_bool smbc_setOptionProtocols(SMBCCTX *c, const char *min_proto, const char *max_proto);

#endif /* libsmbclient_minimal_h */
