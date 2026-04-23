//
//  SMBBridge.c
//  Yattee
//
//  C implementation of libsmbclient bridge for directory browsing using context-specific
//  function pointers. This provides complete isolation from other libsmbclient users
//  (e.g., FFmpeg in MPV) by avoiding smbc_set_context() which modifies global state.
//

#include "SMBBridge.h"
#include "libsmbclient_minimal.h"
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>

// Context wrapper that bundles SMBCCTX with auth data
struct SMBContextWrapper {
    SMBCCTX *ctx;             // Isolated libsmbclient context
    char workgroup[128];
    char username[128];
    char password[128];
    SMBProtocolVersion version;
    pthread_mutex_t mutex;    // Per-context mutex for thread safety
};

// Authentication callback for libsmbclient context (called during SMB operations)
static void auth_fn_with_context(
    SMBCCTX *ctx,
    const char *server, const char *share,
    char *workgroup, int wgmaxlen,
    char *username, int unmaxlen,
    char *password, int pwmaxlen
) {
    fprintf(stderr, "[SMBBridge] Auth callback invoked for server: %s, share: %s\n",
            server ? server : "(null)", share ? share : "(null)");

    // Get auth data from context's user data
    struct SMBContextWrapper *wrapper = (struct SMBContextWrapper *)smbc_getOptionUserData(ctx);
    if (wrapper) {
        fprintf(stderr, "[SMBBridge] Auth: using workgroup=%s, username=%s, has_password=%s\n",
                wrapper->workgroup,
                wrapper->username[0] ? wrapper->username : "(empty)",
                wrapper->password[0] ? "yes" : "no");

        if (wrapper->workgroup[0]) {
            strncpy(workgroup, wrapper->workgroup, wgmaxlen - 1);
            workgroup[wgmaxlen - 1] = '\0';
        }
        if (wrapper->username[0]) {
            strncpy(username, wrapper->username, unmaxlen - 1);
            username[unmaxlen - 1] = '\0';
        }
        if (wrapper->password[0]) {
            strncpy(password, wrapper->password, pwmaxlen - 1);
            password[pwmaxlen - 1] = '\0';
        }
    } else {
        fprintf(stderr, "[SMBBridge] Auth: WARNING - no wrapper found!\n");
    }
}

void* smb_init_context(const char *workgroup,
                      const char *username,
                      const char *password,
                      SMBProtocolVersion version) {
    fprintf(stderr, "[SMBBridge] Creating new isolated SMB context\n");
    
    // Allocate context wrapper
    struct SMBContextWrapper *wrapper = (struct SMBContextWrapper *)calloc(1, sizeof(struct SMBContextWrapper));
    if (!wrapper) {
        fprintf(stderr, "[SMBBridge] Failed to allocate context wrapper\n");
        return NULL;
    }
    
    // Initialize mutex for this context
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&wrapper->mutex, &attr);
    pthread_mutexattr_destroy(&attr);
    
    // Copy credentials
    strncpy(wrapper->workgroup, workgroup ? workgroup : "WORKGROUP", sizeof(wrapper->workgroup) - 1);
    strncpy(wrapper->username, username ? username : "", sizeof(wrapper->username) - 1);
    strncpy(wrapper->password, password ? password : "", sizeof(wrapper->password) - 1);
    wrapper->version = version;
    
    // Create NEW isolated libsmbclient context
    wrapper->ctx = smbc_new_context();
    if (!wrapper->ctx) {
        fprintf(stderr, "[SMBBridge] Failed to create libsmbclient context\n");
        pthread_mutex_destroy(&wrapper->mutex);
        free(wrapper);
        return NULL;
    }
    
    // Configure THIS context only (does not affect global state or other contexts)
    smbc_setFunctionAuthDataWithContext(wrapper->ctx, auth_fn_with_context);
    smbc_setOptionUserData(wrapper->ctx, wrapper);
    smbc_setTimeout(wrapper->ctx, 10000); // 10 second timeout
    smbc_setWorkgroup(wrapper->ctx, wrapper->workgroup);
    if (wrapper->username[0]) {
        smbc_setUser(wrapper->ctx, wrapper->username);
    }

    // Set protocol version BEFORE initialization (must be set before smbc_init_context)
    // Note: We set min_proto to allow negotiation, and max_proto to limit the highest version
    if (wrapper->version != SMB_PROTOCOL_AUTO) {
        const char *min_proto = "NT1";  // Allow negotiation from SMB1
        const char *max_proto = NULL;
        switch (wrapper->version) {
            case SMB_PROTOCOL_SMB1:
                max_proto = "NT1";
                min_proto = "NT1";  // Force SMB1 only
                break;
            case SMB_PROTOCOL_SMB2:
                max_proto = "SMB2";
                break;
            case SMB_PROTOCOL_SMB3:
                max_proto = "SMB3";
                break;
            default:
                break;
        }
        if (max_proto) {
            fprintf(stderr, "[SMBBridge] Setting protocol range: %s to %s\n", min_proto, max_proto);
            smbc_bool result = smbc_setOptionProtocols(wrapper->ctx, min_proto, max_proto);
            fprintf(stderr, "[SMBBridge] smbc_setOptionProtocols returned: %d\n", result);
        }
    }

    // Initialize context AFTER all options are set
    if (smbc_init_context(wrapper->ctx) == NULL) {
        fprintf(stderr, "[SMBBridge] Failed to initialize libsmbclient context\n");
        smbc_free_context(wrapper->ctx, 0);
        pthread_mutex_destroy(&wrapper->mutex);
        free(wrapper);
        return NULL;
    }

    fprintf(stderr, "[SMBBridge] Successfully created isolated SMB context (workgroup: %s, user: %s)\n",
            wrapper->workgroup, wrapper->username[0] ? wrapper->username : "(guest)");
    
    return (void *)wrapper;
}

void smb_free_context(void *ctx_ptr) {
    if (!ctx_ptr) return;
    
    struct SMBContextWrapper *wrapper = (struct SMBContextWrapper *)ctx_ptr;
    
    fprintf(stderr, "[SMBBridge] Freeing SMB context\n");
    
    // Lock before cleanup
    pthread_mutex_lock(&wrapper->mutex);
    
    // Free libsmbclient context
    if (wrapper->ctx) {
        smbc_free_context(wrapper->ctx, 1); // shutdown_ctx = 1
        wrapper->ctx = NULL;
    }
    
    pthread_mutex_unlock(&wrapper->mutex);
    pthread_mutex_destroy(&wrapper->mutex);
    
    // Clear sensitive data
    memset(wrapper->password, 0, sizeof(wrapper->password));
    memset(wrapper->username, 0, sizeof(wrapper->username));
    
    free(wrapper);
    
    fprintf(stderr, "[SMBBridge] SMB context freed\n");
}

SMBFileInfo* smb_list_directory(void *ctx_ptr,
                                const char *url,
                                int *count,
                                char **error) {
    *count = 0;
    *error = NULL;
    
    if (!ctx_ptr || !url) {
        if (error) {
            *error = strdup("Invalid parameters");
        }
        return NULL;
    }
    
    struct SMBContextWrapper *wrapper = (struct SMBContextWrapper *)ctx_ptr;
    
    // Lock THIS context's mutex for thread safety
    pthread_mutex_lock(&wrapper->mutex);
    
    fprintf(stderr, "[SMBBridge] Listing directory: %s\n", url);
    
    // Get context-specific function pointers (avoids smbc_set_context which conflicts with MPV/FFmpeg)
    smbc_opendir_fn opendir_fn = smbc_getFunctionOpendir(wrapper->ctx);
    smbc_readdir_fn readdir_fn = smbc_getFunctionReaddir(wrapper->ctx);
    smbc_closedir_fn closedir_fn = smbc_getFunctionClosedir(wrapper->ctx);
    smbc_lseekdir_fn lseekdir_fn = smbc_getFunctionLseekdir(wrapper->ctx);
    smbc_stat_fn stat_fn = smbc_getFunctionStat(wrapper->ctx);
    
    // Detect if we're listing shares at the server root
    // URL format: "smb://server/" - no path after server
    int is_listing_shares = 0;
    {
        const char *server_start = strstr(url, "://");
        if (server_start) {
            server_start += 3; // Skip "://"
            const char *first_slash = strchr(server_start, '/');
            if (first_slash) {
                const char *path_start = first_slash + 1;
                if (*path_start == '\0' || (*path_start == '/' && *(path_start + 1) == '\0')) {
                    is_listing_shares = 1;
                }
            }
        }
    }
    
    fprintf(stderr, "[SMBBridge] Listing mode: %s\n", is_listing_shares ? "shares" : "files/dirs");
    
    // Open directory using context-specific function
    errno = 0;
    SMBCFILE *dir = opendir_fn(wrapper->ctx, url);
    int saved_errno = errno;
    
    if (!dir) {
        fprintf(stderr, "[SMBBridge] Failed to open directory: %s (errno: %d)\n", 
                strerror(saved_errno), saved_errno);
        pthread_mutex_unlock(&wrapper->mutex);
        if (error) {
            char err_buf[256];
            snprintf(err_buf, sizeof(err_buf), "Failed to open directory: %s (errno: %d)", 
                    strerror(saved_errno), saved_errno);
            *error = strdup(err_buf);
        }
        return NULL;
    }
    
    // First pass: count valid entries
    struct smbc_dirent *dirent;
    int entry_count = 0;
    while ((dirent = readdir_fn(wrapper->ctx, dir)) != NULL) {
        // Skip . and ..
        if (strcmp(dirent->name, ".") == 0 || strcmp(dirent->name, "..") == 0) {
            continue;
        }
        
        if (is_listing_shares) {
            // When listing shares, only count SMBC_FILE_SHARE (type 3)
            if (dirent->smbc_type == SMBC_FILE_SHARE) {
                entry_count++;
            }
        } else {
            // When listing directory contents, count files and directories
            if (dirent->smbc_type == SMBC_DIR || dirent->smbc_type == SMBC_FILE) {
                entry_count++;
            }
        }
    }
    
    // Empty directory is valid (not an error)
    if (entry_count == 0) {
        fprintf(stderr, "[SMBBridge] Empty directory\n");
        closedir_fn(wrapper->ctx, dir);
        pthread_mutex_unlock(&wrapper->mutex);
        return NULL;
    }
    
    fprintf(stderr, "[SMBBridge] Found %d entries\n", entry_count);
    
    // Allocate result array
    SMBFileInfo *files = (SMBFileInfo *)calloc(entry_count, sizeof(SMBFileInfo));
    if (!files) {
        fprintf(stderr, "[SMBBridge] Out of memory\n");
        if (error) {
            *error = strdup("Out of memory");
        }
        closedir_fn(wrapper->ctx, dir);
        pthread_mutex_unlock(&wrapper->mutex);
        return NULL;
    }
    
    // Second pass: populate array (seek back to start)
    lseekdir_fn(wrapper->ctx, dir, 0);
    
    int i = 0;
    while ((dirent = readdir_fn(wrapper->ctx, dir)) != NULL && i < entry_count) {
        // Skip . and ..
        if (strcmp(dirent->name, ".") == 0 || strcmp(dirent->name, "..") == 0) {
            continue;
        }
        
        // Filter based on listing mode
        int should_include = 0;
        if (is_listing_shares) {
            should_include = (dirent->smbc_type == SMBC_FILE_SHARE);
        } else {
            should_include = (dirent->smbc_type == SMBC_DIR || dirent->smbc_type == SMBC_FILE);
        }
        
        if (!should_include) {
            continue;
        }
        
        // Copy name
        files[i].name = strdup(dirent->name);
        files[i].type = dirent->smbc_type;
        
        // Build full path for stat
        size_t url_len = strlen(url);
        size_t name_len = strlen(dirent->name);
        char *full_path = (char *)malloc(url_len + name_len + 2);
        if (full_path) {
            strcpy(full_path, url);
            if (url[url_len - 1] != '/') {
                strcat(full_path, "/");
            }
            strcat(full_path, dirent->name);
            
            // Get detailed file info using context-specific function
            struct stat st;
            if (stat_fn(wrapper->ctx, full_path, &st) == 0) {
                files[i].size = st.st_size;
                files[i].mtime = st.st_mtime;
                files[i].ctime = st.st_ctime;
            } else {
                // If stat fails, use defaults
                files[i].size = 0;
                files[i].mtime = 0;
                files[i].ctime = 0;
            }
            
            free(full_path);
        }
        
        i++;
    }
    
    closedir_fn(wrapper->ctx, dir);
    
    pthread_mutex_unlock(&wrapper->mutex);
    
    fprintf(stderr, "[SMBBridge] Directory listing complete. Count: %d\n", i);
    
    *count = i;
    return files;
}

void smb_free_file_list(SMBFileInfo *files, int count) {
    if (!files) return;
    
    for (int i = 0; i < count; i++) {
        if (files[i].name) {
            free(files[i].name);
        }
    }
    free(files);
}

int smb_test_connection(void *ctx_ptr, const char *url) {
    if (!ctx_ptr || !url) {
        return -EINVAL;
    }
    
    struct SMBContextWrapper *wrapper = (struct SMBContextWrapper *)ctx_ptr;
    
    // Lock context mutex
    pthread_mutex_lock(&wrapper->mutex);
    
    fprintf(stderr, "[SMBBridge] Testing connection to: %s\n", url);
    
    // Get context-specific function pointers (avoids smbc_set_context which conflicts with MPV/FFmpeg)
    smbc_opendir_fn opendir_fn = smbc_getFunctionOpendir(wrapper->ctx);
    smbc_closedir_fn closedir_fn = smbc_getFunctionClosedir(wrapper->ctx);
    
    // Try to open directory using context-specific function
    errno = 0;
    SMBCFILE *dir = opendir_fn(wrapper->ctx, url);
    int saved_errno = errno;
    
    if (!dir) {
        fprintf(stderr, "[SMBBridge] Connection test failed: %s (errno: %d)\n", 
                strerror(saved_errno), saved_errno);
        pthread_mutex_unlock(&wrapper->mutex);
        return -saved_errno;
    }
    
    closedir_fn(wrapper->ctx, dir);
    
    pthread_mutex_unlock(&wrapper->mutex);
    
    fprintf(stderr, "[SMBBridge] Connection test succeeded\n");
    return 0;
}

int smb_download_file(void *ctx_ptr, const char *url, const char *local_path, char **error) {
    *error = NULL;
    
    if (!ctx_ptr || !url || !local_path) {
        if (error) {
            *error = strdup("Invalid parameters");
        }
        return -EINVAL;
    }
    
    struct SMBContextWrapper *wrapper = (struct SMBContextWrapper *)ctx_ptr;
    
    // Lock context mutex
    pthread_mutex_lock(&wrapper->mutex);
    
    fprintf(stderr, "[SMBBridge] Downloading file: %s -> %s\n", url, local_path);
    
    // Get context-specific function pointers (avoids smbc_set_context which conflicts with MPV/FFmpeg)
    smbc_open_fn open_fn = smbc_getFunctionOpen(wrapper->ctx);
    smbc_read_fn read_fn = smbc_getFunctionRead(wrapper->ctx);
    smbc_close_fn close_fn = smbc_getFunctionClose(wrapper->ctx);
    
    // Open remote file for reading using context-specific function
    errno = 0;
    SMBCFILE *file = open_fn(wrapper->ctx, url, O_RDONLY, 0);
    int saved_errno = errno;
    
    if (!file) {
        fprintf(stderr, "[SMBBridge] Failed to open SMB file: %s (errno: %d)\n", 
                strerror(saved_errno), saved_errno);
        pthread_mutex_unlock(&wrapper->mutex);
        if (error) {
            char buf[256];
            snprintf(buf, sizeof(buf), "Failed to open SMB file: %s (errno: %d)", 
                    strerror(saved_errno), saved_errno);
            *error = strdup(buf);
        }
        return -saved_errno;
    }
    
    // Open local file for writing
    FILE *local_file = fopen(local_path, "wb");
    if (!local_file) {
        int local_errno = errno;
        fprintf(stderr, "[SMBBridge] Failed to create local file: %s (errno: %d)\n", 
                strerror(local_errno), local_errno);
        close_fn(wrapper->ctx, file);
        pthread_mutex_unlock(&wrapper->mutex);
        if (error) {
            char buf[256];
            snprintf(buf, sizeof(buf), "Failed to create local file: %s (errno: %d)", 
                    strerror(local_errno), local_errno);
            *error = strdup(buf);
        }
        return -local_errno;
    }
    
    // Read from SMB and write to local file
    char buffer[8192];
    ssize_t bytes_read;
    size_t total_bytes = 0;
    
    while ((bytes_read = read_fn(wrapper->ctx, file, buffer, sizeof(buffer))) > 0) {
        size_t bytes_written = fwrite(buffer, 1, bytes_read, local_file);
        if (bytes_written != (size_t)bytes_read) {
            // Write error
            int local_errno = errno;
            fprintf(stderr, "[SMBBridge] Failed to write to local file (errno: %d)\n", local_errno);
            fclose(local_file);
            close_fn(wrapper->ctx, file);
            pthread_mutex_unlock(&wrapper->mutex);
            unlink(local_path); // Clean up partial file
            if (error) {
                *error = strdup("Failed to write to local file");
            }
            return -local_errno;
        }
        total_bytes += bytes_written;
    }
    
    // Check for read errors
    if (bytes_read < 0) {
        int read_errno = errno;
        fprintf(stderr, "[SMBBridge] Failed to read from SMB: %s\n", strerror(read_errno));
        fclose(local_file);
        close_fn(wrapper->ctx, file);
        pthread_mutex_unlock(&wrapper->mutex);
        unlink(local_path); // Clean up partial file
        if (error) {
            char buf[256];
            snprintf(buf, sizeof(buf), "Failed to read from SMB: %s", strerror(read_errno));
            *error = strdup(buf);
        }
        return -read_errno;
    }
    
    // Clean up
    fclose(local_file);
    close_fn(wrapper->ctx, file);
    pthread_mutex_unlock(&wrapper->mutex);
    
    fprintf(stderr, "[SMBBridge] Download complete: %zu bytes\n", total_bytes);
    return 0;
}
