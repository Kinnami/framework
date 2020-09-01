//
//  GMAvailability.h
//  OSXFUSE
//

//  Copyright (c) 2016-2017 Benjamin Fleischer.
//  All rights reserved.

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
typedef UInt32                          FourCharCode;
typedef FourCharCode                    ResType;
typedef SInt16                          ResID;

#if !defined (ENOATTR)
#define ENOATTR						ENODATA					/* Linux getxattr(2) etc returns ENODATA. ENOATTR has been removed, although it used to be defined like this https://linux.die.net/man/2/lgetxattr */
#endif	/* !defined (ENOATTR) */

/*****************************************************************************/

#endif	/* !defined (__APPLE__) */

