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

#import "GMAvailability.h"

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

/*!
 * @header GMFinderInfo
 *
 * A utility class to construct raw data for FinderInfo. 
 * 
 * In OS 10.4, the FinderInfo for a file may be present in an AppleDouble (._) 
 * file that is associated with the file. In 10.5+, the FinderInfo is present in 
 * the com.apple.FinderInfo extended attribute on a file.
 */

/*!
 * @class
 * @discussion This class can be used to construct raw NSData for FinderInfo.
 * For more information about FinderInfo and what it can contain, see
 * the CarbonCore/Finder.h header file.
 */
GM_EXPORT_INTERFACE	@interface GMFinderInfo : NSObject {
 @private
  UInt16 flags_;
  UInt16 extendedFlags_;
  OSType typeCode_;
  OSType creatorCode_;
}

/*! @abstract Returns an autoreleased GMFinderInfo */
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
