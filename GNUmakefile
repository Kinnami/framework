#**************************************************************************************#
#
# GNUstep makefile to build OSXFUSE/framework for the GNUstep environment
#
# See http://www.gnustep.org/resources/documentation/Developer/Make/Manual/make_toc.html
#    for details about the GNUstep Makefile system
#
#**************************************************************************************#

# Include the common variables defined by the Makefile Package
include $(GNUSTEP_MAKEFILES)/common.make

# Build a framework project.
# Note: There is not much documentation. Read $GNUSTEP_MAKEFILES/Instance/framework.make for information
FRAMEWORK_NAME = OSXFUSE

BASE_USR_DIR="$(HOME)/.."

# Framework compiled version name (default "0")
#$(FRAMEWORK_NAME)_CURRENT_VERSION_NAME =

# Framework version being built should be made the current/default? (default is yes)
#$(FRAMEWORK_NAME)_MAKE_CURRENT_VERSION	=

# Framework needs GUI (AppKit graphical application) support? (default is yes)
$(FRAMEWORK_NAME)_NEEDS_GUI	= no

# Framework subprojects
#$(FRAMEWORK_NAME)_SUBPROJECTS	=

# First, define GCC and CLANG combined and compiler-specific options
#	Enabled when either $(FRAMEWORK_NAME)_USING_CLANG or $(FRAMEWORK_NAME)_USING_GCC are true
#
# CJEC, 3-Nov-09: -Wnon-virtual-dtor is a very useful warning. non-virtual destructors are
#			legal C++ iff the destructor is protected because the derived class is already
#			destroyed. Otherwise, the behaviour is "undefined".
#			See http://www.gotw.ca/publications/mill18.htm Guideline #4 for an explanation
#
# CJEC, 29-Oct-09: When compiling Objective C++, always call C++ constructors and
#			destructors during Objective C object creation and deletion so that
#			C++ member objects in Objective C classes with virtual functions work
#			properly
#			See http://gcc.gnu.org/onlinedocs/gcc-4.4.2/gcc/Objective_002dC-and-Objective_002dC_002b_002b-Dialect-Options.html#Objective_002dC-and-Objective_002dC_002b_002b-Dialect-Options
#			for details
#
# CJEC, 10-Feb-22: _FORTIFY_SOURCE is most effective when using gcc and glibc, IE Linux. See
#					featre_test_macros(7) on Linux. However clang and other OS platforms
#					(EG macOS, MINGW64) are slowly gaining support, so enable it here.
#
$(FRAMEWORK_NAME)_GCCCLANG_CPPFLAGS = -D_FORTIFY_SOURCE -D_FILE_OFFSET_BITS=64
$(FRAMEWORK_NAME)_GCCCLANG_CFLAGS = -std=gnu11 -Wall -Wextra -Wno-misleading-indentation -Wno-unused-but-set-variable -Wno-expansion-to-defined
$(FRAMEWORK_NAME)_GCCCLANG_CCFLAGS = -std=c++11 -Wall -Wextra -Wno-misleading-indentation -Wno-unused-but-set-variable -Wno-expansion-to-defined -Wnon-virtual-dtor
$(FRAMEWORK_NAME)_GCCCLANG_OBJCFLAGS = -std=gnu11 -Wall -Wextra -Wno-misleading-indentation -Wno-unused-but-set-variable -Wno-expansion-to-defined
$(FRAMEWORK_NAME)_GCCCLANG_OBJCCFLAGS = -std=c++11 -fobjc-call-cxx-cdtors -Wall -Wextra -Wno-misleading-indentation -Wno-unused-but-set-variable -Wno-expansion-to-defined -Wnon-virtual-dtor
$(FRAMEWORK_NAME)_GCCCLANG_LDFLAGS =

# Enabled when $(FRAMEWORK_NAME)_USING_GCC is true
#
$(FRAMEWORK_NAME)_GCC_CPPFLAGS =
$(FRAMEWORK_NAME)_GCC_CFLAGS =
$(FRAMEWORK_NAME)_GCC_CCFLAGS =
$(FRAMEWORK_NAME)_GCC_OBJCFLAGS = -Wno-unknown-pragmas
$(FRAMEWORK_NAME)_GCC_OBJCCFLAGS = -Wno-unknown-pragmas
$(FRAMEWORK_NAME)_GCC_LDFLAGS =

# Enabled when $(FRAMEWORK_NAME)_USING_CLANG is true
# Note: C++ & Objective C exceptions and blocks are always enabled when building with clang
#
$(FRAMEWORK_NAME)_CLANG_CPPFLAGS = -D_NATIVE_OBJC_EXCEPTIONS
$(FRAMEWORK_NAME)_CLANG_CFLAGS = -Wno-unknown-warning-option -Wno-nonportable-include-path
$(FRAMEWORK_NAME)_CLANG_CCFLAGS = -Wno-unknown-warning-option -fexceptions
$(FRAMEWORK_NAME)_CLANG_OBJCFLAGS = -Wno-unknown-warning-option -Wno-nonportable-include-path -fobjc-exceptions -fexceptions
$(FRAMEWORK_NAME)_CLANG_OBJCCFLAGS = -Wno-unknown-warning-option -Wno-nonportable-include-path -fobjc-exceptions -fexceptions
$(FRAMEWORK_NAME)_CLANG_LDFLAGS = -rdynamic -pthread -fexceptions -fobjc-runtime=gnustep-2.0 -fblocks

# Next, define the platform specific options
#
# CJEC, 22-Oct-09: Note: Must use statically linked C++ libraries for
#							Windows because we have't defined all the C++ classes as
#							dllexport.
#							Must use dynamically linked libraries for Darwin/OS X
#							because static libraries have a related visibility
#							problem
#
# CJEC, 15-Jul-20: TODO: On Windows7+ 64-bit with clang and libobjc4 (the GNUstep 2.0
#							Objective C runtime library labelled libobjc2 at Github,)
#							the above is almost certainly not what we want.
#							We should use dynamic linking whereever possible in case
#							the category problem also exists for GNUstep
#
# CJEC, 19-Jan-10: Note: Must use dynamic linked libraries for all
#							Objective C libraries otherwise categories don't work as
#							they won't be demand-loaded by the Objective C runtime.
#							Consequently, only C++ libraries can be built statically
#							if desired
#
# CJEC, 15-Jul-20: Note: When using clang & libobjc4 (the GNUstep 2.0 Objective C runtime
#							library labelled libobjc2 at Github,) need to include libdispatch
#
# CJEC, 16-Dec-21: TODO: WindowsXP, WindowsVista were built using MSYS/MinGW32 and have not (yet)
#							been upgraded to use MSYS2/MinGW64-w64-MinGW32. Those platforms may
#							not be supported by MSYS2/MinGW64-w64.
#							Windows7 should be supported by MSYS2/MinGW64-w64 but the older
#							MSYS2/MinGW32 build settings have not been upgraded yet.
#
ifeq ($(GNUSTEP_HOST_OS), mingw32)
# Note: Assuming this is Windows 10
	$(FRAMEWORK_NAME)_USING_CLANG = 0
	$(FRAMEWORK_NAME)_USING_GCC = 1
# Note: Need to define the value of Windows10 here so that the framework's derived source, which is automatically generated, does not fail to compile in a Windows header file
	$(FRAMEWORK_NAME)_TARGET_CPPFLAGS = -DWindows10=0x0A00 -D_WIN32_WINNT=Windows10 -D_NATIVE_OBJC_EXCEPTIONS
	$(FRAMEWORK_NAME)_TARGET_CFLAGS = -I/mingw64/x86_64-w64-mingw32/include/ddk
	$(FRAMEWORK_NAME)_TARGET_CCFLAGS = -I/mingw64/x86_64-w64-mingw32/include/ddk -fexceptions
	$(FRAMEWORK_NAME)_TARGET_OBJCFLAGS = -I/mingw64/x86_64-w64-mingw32/include/ddk -fobjc-exceptions -fexceptions
	$(FRAMEWORK_NAME)_TARGET_OBJCCFLAGS = -I/mingw64/x86_64-w64-mingw32/include/ddk -fobjc-exceptions -fexceptions
    $(FRAMEWORK_NAME)_TARGET_LDFLAGS = -pthread  -fexceptions
endif
ifeq ($(GNUSTEP_HOST_OS), linux-gnu)
	$(FRAMEWORK_NAME)_USING_CLANG = 1
	$(FRAMEWORK_NAME)_USING_GCC = 0
	$(FRAMEWORK_NAME)_TARGET_CPPFLAGS = -D_GNU_SOURCE
	$(FRAMEWORK_NAME)_TARGET_CFLAGS =
	$(FRAMEWORK_NAME)_TARGET_CCFLAGS =
	$(FRAMEWORK_NAME)_TARGET_OBJCFLAGS =
	$(FRAMEWORK_NAME)_TARGET_OBJCCFLAGS =
    $(FRAMEWORK_NAME)_TARGET_LDFLAGS = -fuse-ld=$(BASE_USR_DIR)/usr/bin/ld.gold
endif
ifeq ($(GNUSTEP_HOST_OS), linux-gnueabihf)
	$(FRAMEWORK_NAME)_USING_CLANG = 1
	$(FRAMEWORK_NAME)_USING_GCC = 0
	$(FRAMEWORK_NAME)_TARGET_CPPFLAGS = -D_GNU_SOURCE
	$(FRAMEWORK_NAME)_TARGET_CFLAGS =
	$(FRAMEWORK_NAME)_TARGET_CCFLAGS =
	$(FRAMEWORK_NAME)_TARGET_OBJCFLAGS =
	$(FRAMEWORK_NAME)_TARGET_OBJCCFLAGS =
    $(FRAMEWORK_NAME)_TARGET_LDFLAGS = -fuse-ld=$(BASE_USR_DIR)/usr/bin/ld.gold
endif
ifeq ($(GNUSTEP_HOST_OS), freebsd)
	$(FRAMEWORK_NAME)_USING_CLANG = 1
	$(FRAMEWORK_NAME)_USING_GCC = 0
	$(FRAMEWORK_NAME)_TARGET_CPPFLAGS = -D_GNU_SOURCE
	$(FRAMEWORK_NAME)_TARGET_CFLAGS =
	$(FRAMEWORK_NAME)_TARGET_CCFLAGS =
	$(FRAMEWORK_NAME)_TARGET_OBJCFLAGS =
	$(FRAMEWORK_NAME)_TARGET_OBJCCFLAGS =
    $(FRAMEWORK_NAME)_TARGET_LDFLAGS = -fuse-ld=$(BASE_USR_DIR)/usr/local/bin/ld.gold
endif

# Framework preprocessor, compiler and linker flags and include directories
$(FRAMEWORK_NAME)_INCLUDE_DIRS	= -I$(AMISHARE_BASE)/ReplicatingPeer/src/libTracelog/src -I$(AMISHARE_BASE)/ReplicatingPeer/src/libTracelog -I/usr/include/gnutls -I/usr/include/openssl

# Now create the full set of compiler flags in the correct order, to allow them to be overridden
#	if necessary
#
# CJEC, 30-Oct-09: Note: Compiler warning C++ compatibility with C source is a good idea, but unfortunately
#							ADDITIONAL_CFLAGS is also passed to the C++ compiler which may emit warnings
#							for C specific options
#
ifeq ($($(FRAMEWORK_NAME)_USING_CLANG), 1)
	$(FRAMEWORK_NAME)_CPPFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_CPPFLAGS) $($(FRAMEWORK_NAME)_CLANG_CPPFLAGS) $($(FRAMEWORK_NAME)_TARGET_CPPFLAGS) -D$(FRAMEWORK_NAME)_USING_CLANG=$($(FRAMEWORK_NAME)_USING_CLANG) -D$(FRAMEWORK_NAME)_USING_GCC=$($(FRAMEWORK_NAME)_USING_GCC)
	$(FRAMEWORK_NAME)_CFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_CFLAGS) $($(FRAMEWORK_NAME)_CLANG_CFLAGS) $($(FRAMEWORK_NAME)_TARGET_CFLAGS)
	$(FRAMEWORK_NAME)_CCFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_CCFLAGS) $($(FRAMEWORK_NAME)_CLANG_CCFLAGS) $($(FRAMEWORK_NAME)_TARGET_CCFLAGS)
	$(FRAMEWORK_NAME)_OBJCFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_OBJCFLAGS) $($(FRAMEWORK_NAME)_CLANG_OBJCFLAGS) $($(FRAMEWORK_NAME)_TARGET_OBJCFLAGS)
	$(FRAMEWORK_NAME)_OBJCCFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_OBJCCFLAGS) $($(FRAMEWORK_NAME)_CLANG_OBJCCFLAGS) $($(FRAMEWORK_NAME)_TARGET_OBJCCFLAGS)
	$(FRAMEWORK_NAME)_LDFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_LDFLAGS) $($(FRAMEWORK_NAME)_CLANG_LDFLAGS) $($(FRAMEWORK_NAME)_TARGET_LDFLAGS)
else
	ifeq ($($(FRAMEWORK_NAME)_USING_GCC), 1)
		$(FRAMEWORK_NAME)_CPPFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_CPPFLAGS) $($(FRAMEWORK_NAME)_GCC_CPPFLAGS) $($(FRAMEWORK_NAME)_TARGET_CPPFLAGS) -D$(FRAMEWORK_NAME)_USING_CLANG=$($(FRAMEWORK_NAME)_USING_CLANG) -D$(FRAMEWORK_NAME)_USING_GCC=$($(FRAMEWORK_NAME)_USING_GCC)
		$(FRAMEWORK_NAME)_CFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_CFLAGS) $($(FRAMEWORK_NAME)_GCC_CFLAGS) $($(FRAMEWORK_NAME)_TARGET_CFLAGS)
		$(FRAMEWORK_NAME)_CCFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_CCFLAGS) $($(FRAMEWORK_NAME)_GCC_CCFLAGS) $($(FRAMEWORK_NAME)_TARGET_CCFLAGS)
		$(FRAMEWORK_NAME)_OBJCFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_OBJCFLAGS) $($(FRAMEWORK_NAME)_GCC_OBJCFLAGS) $($(FRAMEWORK_NAME)_TARGET_OBJCFLAGS)
		$(FRAMEWORK_NAME)_OBJCCFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_OBJCCFLAGS) $($(FRAMEWORK_NAME)_GCC_OBJCCFLAGS) $($(FRAMEWORK_NAME)_TARGET_OBJCCFLAGS)
		$(FRAMEWORK_NAME)_LDFLAGS = $($(FRAMEWORK_NAME)_GCCCLANG_LDFLAGS) $($(FRAMEWORK_NAME)_GCC_LDFLAGS) $($(FRAMEWORK_NAME)_TARGET_LDFLAGS)
	else
# CJEC, 16-Dec-21: TODO: FIXME: This generates an error in the makefile, rather than reporting the error and stopping make.
		echo "GNUmakefile: Neither $(FRAMEWORK_NAME)_USING_CLANG nor $(FRAMEWORK_NAME)_USING_GCC are true"
		exit 1
	endif
endif

# Libaries. Must be specified for Windows when linking a DLL. https://www.msys2.org/wiki/Porting/
ifeq ($(GNUSTEP_HOST_OS), mingw32)
# Note: Assuming this is Windows 10
	$(FRAMEWORK_NAME)_LIB_DIRS 			= -L$(AMISHARE_BASE)/ReplicatingPeer/src/libTracelog/src/$(AMISHARE_TARGET)/obj/$(AMISHARE_TARGET_BINARY) -lTracelog
else
	ifeq ($(GNUSTEP_HOST_OS), linux-gnu)
# 64-bit Linux requires libfuse
		$(FRAMEWORK_NAME)_LIB_DIRS		= -L$(AMISHARE_BASE)/ReplicatingPeer/src/libTracelog/src/$(AMISHARE_TARGET)/obj/$(AMISHARE_TARGET_BINARY) -lTracelog -lfuse
	else
		ifeq ($(GNUSTEP_HOST_OS), linux-gnueabihf)
# 32-bit ARM Linux (Tested on Raspberry Pi 0W, Pi 0W2) requires libfuse
			$(FRAMEWORK_NAME)_LIB_DIRS		= -L$(AMISHARE_BASE)/ReplicatingPeer/src/libTracelog/src/$(AMISHARE_TARGET)/obj/$(AMISHARE_TARGET_BINARY) -lTracelog -lfuse
		else
			ifeq ($(GNUSTEP_HOST_OS), freebsd)
				$(FRAMEWORK_NAME)_LIB_DIRS	= -L$(AMISHARE_BASE)/ReplicatingPeer/src/libTracelog/src/$(AMISHARE_TARGET)/obj/$(AMISHARE_TARGET_BINARY) -lTracelog
			endif
		endif
	endif
endif

# Framework principal class
#$(FRAMEWORK_NAME)_PRINCIPAL_CLASS	=

# Framework Info-gnustep.plist is automatically genereated. Custom entries can be provided
#	in $(FRAMEWORK_NAME)Info.plist and will be automatically merged

# Framework header directory (default == ./) and files
#$(FRAMEWORK_NAME)_HEADER_FILES_DIR	=
$(FRAMEWORK_NAME)_HEADER_FILES 		= OSXFUSE.h \
										GMAvailability.h \
										GMFinderInfo.h \
										GMResourceFork.h \
										GMUserFileSystem.h

# Framework header file installation directory inside the framework installation directory.
#	(defaults to the framework name [without .framework]).  Can't be `.'
#
#	The HEADER_FILES_INSTALL_DIR might look somewhat weird - because in
# 	most if not all cases, you want it to be the framework name.  At the
# 	moment, it allows you to put headers for framework XXX in directory
# 	YYY, so that you can refer to them by using #include
# 	<YYY/MyHeader.h> rather than #include <XXX/MyHeader.h>.  It seems to
# 	be mostly used to have a framework with name XXX work as a drop-in
# 	replacement for another framework, which has name YYY -- and which
# 	might be installed at the same time.
#$(FRAMEWORK_NAME)_HEADER_FILES_INSTALL_DIR	=

# Framework Objective C files
$(FRAMEWORK_NAME)_OBJC_FILES 	= GMDataBackedFileDelegate.m \
									GMFinderInfo.m \
									GMResourceFork.m \
									GMUserFileSystem.m


# Framework tests directory. 'make check' will cause tests to be run using gnustep-tests.
#$(FRAMEWORK_NAME)_TEST_DIR	=

# Framework resource directories and files
#$(FRAMEWORK_NAME)_RESOURCE_DIRS	=
#$(FRAMEWORK_NAME)_RESOURCE_FILES	=

# Framework webserver GSWeb components
#$(FRAMEWORK_NAME)_COMPONENTS	=

# Framework webserver resource directories and files
#$(FRAMEWORK_NAME)_WEBSERVER_RESOURCE_DIRS	=
#$(FRAMEWORK_NAME)_WEBSERVER_RESOURCE_FILES	=

# Framework languages
# $(FRAMEWORK_NAME)_LANGUAGES =

# Framework localised resource files
#$(FRAMEWORK_NAME)_LOCALIZED_RESOURCE_FILES =

# Framework localised webserver resource diretories and files
#$(FRAMEWORK_NAME)_WEBSERVER_LOCALIZED_RESOURCE_DIRS	=
#$(FRAMEWORK_NAME)_WEBSERVER_LOCALIZED_RESOURCE_FILES 	=

include $(GNUSTEP_MAKEFILES)/framework.make
