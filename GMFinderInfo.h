//
//  GMFinderInfo.h
//  OSXFUSE
//

//  Copyright (c) 2014-2016 Benjamin Fleischer.
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

/*!
 * @header GMFinderInfo
 *
 * A utility class to construct raw data for FinderInfo. 
 * 
 * In OS 10.4, the FinderInfo for a file may be present in an AppleDouble (._) 
 * file that is associated with the file. In 10.5+, the FinderInfo is present in 
 * the com.apple.FinderInfo extended attribute on a file.
 */

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
#define _DARWIN_USE_64_BIT_INODE	1			/* Always use 64 bit inode definitions for things like struct stat */
#endif	/* defined (__APPLE__) */

#if defined (__linux__)
#define _GNU_SOURCE					1			/* Required for dladdr() and struct Dl_info on Linux */
#endif	/* defined (__linux__) */

/* Include the essential Objective C environment umbrella header file(s) */
#import <Foundation/Foundation.h>				/* See "Foundation Framework Reference" and "Foundation Reference Update" */

#import <OSXFUSE/GMAvailability.h>

#define GM_EXPORT __attribute__((visibility("default")))

/*!
 * @class
 * @discussion This class can be used to construct raw NSData for FinderInfo.
 * For more information about FinderInfo and what it can contain, see
 * the CarbonCore/Finder.h header file.
 */
GM_EXPORT @interface GMFinderInfo : NSObject {
 @private
  UInt16 flags_;
  UInt16 extendedFlags_;
  OSType typeCode_;
  OSType creatorCode_;
}

/*! @abstract Returns an autorleased GMFinderInfo */
+ (GMFinderInfo *)finderInfo GM_AVAILABLE(2_0);

/*! 
 * @abstract Sets FinderInfo flags.
 * @discussion See CarbonCore/Finder.h for the set of flags.
 * @param flags OR'd set of valid Finder flags.
 */
- (void)setFlags:(UInt16)flags GM_AVAILABLE(2_0);

/*! 
 * @abstract Sets FinderInfo extended flags.
 * @discussion See CarbonCore/Finder.h for the set of extended flags.
 * @param flags OR'd set of valid Finder extended flags.
 */
- (void)setExtendedFlags:(UInt16)extendedFlags GM_AVAILABLE(2_0);

/*! 
 * @abstract Sets FinderInfo four-char type code.
 * @param typeCode The four-char type code to set.
 */
- (void)setTypeCode:(OSType)typeCode GM_AVAILABLE(2_0);

/*! 
 * @abstract Sets FinderInfo four-char creator code.
 * @param typeCode The four-char creator code to set.
 */
- (void)setCreatorCode:(OSType)creatorCode GM_AVAILABLE(2_0);

/*! 
 * @abstract Constucts the raw data for the FinderInfo.
 * @result NSData for the FinderInfo based on the current settings.
 */
- (NSData *)data GM_AVAILABLE(2_0);

@end

#undef GM_EXPORT
