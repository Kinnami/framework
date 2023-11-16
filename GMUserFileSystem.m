//
//  GMUserFileSystem.m
//  OSXFUSE
//

//  Copyright (c) 2011-2017 Benjamin Fleischer.
//  All rights reserved.

//  OSXFUSE.framework is based on MacFUSE.framework. MacFUSE.framework is
//  covered under the following BSD-style license:
//
//  Copyright (c) 2007 Google Inc.
//  All rights reserved.
//
//  Redistribution  and  use  in  source  and  binary  forms,  with  or  without
//  modification, are permitted provided that the following conditions are met:
//
//  1. Redistributions of source code must retain the  above  copyright  notice,
//     this list of conditions and the following disclaimer.
//  2. Redistributions in binary form must reproduce the above copyright notice,
//     this list of conditions and the following disclaimer in the documentation
//     and/or other materials provided with the distribution.
//  3. Neither the name of Google Inc. nor the names of its contributors may  be
//     used to endorse or promote products derived from  this  software  without
//     specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS  IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT  LIMITED  TO,  THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A  PARTICULAR  PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT  OWNER  OR  CONTRIBUTORS  BE
//  LIABLE  FOR  ANY  DIRECT,  INDIRECT,  INCIDENTAL,  SPECIAL,  EXEMPLARY,   OR
//  CONSEQUENTIAL  DAMAGES  (INCLUDING,  BUT  NOT  LIMITED  TO,  PROCUREMENT  OF
//  SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA,  OR  PROFITS;  OR  BUSINESS
//  INTERRUPTION) HOWEVER CAUSED AND ON ANY  THEORY  OF  LIABILITY,  WHETHER  IN
//  CONTRACT, STRICT LIABILITY, OR  TORT  (INCLUDING  NEGLIGENCE  OR  OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED  OF  THE
//  POSSIBILITY OF SUCH DAMAGE.

//  Based on FUSEFileSystem originally by alcor.

/*	CJEC, 23-May-22: TODO: Optimise. OSXFUSE uses the "high level Fuse API" which is synchronous
                and so essentially single threaded. (Notifications are asynchronous,
                but the fuse_invalidate_*() functions serialise their operation with
                a mutex.
                On the other hand, the "low level Fuse API" is asynchronous, allowing
                parallel I/O operations. Rewriting the OSXFUSE framework to use it
                would speed things up.
*/
#import "GMAvailability.h"						/* Always include this first */
#import "GMUserFileSystem.h"

/* FUSE_USE_VERSION: Which version of the libFuse API for which platform?
		https://stackoverflow.com/questions/49739325/what-exactly-is-the-difference-between-fuse2-and-fuse3
		OSXFUSE 3.8.3 implements the Fuse 2.6 API
    Ubuntu Linux 20.04 implements the Fuse 2.9 API (Reported by fusermount(1) -V)
    GhostBSD (FreeBSD 12.2-STABLE) implements the Fuse 2.9 API (Estimated from fuse.h. Needs confirmation)
*/
#define FUSE_USE_VERSION 26
#include <fuse.h>
#include <fuse/fuse_lowlevel.h>

#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/param.h>
#include <sys/mount.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/statvfs.h>

#if defined (__linux__)
#include <sys/statfs.h>
#endif	/* defined (__linux__) */

#if !defined (__linux__)
#include <sys/sysctl.h>
#endif	/* !defined (__linux__) */

#include <sys/utsname.h>

#if defined (__APPLE__) || defined (__FreeBSD__)
#include <sys/vnode.h>
#endif	/* defined (__APPLE__) || defined (__FreeBSD__) */

#import "GMFinderInfo.h"
#import "GMResourceFork.h"
#import "GMDataBackedFileDelegate.h"

#if defined (__APPLE__)
#import "GMDTrace.h"
#endif	/* defined (__APPLE__) */

// Creates a dtrace-ready string with any newlines removed.
#define DTRACE_STRING(s)  \
((char *)[[s stringByReplacingOccurrencesOfString:@"\n" withString:@" "] UTF8String])

// See "64-bit Class and Instance Variable Access Control"
// Note: For reasons I don't understand, this definition cannot be placed in
//			GMAvailability.h.
//			If it is, the preprocessor on macOS thinks that while GM_EXPORT is
//			defined in GMAvailability.h, it is not defined in this file, despite
//			the #import.
#define GM_EXPORT					__attribute__((visibility("default")))

#if !defined (GM_EXPORT_INTERFACE)
#if defined (__clang__) || defined (__APPLE__)
#define	GM_EXPORT_INTERFACE			GM_EXPORT
#else
#define GM_EXPORT_INTERFACE
#endif	/* defined (__clang__) || defined (__APPLE__) */
#endif	/* !defined (GM_EXPORT_INTERFACE) */

// Operation Context
GM_EXPORT NSString* const kGMUserFileSystemContextUserIDKey = @"kGMUserFileSystemContextUserIDKey";
GM_EXPORT NSString* const kGMUserFileSystemContextGroupIDKey = @"kGMUserFileSystemContextGroupIDKey";
GM_EXPORT NSString* const kGMUserFileSystemContextProcessIDKey = @"kGMUserFileSystemContextProcessIDKey";

// Notifications
GM_EXPORT NSString* const kGMUserFileSystemErrorDomain = @"GMUserFileSystemErrorDomain";
GM_EXPORT NSString* const kGMUserFileSystemMountPathKey = @"mountPath";
GM_EXPORT NSString* const kGMUserFileSystemErrorKey = @"error";
GM_EXPORT NSString* const kGMUserFileSystemMountFailed = @"kGMUserFileSystemMountFailed";
GM_EXPORT NSString* const kGMUserFileSystemDidMount = @"kGMUserFileSystemDidMount";
GM_EXPORT NSString* const kGMUserFileSystemDidUnmount = @"kGMUserFileSystemDidUnmount";

// Attribute keys
GM_EXPORT NSString* const kGMUserFileSystemFileFlagsKey = @"kGMUserFileSystemFileFlagsKey";
GM_EXPORT NSString* const kGMUserFileSystemFileAccessDateKey = @"kGMUserFileSystemFileAccessDateKey";
GM_EXPORT NSString* const kGMUserFileSystemFileChangeDateKey = @"kGMUserFileSystemFileChangeDateKey";
GM_EXPORT NSString* const kGMUserFileSystemFileBackupDateKey = @"kGMUserFileSystemFileBackupDateKey";
GM_EXPORT NSString* const kGMUserFileSystemFileSizeInBlocksKey = @"kGMUserFileSystemFileSizeInBlocksKey";
GM_EXPORT NSString* const kGMUserFileSystemFileOptimalIOSizeKey = @"kGMUserFileSystemFileOptimalIOSizeKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeSupportsAllocateKey = @"kGMUserFileSystemVolumeSupportsAllocateKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey = @"kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeSupportsExchangeDataKey = @"kGMUserFileSystemVolumeSupportsExchangeDataKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeSupportsExtendedDatesKey = @"kGMUserFileSystemVolumeSupportsExtendedDatesKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeMaxFilenameLengthKey = @"kGMUserFileSystemVolumeMaxFilenameLengthKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeFileSystemBlockSizeKey = @"kGMUserFileSystemVolumeFileSystemBlockSizeKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeFileSystemOptimalIOSizeKey = @"kGMUserFileSystemVolumeFileSystemOptimalIOSizeKey";


GM_EXPORT NSString* const kGMUserFileSystemVolumeSupportsSetVolumeNameKey = @"kGMUserFileSystemVolumeSupportsSetVolumeNameKey";
GM_EXPORT NSString* const kGMUserFileSystemVolumeNameKey = @"kGMUserFileSystemVolumeNameKey";

/* CJEC, 14-Oct-20: Added to OSXFUSE 3.8.3 */
GM_EXPORT NSString* const kGMUserFileSystemFileTypeFIFOSpecialKey = @"kGMUserFileSystemFileTypeFIFOSpecialKey";
GM_EXPORT NSString* const kGMUserFileSystemFileTypeWhiteoutSpecialKey = @"kGMUserFileSystemFileTypeWhiteoutSpecialKey";

// FinderInfo and ResourceFork keys
GM_EXPORT NSString* const kGMUserFileSystemFinderFlagsKey = @"kGMUserFileSystemFinderFlagsKey";
GM_EXPORT NSString* const kGMUserFileSystemFinderExtendedFlagsKey = @"kGMUserFileSystemFinderExtendedFlagsKey";
GM_EXPORT NSString* const kGMUserFileSystemCustomIconDataKey = @"kGMUserFileSystemCustomIconDataKey";
GM_EXPORT NSString* const kGMUserFileSystemWeblocURLKey = @"kGMUserFileSystemWeblocURLKey";

// Used for time conversions to/from tv_nsec.
static const double kNanoSecondsPerSecond = 1000000000.0;

typedef enum {
  // Unable to unmount a dead FUSE files system located at mount point.
  GMUserFileSystem_ERROR_UNMOUNT_DEADFS = 1000,
  
  // Gave up waiting for system removal of existing dir in /Volumes/x after 
  // unmounting a dead FUSE file system.
  GMUserFileSystem_ERROR_UNMOUNT_DEADFS_RMDIR = 1001,
  
  // The mount point did not exist, and we were unable to mkdir it.
  GMUserFileSystem_ERROR_MOUNT_MKDIR = 1002,
  
  // fuse_main returned while trying to mount and don't know why.
  GMUserFileSystem_ERROR_MOUNT_FUSE_MAIN_INTERNAL = 1003,
} GMUserFileSystemErrorCode;

typedef enum {
  GMUserFileSystem_NOT_MOUNTED,     // Not mounted.
  GMUserFileSystem_MOUNTING,        // In the process of mounting.
  GMUserFileSystem_INITIALIZING,    // Almost done mounting.
  GMUserFileSystem_MOUNTED,         // Confirmed to be mounted.
  GMUserFileSystem_UNMOUNTING,      // In the process of unmounting.
  GMUserFileSystem_FAILURE,         // Failed state; probably a mount failure.
} GMUserFileSystemStatus;

@interface GMUserFileSystemInternal : NSObject {
  struct fuse* handle_;
  NSString* mountPath_;
  GMUserFileSystemStatus status_;
  BOOL shouldCheckForResource_;     // Try to handle FinderInfo/Resource Forks?
  BOOL isThreadSafe_;               // Is the delegate thread-safe?
  BOOL supportsAllocate_;           // Delegate supports preallocation of files?
  BOOL supportsCaseSensitiveNames_; // Delegate supports case sensitive names?
  BOOL supportsExchangeData_;       // Delegate supports exchange data?
  BOOL supportsExtendedTimes_;      // Delegate supports create and backup times?
  BOOL supportsSetVolumeName_;      // Delegate supports setvolname?
  BOOL isReadOnly_;                 // Is this mounted read-only?
  id delegate_;
}
- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe;
- (void)setDelegate:(id)delegate;
@end

/* /sbin/umount is a setuid command on Linux and FreeBSD because umount2(2) and umount(2) respectively
	require root priviledges. Executing the command avoids the need for setuid permission for this program.
  Interestingly, /sbin/umount is not a setuid command on OS X/Darwin.
*/
static int	Unmount (NSArray * a_poaoArgs)
	{
  NSString *	poszUnmount;
	NSTask *		poTaskUnmount;
  int					iExitCode;
  int					iErrno;

#if defined (__linux__)
	poszUnmount = @"/bin/umount";
#else
  poszUnmount = @"/sbin/umount";		/* OS X/Darwin, FreeBSD, ... */
#endif
	poTaskUnmount = [NSTask launchedTaskWithLaunchPath: poszUnmount arguments: a_poaoArgs];
	[poTaskUnmount waitUntilExit];
  iExitCode = [poTaskUnmount terminationStatus];
  switch (iExitCode)				/* Try to simulate the return codes of unmount2(2)/unmount(2) system call */
  	{
    case 0:
    	{
      iErrno = 0;
      break;
      }
    case 1:										/* Linux: /bin/umount returns 1 when not mounted. CJEC, 13-Oct-20: TODO: What about OS X/Darwin and FreeBSD? */
    	{
      iErrno = EINVAL;
      break;
      }
	case 32:  // On Android, /bin/umount returns 32 when not mounted.
      {
	iErrno = EINVAL;
	break;
      }
	
    default:
    	{
      NSLog (@"Fuse: FATAL ERROR: UNEXPECTED: '%@': exit code %i. Returning EPERM", poszUnmount, iExitCode);
      iErrno = EPERM;					/* Use an errno value that cann't be handled and generates an error */
      break;
      }
    }
  return iErrno;
  }

@implementation GMUserFileSystemInternal

- (id)init {
  return [self initWithDelegate:nil isThreadSafe:NO];
}

- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe {
  self = [super init];
  if (self) {
    status_ = GMUserFileSystem_NOT_MOUNTED;
    isThreadSafe_ = isThreadSafe;
    supportsAllocate_ = NO;
    supportsCaseSensitiveNames_ = YES;
    supportsExchangeData_ = NO;
    supportsExtendedTimes_ = NO;
    supportsSetVolumeName_ = NO;
    isReadOnly_ = NO;
    [self setDelegate:delegate];
  }
  return self;
}
- (void)dealloc {
  [mountPath_ release];
  [super dealloc];
}

- (struct fuse*)handle { return handle_; }
- (void)setHandle:(struct fuse *)handle { handle_ = handle; }
- (NSString *)mountPath { return mountPath_; }
- (void)setMountPath:(NSString *)mountPath {
  [mountPath_ autorelease];
  mountPath_ = [mountPath copy];
}
- (GMUserFileSystemStatus)status { return status_; }
- (void)setStatus:(GMUserFileSystemStatus)status { status_ = status; }
- (BOOL)isThreadSafe { return isThreadSafe_; }
- (BOOL)supportsAllocate { return supportsAllocate_; };
- (void)setSupportsAllocate:(BOOL)val { supportsAllocate_ = val; }
- (BOOL)supportsCaseSensitiveNames { return supportsCaseSensitiveNames_; }
- (void)setSupportsCaseSensitiveNames:(BOOL)val { supportsCaseSensitiveNames_ = val; }
- (BOOL)supportsExchangeData { return supportsExchangeData_; }
- (void)setSupportsExchangeData:(BOOL)val { supportsExchangeData_ = val; }
- (BOOL)supportsExtendedTimes { return supportsExtendedTimes_; }
- (void)setSupportsExtendedTimes:(BOOL)val { supportsExtendedTimes_ = val; }
- (BOOL)supportsSetVolumeName { return supportsSetVolumeName_; }
- (void)setSupportsSetVolumeName:(BOOL)val { supportsSetVolumeName_ = val; }
- (BOOL)shouldCheckForResource { return shouldCheckForResource_; }
- (BOOL)isReadOnly { return isReadOnly_; }
- (void)setIsReadOnly:(BOOL)val { isReadOnly_ = val; }
- (id)delegate { return delegate_; }
- (void)setDelegate:(id)delegate { 
  delegate_ = delegate;
  shouldCheckForResource_ =
    [delegate_ respondsToSelector:@selector(finderAttributesAtPath:error:)] ||
    [delegate_ respondsToSelector:@selector(resourceAttributesAtPath:error:)];
  
  // Check for deprecated methods.
  SEL deprecatedMethods[] = {
    @selector(createFileAtPath:attributes:userData:error:)
  };
  for (unsigned int i = 0; i < sizeof(deprecatedMethods) / sizeof(SEL); ++i) {
    SEL sel = deprecatedMethods[i];
    if ([delegate_ respondsToSelector:sel]) {
      NSLog(@"Fuse: WARNING: GMUserFileSystem delegate implements deprecated "
            @"selector: %@", NSStringFromSelector(sel));
    }
  }
}

@end

// Deprecated delegate methods that we still support for backward compatibility
// with previously compiled file systems. This will be actively trimmed as
// new releases occur.
@interface NSObject (GMUserFileSystemDeprecated)

- (BOOL)createFileAtPath:(NSString *)path
              attributes:(NSDictionary *)attributes
                userData:(id *)userData
                   error:(NSError **)error;

@end

@interface GMUserFileSystem (GMUserFileSystemPrivate)

// The file system for the current thread. Valid only during a FUSE callback.
+ (GMUserFileSystem *)currentFS;

// Convenience method to creates an autoreleased NSError in the 
// NSPOSIXErrorDomain. Filesystem errors returned by the delegate must be
// standard posix errno values.
+ (NSError *)errorWithCode:(int)code;

- (void)postMountError:(NSError *)error;
- (void)mount:(NSDictionary *)args;
- (void)waitUntilMounted:(NSNumber *)fileDescriptor;

- (NSDictionary *)finderAttributesAtPath:(NSString *)path;
- (NSDictionary *)resourceAttributesAtPath:(NSString *)path;

- (BOOL)hasCustomIconAtPath:(NSString *)path;
- (BOOL)isDirectoryIconAtPath:(NSString *)path dirPath:(NSString **)dirPath;
- (NSData *)finderDataForAttributes:(NSDictionary *)attributes;
- (NSData *)resourceDataForAttributes:(NSDictionary *)attributes;

- (NSDictionary *)defaultAttributesOfItemAtPath:(NSString *)path 
                                       userData:userData
                                          error:(NSError **)error;  
- (BOOL)fillStatBuffer:(struct fuse_stat *)stbuf 
               forPath:(NSString *)path
              userData:(id)userData
                 error:(NSError **)error;
- (BOOL)fillStatfsBuffer:(struct statfs *)stbuf
                 forPath:(NSString *)path
                   error:(NSError **)error;

- (BOOL)fillStatvfsBuffer:(struct statvfs *)stbuf
                 forPath:(NSString *)path
                   error:(NSError **)error;
- (void)fuseInit;
- (void)fuseDestroy;

@end

@implementation GMUserFileSystem

+ (NSDictionary *)currentContext {
  struct fuse_context* context = fuse_get_context();
  if (!context) {
    return nil;
  }
  
  NSMutableDictionary* dict = [[NSMutableDictionary alloc] init];
  [dict setObject:[NSNumber numberWithUnsignedInt:context->uid]
                 forKey:kGMUserFileSystemContextUserIDKey];
  [dict setObject:[NSNumber numberWithUnsignedInt:context->gid]
                 forKey:kGMUserFileSystemContextGroupIDKey];
  [dict setObject:[NSNumber numberWithInt:context->pid]
                 forKey:kGMUserFileSystemContextProcessIDKey];
  return [dict autorelease];
}

- (id)init {
  return [self initWithDelegate:nil isThreadSafe:NO];
}

- (id)initWithDelegate:(id)delegate isThreadSafe:(BOOL)isThreadSafe {
  self = [super init];
  if (self) {
    internal_ = [[GMUserFileSystemInternal alloc] initWithDelegate:delegate
                                                      isThreadSafe:isThreadSafe];
  }
  return self;
}

- (void)dealloc {
  [internal_ release];
  [super dealloc];
}

- (void)setDelegate:(id)delegate {
  [internal_ setDelegate:delegate];
}
- (id)delegate {
  return [internal_ delegate];
}

- (BOOL)enableAllocate {
  return [internal_ supportsAllocate];
}
- (BOOL)enableCaseSensitiveNames {
  return [internal_ supportsCaseSensitiveNames];
}
- (BOOL)enableExchangeData {
  return [internal_ supportsExchangeData];
}
- (BOOL)enableExtendedTimes {
  return [internal_ supportsExtendedTimes];
}
- (BOOL)enableSetVolumeName {
  return [internal_ supportsSetVolumeName];
}

- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options {
  [self mountAtPath:mountPath
        withOptions:options
   shouldForeground:YES
    detachNewThread:YES];
}

- (void)mountAtPath:(NSString *)mountPath 
        withOptions:(NSArray *)options
   shouldForeground:(BOOL)shouldForeground
    detachNewThread:(BOOL)detachNewThread {
  [internal_ setMountPath:mountPath];
  NSMutableArray* optionsCopy = [NSMutableArray array];
  for (NSUInteger i = 0; i < [options count]; ++i) {
    NSString* option = [options objectAtIndex:i];
    NSString* optionLowercase = [option lowercaseString];
    if ([optionLowercase compare:@"rdonly"] == NSOrderedSame ||
        [optionLowercase compare:@"ro"] == NSOrderedSame) {
      [internal_ setIsReadOnly:YES];
    }
    [optionsCopy addObject:[[option copy] autorelease]];
  }
  NSDictionary* args = 
  [[NSDictionary alloc] initWithObjectsAndKeys:
   optionsCopy, @"options",
   [NSNumber numberWithBool:shouldForeground], @"shouldForeground", 
   nil, nil];
  if (detachNewThread) {
    [NSThread detachNewThreadSelector:@selector(mount:) 
                             toTarget:self 
                           withObject:args];
  } else {
    [self mount:args];
  }
}

- (void)unmount {
  if ([internal_ status] == GMUserFileSystem_MOUNTED) {
    NSArray* args = [NSArray arrayWithObjects:@"-v", [internal_ mountPath], nil];
    Unmount (args);
  }
  else
  	NSLog (@"Fuse: ERROR: File system '%@' is not mounted IN %@", [internal_ mountPath], self);
}

- (BOOL)invalidateItemAtPath:(NSString *)path error:(NSError **)error {
  int ret = -ENOTCONN;

  if ([internal_ status] == GMUserFileSystem_MOUNTED) {		/* CJEC, 2-Aug-19: TODO: OSXFUSE 3.8.3 BUG: Add this line of code to OSXFUSE in GITHUB to prevent invalidation when not mounted */
    struct fuse* handle = [internal_ handle];
    if (handle) {
#if defined (__APPLE__)
      ret = fuse_invalidate_path(handle, [path fileSystemRepresentation]);
    
      // Note: fuse_invalidate_path() may return -ENOENT to indicate that there
      // was no entry to be invalidated, e.g., because the path has not been seen
      // before or has been forgotten. This should not be considered to be an
      // error.
      if (ret == -ENOENT) {
        ret = 0;
      }
#else
			/* CJEC, 18-Dec-20: TODO: Implement -[GMUserFileSystem invalidateItemAtPath: error:] on non OS X/Darwin platforms
      */
      NSLog (@"Fuse: ERROR: UNIMPLEMENTED: fuse_invalidate_path(). Returning ENOTSUP IN %@", self);
		  ret = -ENOTSUP;
#endif	/* defined (__APPLE__) */
    }
  }
  if (ret != 0) {
    if (error) {
      *error = [GMUserFileSystem errorWithCode:-ret];
    }
    return NO;
  }

  return YES;
}

+ (NSError *)errorWithCode:(int)code {
  return [NSError errorWithDomain:NSPOSIXErrorDomain code:code userInfo:nil];
}

+ (GMUserFileSystem *)currentFS {
  struct fuse_context* context = fuse_get_context();
  assert(context);
  return (GMUserFileSystem *)context->private_data;
}

#if defined (__APPLE__)
/* Fuse on OS X/Darwin does not mount file systems synchronously. Instead, the OS X/Darwin Fuse-specific
		ioctl(FUSEDEVIOCGETHANDSHAKECOMPLETE) indicates when mount has finished.
*/
#define FUSEDEVIOCGETHANDSHAKECOMPLETE _IOR('F', 2, u_int32_t)
static const int kMaxWaitForMountTries = 50;
static const int kWaitForMountUSleepInterval = 100000;  // 100 ms
#endif	/* defined (__APPLE__) */

- (void)waitUntilMounted:(NSNumber *)fileDescriptor {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

#if defined (__APPLE__)
  for (int i = 0; i < kMaxWaitForMountTries; ++i) {
    UInt32 handShakeComplete = 0;
    int ret = ioctl([fileDescriptor intValue], FUSEDEVIOCGETHANDSHAKECOMPLETE,
                    &handShakeComplete);
    if (ret == 0 && handShakeComplete) {
      [internal_ setStatus:GMUserFileSystem_MOUNTED];
#endif	/* defined (__APPLE__) */

      // Successfully mounted, so post notification.
      NSDictionary* userInfo = 
        [NSDictionary dictionaryWithObjectsAndKeys:
         [internal_ mountPath], kGMUserFileSystemMountPathKey,
         nil];
      NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
      [center postNotificationName:kGMUserFileSystemDidMount object:self
                          userInfo:userInfo];
      [pool release];
      return;
#if defined (__APPLE__)
    }
    else
      if (ret < 0)
        NSLog (@"Fuse: ERROR: ioctl (FUSEDEVIOCGETHANDSHAKECOMPLETE %lu) FAILED. errno %i, %s IN %@", FUSEDEVIOCGETHANDSHAKECOMPLETE, errno, strerror (errno), self);
    usleep(kWaitForMountUSleepInterval);
  }
  
  // Tried for a long time and no luck :-(
  // Unmount and report failure?
  [self postMountError: [NSError errorWithDomain: NSPOSIXErrorDomain code: EIO userInfo: nil]];
  [pool release];
#endif	/* defined (__APPLE__) */
}

- (void)fuseInit {
  struct fuse_context* context = fuse_get_context();

  [internal_ setHandle:context->fuse];
  [internal_ setStatus:GMUserFileSystem_INITIALIZING];

  NSError* error = nil;
  NSDictionary* attribs = [self attributesOfFileSystemForPath:@"/" error:&error];

  if (attribs) {
    NSNumber* supports = nil;

    supports = [attribs objectForKey:kGMUserFileSystemVolumeSupportsAllocateKey];
    if (supports) {
      [internal_ setSupportsAllocate:[supports boolValue]];
    }

    supports = [attribs objectForKey:kGMUserFileSystemVolumeSupportsCaseSensitiveNamesKey];
    if (supports) {
      [internal_ setSupportsCaseSensitiveNames:[supports boolValue]];
    }

#if defined (__APPLE__)
		/* The exchangedata(2) system call is only available on OS X/Darwin and is deprecated as of
  		OS X 10.13 in favour of renamex_np(2) and renameatx_np(2), which are very similar to
      the Linux renameat2(2) system call.
    */
    supports = [attribs objectForKey:kGMUserFileSystemVolumeSupportsExchangeDataKey];
    if (supports) {
      [internal_ setSupportsExchangeData:[supports boolValue]];
    }
#endif	/* defined (__APPLE__) */

    supports = [attribs objectForKey:kGMUserFileSystemVolumeSupportsExtendedDatesKey];
    if (supports) {
      [internal_ setSupportsExtendedTimes:[supports boolValue]];
    }

    supports = [attribs objectForKey:kGMUserFileSystemVolumeSupportsSetVolumeNameKey];
    if (supports) {
      [internal_ setSupportsSetVolumeName:[supports boolValue]];
    }
  }
  // For Fuse for OS X/Darwin:
  // The mount point won't actually show up until this winds its way
  // back through the kernel after this routine returns. In order to post
  // the kGMUserFileSystemDidMount notification we start a new thread that will
  // poll until it is mounted.
  struct fuse_session* se = fuse_get_session(context->fuse);
  struct fuse_chan* chan = fuse_session_next_chan(se, NULL);
  int fd = fuse_chan_fd(chan);
  
  [NSThread detachNewThreadSelector:@selector(waitUntilMounted:)
                           toTarget:self
                         withObject:[NSNumber numberWithInteger:fd]];
}

- (void)fuseDestroy {
  if ([[internal_ delegate] respondsToSelector:@selector(willUnmount)]) {
    [[internal_ delegate] willUnmount];
  }
  [internal_ setStatus:GMUserFileSystem_UNMOUNTING];

  NSDictionary* userInfo = 
    [NSDictionary dictionaryWithObjectsAndKeys:
     [internal_ mountPath], kGMUserFileSystemMountPathKey,
     nil];
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center postNotificationName:kGMUserFileSystemDidUnmount object:self
                      userInfo:userInfo];
  [internal_ setStatus:GMUserFileSystem_NOT_MOUNTED];
}

#pragma mark Finder Info, Resource Forks and HFS headers
#if defined (__APPLE__)
- (NSDictionary *)finderAttributesAtPath:(NSString *)path {
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  UInt16 flags = 0;

  // If a directory icon, we'll make invisible and update the path to parent.
  if ([self isDirectoryIconAtPath:path dirPath:&path]) {
    flags |= kIsInvisible;
  }

  id delegate = [internal_ delegate];
  if ([delegate respondsToSelector:@selector(finderAttributesAtPath:error:)]) {
    NSError* error = nil;
    NSDictionary* dict = [delegate finderAttributesAtPath:path error:&error];
    if (dict != nil) {
      if ([dict objectForKey:kGMUserFileSystemCustomIconDataKey]) {
        // They have custom icon data, so make sure the FinderFlags bit is set.
        flags |= kHasCustomIcon;
      }
      if (flags != 0) {
        // May need to update kGMUserFileSystemFinderFlagsKey if different.
        NSNumber* finderFlags = [dict objectForKey:kGMUserFileSystemFinderFlagsKey];
        if (finderFlags != nil) {
          UInt16 tmp = (UInt16)[finderFlags longValue];
          if (flags == tmp) {
            return dict;  // They already have our desired flags.
          }          
          flags |= tmp;
        }
        // Doh! We need to create a new dict with the updated flags key.
        NSMutableDictionary* newDict = 
          [NSMutableDictionary dictionaryWithDictionary:dict];
        [newDict setObject:[NSNumber numberWithLong:flags] 
                    forKey:kGMUserFileSystemFinderFlagsKey];
        return newDict;
      }
      return dict;
    }
    // Fall through and create dictionary based on flags if necessary.
  }
  if (flags != 0) {
    return [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:flags]
                                       forKey:kGMUserFileSystemFinderFlagsKey];
  }
  return nil;
}

- (NSDictionary *)resourceAttributesAtPath:(NSString *)path {
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }

  id delegate = [internal_ delegate];
  if ([delegate respondsToSelector:@selector(resourceAttributesAtPath:error:)]) {
    NSError* error = nil;
    return [delegate resourceAttributesAtPath:path error:&error];
  }
  return nil;
}

- (BOOL)hasCustomIconAtPath:(NSString *)path {
  if ([path isEqualToString:@"/"]) {
    return NO;  // For a volume icon they should use the volicon= option.
  }
  NSDictionary* finderAttribs = [self finderAttributesAtPath:path];
  if (finderAttribs) {
    NSNumber* finderFlags = 
      [finderAttribs objectForKey:kGMUserFileSystemFinderFlagsKey];
    if (finderFlags) {
      UInt16 flags = (UInt16)[finderFlags longValue];
      return (flags & kHasCustomIcon) == kHasCustomIcon;
    }
  }
  return NO;
}
#endif	/* defined (__APPLE__) */

- (BOOL)isDirectoryIconAtPath:(NSString *)path dirPath:(NSString **)dirPath {
  NSString* name = [path lastPathComponent];
  if ([name isEqualToString:@"Icon\r"]) {
    if (dirPath) {
      *dirPath = [path stringByDeletingLastPathComponent];
    }
    return YES;
  }
  return NO;
}

// If the given attribs dictionary contains any FinderInfo attributes then 
// returns NSData for FinderInfo; otherwise returns nil.
- (NSData *)finderDataForAttributes:(NSDictionary *)attribs {
  if (!attribs) { 
    return nil;
  }

  GMFinderInfo* info = [GMFinderInfo finderInfo];
  BOOL attributeFound = NO;  // Have we found at least one relevant attribute?

  NSNumber* flags = [attribs objectForKey:kGMUserFileSystemFinderFlagsKey];
  if (flags) {
    attributeFound = YES;
    [info setFlags:(UInt16)[flags longValue]];
  }
  
  NSNumber* extendedFlags = 
    [attribs objectForKey:kGMUserFileSystemFinderExtendedFlagsKey];
  if (extendedFlags) {
    attributeFound = YES;
    [info setExtendedFlags:(UInt16)[extendedFlags longValue]];
  }
  
  NSNumber* typeCode = [attribs objectForKey:NSFileHFSTypeCode];
  if (typeCode) {
    attributeFound = YES;
    [info setTypeCode:(OSType)[typeCode longValue]];
  }

  NSNumber* creatorCode = [attribs objectForKey:NSFileHFSCreatorCode];
  if (creatorCode) {
    attributeFound = YES;
    [info setCreatorCode:(OSType)[creatorCode longValue]];
  }

  return attributeFound ? [info data] : nil;
}

#if defined (__APPLE__)
// If the given attribs dictionary contains any ResourceFork attributes then 
// returns NSData for the ResourceFork; otherwise returns nil.
- (NSData *)resourceDataForAttributes:(NSDictionary *)attribs {
  if (!attribs) {
    return nil;
  }

  GMResourceFork* fork = [GMResourceFork resourceFork];
  BOOL attributeFound = NO;  // Have we found at least one relevant attribute?
  
  NSData* imageData = [attribs objectForKey:kGMUserFileSystemCustomIconDataKey];
  if (imageData) {
    attributeFound = YES;
    [fork addResourceWithType:'icns'
                        resID:kCustomIconResource // -16455
                         name:nil
                         data:imageData];    
  }
  NSURL* url = [attribs objectForKey:kGMUserFileSystemWeblocURLKey];
  if (url) {
    attributeFound = YES;
    NSString* urlString = [url absoluteString];
    NSData* data = [urlString dataUsingEncoding:NSUTF8StringEncoding];
    [fork addResourceWithType:'url '
                        resID:256
                         name:nil
                         data:data];
  }
  return attributeFound ? [fork data] : nil;
}
#endif	/* defined (__APPLE__) */

#pragma mark Internal Stat Operations

- (BOOL)fillStatfsBuffer:(struct statfs *)stbuf
                 forPath:(NSString *)path
                   error:(NSError **)error {
  NSDictionary* attributes = [self attributesOfFileSystemForPath:path error:error];
  if (!attributes) {
    return NO;
  }
  
  // CJEC, 13-Oct-21: This "block size" is actually the optimal IO size, not the file sytem's
  //									block size. See statfs(2) and statvfs(2).
  //									Patched this code to use the correct key from the orginal OSXFUSE 3.8.3
  //									source
  // Optimal IO size
  NSNumber* iosize = [attributes objectForKey:kGMUserFileSystemVolumeFileSystemOptimalIOSizeKey];
  assert(iosize);
#if defined (__linux__)
  stbuf->f_bsize = (int32_t)[iosize intValue];
#else
  stbuf->f_iosize = (int32_t)[iosize intValue];
#endif	/* defined (__linux__) */
  
  // Block size
  NSNumber* blocksize = [attributes objectForKey:kGMUserFileSystemVolumeFileSystemBlockSizeKey];
  assert(blocksize);
#if defined (__linux__)
  stbuf->f_frsize = (uint32_t)[blocksize unsignedIntValue];
#else
  stbuf->f_bsize = (uint32_t)[blocksize unsignedIntValue];
#endif	/* defined (__linux__) */

  // Size in blocks
  NSNumber* size = [attributes objectForKey:NSFileSystemSize];
  assert(size);
  stbuf->f_blocks = (uint64_t)([size unsignedLongLongValue] / stbuf->f_bsize);
  
  // Number of free / available blocks
  NSNumber* freeSize = [attributes objectForKey:NSFileSystemFreeSize];
  assert(freeSize);
  stbuf->f_bavail = stbuf->f_bfree =
    (uint64_t)([freeSize unsignedLongLongValue] / stbuf->f_bsize);
  
  // Number of nodes
  NSNumber* numNodes = [attributes objectForKey:NSFileSystemNodes];
  assert(numNodes);
  stbuf->f_files = (uint64_t)[numNodes unsignedLongLongValue];
  
  // Number of free / available nodes
  NSNumber* freeNodes = [attributes objectForKey:NSFileSystemFreeNodes];
  assert(freeNodes);
  stbuf->f_ffree = (uint64_t)[freeNodes unsignedLongLongValue];
  
  return YES;
}

- (BOOL)fillStatvfsBuffer:(struct statvfs *)stbuf
                 forPath:(NSString *)path
                   error:(NSError **)error {
  NSDictionary* attributes = [self attributesOfFileSystemForPath:path error:error];
  if (!attributes) {
    return NO;
  }
  
  // Block size
  #if 0
  NSNumber* blocksize = [attributes objectForKey:kGMUserFileSystemVolumeFileSystemBlockSizeKey];
  assert(blocksize);
  stbuf->f_bsize = (uint32_t)[blocksize unsignedIntValue];

  #else
  // CJEC, 13-Oct-21: This "block size" is actually the optimal IO size, not the file sytem's
  //									block size. See statfs(2) and statvfs(2).
  //									Patched this code to use the correct key from the orginal OSXFUSE 3.8.3
  //									source
  NSNumber* iosize = [attributes objectForKey:kGMUserFileSystemVolumeFileSystemOptimalIOSizeKey];
  assert(iosize);
  stbuf->f_bsize = (uint32_t)[iosize unsignedIntValue];

	// The file system block size
  NSNumber* blocksize = [attributes objectForKey:kGMUserFileSystemVolumeFileSystemBlockSizeKey];
  assert(blocksize);
  stbuf->f_frsize = (uint32_t)[blocksize unsignedIntValue];

#endif

  // Size in blocks
  NSNumber* size = [attributes objectForKey:NSFileSystemSize];
  assert(size);
  stbuf->f_blocks = (uint64_t)([size unsignedLongLongValue] / stbuf->f_bsize);
  
  // Number of free / available blocks
  NSNumber* freeSize = [attributes objectForKey:NSFileSystemFreeSize];
  assert(freeSize);
  stbuf->f_bavail = stbuf->f_bfree =
    (uint64_t)([freeSize unsignedLongLongValue] / stbuf->f_bsize);
  
  // Number of nodes
  NSNumber* numNodes = [attributes objectForKey:NSFileSystemNodes];
  assert(numNodes);
  stbuf->f_files = (uint64_t)[numNodes unsignedLongLongValue];
  
  // Number of free / available nodes
  NSNumber* freeNodes = [attributes objectForKey:NSFileSystemFreeNodes];
  assert(freeNodes);
  stbuf->f_ffree = (uint64_t)[freeNodes unsignedLongLongValue];
  
  // CJEC, 13-Oct-21: Add support for the maximum filename length
  // Maximum lengh of a filename
  //
  // Note: OS X/Darwin and FreeBSD statvfs(3) man pages both state that
  //				pathconf(2) should be used instead
  NSNumber* namemax = [attributes objectForKey:kGMUserFileSystemVolumeMaxFilenameLengthKey];
  assert(namemax);
  stbuf->f_namemax = [namemax unsignedLongValue];
  
  return YES;
}

- (BOOL)fillStatBuffer:(struct fuse_stat *)stbuf 
               forPath:(NSString *)path 
              userData:(id)userData
                 error:(NSError **)error {
  NSDictionary* attributes = [self defaultAttributesOfItemAtPath:path 
                                                        userData:userData
                                                           error:error];
  if (!attributes) {
    return NO;
  }

  // Inode
  /* CJEC, 23-Dec-20: TODO: OSXFUSE 3.10.5 documents a problem with 64-bit INodeIDs losing the top 32 bits
  														due to a kernel problem https://github.com/osxfuse/osxfuse/releases/tag/osxfuse-3.10.5 
                              This fix needs to be applied to this code base, or use Benjamin Fleischer's modern
                              macFUSE 4.x, which is not open source.
  	  
    Note: For non-UNIX file system, the INodeID is meaningless.
          See https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/stat-functions?view=msvc-170
  */
  NSNumber* inode = [attributes objectForKey:NSFileSystemFileNumber];
  if (inode) {
    stbuf->st_ino = [inode longLongValue];	/* Note: FUSE assumes ino_t is 64 bits wide in its fuse_ino_t type */
  }
  
  // Permissions (mode)
  NSNumber* perm = [attributes objectForKey:NSFilePosixPermissions];
  stbuf->st_mode = [perm longValue];
  NSString* fileType = [attributes objectForKey:NSFileType];
  if ([fileType isEqualToString:NSFileTypeDirectory ]) {
    stbuf->st_mode |= S_IFDIR;
  } else if ([fileType isEqualToString:NSFileTypeRegular]) {
    stbuf->st_mode |= S_IFREG;
  } else if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
    stbuf->st_mode |= S_IFLNK;
  } else if ([fileType isEqualToString:NSFileTypeBlockSpecial]) {
    stbuf->st_mode |= S_IFBLK;
  } else if ([fileType isEqualToString:NSFileTypeCharacterSpecial]) {
    stbuf->st_mode |= S_IFCHR;
  } else if ([fileType isEqualToString:NSFileTypeSocket]) {
    stbuf->st_mode |= S_IFSOCK;
  } else if ([fileType isEqualToString:kGMUserFileSystemFileTypeFIFOSpecialKey]) {
    stbuf->st_mode |= S_IFIFO;
#if defined (__APPLE__) || defined (__FreeBSD__)
  } else if ([fileType isEqualToString:kGMUserFileSystemFileTypeWhiteoutSpecialKey]) {
    stbuf->st_mode |= S_IFWHT;
#endif	/* defined (__APPLE__) || defined (__FreeBSD__) */
  } else {
#if defined (__APPLE__)
    *error = [GMUserFileSystem errorWithCode:EFTYPE];
#else
    *error = [GMUserFileSystem errorWithCode:EINVAL];		/* Note: Linux & FreeBSD mknod(2) returns this for an invalid file type */
#endif	/* defined (__APPLE__) */
    return NO;
  }
  
  // Owner and Group
  // Note that if the owner or group IDs are not specified, the effective
  // user and group IDs for the current process are used as defaults.
  NSNumber* uid = [attributes objectForKey:NSFileOwnerAccountID];
  NSNumber* gid = [attributes objectForKey:NSFileGroupOwnerAccountID];
  stbuf->st_uid = uid ? [uid unsignedLongValue] : geteuid();
  stbuf->st_gid = gid ? [gid unsignedLongValue] : getegid();

  // nlink
  NSNumber* nlink = [attributes objectForKey:NSFileReferenceCount];
  stbuf->st_nlink = [nlink longValue];

#if defined (__APPLE__) || defined (__FreeBSD__)
  // flags
  // CJEC, 15-Jul-22: TODO: Support Linux INode flags, which are very similar. https://man7.org/linux/man-pages/man2/ioctl_iflags.2.html 
  NSNumber* flags = [attributes objectForKey:kGMUserFileSystemFileFlagsKey];
  if (flags) {
    stbuf->st_flags = [flags longValue];
  } else {
    // Just in case they tried to use NSFileImmutable or NSFileAppendOnly
    NSNumber* immutableFlag = [attributes objectForKey:NSFileImmutable];
    if (immutableFlag && [immutableFlag boolValue]) {
      stbuf->st_flags |= UF_IMMUTABLE;
    }
    NSNumber* appendFlag = [attributes objectForKey:NSFileAppendOnly];
    if (appendFlag && [appendFlag boolValue]) {
      stbuf->st_flags |= UF_APPEND;
    }
  }
#endif	/* defined (__APPLE__) || defined (__FreeBSD__) */

  // Note: We default atime, ctime to mtime if it is provided.
  NSDate* mdate = [attributes objectForKey:NSFileModificationDate];
  if (mdate) {
    const double seconds_dp = [mdate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond); 
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;

#if defined (__linux__)
    stbuf->st_mtim.tv_sec = t_sec;
    stbuf->st_mtim.tv_nsec = t_nsec;
    stbuf->st_atim = stbuf->st_mtim;  // Default to mtime
    stbuf->st_ctim = stbuf->st_mtim;  // Default to mtime
//    NSLog (@"Fuse: DEBUG: %s, %s{%u}: NSModificationDate %@, timespec %lu,%lu for path '%@' IN %@", __PRETTY_FUNCTION__, __FILE__, __LINE__, [attributes objectForKey: NSFileModificationDate], stbuf -> st_mtim.tv_sec, stbuf -> st_mtim.tv_nsec, path, self);
#else
    stbuf->st_mtimespec.tv_sec = t_sec;
    stbuf->st_mtimespec.tv_nsec = t_nsec;
    stbuf->st_atimespec = stbuf->st_mtimespec;  // Default to mtime
    stbuf->st_ctimespec = stbuf->st_mtimespec;  // Default to mtime
//    NSLog (@"Fuse: DEBUG: %s, %s{%u}: NSModificationDate %@, timespec %lu,%lu for path '%@' IN %@", __PRETTY_FUNCTION__, __FILE__, __LINE__, [attributes objectForKey: NSFileModificationDate], stbuf -> st_mtimespec.tv_sec, stbuf -> st_mtimespec.tv_nsec, path, self);
#endif	/* defined (__linux__) */
  }
  NSDate* adate = [attributes objectForKey:kGMUserFileSystemFileAccessDateKey];
  if (adate) {
    const double seconds_dp = [adate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond); 
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
#if defined (__linux__)
    stbuf->st_atim.tv_sec = t_sec;
    stbuf->st_atim.tv_nsec = t_nsec;
#else
    stbuf->st_atimespec.tv_sec = t_sec;
    stbuf->st_atimespec.tv_nsec = t_nsec;
#endif	/* defined (__linux__) */
  }
  // Note: For non-UNIX file system, the INodeID is meaningless.
  //				See https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/stat-functions?view=msvc-170
  // Note: On Windows, the C Runtime's stat(3) function uses st_ctime for the creation time,
  //				rather than the inode change time
  NSDate* cdate = [attributes objectForKey:kGMUserFileSystemFileChangeDateKey];
  if (cdate) {
    const double seconds_dp = [cdate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond); 
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
#if defined (__linux__)
    stbuf->st_ctim.tv_sec = t_sec;
    stbuf->st_ctim.tv_nsec = t_nsec;
#else
    stbuf->st_ctimespec.tv_sec = t_sec;
    stbuf->st_ctimespec.tv_nsec = t_nsec;
#endif	/* defined (__linux__) */
  }

  // Note: For compatibility with UNIX, use st_birthtime for the Windows create time instead of st_ctime
#if defined (_DARWIN_USE_64_BIT_INODE) || defined (__FreeBSD__) || defined (_WIN32)
  /* CJEC, 14-Oct-20: TODO: Linux has statx(2) which provides struct statx.stx_btime
                            but this is not supported by Fuse 2.6 API
  */
  NSDate* bdate = [attributes objectForKey:NSFileCreationDate];
  if (bdate) {
    const double seconds_dp = [bdate timeIntervalSince1970];
    const time_t t_sec = (time_t) seconds_dp;
    const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond); 
    const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
    stbuf->st_birthtimespec.tv_sec = t_sec;
    stbuf->st_birthtimespec.tv_nsec = t_nsec;
  }
#endif	/* defined (_DARWIN_USE_64_BIT_INODE) || defined (__FreeBSD__) */

  // File size
  // Note that the actual file size of a directory depends on the internal 
  // representation of directories in the particular file system. In general
  // this is not the combined size of the files in that directory.
  NSNumber* size = [attributes objectForKey:NSFileSize];
  if (size) {
    stbuf->st_size = [size longLongValue];
//    NSLog (@"Fuse: DEBUG: %s, %s{%u}: NSFileSize %@, file size %llu for path '%@' IN %@", __PRETTY_FUNCTION__, __FILE__, __LINE__, [attributes objectForKey: NSFileSize], (unsigned long long) stbuf -> st_size, path, self);
  }

  // Set the number of blocks used so that Finder will display size on disk 
  // properly. The man page says that this is in terms of 512 byte blocks.
  NSNumber* blocks = [attributes objectForKey:kGMUserFileSystemFileSizeInBlocksKey];
  if (blocks) {
    stbuf->st_blocks = [blocks longLongValue];
  } else if (stbuf->st_size > 0) {
    stbuf->st_blocks = stbuf->st_size / 512;
    if (stbuf->st_size % 512) {
      ++(stbuf->st_blocks);
    }
  }

  // Optimal file I/O size
  NSNumber *ioSize = [attributes objectForKey:kGMUserFileSystemFileOptimalIOSizeKey];
  if (ioSize) {
    stbuf->st_blksize = [ioSize intValue];
  }

	// CJEC, 13-Oct-21: Add support for the device file's INodeID
 	// Device file number
  NSNumber *device = [attributes objectForKey: NSFileDeviceIdentifier];
  if (device) {
    stbuf->st_dev = (dev_t) [device intValue];
  }
  
  return YES;  
}

#pragma mark Creating an Item

- (BOOL)createDirectoryAtPath:(NSString *)path 
                   attributes:(NSDictionary *)attributes
                        error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSMutableString* traceinfo = 
     [NSMutableString stringWithFormat:@"%@ [%@]", path, attributes]; 
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(createDirectoryAtPath:attributes:error:)]) {
    return [[internal_ delegate] createDirectoryAtPath:path attributes:attributes error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

- (BOOL)createFileAtPath:(NSString *)path 
              attributes:(NSDictionary *)attributes
                   flags:(int)flags
                userData:(id *)userData
                   error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = [NSString stringWithFormat:@"%@ [%@]", path, attributes]; 
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(createFileAtPath:attributes:flags:userData:error:)]) {
    return [[internal_ delegate] createFileAtPath:path
                                       attributes:attributes
                                            flags:flags
                                         userData:userData
                                            error:error];
  } else if ([[internal_ delegate] respondsToSelector:@selector(createFileAtPath:attributes:userData:error:)]) {
    return [[internal_ delegate] createFileAtPath:path
                                       attributes:attributes
                                         userData:userData
                                            error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Removing an Item

- (BOOL)removeDirectoryAtPath:(NSString *)path error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }  
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(removeDirectoryAtPath:error:)]) {
    return [[internal_ delegate] removeDirectoryAtPath:path error:error];
  }
  return [self removeItemAtPath:path error:error];
}

- (BOOL)removeItemAtPath:(NSString *)path error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }  
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(removeItemAtPath:error:)]) {
    return [[internal_ delegate] removeItemAtPath:path error:error];
  }

  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Moving an Item

/* Note: renameat2(2) support was added to Linux in the Fuse 3.0 API specification
          and renamex_np(2) support was added to OS X/Darwin in macFUSE 4.0.0
*/
- (BOOL)moveItemAtPath:(NSString *)source 
                toPath:(NSString *)destination
                 error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@ -> %@", source, destination];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(moveItemAtPath:toPath:error:)]) {
    return [[internal_ delegate] moveItemAtPath:source toPath:destination error:error];
  }  
  
  *error = [GMUserFileSystem errorWithCode:EACCES];
  return NO;
}

#pragma mark Linking an Item

- (BOOL)linkItemAtPath:(NSString *)path
                toPath:(NSString *)otherPath
                 error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = [NSString stringWithFormat:@"%@ -> %@", path, otherPath];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(linkItemAtPath:toPath:error:)]) {
    return [[internal_ delegate] linkItemAtPath:path toPath:otherPath error:error];
  }  

  *error = [GMUserFileSystem errorWithCode:ENOTSUP];  // Note: error not in man page.
  return NO;
}

#pragma mark Symbolic Links

- (BOOL)createSymbolicLinkAtPath:(NSString *)path 
             withDestinationPath:(NSString *)otherPath
                           error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = [NSString stringWithFormat:@"%@ -> %@", path, otherPath];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }  
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(createSymbolicLinkAtPath:withDestinationPath:error:)]) {
    return [[internal_ delegate] createSymbolicLinkAtPath:path
                                      withDestinationPath:otherPath
                                                    error:error];
  }

  *error = [GMUserFileSystem errorWithCode:ENOTSUP];  // Note: error not in man page.
  return NO; 
}

- (NSString *)destinationOfSymbolicLinkAtPath:(NSString *)path
                                        error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(destinationOfSymbolicLinkAtPath:error:)]) {
    return [[internal_ delegate] destinationOfSymbolicLinkAtPath:path error:error];
  }

  *error = [GMUserFileSystem errorWithCode:ENOENT];
  return nil;
}

#pragma mark Directory Contents

- (NSArray *)contentsOfDirectoryAtPath:(NSString *)path error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }
#endif	/* defined (__APPLE__) */

  NSArray* contents = nil;
  if ([[internal_ delegate] respondsToSelector:@selector(contentsOfDirectoryAtPath:error:)]) {
    contents = [[internal_ delegate] contentsOfDirectoryAtPath:path error:error];
  } else if ([path isEqualToString:@"/"]) {
    contents = [NSArray array];  // Give them an empty root directory for free.
  }
  return contents;
}

#pragma mark File Contents

// Note: Only call this if the delegate does indeed support this method.
- (NSData *)contentsAtPath:(NSString *)path {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }
#endif	/* defined (__APPLE__) */

  id delegate = [internal_ delegate];
  return [delegate contentsAtPath:path];
}

- (BOOL)openFileAtPath:(NSString *)path 
                  mode:(int)mode
              userData:(id *)userData 
                 error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = [NSString stringWithFormat:@"%@, mode=0x%x", path, mode];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  id delegate = [internal_ delegate];
  if ([delegate respondsToSelector:@selector(contentsAtPath:)]) {
    NSData* data = [self contentsAtPath:path];
    if (data != nil) {
      *userData = [GMDataBackedFileDelegate fileDelegateWithData:data];
      return YES;
    }
  } else if ([delegate respondsToSelector:@selector(openFileAtPath:mode:userData:error:)]) {
    if ([delegate openFileAtPath:path 
                            mode:mode 
                        userData:userData 
                           error:error]) {
      return YES;  // They handled it.
    }
  }

  // Still unable to open the file; maybe it is an Icon\r or AppleDouble?
  if ([internal_ shouldCheckForResource]) {
    NSData* data = nil;  // Synthesized data that we provide a file delegate for.

    // Is it an Icon\r file that we handle?
    if ([self isDirectoryIconAtPath:path dirPath: NULL]) {
      data = [NSData data];  // The Icon\r file is empty.
    }

    if (data != nil) {
      if ((mode & O_ACCMODE) == O_RDONLY) {
        *userData = [GMDataBackedFileDelegate fileDelegateWithData:data];
      } else {
        NSMutableData* mutableData = [NSMutableData dataWithData:data];
        *userData = 
          [GMMutableDataBackedFileDelegate fileDelegateWithData:mutableData];
      }
      return YES;  // Handled by a synthesized file delegate.
    }
  }
  
  if (*error == nil) {
    *error = [GMUserFileSystem errorWithCode:ENOENT];
  }
  return NO;
}

- (void)releaseFileAtPath:(NSString *)path userData:(id)userData {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p", path, userData];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if (userData != nil && 
      [userData isKindOfClass:[GMDataBackedFileDelegate class]]) {
    return;  // Don't report releaseFileAtPath for internal file.
  }
  if ([[internal_ delegate] respondsToSelector:@selector(releaseFileAtPath:userData:)]) {
    [[internal_ delegate] releaseFileAtPath:path userData:userData];
  }
}

- (int)readFileAtPath:(NSString *)path 
             userData:(id)userData
               buffer:(char *)buffer 
                 size:(size_t)size 
               offset:(fuse_off_t)offset
                error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p, offset=%lld, size=%lu", 
       path, userData, offset, (unsigned long)size];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if (userData != nil &&
      [userData respondsToSelector:@selector(readToBuffer:size:offset:error:)]) {
    return [userData readToBuffer:buffer size:size offset:offset error:error];
  } else if ([[internal_ delegate] respondsToSelector:@selector(readFileAtPath:userData:buffer:size:offset:error:)]) {
    return [[internal_ delegate] readFileAtPath:path
                                       userData:userData
                                         buffer:buffer
                                           size:size
                                         offset:offset
                                          error:error];
  }
  *error = [GMUserFileSystem errorWithCode:EACCES];
  return -1;
}

- (int)writeFileAtPath:(NSString *)path 
              userData:(id)userData
                buffer:(const char *)buffer
                  size:(size_t)size 
                offset:(fuse_off_t)offset
                 error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, userData=%p, offset=%lld, size=%lu", 
       path, userData, offset, (unsigned long)size];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if (userData != nil &&
      [userData respondsToSelector:@selector(writeFromBuffer:size:offset:error:)]) {
    return [userData writeFromBuffer:buffer size:size offset:offset error:error];
  } else if ([[internal_ delegate] respondsToSelector:@selector(writeFileAtPath:userData:buffer:size:offset:error:)]) {
    return [[internal_ delegate] writeFileAtPath:path
                                        userData:userData
                                          buffer:buffer
                                            size:size
                                          offset:offset
                                           error:error];
  }
  *error = [GMUserFileSystem errorWithCode:EACCES];
  return -1; 
}

- (BOOL)truncateFileAtPath:(NSString *)path
                  userData:(id)userData
                    offset:(fuse_off_t)offset 
                     error:(NSError **)error
                   handled:(BOOL*)handled {
	(void) path;										/* Avoid unused argument compiler warning */

  if (userData != nil &&
      [userData respondsToSelector:@selector(truncateToOffset:error:)]) {
    *handled = YES;
    return [userData truncateToOffset:offset error:error];
  }
  *handled = NO;
  return NO;
}

- (BOOL)supportsAllocateFileAtPath {
  id delegate = [internal_ delegate];
  return [delegate respondsToSelector:@selector(preallocateFileAtPath:userData:options:offset:length:error:)];
}

- (BOOL)allocateFileAtPath:(NSString *)path
                  userData:(id)userData
                   options:(int)options
                    offset:(fuse_off_t)offset
                    length:(fuse_off_t)length
                     error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, userData=%p, options=%d, offset=%lld, length=%lld",
       path, userData, options, offset, length];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([self supportsAllocateFileAtPath]) {
#if defined (__APPLE__)
    if ((options & PREALLOCATE) == PREALLOCATE) {
#endif	/* defined (__APPLE__) */
      if ([[internal_ delegate] respondsToSelector:@selector(preallocateFileAtPath:userData:options:offset:length:error:)]) {
        return [[internal_ delegate] preallocateFileAtPath:path
                                                  userData:userData
                                                   options:options
                                                    offset:offset
                                                    length:length
                                                     error:error];
      }
    }
#if defined (__APPLE__)
    *error = [GMUserFileSystem errorWithCode:ENOTSUP];
    return NO;
  }
#endif	/* defined (__APPLE__) */
  *error = [GMUserFileSystem errorWithCode:ENOSYS];
  return NO;
}

- (BOOL)supportsExchangeData {
  id delegate = [internal_ delegate];
  return [delegate respondsToSelector:@selector(exchangeDataOfItemAtPath:withItemAtPath:error:)];
}

- (BOOL)exchangeDataOfItemAtPath:(NSString *)path1
                  withItemAtPath:(NSString *)path2
                           error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = [NSString stringWithFormat:@"%@ <-> %@", path1, path2];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(exchangeDataOfItemAtPath:withItemAtPath:error:)]) {
    return [[internal_ delegate] exchangeDataOfItemAtPath:path1
                                           withItemAtPath:path2
                                                    error:error];
  }  
  *error = [GMUserFileSystem errorWithCode:ENOSYS];
  return NO;
}

#pragma mark Getting and Setting Attributes

- (NSDictionary *)attributesOfFileSystemForPath:(NSString *)path
                                          error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }  
#endif	/* defined (__APPLE__) */

  NSMutableDictionary* attributes = [NSMutableDictionary dictionary];

  NSNumber* defaultSize = [NSNumber numberWithLongLong:(2LL * 1024 * 1024 * 1024)];
  [attributes setObject:defaultSize forKey:NSFileSystemSize];
  [attributes setObject:defaultSize forKey:NSFileSystemFreeSize];
  [attributes setObject:defaultSize forKey:NSFileSystemNodes];
  [attributes setObject:defaultSize forKey:NSFileSystemFreeNodes];
  [attributes setObject:[NSNumber numberWithInt:255] forKey:kGMUserFileSystemVolumeMaxFilenameLengthKey];
  [attributes setObject:[NSNumber numberWithInt:4096] forKey:kGMUserFileSystemVolumeFileSystemOptimalIOSizeKey];	/* CJEC, 13-Oct-21: This "block size" is actually the optimal IO size, not the file sytem's block size. See statfs(2) and statvfs(2) */
  [attributes setObject:[NSNumber numberWithInt:512] forKey:kGMUserFileSystemVolumeFileSystemBlockSizeKey];

  NSNumber* supports = nil;

  supports = [NSNumber numberWithBool:[self supportsExchangeData]];
  [attributes setObject:supports forKey:kGMUserFileSystemVolumeSupportsExchangeDataKey];

  supports = [NSNumber numberWithBool:[self supportsAllocateFileAtPath]];
  [attributes setObject:supports forKey:kGMUserFileSystemVolumeSupportsAllocateKey];

  // The delegate can override any of the above defaults by implementing the
  // attributesOfFileSystemForPath selector and returning a custom dictionary.
  if ([[internal_ delegate] respondsToSelector:@selector(attributesOfFileSystemForPath:error:)]) {
    *error = nil;
    NSDictionary* customAttribs = 
      [[internal_ delegate] attributesOfFileSystemForPath:path error:error];    
    if (!customAttribs) {
      if (!(*error)) {
        *error = [GMUserFileSystem errorWithCode:ENODEV];
      }
      return nil;
    }
    [attributes addEntriesFromDictionary:customAttribs];
  }
  return attributes;
}

- (BOOL)setAttributes:(NSDictionary *)attributes
   ofFileSystemAtPath:(NSString *)path
                error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, attributes=%@", path, attributes];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(setAttributes:ofFileSystemAtPath:error:)]) {
    return [[internal_ delegate] setAttributes:attributes ofFileSystemAtPath:path error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOSYS];
  return NO;
}

- (BOOL)supportsAttributesOfItemAtPath {
  id delegate = [internal_ delegate];
  return [delegate respondsToSelector:@selector(attributesOfItemAtPath:userData:error:)];
}

- (NSDictionary *)attributesOfItemAtPath:(NSString *)path
                                userData:userData
                                   error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo =
      [NSString stringWithFormat:@"%@, userData=%p", path, userData];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  id delegate = [internal_ delegate];
  if ([delegate respondsToSelector:@selector(attributesOfItemAtPath:userData:error:)]) {
    return [delegate attributesOfItemAtPath:path userData:userData error:error];
  }
  return nil;
}

// Get attributesOfItemAtPath from the delegate with default values.
- (NSDictionary *)defaultAttributesOfItemAtPath:(NSString *)path 
                                       userData:userData
                                          error:(NSError **)error {
  // Set up default item attributes.
  NSMutableDictionary* attributes = [NSMutableDictionary dictionary];
  BOOL isReadOnly = [internal_ isReadOnly];
  [attributes setObject:[NSNumber numberWithLong:(isReadOnly ? 0555 : 0775)]
                 forKey:NSFilePosixPermissions];
  [attributes setObject:[NSNumber numberWithLong:1]
                 forKey:NSFileReferenceCount];    // 1 means "don't know"
  if ([path isEqualToString:@"/"]) {
    [attributes setObject:NSFileTypeDirectory forKey:NSFileType];
  } else {
    [attributes setObject:NSFileTypeRegular forKey:NSFileType];
  }
  
  id delegate = [internal_ delegate];
  BOOL isDirectoryIcon = NO;

  // The delegate can override any of the above defaults by implementing the
  // attributesOfItemAtPath: selector and returning a custom dictionary.
  NSDictionary* customAttribs = nil;
  BOOL supportsAttributesSelector = [self supportsAttributesOfItemAtPath];
  if (supportsAttributesSelector) {
    customAttribs = [self attributesOfItemAtPath:path 
                                        userData:userData
                                           error:error];
  }
  
  // Maybe this is the root directory?  If so, we'll claim it always exists.
  if (!customAttribs && [path isEqualToString:@"/"]) {
    return attributes;  // The root directory always exists.
  }
  
  // Maybe check to see if this is a special file that we should handle. If they
  // wanted to handle it, then they would have given us back customAttribs.
  if (!customAttribs && [internal_ shouldCheckForResource]) {
    // If the maybe-fixed-up path is a directoryIcon, we'll modify the path to
    // refer to the parent directory and note that we are a directory icon.
    isDirectoryIcon = [self isDirectoryIconAtPath:path dirPath:&path];
    
    // Maybe we'll try again to get custom attribs on the real path.
    if (supportsAttributesSelector && isDirectoryIcon) {
      customAttribs = [self attributesOfItemAtPath:path 
                                          userData:userData
                                             error:error];
    }
  }
  
  if (customAttribs) {
    [attributes addEntriesFromDictionary:customAttribs];
  } else if (supportsAttributesSelector) {
    // They explicitly support attributesOfItemAtPath: and returned nil.
    if (!(*error)) {
      *error = [GMUserFileSystem errorWithCode:ENOENT];
    }
    return nil;
  }
  
  // If this is a directory Icon\r then it is an empty file and we're done.
  if (isDirectoryIcon) {
    if ([self hasCustomIconAtPath:path]) {
      [attributes setObject:NSFileTypeRegular forKey:NSFileType];
      [attributes setObject:[NSNumber numberWithLongLong:0] forKey:NSFileSize];
      return attributes;
    }
    *error = [GMUserFileSystem errorWithCode:ENOENT];
    return nil;
  }
  
  // If they don't supply a size and it is a file then we try to compute it.
  if (![attributes objectForKey:NSFileSize] &&
      ![[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory] &&
      [delegate respondsToSelector:@selector(contentsAtPath:)]) {
    NSData* data = [self contentsAtPath:path];
    if (data == nil) {
      *error = [GMUserFileSystem errorWithCode:ENOENT];
      return nil;
    }
    [attributes setObject:[NSNumber numberWithLongLong:[data length]]
                   forKey:NSFileSize];
  }
  
  return attributes;
}

- (NSDictionary *)extendedTimesOfItemAtPath:(NSString *)path
                                   userData:(id)userData
                                      error:(NSError **)error {
  if (![self supportsAttributesOfItemAtPath]) {
    *error = [GMUserFileSystem errorWithCode:ENOSYS];
    return nil;
  }
  return [self attributesOfItemAtPath:path 
                             userData:userData
                                error:error];
}

- (BOOL)setAttributes:(NSDictionary *)attributes 
         ofItemAtPath:(NSString *)path
             userData:(id)userData
                error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, userData=%p, attributes=%@", 
       path, userData, attributes];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  if ([attributes objectForKey:NSFileSize] != nil) {
    BOOL handled = NO;  // Did they have a delegate method that handles truncation?    
    NSNumber* offsetNumber = [attributes objectForKey:NSFileSize];
    fuse_off_t offset = [offsetNumber longLongValue];
    BOOL ret = [self truncateFileAtPath:path 
                               userData:userData
                                 offset:offset 
                                  error:error 
                                handled:&handled];
    if (handled && (!ret || [attributes count] == 1)) {
      // Either the truncate call failed, or we only had NSFileSize, so we are done.
      return ret;
    }
  }
  
  if ([[internal_ delegate] respondsToSelector:@selector(setAttributes:ofItemAtPath:userData:error:)]) {
    return [[internal_ delegate] setAttributes:attributes ofItemAtPath:path userData:userData error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENODEV];
  return NO;
}

#pragma mark Extended Attributes

/* Note: Linux listxattr(2) limits the size of the extended attribute name list to 64KB (XATTR_LIST_MAX). https://man7.org/linux/man-pages/man7/xattr.7.html */

- (NSArray *)extendedAttributesOfItemAtPath:path error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(path));
  }
#endif	/* defined (__APPLE__) */

  if ([[internal_ delegate] respondsToSelector:@selector(extendedAttributesOfItemAtPath:error:)]) {
    return [[internal_ delegate] extendedAttributesOfItemAtPath:path error:error];
  }
  *error = [GMUserFileSystem errorWithCode:ENOTSUP];
  return nil;
}

- (NSData *)valueOfExtendedAttribute:(NSString *)name 
                        ofItemAtPath:(NSString *)path
                            position:(fuse_off_t)position
                               error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, name=%@, position=%lld", path, name, position];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  id delegate = [internal_ delegate];
  NSData* data = nil;
  BOOL xattrSupported = NO;
  if ([delegate respondsToSelector:@selector(valueOfExtendedAttribute:ofItemAtPath:position:error:)]) {
    xattrSupported = YES;
    data = [delegate valueOfExtendedAttribute:name 
                                 ofItemAtPath:path 
                                     position:position 
                                        error:error];
  }

  if (!data && [internal_ shouldCheckForResource]) {
    if ([name isEqualToString:@"com.apple.FinderInfo"]) {
      NSDictionary* finderAttributes = [self finderAttributesAtPath:path];
      data = [self finderDataForAttributes:finderAttributes];
    } else if ([name isEqualToString:@"com.apple.ResourceFork"]) {
      [self isDirectoryIconAtPath:path dirPath:&path];  // Maybe update path.
      NSDictionary* attributes = [self resourceAttributesAtPath:path];
      data = [self resourceDataForAttributes:attributes];
    }
    if (data != nil && position > 0) {
      // We have all the data, but they are only requesting a subrange.
      size_t length = [data length];
      if (position > (fuse_off_t) length) {
        *error = [GMUserFileSystem errorWithCode:ERANGE];
        return nil;
      }
      data = [data subdataWithRange:NSMakeRange(position, length - position)];
    }
  }
  if (data == nil && *error == nil) {
    *error = [GMUserFileSystem errorWithCode:xattrSupported ? ENOATTR : ENOTSUP];
  }
  return data;
}

- (BOOL)setExtendedAttribute:(NSString *)name 
                ofItemAtPath:(NSString *)path 
                       value:(NSData *)value
                    position:(fuse_off_t)position
                     options:(int)options
                       error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, name=%@, position=%lld, options=0x%x", 
       path, name, position, options];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }
#endif	/* defined (__APPLE__) */

  id delegate = [internal_ delegate];
  if ([delegate respondsToSelector:@selector(setExtendedAttribute:ofItemAtPath:value:position:options:error:)]) {
    return [delegate setExtendedAttribute:name 
                             ofItemAtPath:path 
                                    value:value
                                 position:position
                                  options:options
                                    error:error]; 
  }
  *error = [GMUserFileSystem errorWithCode:ENOTSUP];
  return NO;
}

- (BOOL)removeExtendedAttribute:(NSString *)name
                   ofItemAtPath:(NSString *)path
                          error:(NSError **)error {
#if defined (__APPLE__)
  if (OSXFUSE_OBJC_DELEGATE_ENTRY_ENABLED()) {
    NSString* traceinfo = 
      [NSString stringWithFormat:@"%@, name=%@", path, name];
    OSXFUSE_OBJC_DELEGATE_ENTRY(DTRACE_STRING(traceinfo));
  }  
#endif	/* defined (__APPLE__) */

  id delegate = [internal_ delegate];
  if ([delegate respondsToSelector:@selector(removeExtendedAttribute:ofItemAtPath:error:)]) {
    return [delegate removeExtendedAttribute:name 
                                ofItemAtPath:path 
                                       error:error];
  }  
  *error = [GMUserFileSystem errorWithCode:ENOTSUP];
  return NO;  
}

#pragma mark FUSE Operations

#define SET_CAPABILITY(conn, flag, enable)                                \
  do {                                                                    \
    if (enable) {                                                         \
      (conn)->want |= (flag);                                             \
    } else {                                                              \
      (conn)->want &= ~(flag);                                            \
    }                                                                     \
  } while (0)

#define MAYBE_USE_ERROR(var, error)                                       \
  if ((error) != nil &&                                                   \
      [[(error) domain] isEqualToString:NSPOSIXErrorDomain]) {            \
    int code = [(error) code];                                            \
    if (code != 0) {                                                      \
      (var) = -code;                                                      \
    }                                                                     \
  }

static void* fusefm_init(struct fuse_conn_info* conn) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  GMUserFileSystem* fs = [GMUserFileSystem currentFS];
  [fs retain];
  @try {
    [fs fuseInit];
  }
  @catch (id exception) { }

#if defined (__APPLE__)
  SET_CAPABILITY(conn, FUSE_CAP_ALLOCATE, [fs enableAllocate]);
  SET_CAPABILITY(conn, FUSE_CAP_XTIMES, [fs enableExtendedTimes]);
  SET_CAPABILITY(conn, FUSE_CAP_VOL_RENAME, [fs enableSetVolumeName]);
  SET_CAPABILITY(conn, FUSE_CAP_CASE_INSENSITIVE, ![fs enableCaseSensitiveNames]);
  SET_CAPABILITY(conn, FUSE_CAP_EXCHANGE_DATA, [fs enableExchangeData]);
#else
   (void) conn;										/* Avoid unused argument compiler warning */
#endif	/* defined (__APPLE__) */

	/* CJEC, 9-Jul-19: Enable atomic O_TRUNC support in open().
  
    	Note: Currently (OSXFUSE 3.8.3) this is not needed as -[BoxAFSFuseFD truncateToOffset: error:]
      			provides an alternative when mounted with the "nosyncwrites" mount option. Unfortunately,
            on Linux, this results in an intermediate 0 byte version being created, which is very
            undesirable.
   
     CJEC, 12-Oct-20: TODO: Optimise. Do we need this capability for fuse on macOS, FreeBSD, etc. to
     													avoid the double version problem?
                              Also, what about the other generic capabilities? FUSE_CAP_BIG_WRITES in
                              particular looks desirable on all platforms, and FUSE_CAP_SPLICE_WRITE &
                              FUSE_CAP_SPLICE_READ look useful on Linux. (splice(2) is Linux-specific.)
   														FUSE_CAP_BIG_WRITES is ignored in OS X/Darwin and is not referenced in the
                              OSXFUSE kernel extension so has been disabled for OS X/Darwin.
                              FUSE_CAP_SPLICE_WRITE seems to make a difference for the ROS project I/O
                              pattern, (which creates/truncates many small files,) but needs more
                              investigation.
  */

  SET_CAPABILITY(conn, FUSE_CAP_ATOMIC_O_TRUNC, true);
  NSLog (@"Fuse: INFORMATION: Enabled FUSE_CAP_ATOMIC_O_TRUNC");

#if !defined (__APPLE__)
  SET_CAPABILITY(conn, FUSE_CAP_BIG_WRITES, true);
  NSLog (@"Fuse: INFORMATION: Enabled FUSE_CAP_BIG_WRITES");
#endif	/* !defined (__APPLE__) */

#if defined (__linux__)
// 	SET_CAPABILITY(conn, FUSE_CAP_SPLICE_READ, true);
// 	NSLog (@"Fuse: INFORMATION: Enabled FUSE_CAP_SPLICE_READ");
	SET_CAPABILITY(conn, FUSE_CAP_SPLICE_WRITE, true);
	NSLog (@"Fuse: INFORMATION: Enabled FUSE_CAP_SPLICE_WRITE");
#endif	/* defined (__linux__) */

  [pool release];
  return fs;
}

static void fusefm_destroy(void* private_data) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  GMUserFileSystem* fs = (GMUserFileSystem *)private_data;
  @try {
    [fs fuseDestroy];
  }
  @catch (id exception) { }
  [fs release];
  [pool release];
}

static int fusefm_mkdir(const char* path, mode_t mode) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError* error = nil;
    unsigned long perm = mode & ALLPERMS;
    NSDictionary* attribs = 
      [NSDictionary dictionaryWithObject:[NSNumber numberWithLong:perm]
                                  forKey:NSFilePosixPermissions];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs createDirectoryAtPath:[NSString stringWithUTF8String:path] 
                       attributes:attribs
                            error:&error]) {
      ret = 0;  // Success!
    } else {
      if (error != nil) {
        ret = -[error code];
      }
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_create(const char* path, mode_t mode, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError* error = nil;
    id userData = nil;
    unsigned long perms = mode & ALLPERMS;
    NSDictionary* attribs =
      [NSDictionary dictionaryWithObject:[NSNumber numberWithUnsignedLong:perms]
                                  forKey:NSFilePosixPermissions];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs createFileAtPath:[NSString stringWithUTF8String:path]
                  attributes:attribs
                       flags:fi->flags
                    userData:&userData
                       error:&error]) {
      ret = 0;
      if (userData != nil) {
        [userData retain];
        fi->fh = (uintptr_t)userData;
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_rmdir(const char* path) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs removeDirectoryAtPath:[NSString stringWithUTF8String:path] 
                            error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_unlink(const char* path) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs removeItemAtPath:[NSString stringWithUTF8String:path] 
                       error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

/* Note: renameat2(2) support was added to Linux in the Fuse 3.0 API specification
					and renamex_np(2) support was added to OS X/Darwin in macFUSE 4.0.0
*/
static int fusefm_rename(const char* path, const char* toPath) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;

  @try {
    NSString* source = [NSString stringWithUTF8String:path];
    NSString* destination = [NSString stringWithUTF8String:toPath];
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs moveItemAtPath:source toPath:destination error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;  
}

static int fusefm_link(const char* path1, const char* path2) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs linkItemAtPath:[NSString stringWithUTF8String:path1]
                    toPath:[NSString stringWithUTF8String:path2]
                     error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_symlink(const char* path1, const char* path2) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EACCES;
  
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs createSymbolicLinkAtPath:[NSString stringWithUTF8String:path2]
                 withDestinationPath:[NSString stringWithUTF8String:path1]
                       error:&error]) {
      ret = 0;  // Success!
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_readlink(const char *path, char *buf, size_t size)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSString* linkPath = [NSString stringWithUTF8String:path];
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    NSString *pathContent = [fs destinationOfSymbolicLinkAtPath:linkPath
                                                          error:&error];
    if (pathContent != nil) {
      ret = 0;
      [pathContent getFileSystemRepresentation:buf maxLength:size];
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                          fuse_off_t offset, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  (void) offset;									/* Avoid unused argument compiler warning */
  (void) fi;											/* Avoid unused argument compiler warning */
  
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    NSArray *contents = 
    [fs contentsOfDirectoryAtPath:[NSString stringWithUTF8String:path] 
                            error:&error];
    if (contents) {
      ret = 0;
      filler(buf, ".", NULL, 0);
      filler(buf, "..", NULL, 0);
      for (int i = 0, count = [contents count]; i < count; i++) {
        filler(buf, [[contents objectAtIndex:i] UTF8String], NULL, 0);
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_open(const char *path, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;  // TODO: Default to 0 (success) since a file-system does
                      // not necessarily need to implement open?

  @try {
    id userData = nil;
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs openFileAtPath:[NSString stringWithUTF8String:path]
                      mode:fi->flags
                  userData:&userData
                     error:&error]) {
      ret = 0;
      if (userData != nil) {
        [userData retain];
        fi->fh = (uintptr_t)userData;
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_release(const char *path, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  @try {
    id userData = (id)(uintptr_t)fi->fh;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    [fs releaseFileAtPath:[NSString stringWithUTF8String:path] userData:userData];
    if (userData) {
      [userData release]; 
    }
  }
  @catch (id exception) { }
  [pool release];
  return 0;
}

static int fusefm_read(const char *path, char *buf, size_t size, fuse_off_t offset,
                       struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EIO;

  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    ret = [fs readFileAtPath:[NSString stringWithUTF8String:path]
                    userData:(id)(uintptr_t)fi->fh
                      buffer:buf
                        size:size
                      offset:offset
                       error:&error];
    MAYBE_USE_ERROR(ret, error);
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_write(const char* path, const char* buf, size_t size, 
                        fuse_off_t offset, struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EIO;
  
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    ret = [fs writeFileAtPath:[NSString stringWithUTF8String:path]
                     userData:(id)(uintptr_t)fi->fh
                       buffer:buf
                         size:size
                       offset:offset
                        error:&error];
    MAYBE_USE_ERROR(ret, error);
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_fsync(const char* path, int isdatasync,
                        struct fuse_file_info* fi) {
  // TODO: Support fsync?
  
  (void) path;													/* Avoid unused argument compiler warning */
  (void) isdatasync;										/* Avoid unused argument compiler warning */
  (void) fi;														/* Avoid unused argument compiler warning */
  
  return 0;
}

static int fusefm_fallocate(const char* path, int mode, fuse_off_t offset, fuse_off_t length,
                            struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOSYS;
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs allocateFileAtPath:[NSString stringWithUTF8String:path]
                      userData:(fi ? (id)(uintptr_t)fi->fh : nil)
                       options:mode
                        offset:offset
                        length:length
                         error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

#if defined (__APPLE__)
static int fusefm_exchange(const char* p1, const char* p2, unsigned long opts) {

	(void) opts;												/* Avoid unused argument compiler warning */

  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOSYS;
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs exchangeDataOfItemAtPath:[NSString stringWithUTF8String:p1]
                      withItemAtPath:[NSString stringWithUTF8String:p2]
                               error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;  
}

static int fusefm_statfs_x(const char* path, struct statfs* stbuf) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(stbuf, 0, sizeof(struct statfs));
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs fillStatfsBuffer:stbuf
                     forPath:[NSString stringWithUTF8String:path]
                       error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_setvolname(const char* name) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOSYS;
  @try {
    NSError* error = nil;
    NSDictionary* attribs = 
      [NSDictionary dictionaryWithObject:[NSString stringWithUTF8String:name]
                                  forKey:kGMUserFileSystemVolumeNameKey];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs setAttributes:attribs ofFileSystemAtPath:@"/" error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}
#endif	/* defined (__APPLE__) */

/* Theis method is not used by Fuse on OS X/Darwin because
		fusefm_statfs_x() is a better alternative
		and is used instead.
*/
#if !defined (__APPLE__)
static int	fusefm_statfs (const char * a_pszPath, struct statvfs * a_pStatVFS)
	{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(a_pStatVFS, 0, sizeof(struct statvfs));
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs fillStatvfsBuffer:a_pStatVFS
                     forPath:[NSString stringWithUTF8String:a_pszPath]
                       error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
  }
#endif	/* !defined (__APPLE__) */

static int fusefm_fgetattr(const char *path, struct stat *stbuf, 
                           struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;
  @try {
    memset(stbuf, 0, sizeof(struct stat));
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    id userData = fi ? (id)(uintptr_t)fi->fh : nil;
    if ([fs fillStatBuffer:stbuf 
                   forPath:[NSString stringWithUTF8String:path]
                  userData:userData
                     error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_getattr(const char *path, struct stat *stbuf) {
  return fusefm_fgetattr(path, stbuf, NULL);
}

#if defined (__APPLE__)
/* CJEC, 14-Oct-20: TODO: Investigate something similar to this for Linux & FreeBSD in newer Fuse APIs.
														Linux has statx(2) which provides more information, like getattrlist(2) on
                            OS X/Darwin
*/
static int fusefm_getxtimes(const char* path, struct timespec* bkuptime, 
                            struct timespec* crtime) {  
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOENT;

  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    NSDictionary* attribs = 
      [fs extendedTimesOfItemAtPath:[NSString stringWithUTF8String:path]
                           userData:nil  // TODO: Maybe this should support FH?
                              error:&error];
    if (attribs) {
      ret = 0;
      NSDate* creationDate = [attribs objectForKey:NSFileCreationDate];
      if (creationDate) {
        const double seconds_dp = [creationDate timeIntervalSince1970];
        const time_t t_sec = (time_t) seconds_dp;
        const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond); 
        const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
        crtime->tv_sec = t_sec;
        crtime->tv_nsec = t_nsec;          
      } else {
        memset(crtime, 0, sizeof(struct timespec));
      }
      NSDate* backupDate = [attribs objectForKey:kGMUserFileSystemFileBackupDateKey];
      if (backupDate) {
        const double seconds_dp = [backupDate timeIntervalSince1970];
        const time_t t_sec = (time_t) seconds_dp;
        const double nanoseconds_dp = ((seconds_dp - t_sec) * kNanoSecondsPerSecond); 
        const long t_nsec = (nanoseconds_dp > 0 ) ? nanoseconds_dp : 0;
        bkuptime->tv_sec = t_sec;
        bkuptime->tv_nsec = t_nsec;
      } else {
        memset(bkuptime, 0, sizeof(struct timespec));
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}
#endif	/* defined (__APPLE__) */

static NSDate* dateWithTimespec(const struct timespec* spec) {
  const NSTimeInterval time_ns = spec->tv_nsec;
  const NSTimeInterval time_sec = spec->tv_sec + (time_ns / kNanoSecondsPerSecond);
  return [NSDate dateWithTimeIntervalSince1970:time_sec];
}

#if defined (__APPLE__)
static NSDictionary* dictionaryWithAttributes(const struct setattr_x* attrs) {
  NSMutableDictionary* dict = [NSMutableDictionary dictionary];
  if (SETATTR_WANTS_MODE(attrs)) {
    unsigned long perm = attrs->mode & ALLPERMS;
    [dict setObject:[NSNumber numberWithLong:perm] 
             forKey:NSFilePosixPermissions];    
  }
  if (SETATTR_WANTS_UID(attrs)) {
    [dict setObject:[NSNumber numberWithLong:attrs->uid] 
             forKey:NSFileOwnerAccountID];
  }
  if (SETATTR_WANTS_GID(attrs)) {
    [dict setObject:[NSNumber numberWithLong:attrs->gid] 
             forKey:NSFileGroupOwnerAccountID];
  }
  if (SETATTR_WANTS_SIZE(attrs)) {
    [dict setObject:[NSNumber numberWithLongLong:attrs->size]
             forKey:NSFileSize];
  }
  if (SETATTR_WANTS_ACCTIME(attrs)) {
    [dict setObject:dateWithTimespec(&(attrs->acctime))
             forKey:kGMUserFileSystemFileAccessDateKey];
  }
  if (SETATTR_WANTS_MODTIME(attrs)) {
    [dict setObject:dateWithTimespec(&(attrs->modtime))
             forKey:NSFileModificationDate];
  }
  if (SETATTR_WANTS_CRTIME(attrs)) {
    [dict setObject:dateWithTimespec(&(attrs->crtime))
             forKey:NSFileCreationDate];
  }
  if (SETATTR_WANTS_CHGTIME(attrs)) {
    [dict setObject:dateWithTimespec(&(attrs->chgtime))
             forKey:kGMUserFileSystemFileChangeDateKey];
  }
  if (SETATTR_WANTS_BKUPTIME(attrs)) {
    [dict setObject:dateWithTimespec(&(attrs->bkuptime))
             forKey:kGMUserFileSystemFileBackupDateKey];
  }
  if (SETATTR_WANTS_FLAGS(attrs)) {
    [dict setObject:[NSNumber numberWithLong:attrs->flags]
             forKey:kGMUserFileSystemFileFlagsKey];
  }
  return dict;
}

static int fusefm_fsetattr_x(const char* path, struct setattr_x* attrs,
                             struct fuse_file_info* fi) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // Note: Return success by default.

  @try {
    NSError* error = nil;
    NSDictionary* attribs = dictionaryWithAttributes(attrs);
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs setAttributes:attribs 
             ofItemAtPath:[NSString stringWithUTF8String:path]
                 userData:(fi ? (id)(uintptr_t)fi->fh : nil)
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_setattr_x(const char* path, struct setattr_x* attrs) {
  return fusefm_fsetattr_x(path, attrs, nil);
}
#endif	/* defined (__APPLE__) */

/* These methods are not used by Fuse on OS X/Darwin because
		fusefm_setattr_x() and fusefm_fsetattr_x() are better alternatives
		and are used instead.
    
    Note: It appears that btime and ctime cannot be set on Linux or FreeBSD.

    CJEC, 14-Oct-20: TODO: FreeBSD: What about chflags(2)? See https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=238197
*/
#if !defined (__APPLE__)
static int	fusefm_utimens (const char * a_pszPath, const struct timespec a_TimeSpecs [2])
	{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // Note: Return success by default.

  @try {
    NSError* error = nil;
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];

    [attribs setObject:dateWithTimespec(&(a_TimeSpecs [0])) forKey:kGMUserFileSystemFileAccessDateKey];
    [attribs setObject:dateWithTimespec(&(a_TimeSpecs [1])) forKey:NSFileModificationDate];
    if ([fs setAttributes:attribs
             ofItemAtPath:[NSString stringWithUTF8String:a_pszPath]
                 userData:nil
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
  }

static int	fusefm_chmod (const char * a_pszPath, mode_t a_Mode)
	{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // Note: Return success by default.

  @try {
    NSError* error = nil;
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];

    [attribs setObject: [NSNumber numberWithLong: (long) a_Mode] forKey: NSFilePosixPermissions];
    if ([fs setAttributes:attribs
             ofItemAtPath:[NSString stringWithUTF8String:a_pszPath]
                 userData:nil
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
  }

static int	fusefm_chown (const char * a_pszPath, uid_t a_UID, gid_t a_GID)
	{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // Note: Return success by default.

  @try {
    NSError* error = nil;
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];

    [attribs setObject: [NSNumber numberWithLong: (long) a_UID] forKey: NSFileOwnerAccountID];
    [attribs setObject: [NSNumber numberWithLong: (long) a_GID] forKey: NSFileGroupOwnerAccountID];
    if ([fs setAttributes:attribs
             ofItemAtPath:[NSString stringWithUTF8String:a_pszPath]
                 userData:nil
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
  }

static int	fusefm_ftruncate (const char * a_pszPath, fuse_off_t a_cbSize, struct fuse_file_info * a_pFuseFileInfo)
	{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = 0;  // Note: Return success by default.

  @try {
    NSError* error = nil;
    NSMutableDictionary* attribs = [NSMutableDictionary dictionary];
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];

    [attribs setObject: [NSNumber numberWithLongLong: a_cbSize] forKey: NSFileSize];
    if ([fs setAttributes:attribs
             ofItemAtPath:[NSString stringWithUTF8String:a_pszPath]
                 userData:(a_pFuseFileInfo ? (id)(uintptr_t)a_pFuseFileInfo->fh : nil)
                    error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
  }

static int	fusefm_truncate (const char * a_pszPath, fuse_off_t a_cbSize)
	{
  return fusefm_ftruncate (a_pszPath, a_cbSize, NULL);
  }

#endif	/* !defined (__APPLE__) */

static int fusefm_listxattr(const char *path, char *list, size_t size)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOTSUP;
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    NSArray* attributeNames =
      [fs extendedAttributesOfItemAtPath:[NSString stringWithUTF8String:path]
                                   error:&error];
    if (attributeNames != nil) {
      char zero = 0;
      NSMutableData* data = [NSMutableData dataWithCapacity:size];  
      for (int i = 0, count = [attributeNames count]; i < count; i++) {
        [data appendData:[[attributeNames objectAtIndex:i] dataUsingEncoding:NSUTF8StringEncoding]];
        [data appendBytes:&zero length:1];
      }
      ret = [data length];  // default to returning size of buffer.
      if (list) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:list length:size];
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

#if defined (__APPLE__)
static int fusefm_getxattr(const char *path, const char *name, char *value,
                           size_t size, uint32_t position) {
#else
static int fusefm_getxattr(const char *path, const char *name, char *value,
                           size_t size) {
  uint32_t	position = 0;				/* Only OS X/Darwin has this parameter */
#endif	/* defined (__APPLE__) */
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOATTR;
  
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    NSData *data = [fs valueOfExtendedAttribute:[NSString stringWithUTF8String:name]
                                   ofItemAtPath:[NSString stringWithUTF8String:path]
                                       position:position
                                          error:&error];
    if (data != nil) {
      ret = [data length];  // default to returning size of buffer.
      if (value) {
        if (size > [data length]) {
          size = [data length];
        }
        [data getBytes:value length:size];
        ret = size;  // bytes read
      }
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

#if defined (__APPLE__)
static int fusefm_setxattr(const char *path, const char *name, const char *value,
                           size_t size, int flags, uint32_t position) {
#else
static int fusefm_setxattr(const char *path, const char *name, const char *value,
                           size_t size, int flags) {
  uint32_t position	= 0;								/* Only OS X/Darwin has this parameter */
#endif	/* defined (__APPLE__) */
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -EPERM;
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs setExtendedAttribute:[NSString stringWithUTF8String:name]
                    ofItemAtPath:[NSString stringWithUTF8String:path]
                           value:[NSData dataWithBytes:value length:size]
                        position:position
                         options:flags
                           error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

static int fusefm_removexattr(const char *path, const char *name) {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
  int ret = -ENOATTR;
  @try {
    NSError* error = nil;
    GMUserFileSystem* fs = [GMUserFileSystem currentFS];
    if ([fs removeExtendedAttribute:[NSString stringWithUTF8String:name]
                    ofItemAtPath:[NSString stringWithUTF8String:path]
                           error:&error]) {
      ret = 0;
    } else {
      MAYBE_USE_ERROR(ret, error);
    }
  }
  @catch (id exception) { }
  [pool release];
  return ret;
}

#undef MAYBE_USE_ERROR

#pragma mark struct fuse_operations
static struct fuse_operations fusefm_oper = {
  .init = fusefm_init,
  .destroy = fusefm_destroy,
  
  // Creating an Item
  .mkdir = fusefm_mkdir,
  .create = fusefm_create,
  
  // Removing an Item
  .rmdir = fusefm_rmdir,
  .unlink = fusefm_unlink,
  
  // Moving an Item
  /* Note: renameat2(2) support was added to Linux in the Fuse 3.0 API specification,
  					and renamex_np(2) support was added to OS X/Darwin in macFUSE 4.0.0
  */
  .rename = fusefm_rename,
  
  // Linking an Item
  .link = fusefm_link,
  
  // Symbolic Links
  .symlink = fusefm_symlink,
  .readlink = fusefm_readlink,
  
  // Directory Contents
  .readdir = fusefm_readdir,
  
  // File Contents
  .open	= fusefm_open,
  .release = fusefm_release,
  .read	= fusefm_read,
  .write = fusefm_write,
  .fsync = fusefm_fsync,
  .fallocate = fusefm_fallocate,
#if defined (__APPLE__)
  .exchange = fusefm_exchange,
#endif	/* defined (__APPLE__) */

  // Getting and Setting Attributes
#if defined (__APPLE__)
  .statfs_x = fusefm_statfs_x,
  .setvolname = fusefm_setvolname,
#else
  .statfs = fusefm_statfs,
#endif	/* defined (__APPLE__) */
  .getattr = fusefm_getattr,
  .fgetattr = fusefm_fgetattr,
#if defined (__APPLE__)
  .getxtimes = fusefm_getxtimes,
  .setattr_x = fusefm_setattr_x,
  .fsetattr_x = fusefm_fsetattr_x,
#else
  /* Standard attribute methods. Not used on OS X/Darwin as it has its own alternatives */
  .utimens = fusefm_utimens,
  .chmod = fusefm_chmod,
  .chown = fusefm_chown,
  .truncate = fusefm_truncate,
  .ftruncate = fusefm_ftruncate,
  /* CJEC, 14-Oct-20: TODO: FreeBSD: What about chflags(2) ? See https://bugs.freebsd.org/bugzilla/show_bug.cgi?id=238197 */
#endif	/* defined (__APPLE__) */

  // Extended Attributes
  .listxattr = fusefm_listxattr,
  .getxattr = fusefm_getxattr,
  .setxattr = fusefm_setxattr,
  .removexattr = fusefm_removexattr,
  
  // Fuse operation flags. See declaration of struct fuse_operations in fuse.h
  .flag_reserved = 0,
  .flag_nullpath_ok = false,				/* CJEC, 16-Dec-20: TODO: Optimise by enabling this so the path doesn't need to be generated when the file has been deleted */
  .flag_nopath = false,							/* CJEC, 16-Dec-20: TODO: Optimise by enabling this so the path doesn't need to be generated */
  .flag_utime_omit_ok = false,			/* CJEC, 16-Dec-20: TODO: Support UTIME_NOW and UTIME_OMIT for utimesat(2) support on Linux, FreeBSD */
};

#pragma mark Internal Mount

- (void)postMountError:(NSError *)error {
  assert([internal_ status] == GMUserFileSystem_MOUNTING);
  [internal_ setStatus:GMUserFileSystem_FAILURE];

  NSDictionary* userInfo = 
    [NSDictionary dictionaryWithObjectsAndKeys:
     [internal_ mountPath], kGMUserFileSystemMountPathKey,
     error, kGMUserFileSystemErrorKey,
     nil];
  NSNotificationCenter* center = [NSNotificationCenter defaultCenter];
  [center postNotificationName:kGMUserFileSystemMountFailed object:self
                      userInfo:userInfo];
#if !defined (__APPLE__)
  NSLog (@"Fuse: ERROR: Mount FAILED. %@ %@ IN %@", error, userInfo, self);			/* Also log it, in case we're not using NSNotificationCenter (EG because we're not using NSApplication, which on GNUstep requires a GUI application) */
#endif	/* !defined (__APPLE__) */
}

- (void)mount:(NSDictionary *)args {
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  assert([internal_ status] == GMUserFileSystem_NOT_MOUNTED);
  [internal_ setStatus:GMUserFileSystem_MOUNTING];

  NSArray* options = [args objectForKey:@"options"];
  BOOL isThreadSafe = [internal_ isThreadSafe];
  BOOL shouldForeground = [[args objectForKey:@"shouldForeground"] boolValue];
	BOOL fNotMounted	= YES;
  int  iErrno;

  // Maybe there is a dead FUSE file system stuck on our mount point?
  struct statfs statfs_buf;
  memset(&statfs_buf, 0, sizeof(statfs_buf));
  int ret = statfs([[internal_ mountPath] UTF8String], &statfs_buf);
  if (ret == 0) {
#if defined (__APPLE__)
    if (statfs_buf.f_fssubtype == (uint32_t)(-1)) {
      // We use a special indicator value from FUSE in the f_fssubtype field to
      // indicate that the currently mounted filesystem is dead. It probably
      // crashed and was never unmounted.
      // This is a better check than relying on unmount(2) returning EINVAL, but
      // only applies to OSXFUSE file systems
      // https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/unmount.2.html
      ret = unmount([[internal_ mountPath] UTF8String], 0);
      iErrno = ret < 0 ? errno : 0;
      fNotMounted = iErrno == 0;
#else
#if defined (__FreeBSD__)
		/* CJEC, 18-Dec-20: TODO: Determine whether the mount point is a deadfs
    */
    NSLog (@"Fuse: WARNING: UNIMPLEMENTED: Determine deadfs at mountpoint. Attempting dismount anyway. Ignore possible subsequent error IN %@", self);
      {
//    ret = unmount([[internal_ mountPath] UTF8String], 0);	/* https://www.man7.org/linux/man-pages/man2/umount.2.html */
//    iErrno = ret < 0 ? errno : 0;
      NSArray* args = [NSArray arrayWithObjects:@"-v", [internal_ mountPath], nil];
      iErrno = Unmount (args);	/* Can't use unmount(2) without root priviledge */
      fNotMounted = (iErrno == 0) || (iErrno == EINVAL);	/* unmount(2) returns EINVAL if not in the mount table */
#else
#if defined (__linux__)
		/* CJEC, 18-Dec-20: TODO: Determine whether the mount point is a deadfs
    */
    NSLog (@"Fuse: WARNING: UNIMPLEMENTED: Determine deadfs at mountpoint. Attempting dismount anyway. Ignore possible subsequent error IN %@", self);
      {
//    ret = umount2([[internal_ mountPath] UTF8String], 0);	/* https://www.man7.org/linux/man-pages/man2/umount.2.html */
//    iErrno = ret < 0 ? errno : 0;
      NSArray* args = [NSArray arrayWithObjects:@"-v", [internal_ mountPath], nil];
      iErrno = Unmount (args);	/* Can't use unmount(2) without root priviledge */
      fNotMounted = (iErrno == 0) || (iErrno == EINVAL);	/* unmount2(2) returns EINVAL if not a mount point (among other reasons) */
#endif	/* defined (__linux__) */
#endif	/* defined (__FreeBSD__) */
#endif	/* defined (__APPLE__) */

      if (iErrno != 0) {
        NSString* description = [NSString stringWithFormat: @"Unable to dismount an existing 'dead?' file system at '%@'. errno %i, %s", [internal_ mountPath], iErrno, strerror (iErrno)];
        NSDictionary* userInfo =
          [NSDictionary dictionaryWithObjectsAndKeys:
           description, NSLocalizedDescriptionKey,
           [GMUserFileSystem errorWithCode:iErrno], NSUnderlyingErrorKey,
           nil];
        NSError* error = [NSError errorWithDomain:kGMUserFileSystemErrorDomain
                                             code:GMUserFileSystem_ERROR_UNMOUNT_DEADFS
                                         userInfo:userInfo];
        if (fNotMounted)
          NSLog (@"Fuse: WARNING: %@", description);
        else
          {
          [self postMountError:error];
          [pool release];
          return;
          }
      }
#if defined (__APPLE__)
      if ([[internal_ mountPath] hasPrefix:@"/Volumes/"]) {
        // OS X/Darwin only:
        // Directories for mounts in @"/Volumes/..." are removed automatically
        // when an unmount occurs. This is an asynchronous process, so we need
        // to wait until the directory is removed before proceeding. Otherwise,
        // it may be removed after we try to create the mount directory and the
        // mount attempt will fail.
        BOOL isDirectoryRemoved = NO;
        static const int kWaitForDeadFSTimeoutSeconds = 5;
        struct stat stat_buf;
        for (int i = 0; i < 2 * kWaitForDeadFSTimeoutSeconds; ++i) {
          usleep(500000);  // .5 seconds
          ret = stat([[internal_ mountPath] UTF8String], &stat_buf);
          if (ret != 0 && errno == ENOENT) {
            isDirectoryRemoved = YES;
            break;
          }
        }
        if (!isDirectoryRemoved) {
          NSString* description = 
            @"Gave up waiting for directory under /Volumes to be removed after "
             "cleaning up a dead file system mount.";
          NSDictionary* userInfo =
            [NSDictionary dictionaryWithObjectsAndKeys:
             description, NSLocalizedDescriptionKey,
             nil];
          NSError* error = [NSError errorWithDomain:kGMUserFileSystemErrorDomain
                                               code:GMUserFileSystem_ERROR_UNMOUNT_DEADFS_RMDIR
                                           userInfo:userInfo];
          [self postMountError:error];
          [pool release];
          return;
        }
      }
#endif	/* defined (__APPLE__) */
    }
  }

  // Check mount path as necessary.
  struct stat stat_buf;
  memset(&stat_buf, 0, sizeof(stat_buf));
  ret = stat([[internal_ mountPath] UTF8String], &stat_buf);
  if ((ret == 0 && !S_ISDIR(stat_buf.st_mode)) ||
      (ret != 0 && errno == ENOTDIR)) {
    [self postMountError:[GMUserFileSystem errorWithCode:ENOTDIR]];
    [pool release];
    return;
  }

  // Trigger initialization of NSFileManager. This is rather lame, but if we
  // don't call directoryContents before we mount our FUSE filesystem and 
  // the filesystem uses NSFileManager we may deadlock. It seems that the
  // NSFileManager class will do lazy init and will query all mounted
  // filesystems. This leads to deadlock when we re-enter our mounted FUSE file
  // system. Once initialized it seems to work fine.
  NSFileManager* fileManager = [[NSFileManager alloc] init];
  [fileManager contentsOfDirectoryAtPath:@"/Volumes" error:NULL];
  [fileManager release];

  NSMutableArray* arguments = 
    [NSMutableArray arrayWithObject:[[NSBundle mainBundle] executablePath]];
  if (!isThreadSafe) {
    [arguments addObject:@"-s"];  // Force single-threaded mode.
  }
  if (shouldForeground) {
    [arguments addObject:@"-f"];  // Forground rather than daemonize.
  }
  for (NSUInteger i = 0; i < [options count]; ++i) {
    NSString* option = [options objectAtIndex:i];
    if ([option length] > 0) {
      [arguments addObject:[NSString stringWithFormat:@"-o%@",option]];
    }
  }
  [arguments addObject:[internal_ mountPath]];
  [args release];  // We don't need packaged up args any more.

  // Start Fuse Main
  int argc = [arguments count];
  const char* argv[argc];
  for (int i = 0, count = [arguments count]; i < count; i++) {
    NSString* argument = [arguments objectAtIndex:i];
    argv[i] = strdup([argument UTF8String]);  // We'll just leak this for now.
  }
  if ([[internal_ delegate] respondsToSelector:@selector(willMount)]) {
    [[internal_ delegate] willMount];
  }
  [pool release];
  NSLog(@"Starting fuse_main");
  ret = fuse_main(argc, (char **)argv, &fusefm_oper, self);
  NSLog(@"Ending fuse_main");

  pool = [[NSAutoreleasePool alloc] init];

  if ([internal_ status] == GMUserFileSystem_MOUNTING) {
    // If we returned from fuse_main while we still think we are 
    // mounting then an error must have occurred during mount.
    NSString* description = [NSString stringWithFormat:@
      "Internal FUSE error (rc=%d) while attempting to mount the file system. "
      "For now, the best way to diagnose is to look for error messages using "
      "Console.", ret];
    NSDictionary* userInfo =
    [NSDictionary dictionaryWithObjectsAndKeys:
     description, NSLocalizedDescriptionKey,
     nil];
    NSError* error = [NSError errorWithDomain:kGMUserFileSystemErrorDomain
                                         code:GMUserFileSystem_ERROR_MOUNT_FUSE_MAIN_INTERNAL
                                     userInfo:userInfo];
    [self postMountError:error];
  } else {
    [internal_ setStatus:GMUserFileSystem_NOT_MOUNTED];
  }

  [pool release];
}

@end
