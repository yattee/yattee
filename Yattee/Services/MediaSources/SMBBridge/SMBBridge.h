//
//  SMBBridge.h
//  Yattee
//
//  C bridge to libsmbclient for SMB directory browsing.
//

#ifndef SMBBridge_h
#define SMBBridge_h

#include <sys/types.h>
#include <time.h>

// SMB protocol version options
typedef enum {
    SMB_PROTOCOL_AUTO = 0,
    SMB_PROTOCOL_SMB1 = 1,
    SMB_PROTOCOL_SMB2 = 2,
    SMB_PROTOCOL_SMB3 = 3
} SMBProtocolVersion;

// File information structure for Swift interop
typedef struct {
    char *name;           // File/directory name (caller must free)
    unsigned int type;    // SMBC_DIR=7, SMBC_FILE=8
    off_t size;          // File size in bytes
    time_t mtime;        // Modification time
    time_t ctime;        // Creation/change time
} SMBFileInfo;

// Initialize SMB context with authentication and protocol preferences
// Returns NULL on failure
// Parameters:
//   workgroup: Workgroup/domain name (e.g., "WORKGROUP")
//   username: Username for authentication (NULL for guest access)
//   password: Password for authentication (NULL for guest access)
//   version: SMB protocol version preference
void* smb_init_context(const char *workgroup,
                      const char *username,
                      const char *password,
                      SMBProtocolVersion version);

// Clean up SMB context and free resources
void smb_free_context(void *ctx);

// List directory contents at given SMB URL
// Returns array of SMBFileInfo (caller must free with smb_free_file_list)
// Parameters:
//   ctx: Context from smb_init_context
//   url: Full SMB URL (e.g., "smb://server/share/path")
//   count: Output parameter - number of items returned
//   error: Output parameter - error message if failed (caller must free)
SMBFileInfo* smb_list_directory(void *ctx,
                                const char *url,
                                int *count,
                                char **error);

// Free directory listing returned by smb_list_directory
void smb_free_file_list(SMBFileInfo *files, int count);

// Test connection to SMB URL
// Returns 0 on success, negative error code on failure
int smb_test_connection(void *ctx, const char *url);

// Download file from SMB to local path
// Returns 0 on success, negative error code on failure
// Parameters:
//   ctx: Context from smb_init_context
//   url: Full SMB URL (e.g., "smb://server/share/path/file.srt")
//   local_path: Local filesystem path to write to
//   error: Output parameter - error message if failed (caller must free)
int smb_download_file(void *ctx, const char *url, const char *local_path, char **error);

#endif /* SMBBridge_h */
