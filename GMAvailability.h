//
//  GMAvailability.h
//  OSXFUSE
//

//  Copyright (c) 2016-2017 Benjamin Fleischer.
//  All rights reserved.

/* Before including anything, set essential platform option compiler switches */
#if defined (_WIN32)
#if defined (__MINGW32__)						/* When using MinGW32 or MinGW-w64 */
#define __USE_MINGW_ANSI_STDIO		1			/* Use MinGW-w64 stdio for proper C99 support, such as %llu, _vswprintf(). See https://sourceforge.net/p/mingw-w64/wiki2/printf%20and%20scanf%20family/ */
#include <_mingw.h>
#if defined (__MINGW64__)
#include <sdkddkver.h>							/* Use MSys2/MinGW-w64 standard version header for 64-bit and 32-bit Windows */
#include <w32api.h>								/* Use the system header provided with Msys2/MinGW-w64 */
#define Windows2008					0x0600		/* Missing from w32api.h. Values identified in /mingw64/x86_64-w64-mingw32/include/sdkkddkver.h so these can also be used to define _WIN32_WINNT */
#define Windows7					0x0601
#define Windows8					0x0602
#define WindowsBlue					0x0603
#define Windows10					0x0A00
#else											/* Otherwise buiding with MinGW32 for 32-bit Windows */
#include <w32api.h>								/* Use the system header provided with Msys/MinGW32 */
#endif	/* defined (__MINGW64__) */
#else											/* Otherwise building with Microsoft Visual C/C++ */
#error "Windows: Not building with MinGW32 nor MinGW-w64? Needs porting"
#endif	/* defined (__MINGW32__) */
#if !defined (_WIN32_WINNT)
#warning "Windows: _WIN32_WINNT is not defined. Normally defined in GNUMakefile or make command line. EG make CPPFLAGS='-D_WIN32_WINNT=WindowsXP'"
#else
#if (_WIN32_WINNT >= WindowsVista) && !defined (__MINGW64_VERSION_MAJOR)
#define __MSVCRT_VERSION__ 			0x0700		/* Note: MinGW32: Allow use of later MSVCRT functions. Windows Vista seems to have v7.0 of MSVCRT.DLL. WindowsXP doesn't always have it. Baseline installation has only v4.0. Note: MinGW-w64 always sets this */
#endif	/* (_WIN32_WINNT >= WindowsVista) && !defined (__MINGW64_VERSION_MAJOR) */
#endif	/* !defined (_WIN32_WINNT) */
#include <ws2tcpip.h>							/* Need to include ws2tcpip.h before windows.h to avoid warning in ws2tcpip.h */
#include <windows.h>							/* Need to includes w32api.h and windows.h before Foundation.h to use WSAEVENT */
#endif	/* defined (_WIN32) */

#if defined (__APPLE__)
#define _DARWIN_USE_64_BIT_INODE	1			/* Note: Always use 64 bit ino_t inode definitions for things like struct stat */
#endif	/* defined (__APPLE__) */

#if defined (__linux__)
#define _GNU_SOURCE					1			/* Required for dladdr() and struct Dl_info on Linux */
#endif	/* defined (__linux__) */

/* Include the essential Objective C environment umbrella header file(s) */
#import <Foundation/Foundation.h>				/* See "Foundation Framework Reference" and "Foundation Reference Update" */

#include <sys/types.h>							/* For off_t */
#include <sys/time.h>							/* For struct timespec */

#if defined (_WIN32)

#if defined (__MINGW64__))
typedef off64_t						fuse_off_t;	/* off_t is 32 bits wide on Windows (32 and 64 bit). Always define fuse_off_t to be a 64 bit integer. MINGW64: off64_t is defined in _mingw_off_t.h */
#else
#error "Windows: Not MINGW64. Need to define fuse_off_t"
#endif	/* defined (__MINGW64__) */

typedef uint64_t					fuse_nlink_t;	/* Modern UNIX uses a 64 bit quantity for the number of hard links */
typedef uint32_t					fuse_uid_t;		/* Modern UNIX uses a 32 bit quantity for User IDs (UID) */
typedef uint32_t					fuse_gid_t;	/* Modern UNIX uses a 32 bit quantity for Group IDs (GID) */

struct fuse_stat64_ino64						/* Based on struct _stat64 in _mingw_stat64.h, this uses discrete types and ensures that the INodeID is 64 bits wide to match modern UNIX */
	{
	dev_t			st_dev;
	fuse_ino_t		st_ino;						/* Note: For non-UNIX file system, the INodeID is meaningless. See https://docs.microsoft.com/en-us/cpp/c-runtime-library/reference/stat-functions?view=msvc-170 */
	mode_t			st_mode;
	fuse_nlink_t	st_nlink;
	fuse_uid_t		st_uid;
	fuse_gid_t		st_gid;
	dev_t			st_rdev;
	fuse_off_t		st_size;
	struct timespec	st_atimespec;				/* Note: On Windows, the C Runtime's stat(3) function uses time_t. Use struct timespec for higher resolution timestamps */
	struct timespec	st_mtimespec;
	struct timespec	st_ctimespec;				/* Note: On Windows, the C Runtime's stat(3) function uses st_ctime for the creation time, rather than the inode change time */
	struct timespec	st_birthtimespec;			/* Note: For compatibility with UNIX, use st_birthtime for the Windows create time instead of st_ctime */
	};
#define fuse_stat					fuse_stat64_ino64

#else

typedef off_t						fuse_off_t;	/* off_t should always be defined to be 64 bits wide on UNIX */

#define fuse_stat					stat

#endif	/* defined (_WIN32) */

#define GM_OSXFUSE_2_0 020000
#define GM_OSXFUSE_3_0 030000
#define GM_OSXFUSE_3_5 030500
#define GM_OSXFUSE_3_8 030800

#ifdef GM_VERSION_MIN_REQUIRED

    #define GM_AVAILABILITY_WEAK __attribute__((weak_import))

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_2
        #define GM_AVAILABILITY_INTERNAL__2_0 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__2_0
    #endif

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_3_0
        #define GM_AVAILABILITY_INTERNAL__3_0 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__3_0
    #endif

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_3_5
        #define GM_AVAILABILITY_INTERNAL__3_5 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__3_5
    #endif

    #if GM_VERSION_MIN_REQUIRED < GM_OSXFUSE_3_8
        #define GM_AVAILABILITY_INTERNAL__3_8 GM_AVAILABILITY_WEAK
    #else
        #define GM_AVAILABILITY_INTERNAL__3_8
    #endif

    #define GM_AVAILABLE(_version) GM_AVAILABILITY_INTERNAL__##_version

#else /* !GM_VERSION_MIN_REQUIRED */

    #define GM_AVAILABLE(_version)

#endif /* !GM_VERSION_MIN_REQUIRED */

/*****************************************************************************/

#if !defined (__APPLE__)

/*****************************************************************************/
/*	PORTABILITY MODIFICATIONS FOR NON-APPLE PLATFORMS:
*/
typedef UInt32			FourCharCode;
typedef FourCharCode	ResType;
typedef SInt16			ResID;

#if !defined (ENOATTR)
#define ENOATTR			ENODATA					/* Linux getxattr(2) etc returns ENODATA. ENOATTR has been removed, although it used to be defined like this https://linux.die.net/man/2/lgetxattr */
#endif	/* !defined (ENOATTR) */

/*****************************************************************************/

#endif	/* !defined (__APPLE__) */

